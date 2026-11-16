# encoding: UTF-8
module GameRoomCashAuction
  # Existing tables keep their original single-pack schema. Only creation or
  # an ordinary new game prepares the checklist and pins its selected sources.
  module Content
    using GameRoomLocalization::Translations
    PACKS_KEY = 'content_pack_ids'.freeze
    MANIFEST_KEY = 'content_pack_manifest'.freeze
    VERSION_KEY = 'auction_rules_version'.freeze
    MANIFEST_FIELDS = %w[id set language version checksum].freeze
    MAX_PACKS = 3
    GENERAL_SET_IDS = {'en'=>'quiz.general', 'pl-PL'=>'quiz.wikidata', 'ru-RU'=>'quiz.general.ru'}.freeze
    MAX_ID_BYTES = 128
    MAX_MANIFEST_BYTES = 4096
    MAX_VERSION = (1 << 63) - 1

    class OptionFields
      def initialize(game); @game = game; end
      def fields; []; end
      def refresh(_options, _form); end
      def prepare(options)
        prepared = @game.table_creation_options(options)
        error = @game.validation_error(prepared)
        raise ArgumentError, error if error

        prepared
      end
    end

    def normalize_options(values)
      source = values.is_a?(Hash) ? values : {}
      version = option_source_value(source, VERSION_KEY)
      # Defaults changed with v2. A sparse historical document still means
      # exactly what the original reducer understood, independent of the UI.
      if version.nil? || version == 1
        source = source.dup
        GameRoomCashAuction::Rules::DEFAULT_OPTIONS.each do |key, value|
          source[key] = value unless source.key?(key) || source.key?(key.to_sym)
        end
      end
      result = super(source)
      if source.key?(VERSION_KEY) || source.key?(VERSION_KEY.to_sym)
        result[VERSION_KEY] = version
      end
      if version.nil? || version == 1
        # Base normalizes controls without selected values. Its current
        # checklist therefore occupies the former set control's position;
        # restore the original serialized selector order for old histories.
        selectors = [GameRoomContent::LANGUAGE_OPTION_KEY, GameRoomContent::SET_OPTION_KEY]
        result = selectors.to_h { |key| [key, result.fetch(key)] }.merge(result)
      elsif result.key?(MANIFEST_KEY)
        # Creation first adds the marker and then the manifest. Keep that same
        # JSON order on every normalization and fixed-start round trip.
        manifest = result.delete(MANIFEST_KEY)
        result[MANIFEST_KEY] = manifest
      end
      result
    end

    def table_creation_options(values = {})
      source = values.is_a?(Hash) ? values.dup : {}
      source[VERSION_KEY] = GameRoomCashAuction::Rules::CURRENT_VERSION
      # These describe the former single source, never a synthetic merged pack.
      [GameRoomContent::SET_OPTION_KEY, GameRoomContent::PACK_OPTION_KEY,
        GameRoomContent::PACK_VERSION_KEY, GameRoomContent::PACK_CHECKSUM_KEY].each do |key|
        source.delete(key)
        source.delete(key.to_sym)
      end
      result = super(source)
      # Explicit unavailable/empty selections must reach the option form,
      # where the existing checklist shows them and the user can repair them.
      return result if auction_selection_error(result)

      packs = auction_packs_for_ids(result[PACKS_KEY], result[GameRoomContent::LANGUAGE_OPTION_KEY])
      result[MANIFEST_KEY] = auction_pack_manifest(packs)
      result
    end

    def new_game_options(values)
      table_creation_options(values)
    end

    def option_editor_changes(previous, current)
      changes = super
      if GameRoomCashAuction::Rules.revised_options?(current) && previous[GameRoomContent::LANGUAGE_OPTION_KEY] != current[GameRoomContent::LANGUAGE_OPTION_KEY]
        changes.merge(PACKS_KEY=>auction_default_pack_ids(current[GameRoomContent::LANGUAGE_OPTION_KEY]))
      else
        changes
      end
    end

    def build_option_editor_extension(program, options)
      GameRoomCashAuction::Rules.revised_options?(options) ? OptionFields.new(self) : super
    end

    def remembered_option_definitions(definitions, options: nil)
      # Each new table starts with its language's general set, not the previous
      # checklist. Filtering here covers both reading old and writing new prefs.
      super.reject { |definition| definition.key.to_s == PACKS_KEY }
    end

    def notification_choice(options, key)
      return super unless key == PACKS_KEY
      # Invitations intentionally carry only declared display controls, with
      # no rules marker or manifest. Resolve bounded IDs locally for labels;
      # actual game entry/replay verifies the full pinned identity separately.
      return nil if auction_selection_error(options)

      auction_packs_for_ids(options[PACKS_KEY], options[GameRoomContent::LANGUAGE_OPTION_KEY]).map(&:title).join(', ')
    end

    # Public integration boundary for the replay's one-bank cache. It resolves
    # recorded metadata only; it neither loads question rows nor repairs pins.
    def auction_content_packs(options)
      values = normalize_options(options)
      error = content_options_error(values)
      raise ArgumentError, error if error

      return [selected_content_pack(values)] unless GameRoomCashAuction::Rules.revised_options?(values)

      auction_packs_for_ids(values[PACKS_KEY], values[GameRoomContent::LANGUAGE_OPTION_KEY])
    end

    protected

    def content_option_definitions(selected = {})
      version = option_source_value(selected, VERSION_KEY)
      legacy = version == 1 || (version.nil? &&
        [GameRoomContent::SET_OPTION_KEY, GameRoomContent::PACK_OPTION_KEY].any? { |key| option_source_value(selected, key) != nil })
      return super if legacy

      language = option_source_value(selected, GameRoomContent::LANGUAGE_OPTION_KEY)
      language = default_content_language_id if language.to_s.empty?
      packs = auction_available_packs(language)
      [super(selected).first,
       GameRoomGames::OptionDefinition.new(key: PACKS_KEY, label: _('Question sets (1 to 3)'), kind: :multiple_values,
         default: auction_default_pack_ids(language), choices: packs.map do |pack|
           GameRoomGames::OptionChoice.new(value: pack.id, label: pack.title)
         end)]
    end

    def normalize_content_options(source, result)
      version = option_source_value(source, VERSION_KEY)
      if version.nil? || version == 1
        result.delete(PACKS_KEY)
        result.delete(MANIFEST_KEY)
        return super
      end

      language = option_source_value(source, GameRoomContent::LANGUAGE_OPTION_KEY)
      language = default_content_language_id if language.to_s.empty?
      result[GameRoomContent::LANGUAGE_OPTION_KEY] = language.to_s
      unless source.key?(PACKS_KEY) || source.key?(PACKS_KEY.to_sym)
        result[PACKS_KEY] = auction_default_pack_ids(language)
      end
      if source.key?(MANIFEST_KEY) || source.key?(MANIFEST_KEY.to_sym)
        result[MANIFEST_KEY] = auction_copy_manifest(option_source_value(source, MANIFEST_KEY))
      end
    end

    def content_options_error(options)
      version = option_source_value(options, VERSION_KEY)
      present = options.key?(VERSION_KEY) || options.key?(VERSION_KEY.to_sym)
      unless !present || (version.is_a?(Integer) && [1, 2, 3, 4, GameRoomCashAuction::Rules::CURRENT_VERSION].include?(version))
        return _('Unsupported Cash Auction rules version.')
      end
      return super unless GameRoomCashAuction::Rules.revised_options?(options)

      error = auction_selection_error(options)
      return error if error

      packs = auction_packs_for_ids(options[PACKS_KEY], options[GameRoomContent::LANGUAGE_OPTION_KEY])
      if options[MANIFEST_KEY] != auction_pack_manifest(packs)
        return _('The selected question packs do not match the table.')
      end
      nil
    end

    def content_options_summary(options)
      return super unless GameRoomCashAuction::Rules.revised_options?(options)
      return '' if content_options_error(options)

      language = content_registry.language(options[GameRoomContent::LANGUAGE_OPTION_KEY])
      _('question sets: %{sets}; language: %{language}') % {
        sets: auction_content_packs(options).map(&:title).join(', '),
        language: language ? language.label : options[GameRoomContent::LANGUAGE_OPTION_KEY]
      }
    end

    def auction_available_packs(language)
      available_content_packs.select { |pack| pack.language_id == language.to_s }.sort_by(&:id)
    end

    def auction_default_pack_ids(language)
      # The general set is an editorial default, not the first catalogue item.
      # Leave an absent general set unchecked rather than selecting a topic.
      general = GENERAL_SET_IDS[language.to_s]
      auction_available_packs(language).select { |pack| pack.set_id == general }.map(&:id)
    end

    def auction_selection_error(options)
      language = option_source_value(options, GameRoomContent::LANGUAGE_OPTION_KEY)
      packs = auction_available_packs(language)
      ids = option_source_value(options, PACKS_KEY)
      valid_ids = ids.is_a?(Array) && ids.length <= MAX_PACKS && ids.all? do |id|
          id.is_a?(String) && id.valid_encoding? && id.bytesize.between?(1, MAX_ID_BYTES) && packs.any? { |pack| pack.id == id }
        end
      unless valid_ids && ids.uniq.length == ids.length
        return _('The selected question pack is not installed for this language.')
      end
      unless ids.length.between?(1, [packs.length, MAX_PACKS].min)
        return _('Choose from 1 to 3 question sets in the selected language.')
      end
      nil
    end

    def auction_packs_for_ids(ids, language)
      auction_available_packs(language).select { |pack| ids.include?(pack.id) }
    end

    def auction_pack_manifest(packs)
      packs.map do |pack|
        {'id'=>pack.id.dup, 'set'=>pack.set_id.dup, 'language'=>pack.language_id.dup,
          'version'=>pack.version, 'checksum'=>pack.checksum.dup}
      end
    end

    # Reject malformed/oversized metadata without recursively copying it.
    # Semantically wrong but bounded pins remain unchanged for validation.
    def auction_copy_manifest(value)
      return nil unless value.is_a?(Array) && value.length <= MAX_PACKS
      return nil unless value.all? do |entry|
        entry.is_a?(Hash) && entry.length == MANIFEST_FIELDS.length &&
          entry.keys.all? { |key| key.is_a?(String) } && entry.keys.sort == MANIFEST_FIELDS.sort &&
          entry['version'].is_a?(Integer) && entry['version'].between?(1, MAX_VERSION) &&
          (MANIFEST_FIELDS - ['version']).all? do |key|
            entry[key].is_a?(String) && entry[key].valid_encoding? && entry[key].bytesize.between?(1, MAX_ID_BYTES)
          end
      end
      return nil if JSON.generate(value).bytesize > MAX_MANIFEST_BYTES

      value.map { |entry| entry.transform_values { |item| item.is_a?(String) ? item.dup : item } }
    end
  end
end

module GameRoomGames
  class CashAuction
    include GameRoomCashAuction::Content
  end
end
