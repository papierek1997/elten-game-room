require_relative '../../lib/game_room_localization'
require_relative '../../lib/game_option_values'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Base
    module Options
      public

      def option_definitions
        []
      end

      # Explicit opt-in: never copy private/internal settings into notices.
      def notification_option_keys(_options)
        []
      end

      def notification_variant(options)
        notification_option_keys(options).filter_map { |key| notification_choice(options, key) }.join(", ")
      end

      def notification_choice(options, key)
        return nil unless options.key?(key)
        if key == GameRoomContent::SET_OPTION_KEY
          return available_content_sets(options[GameRoomContent::LANGUAGE_OPTION_KEY]).find { |set| set.id == options[key] }&.title
        end
        definition = effective_option_definitions(options).find { |item| item.key.to_s == key }
        choice = definition&.choices.to_a.find { |item| item.value.to_s == options[key].to_s }
        choice && GameRoomContent.utf8(choice.label)
      end

      def notification_flag(options, key, yes, no)
        return yes if options[key] == true
        return no if options[key] == false
        nil
      end

      def notification_points(options, key)
        count = options[key]
        return nil unless count.is_a?(Integer) && count.positive?
        n_("%{count} point", "%{count} points", count) % {count: count}
      end

      # Local view persistence is declared by its game and never serialized
      # into table options, actions, subscriptions or a saved game.
      def board_preference_definitions
        []
      end

      def content_pack_kind
        nil
      end

      # Word games with one dictionary/deck per language do not need a redundant
      # one-item set picker. Quiz keeps its existing independent set selector.
      def single_content_set?
        false
      end

      def content_registry
        GameRoomContent.registry
      end

      def effective_option_definitions(selected = {})
        definitions = content_option_definitions(selected) + option_definitions.to_a
        definitions << thinking_time_option if thinking_time_range && definitions.none? { |item| item.key == "thinking_time" }
        if supports_bot_move_delay?
          definitions << OptionDefinition.new(key: "bot_delay", label: _("Bot move delay in seconds (0 to 5); zero disables the pause"), kind: :integer, default: default_bot_move_delay,
            summary_label: _("Bot move delay"), summary_unit: :seconds, omit_zero: true)
        end
        keys = definitions.map { |definition| definition.key.to_s }
        raise ArgumentError, "game option keys must be unique" if keys.uniq.length != keys.length

        definitions
      end

      def default_options
        normalize_options({})
      end

      # Presentation choices may be narrower than the canonical replay schema.
      def option_editor_definitions(selected = {})
        effective_option_definitions(selected)
      end

      # Only the creator's option form uses these defaults. Replay and saved
      # tables keep their recorded language, regardless of the viewer's UI.
      def table_creation_options(values = {})
        source = values.dup
        key = content_language_option_key
        if key && option_source_value(source, key).to_s.empty?
          ids = effective_option_definitions.find { |definition| definition.key.to_s == key }.choices.map(&:value)
          code = ->(value) { value.to_s.downcase.split(/[-_]/).first }
          language = ids.find { |id| code.call(id) == code.call(GameRoomLocalization.primary_language) } ||
            ids.find { |id| code.call(id) == "en" }
          raise ArgumentError, "#{id} has no content in the interface language or English" unless language

          source[key] = language
        end
        normalize_options(source)
      end

      def content_language_option_key
        GameRoomContent::LANGUAGE_OPTION_KEY unless content_pack_kind.to_s.empty?
      end

      def new_game_options(values)
        normalize_options(values)
      end

      # Published tournament options already belong to a fixed match identity.
      # New-game defaults must not silently upgrade that accepted document.
      def game_start_options(values, players:, fixed: false)
        options = fixed ? normalize_options(values) : new_game_options(values)
        options_for_team_roster(options, players: players)
      end

      # Games declare dependencies between options, while the shared table
      # configuration form owns hiding and showing the corresponding controls.
      # A hash requires every named option to match. A callable can express a
      # compound condition without putting game-specific branches in the UI.
      def option_visible?(definition, values, normalize: true)
        condition = definition.visible_if
        return true if condition == nil

        options = normalize ? normalize_options(values) : values
        return condition.call(options) == true if condition.respond_to?(:call)
        return false if !condition.respond_to?(:all?)

        condition.all? do |key, expected|
          actual = options[key.to_s]
          expected.respond_to?(:call) ? expected.call(actual) == true : Array(expected).include?(actual)
        end
      end

      def normalize_options(values)
        source = values.is_a?(Hash) ? values : {}
        raise ArgumentError, 'Invalid game option shape' unless GameRoomOptionValues.normalizable_options?(source)
        result = effective_option_definitions.each_with_object({}) do |definition, normalized|
          key = definition.key.to_s
          raw = if source.key?(key)
            source[key]
          elsif source.key?(key.to_sym)
            source[key.to_sym]
          else
            definition.default
          end
          normalized[key] = normalize_option_value(definition, raw)
        end
        team_seats = source[GameRoomTeams::OPTION_KEY] || source[GameRoomTeams::OPTION_KEY.to_sym]
        result[GameRoomTeams::OPTION_KEY] = team_seats.to_a.map(&:to_i) if team_seats.is_a?(Array)
        team_players = source[GameRoomTeams::PLAYERS_KEY] || source[GameRoomTeams::PLAYERS_KEY.to_sym]
        if team_players.is_a?(Array) && team_players.length <= 8 && team_players.all? { |player| player.is_a?(String) && !player.empty? && player.length <= 64 }
          result[GameRoomTeams::PLAYERS_KEY] = team_players.dup
        end
        normalize_content_options(source, result)
        result
      end

      def options_from_json(value)
        parsed = value.to_s.empty? ? {} : JSON.parse(value.to_s)
        normalize_options(parsed)
      rescue JSON::ParserError
        default_options
      end

      def options_error(_options, player_count: nil)
        nil
      end

      # A variant may change a dependent default in the editor, but must retain
      # a value which the user has already customized. Replay never calls this.
      def option_editor_changes(_previous, _current)
        {}
      end

      def validation_error(options, player_count: nil)
        return _('The game settings are invalid.') unless GameRoomOptionValues.normalizable_options?(options)
        content_options_error(options) || multiple_values_options_error(options) || thinking_time_options_error(options) || bot_delay_options_error(options) || options_error(options, player_count: player_count)
      end

      # ID-based checklists are opt-in. Keep unavailable IDs until validation
      # so a changed catalogue cannot silently select a different resource.
      # Existing multiple_choice options retain their historical bit masks.
      def multiple_values_options_error(options)
        effective_option_definitions(options).each do |definition|
          next unless definition.kind.to_s == "multiple_values"

          key = definition.key.to_s
          value = if options.respond_to?(:key?) && (options.key?(key) || options.key?(key.to_sym))
            option_source_value(options, key)
          else
            definition.default
          end
          choices = definition.choices.to_a.map(&:value)
          unless choices.all? { |choice| choice.is_a?(String) && !choice.empty? && choice.valid_encoding? } && choices.uniq.length == choices.length
            raise ArgumentError, "ID-based option choices must be unique strings"
          end
          unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) && choices.include?(item) }
            return _("The selection for %{option} contains an unavailable choice.") % { option: definition.label }
          end
        end
        nil
      end

      # Opt in only when the engine implements an authoritative timeout. A
      # generic legal move is never a safe substitute for a player's decision.
      def thinking_time_range; nil; end

      def thinking_time_option
        OptionDefinition.new(key: "thinking_time", label: _("Thinking time in seconds; zero means no limit"), kind: :integer, default: 0,
          summary_label: _("Thinking time"), summary_unit: :seconds, omit_zero: true)
      end

      def thinking_time_options_error(options)
        range = thinking_time_range
        return nil unless range
        value = normalize_options(options)["thinking_time"]
        return nil if value == 0 || range.include?(value)
        _("Thinking time must be zero or from %{minimum} to %{maximum} seconds.") % { minimum: range.min, maximum: range.max }
      end

      def default_bot_move_delay; 1; end

      def bot_delay_options_error(options)
        return nil unless supports_bot_move_delay?
        values = normalize_options(options)
        return _("Bot move delay must be from 0 to 5 seconds.") unless values["bot_delay"].between?(0, 5)
        limits = %w[thinking_time answer_time round_time auction_decision_time].filter_map do |key|
          value = values[key].to_i
          value if value > 0
        end
        return _("Bot move delay cannot exceed thinking time.") if limits.any? { |limit| values["bot_delay"] > limit }
        nil
      end

      def options_summary(_options)
        ""
      end

      def combined_options_summary(options)
        parts = [content_options_summary(options), options_summary(options)]
          .map { |part| part.to_s.strip }
          .reject(&:empty?)
        parts.join("; ")
      end

      def rules_option_visible?(definition, options)
        option_visible?(definition, options, normalize: false)
      end

      # Read-only snapshot of the effective settings, not the abbreviated lobby
      # summary. Disabled and inapplicable additions are intentionally omitted.
      def rules_options_text(options)
        raise ArgumentError, 'Invalid game option shape' unless GameRoomOptionValues.normalizable_options?(options)
        lines = effective_option_definitions(options).filter_map do |definition|
          next if !rules_option_visible?(definition, options)
          value = GameRoomOptionValues.read(definition, options)
          next if definition.omit_zero && GameRoomOptionValues.integer_value(value) == 0
          label = GameRoomContent.utf8(definition.summary_label || definition.label).sub(/[.\s]+\z/, "")
          case definition.kind.to_sym
          when :boolean
            label if value == true
          when :multiple_choice, :multiple_values
            if !GameRoomOptionValues.selected_choices(definition, value).empty?
              "#{label}: #{GameRoomOptionValues.format(definition, value)}"
            end
          else
            "#{label}: #{GameRoomOptionValues.format(definition, value)}"
          end
        end
        seats = options[GameRoomTeams::OPTION_KEY]
        if seats.is_a?(Array) && GameRoomOptionValues.integer_value(options["team_size"]) > 0
          lines << (_("Teams in seating order: %{teams}") % { teams: seats.map { |team| team.to_i + 1 }.join(", ") })
        end
        lines.empty? ? _("This table uses fixed rules with no configurable additions.") : lines.join("\r\n\r\n")
      end

      def table_options_announcement(options)
        lines = rules_options_text(normalize_options(options)).split(/\r?\n/).map { |line| line.strip.sub(/[.\s]+\z/, "") }.reject(&:empty?)
        ([name] + lines).join(". ")
      end

      def selected_content_pack(options)
        return nil if content_pack_kind.to_s.empty?

        normalized = normalize_options(options)
        pack = content_registry.pack(normalized[GameRoomContent::PACK_OPTION_KEY])
        return nil if pack == nil || !pack.supports?(game_id: id, kind: content_pack_kind)
        return nil if pack.set_id != normalized[GameRoomContent::SET_OPTION_KEY].to_s
        return nil if pack.language_id != normalized[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
        return nil if pack.version != normalized[GameRoomContent::PACK_VERSION_KEY].to_i
        return nil if pack.checksum != normalized[GameRoomContent::PACK_CHECKSUM_KEY].to_s.downcase

        pack
      end

      protected

      def available_content_packs
        return [] if content_pack_kind.to_s.empty?

        content_registry.packs_for(game_id: id, kind: content_pack_kind)
      end

      def available_content_sets(language_id = nil)
        return [] if content_pack_kind.to_s.empty?

        sets = content_registry.pack_sets_for(game_id: id, kind: content_pack_kind)
        return sets if language_id.to_s.empty?

        sets.select { |pack_set| pack_set.language_ids.include?(language_id.to_s) }
      end

      def available_content_languages
        ids = available_content_packs.map(&:language_id).uniq
        ids.map { |language_id| content_registry.language(language_id) }.compact
          .sort_by { |language| [language.label.downcase, language.id] }
      end

      def default_content_language_id(set_id = nil)
        if set_id.to_s.empty?
          return available_content_languages.first&.id
        end

        pack_set = available_content_sets.find { |candidate| candidate.id == set_id.to_s }
        pack_set&.language_ids&.first
      end

      def default_content_set_id(language_id = default_content_language_id)
        sets = available_content_sets(language_id)
        sets = available_content_sets if sets.empty?
        sets.first&.id
      end

      def content_option_definitions(selected = {})
        return [] if content_pack_kind.to_s.empty?

        languages = available_content_languages
        raise ArgumentError, "#{id} requires a #{content_pack_kind} content pack" if available_content_sets.empty?
        language_id = option_source_value(selected, GameRoomContent::LANGUAGE_OPTION_KEY)
        language_id = default_content_language_id if language_id.to_s.empty?
        pack_sets = available_content_sets(language_id)
        pack_sets = available_content_sets if pack_sets.empty?
        [
          OptionDefinition.new(
            key: GameRoomContent::LANGUAGE_OPTION_KEY,
            label: _("Game content language"),
            kind: :choice,
            default: default_content_language_id,
            choices: languages.map do |language|
              OptionChoice.new(value: language.id, label: language.label)
            end
          ),
          OptionDefinition.new(
            key: GameRoomContent::SET_OPTION_KEY,
            label: _("Game content set"),
            kind: :choice,
            default: default_content_set_id(language_id),
            visible_if: single_content_set? ? ->(_options) { false } : nil,
            choices: pack_sets.map do |pack_set|
              OptionChoice.new(value: pack_set.id, label: content_set_choice_label(pack_set, language_id))
            end
          )
        ]
      end

      def content_set_choice_label(pack_set, _language_id = nil)
        pack_set.title
      end

      def normalize_content_options(source, result)
        return if content_pack_kind.to_s.empty?

        requested_language = option_source_value(source, GameRoomContent::LANGUAGE_OPTION_KEY)
        requested_language = default_content_language_id if requested_language.to_s.empty?
        requested_set = option_source_value(source, GameRoomContent::SET_OPTION_KEY)
        requested_set = default_content_set_id(requested_language) if requested_set.to_s.empty?
        known_set = available_content_sets.any? { |candidate| candidate.id == requested_set.to_s }
        known_language = available_content_languages.any? { |candidate| candidate.id == requested_language.to_s }
        if known_set && known_language &&
            !available_content_sets(requested_language).any? { |candidate| candidate.id == requested_set.to_s }
          requested_set = default_content_set_id(requested_language)
        end
        result[GameRoomContent::SET_OPTION_KEY] = requested_set.to_s
        result[GameRoomContent::LANGUAGE_OPTION_KEY] = requested_language.to_s
        pack = content_registry.pack_for(
          game_id: id,
          kind: content_pack_kind,
          set_id: requested_set,
          language_id: requested_language
        )
        stored_pack_id = option_source_value(source, GameRoomContent::PACK_OPTION_KEY)
        stored_version = option_source_value(source, GameRoomContent::PACK_VERSION_KEY)
        stored_checksum = option_source_value(source, GameRoomContent::PACK_CHECKSUM_KEY)
        result[GameRoomContent::PACK_OPTION_KEY] = stored_pack_id == nil ? pack&.id.to_s : stored_pack_id.to_s
        result[GameRoomContent::PACK_VERSION_KEY] = if stored_version == nil
          pack == nil ? 0 : pack.version
        else
          GameRoomOptionValues.integer_value(stored_version)
        end
        result[GameRoomContent::PACK_CHECKSUM_KEY] = if stored_checksum == nil
          pack&.checksum.to_s
        else
          stored_checksum.to_s.downcase
        end
      end

      def content_options_error(options)
        return nil if content_pack_kind.to_s.empty?

        values = options.is_a?(Hash) ? options : {}
        set_id = option_source_value(values, GameRoomContent::SET_OPTION_KEY).to_s
        language_id = option_source_value(values, GameRoomContent::LANGUAGE_OPTION_KEY).to_s
        pack_set = content_registry.pack_set(set_id)
        return _("The selected game content set is not installed.") if pack_set == nil
        if !pack_set.supports?(game_id: id, kind: content_pack_kind)
          return _("The selected content set is not compatible with this game.")
        end
        selected = content_registry.pack_for(
          game_id: id,
          kind: content_pack_kind,
          set_id: set_id,
          language_id: language_id
        )
        return _("The selected language is not available for this content set.") if selected == nil
        pack_id = option_source_value(values, GameRoomContent::PACK_OPTION_KEY).to_s
        pack = content_registry.pack(pack_id)
        return _("The selected game content pack is not installed.") if pack == nil
        if !pack.equal?(selected)
          return _("The selected content pack does not match the set and language.")
        end
        if pack.version != GameRoomOptionValues.integer_value(option_source_value(values, GameRoomContent::PACK_VERSION_KEY))
          return _("The installed game content pack has a different version.")
        end
        if pack.checksum != option_source_value(values, GameRoomContent::PACK_CHECKSUM_KEY).to_s.downcase
          return _("The installed game content pack does not match the table.")
        end
        nil
      end

      def content_options_summary(options)
        pack = selected_content_pack(options)
        return "" if pack == nil

        language = content_registry.language(pack.language_id)
        pack_set = content_registry.pack_set(pack.set_id)
        _("content: %{title}; language: %{language}") % {
          title: pack_set == nil ? pack.title : content_set_choice_label(pack_set, pack.language_id),
          language: language == nil ? pack.language_id : language.label
        }
      end

      def option_source_value(source, key)
        return source[key] if source.respond_to?(:key?) && source.key?(key)
        symbol = key.to_sym
        return source[symbol] if source.respond_to?(:key?) && source.key?(symbol)

        nil
      end

      def normalize_option_value(definition, value)
        case definition.kind.to_s
        when "boolean"
          value == true || value.to_s == "1" || value.to_s.downcase == "true"
        when "integer"
          Integer(value.to_s, 10)
        when "choice"
          choices = definition.choices.to_a
          selected = choices.find { |choice| choice.value.to_s == value.to_s }
          selected ||= choices.find { |choice| choice.value.to_s == definition.default.to_s }
          selected == nil ? nil : selected.value
        when "multiple_choice"
          choices = definition.choices.to_a
          valid_mask = (1 << choices.length) - 1
          if value.is_a?(Array)
            requested = value.map(&:to_s)
            choices.each_with_index.reduce(0) do |mask, (choice, index)|
              requested.include?(choice.value.to_s) ? mask | (1 << index) : mask
            end
          else
            GameRoomOptionValues.integer_value(value) & valid_mask
          end
        when "multiple_values"
          # Do not interpret numbers as a mask or discard unknown identifiers.
          # Validation reports incompatible data instead of picking a fallback.
          return value unless value.is_a?(Array)
          return value.dup unless value.all? { |item| item.is_a?(String) && item.valid_encoding? }

          value.map(&:dup).uniq.sort
        else
          value
        end
      rescue ArgumentError
        definition.default.to_i
      end
    end

    include Options
  end
end
