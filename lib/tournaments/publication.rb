# encoding: UTF-8
require 'json'
require_relative 'draft_details'
require_relative 'strict_json'
require_relative 'tournament_timing'
require_relative '../game_option_values'

module GameRoomTournaments
  # Czysty snapshot; to_row opisuje PROPONOWANE kolumny, nie wdrożony schemat.
  class Publication
    SETTINGS = %w[game_options format rematch players_per_match pairing].map(&:freeze).freeze
    GROUP_SETTINGS = %w[group_count places_per_group].map(&:freeze).freeze
    ADVANCEMENT_SETTINGS = (GROUP_SETTINGS + ['group_advancement'.freeze]).freeze
    ROUND_SETTINGS = %w[knockout_rematch final_rematch].freeze
    WIN_SETTINGS = %w[knockout_wins_to final_wins_to].freeze
    COLUMNS = %w[publication_key schema_version title game rules settings_json schedule_json
      registration_opens_at registration_closes_at timezone].map(&:freeze).freeze
    MAX_ROWS = 4096
    MAX_JSON_BYTES = 65_536
    MAX_RULES_BYTES = 16_384
    MAX_INTEGER = (2**63) - 1

    class Invalid < ArgumentError
      attr_reader :code, :details
      def initialize(code, **details)
        @code = code
        @details = details.freeze
        super(code.to_s)
      end
    end

    class Incomplete < Invalid; end

    # Wspólne wewnętrzne granice danych obu czystych modeli. Bez konwersji typów.
    module Data
      module_function

      def text?(value)
        String === value && value.valid_encoding? && value.encoding.ascii_compatible? &&
          (value.encoding == Encoding::UTF_8 || value.ascii_only?)
      end

      def text!(value, bytes:, length: bytes, multiline: false)
        unless text?(value) && value.bytesize <= bytes && value.length.between?(1, length) &&
            value.match?(/[^[:space:]]/)
          raise Invalid, :invalid_text
        end
        checked = multiline ? value.delete("\r\n\t") : value
        raise Invalid, :invalid_text if checked.match?(/[[:cntrl:]\u2028\u2029]/)
        value
      end

      def key!(value)
        text!(value, bytes: 64)
        raise Invalid, :invalid_key unless value.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
        value
      end

      def integer?(value, minimum = 0)
        Integer === value && value.between?(minimum, MAX_INTEGER)
      end

      def copy(value, max_bytes: MAX_JSON_BYTES, max_nodes: 4096, max_depth: 8)
        result = visit(value, 0, [0, 0], max_bytes, max_nodes, max_depth)
        raise Invalid, :json_budget if JSON.generate(result).bytesize > max_bytes
        result
      end

      def visit(value, depth, budget, bytes, nodes, levels)
        budget[0] += 1
        raise Invalid, :json_budget if budget[0] > nodes || depth > levels
        result = case value
        when Hash
          raise Invalid, :json_budget if value.size > nodes
          pairs = value.map do |key, child|
            raise Invalid, :invalid_json unless String === key
            [visit(key, depth + 1, budget, bytes, nodes, levels), visit(child, depth + 1, budget, bytes, nodes, levels)]
          end
          pairs.sort_by(&:first).to_h
        when Array
          raise Invalid, :json_budget if value.size > nodes
          value.map { |child| visit(child, depth + 1, budget, bytes, nodes, levels) }
        when String
          raise Invalid, :invalid_utf8 unless text?(value)
          budget[1] += value.bytesize
          String.new(value).encode(Encoding::UTF_8)
        when Integer
          raise Invalid, :invalid_json unless value.bit_length <= 63
          value
        when Float
          raise Invalid, :invalid_json unless value.finite?
          value
        when NilClass, TrueClass, FalseClass
          value
        else
          raise Invalid, :invalid_json
        end
        raise Invalid, :json_budget if budget[1] > bytes
        result
      end

      def account(value)
        text!(value, bytes: 256, length: 64)
        raise Invalid, :invalid_account if value.match?(/\A[[:space:]]|[[:space:]]\z/)
        String.new(value).encode(Encoding::UTF_8)
      end

      def metadata(row)
        unless integer?(row['__id'], 1) && integer?(row['__insertion_time'])
          raise Invalid, :invalid_metadata
        end
        { '__id' => row['__id'], '__insertion_time' => row['__insertion_time'],
          '__insertion_user' => account(row['__insertion_user']) }
      end

      def group_hint(row, key_name)
        return nil unless Hash === row
        [account(row['__insertion_user']).downcase, String.new(key!(row[key_name]))]
      rescue Invalid
        nil
      end

      def entries(rows, complete:, key_name:)
        raise Incomplete, :incomplete_snapshot unless true.equal?(complete)
        raise Invalid, :invalid_rows unless Array === rows
        raise Incomplete, :row_budget if rows.size > MAX_ROWS
        bytes = 0
        rows.map do |raw|
          entry = { 'id' => Hash === raw && integer?(raw['__id'], 1) ? raw['__id'] : nil,
            'group' => group_hint(raw, key_name) }
          begin
            row = copy(raw, max_bytes: 160_000)
            raise Invalid, :invalid_row unless Hash === row
            bytes += JSON.generate(row).bytesize
            raise Incomplete, :snapshot_byte_budget if bytes > 16_777_216
            entry['row'] = yield(row)
          rescue Incomplete
            raise
          rescue Invalid => error
            entry['error'] = error.code.to_s
          end
          entry
        end
      end

      def diagnostic(code, entries, group = nil)
        { 'code' => code, 'ids' => entries.map { |entry| entry['id'] }.compact.uniq.sort,
          'account' => group && group[0], 'key' => group && group[1] }
      end

      # Najpierw wszystkie kolizje ID, potem grupy kluczy. Wadliwy alias zatruwa
      # swoją grupę, zamiast znikać przed wykrywaniem konfliktów.
      def reconcile(entries)
        diagnostics = entries.filter_map do |entry|
          diagnostic(entry['error'], [entry], entry['group']) if entry['error']
        end
        bad_ids = entries.select { |entry| entry['id'] }.group_by { |entry| entry['id'] }.filter_map do |id, group|
          next unless group.size > 1 && (group.any? { |entry| entry['error'] } || group.map { |entry| entry['row'] }.uniq.size > 1)
          diagnostics << diagnostic('id_conflict', group)
          id
        end
        groups = entries.select { |entry| entry['group'] }.group_by { |entry| entry['group'] }.filter_map do |key, group|
          # Sam wadliwy wiersz oznacza brak potwierdzenia, nie dowód konfliktu.
          next if group.none? { |entry| entry['row'] }
          valid = group.none? { |entry| entry['error'] || bad_ids.include?(entry['id']) }
          rows = group.map { |entry| entry['row'] }
          if !valid || rows.map { |row| yield(row) }.uniq.size > 1
            diagnostics << diagnostic('key_conflict', group, key)
            next
          end
          rows.uniq
        end
        [groups, diagnostics.uniq.sort_by { |item| JSON.generate(item) }]
      end

      def freeze_tree(value)
        case value
        when Hash
          value.each { |key, child| freeze_tree(key); freeze_tree(child) }
        when Array
          value.each { |child| freeze_tree(child) }
        end
        value.freeze
      end
    end

    def self.from_draft(draft:, registry:, publication_key:, rules:,
      registration_opens_at:, registration_closes_at:, timezone:)
      raise Invalid, :invalid_draft unless Hash === draft
      settings = Data.copy(SETTINGS.to_h { |key| [key, draft[key]] })
      settings['participant_limit'] = draft['participant_limit'] if draft.key?('participant_limit')
      ROUND_SETTINGS.each { |key| settings[key] = draft[key] } if ROUND_SETTINGS.any? { |key| draft.key?(key) }
      WIN_SETTINGS.each{|key|settings[key]=draft[key] if draft.key?(key)}
      if draft['format'] == 'groups_knockout' && ['automatic_cross_groups_v1', 'automatic_compact_groups_v2'].include?(draft['group_advancement'])
        settings.merge!('group_advancement' => draft['group_advancement'], 'group_count' => nil, 'places_per_group' => nil)
      elsif draft['format'] == 'groups_knockout' && GROUP_SETTINGS.any? { |key| !draft[key].nil? }
        settings.merge!(Data.copy(GROUP_SETTINGS.to_h { |key| [key, draft[key]] }))
      end
      schedule = Data.copy({ 'windows' => draft['windows'] })
      optional = draft.key?('starts_at')
      schedule.merge!('starts_at' => draft['starts_at'], 'deadline_at' => draft.fetch('deadline_at', 0)) if optional
      schedule['daily_hours']=Data.copy(draft['daily_hours']) if optional && draft['daily_hours']
      row = Data.copy({ 'publication_key' => publication_key, 'schema_version' => optional ? 2 : 1,
        'title' => draft['name'], 'game' => draft['game_id'], 'rules' => rules,
        'settings_json' => JSON.generate(settings), 'schedule_json' => JSON.generate(schedule),
        'registration_opens_at' => registration_opens_at,
        'registration_closes_at' => registration_closes_at, 'timezone' => timezone }, max_bytes: 160_000)
      validate_content(row, settings, schedule, registry)
      row['settings_json'] = JSON.generate(settings)
      new(row)
    end

    def self.validate_content(row, settings, schedule, registry)
      Data.key!(row['publication_key'])
      raise Invalid, :schema_version unless Integer === row['schema_version'] && [1, 2].include?(row['schema_version'])
      Data.text!(row['title'], bytes: 1024, length: 256)
      Data.text!(row['rules'], bytes: MAX_RULES_BYTES, multiline: true)
      Data.text!(row['timezone'], bytes: 64)
      Data.text!(row['game'], bytes: 32)
      raise Invalid, :invalid_game unless row['game'].match?(/\A[a-z0-9_]+\z/)
      opens, closes = row.values_at('registration_opens_at', 'registration_closes_at')
      if TournamentTiming.optional?(row)
        TournamentTiming.validate!(row, schedule)
      elsif !(Data.integer?(opens) && Data.integer?(closes) && closes > opens)
        raise Invalid, :invalid_registration_time
      end
      shapes = [SETTINGS.sort, (SETTINGS + GROUP_SETTINGS).sort, (SETTINGS + ADVANCEMENT_SETTINGS).sort]
      raise Invalid, :invalid_settings unless Hash === settings
      limit = settings['participant_limit']
      raise Invalid, :invalid_participant_limit if settings.key?('participant_limit') && !(Integer === limit && limit.between?(2, 256))
      unless Hash === settings && shapes.include?((settings.keys - ['participant_limit'] - ROUND_SETTINGS - WIN_SETTINGS).sort) &&
          Hash === schedule && (TournamentTiming.optional?(row) || schedule.keys == ['windows'])
        raise Invalid, :invalid_settings
      end
      if ROUND_SETTINGS.any? { |key| settings.key?(key) }
        raise Invalid, :invalid_rematch unless settings['format'] == 'groups_knockout' && ROUND_SETTINGS.all? { |key| [true, false].include?(settings[key]) }
      end
      WIN_SETTINGS.each do |key|
        next unless settings.key?(key)
        unless settings['format']=='groups_knockout' && settings[key].is_a?(Integer) && settings[key].between?(1,99) && settings[key.sub('wins_to','rematch')]==false
          raise Invalid,:invalid_win_target
        end
      end
      # DraftDetails sprawdza cywilne okna i pairing; jego lokalne 2..8 nie jest
      # kontraktem każdej gry. Liczebność sprawdza niżej rzeczywisty model gry.
      DraftDetails.validate!(settings.merge(schedule).merge('participants' => [], 'players_per_match' => nil))
      raise Invalid, :missing_windows if schedule['windows'].empty? && !TournamentTiming.optional?(row)
      unless %w[round_robin groups_knockout].include?(settings['format']) &&
          [true, false].include?(settings['rematch']) && settings['pairing'] && settings['players_per_match']
        raise Invalid, :incomplete_settings
      end
      if GROUP_SETTINGS.any? { |key| settings.key?(key) }
        automatic = ['automatic_cross_groups_v1', 'automatic_compact_groups_v2'].include?(settings['group_advancement'])
        valid = automatic ? GROUP_SETTINGS.all? { |key| settings[key].nil? } : GROUP_SETTINGS.all? { |key| settings[key].is_a?(Integer) }
        unless settings['format'] == 'groups_knockout' && valid
          raise Invalid, :invalid_group_configuration
        end
      end
      validate_game(row['game'], settings, registry)
    rescue DraftDetails::Invalid => error
      raise Invalid, error.code
    end
    private_class_method :validate_content

    def self.validate_game(id, settings, registry)
      game = registry.build(id)
      raise Invalid, :invalid_game unless game
      count = settings['players_per_match']
      unless Integer === count && count.between?(game.minimum_players, game.maximum_players)
        raise Invalid, :invalid_players_per_match
      end
      options = Data.copy(settings['game_options'])
      raise Invalid, :invalid_options unless Hash === options
      defaults = game.default_options
      # Content selectors are used while constructing their dependent choices.
      # Reject an unknown language before asking the game to load that content;
      # validate the remaining, language-dependent choices below.
      if game.respond_to?(:content_language_option_key) && (key = game.content_language_option_key)
        definition = game.effective_option_definitions.find { |item| item.key.to_s == key.to_s }
        if options.key?(key.to_s) && definition
          raise Invalid, :invalid_options unless definition.choices.to_a.any? { |choice| choice.value.eql?(options[key.to_s]) }
        end
      end
      definitions = game.effective_option_definitions(options).to_h { |definition| [definition.key.to_s, definition] }
      # Nie pozwalamy normalizatorom zamieniać obcych typów w pozornie zdrowe opcje.
      options.each do |key, value|
        definition = definitions[key]
        raise Invalid, :invalid_options if definition && !GameRoomOptionValues.valid?(definition, value)
      end
      metadata = options.reject { |key, _value| definitions.key?(key) }
      prototypes = [defaults]
      unless (metadata.keys - defaults.keys - ['team_seats']).empty?
        # New-game markers need not be editable controls or replay defaults.
        # Never let untrusted metadata authorize itself through a permissive
        # normalizer. Only validated controls seed these game-owned prototypes.
        controls = Data.copy(options.select { |key, _value| definitions.key?(key) })
        creation = Data.copy(game.table_creation_options(controls))
        prototypes << creation << Data.copy(game.new_game_options(Data.copy(creation)))
      end
      metadata.each do |key, value|
        same_type = prototypes.any? do |values|
          values.key?(key) && (values[key].class == value.class ||
            ([true, false].include?(values[key]) && [true, false].include?(value)))
        end
        seats = key == 'team_seats' && Array === value && value.all? { |seat| Integer === seat }
        raise Invalid, :invalid_options unless same_type || seats
      end
      normalized = Data.copy(game.normalize_options(options))
      unchanged = options.all? do |key, value|
        definition = definitions[key]
        if definition
          GameRoomOptionValues.read(definition, normalized).eql?(value)
        else
          normalized.key?(key) && normalized[key].eql?(value)
        end
      end
      raise Invalid, :invalid_options unless unchanged
      raise Invalid, :game_validation if game.validation_error(normalized, player_count: count)
      settings['game_options'] = normalized
    end
    private_class_method :validate_game

    def self.parse_document(value)
      unless Data.text?(value) && value.bytesize <= MAX_JSON_BYTES
        raise Invalid, :invalid_json
      end
      parsed = StrictJson.parse(value, max_nesting: 8)
      Data.copy(parsed)
    rescue StrictJson::IncompatibleRuntime
      raise Invalid, :incompatible_runtime
    rescue JSON::ParserError, EncodingError
      raise Invalid, :invalid_json
    end
    private_class_method :parse_document

    def self.decode(row, registry)
      content = COLUMNS.to_h { |column| [column, row[column]] }
      settings = parse_document(content['settings_json'])
      schedule = parse_document(content['schedule_json'])
      original_settings = Data.copy(settings)
      validate_content(content, settings, schedule, registry)
      raise Invalid, :incomplete_game_options unless settings == original_settings
      content['settings_json'] = JSON.generate(settings)
      content['schedule_json'] = JSON.generate(schedule)
      content.merge(Data.metadata(row))
    end
    private_class_method :decode

    # complete musi pochodzić z pełnego odczytu bramki; krótka strona to za mało.
    # __insertion_time: wyłącznie integer epoch seconds UTC. Wymaga potwierdzenia
    # backendu, podobnie jak autentyczność i niezmienność trzech pól systemowych.
    def self.project(rows:, registry:, complete:)
      entries = Data.entries(rows, complete: complete, key_name: 'publication_key') { |row| decode(row, registry) }
      groups, diagnostics = Data.reconcile(entries) { |row| COLUMNS.map { |column| row[column] } }
      announcements = groups.map do |group|
        canonical = group.min_by { |row| row['__id'] }
        canonical.merge('alias_ids' => group.map { |row| row['__id'] }.uniq.sort)
      end.sort_by { |row| row['__id'] }
      Data.freeze_tree({ 'announcements' => announcements, 'diagnostics' => diagnostics })
    end

    def initialize(row)
      @row = Data.freeze_tree(row)
      freeze
    end
    private_class_method :new

    def to_row
      @row
    end
  end
end
