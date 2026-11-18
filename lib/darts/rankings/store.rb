require 'thread'
require 'json'
require_relative 'result'
require_relative 'record_codec'
require_relative '../../game_room_analytics_client'

module GameRoomDartsRankings
  class Store
    CACHE_SECONDS = 15
    MAX_PUBLIC_ROWS = 4096
    MAX_PERSONAL_ROWS = 128
    MAX_CACHED_RESULTS = MAX_PUBLIC_ROWS * RECORDS_PER_PLAYER
    LEGACY_RECORDS_VERSION = 1
    RECORDS_VERSION = 2
    CATEGORIES = %w[triple average].freeze
    OPERATION_KEY = /\A[0-9a-f]{32}\z/

    def initialize(app_uuid:, user:, client: nil, api: nil, current_user: -> { Session.name },
      feedback_requested: ->(_key) { false }, on_feedback: nil, on_progression: nil,
      monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, enabled: -> { true })
      @app_uuid, @user, @current_user = app_uuid.to_s, user.to_s.dup.freeze, current_user
      @client, @api = client || EltenLink::Client.new, api || EltenLink::Apps
      @feedback_requested, @on_feedback = feedback_requested, on_feedback
      @on_progression = on_progression
      @monotonic, @lock = monotonic, Mutex.new
      @enabled = enabled
    end

    def write_batch(payloads, cancellation_token: nil)
      @lock.synchronize do
        @cache = nil
        public_table = personal_table = nil
        accepted = 0
        payloads.first(25).each do |source|
          check!(cancellation_token)
          case source['kind']
          when 'darts_result'
            validate_result_source!(source)
            payload = source.slice(*Result::FIELDS)
            Result.parse(payload)
            personal_table ||= personal_table_for(cancellation_token)
            personal_record, unlocked = write_personal(personal_table, payload, cancellation_token)
            placements = []
            if source['publish'] == true
              public_table ||= public_table_for(cancellation_token)
              write_public(public_table, payload, cancellation_token)
              placements = public_placements(public_table, payload, cancellation_token)
            end
            deliver_feedback(payload, personal_record, placements, unlocked)
          when 'darts_publish_saved'
            validate_operation_source!(source)
            personal_table ||= personal_table_for(cancellation_token)
            records, = read_records(personal_table, cancellation_token, public: false)
            unless records.empty?
              public_table ||= public_table_for(cancellation_token)
              update_records(public_table, records, cancellation_token, public: true)
            end
          when 'darts_withdraw'
            validate_operation_source!(source)
            public_table ||= public_table_for(cancellation_token)
            withdraw_public(public_table, cancellation_token)
          else
            raise InvalidResult, 'Invalid Darts ranking operation'
          end
          accepted += 1
        end
        accepted
      end
    end

    def ranking(difficulty:, category:, limit: DISPLAY_LIMIT, cancellation_token: nil, fresh: false)
      unless Result::DIFFICULTIES.include?(difficulty) && CATEGORIES.include?(category)
        raise ArgumentError, 'Invalid Darts ranking scope'
      end
      raise ArgumentError, 'Invalid Darts ranking limit' unless limit.is_a?(Integer) && limit.between?(1, 500)
      @lock.synchronize do
        @cache = nil if fresh
        table = public_table_for(cancellation_token)
        key = [difficulty, category, limit]
        entry = @cache&.[](key)
        return copy(entry[:value]) if entry && entry[:at] + CACHE_SECONDS > @monotonic.call
        rows = public_rows(table, cancellation_token)
        candidates = public_candidates(rows, difficulty, category)
        value = ranked_rows(candidates, category).first(limit)
        if candidates.length <= MAX_CACHED_RESULTS
          @cache ||= {}
          @cache.clear if @cache.length >= 8
          @cache[key] = {at: @monotonic.call, value: copy(value)}
        end
        value
      end
    end

    def highest_unlocked_difficulty(cancellation_token: nil)
      @lock.synchronize do
        table = personal_table_for(cancellation_token)
        _records, _rows, highest = read_records(table, cancellation_token, public: false)
        publish_progression(highest)
        highest
      end
    end

    private

    def validate_result_source!(source)
      expected = Result::FIELDS + %w[kind match publish]
      unless source.is_a?(Hash) && source.keys.sort == expected.sort && source['match'] == source['result_key'] &&
          [true, false].include?(source['publish'])
        raise InvalidResult, 'Invalid Darts ranking result operation'
      end
    end

    def validate_operation_source!(source)
      unless source.is_a?(Hash) && source.keys.sort == %w[kind match] && OPERATION_KEY.match?(source['match'].to_s)
        raise InvalidResult, 'Invalid Darts ranking account operation'
      end
    end

    def deliver_feedback(payload, personal_record, placements, unlocked)
      return unless @on_feedback && @feedback_requested.call(payload.fetch('result_key'))
      @on_feedback.call({'result_key'=>payload.fetch('result_key'), 'user'=>@user,
        'difficulty'=>payload.fetch('difficulty'), 'personal_record'=>personal_record,
        'placements'=>placements, 'unlocked_difficulty'=>unlocked})
    end

    def public_placements(table, payload, token)
      rows = public_rows(table, token)
      CATEGORIES.filter_map do |category|
        ranked = ranked_rows(public_candidates(rows, payload.fetch('difficulty'), category), category)
        index = ranked.index do |row|
          GameRoomParticipants.same?(row['user'], @user) && row['result_key'] == payload['result_key']
        end
        current = ranked[index] if index
        {'category'=>category, 'place'=>current.fetch('place')} if current && index < DISPLAY_LIMIT
      end
    end

    def write_public(table, payload, token)
      update_records(table, records_for(payload), token, public: true).first
      true
    end

    def write_personal(table, payload, token)
      records, unlocked = update_records(table, records_for(payload), token, public: false,
        progression_result: payload)
      triple = records.dig(payload.fetch('difficulty'), 'triple', 0)
      personal = triple && triple['key'] == payload['result_key'] ?
        {'score'=>triple.fetch('score'), 'time_ms'=>triple.fetch('time_ms')} : nil
      [personal, unlocked]
    end

    def update_records(table, incoming, token, public:, progression_result: nil)
      records, rows, highest = read_records(table, token, public: public)
      merged = merge_records(records, incoming)
      next_highest = public ? highest : GameRoomDarts::Difficulty.unlock_after(highest, progression_result)
      unlocked = next_highest == highest ? nil : next_highest
      if merged == records && rows.length <= 1 && unlocked == nil
        publish_progression(next_highest) unless public
        return [records, nil]
      end
      encoded = RecordCodec.encode(merged,
        unlocked_level: public ? nil : GameRoomDarts::Difficulty.level(next_highest))
      raise Unavailable, 'Darts ranking records are too large' if encoded.bytesize > Schema::RECORDS_BYTES
      # The API has no compare-and-swap. Never overwrite a snapshot read by a
      # concurrent client: append the merged top three, then retire ONLY the
      # exact snapshots included in it. Concurrent appenders retain separate
      # documents; readers union them and the next write compacts them safely.
      values = {'version'=>RECORDS_VERSION, 'records_json'=>encoded}
      row = table.insert(values)
      check!(token)
      written = validate_record_document!(row, public: public, access: false, author: false)
      raise Unavailable, 'Darts ranking write was not confirmed' unless written.records == merged &&
        rows.none? { |old| old['__id'] == row['__id'] } &&
        (public || document_unlocked_difficulty(written) == next_highest)
      remove_rows(table, rows, token)
      publish_progression(next_highest) unless public
      [merged, unlocked]
    end

    def withdraw_public(table, token)
      3.times do
        _records, rows = read_records(table, token, public: true)
        return true if rows.empty?
        remove_rows(table, rows, token)
      end
      _records, rows = read_records(table, token, public: true)
      return true if rows.empty?
      raise Unavailable, 'Darts public ranking withdrawal was not confirmed'
    end

    def remove_rows(table, rows, token)
      rows.map { |row| row.fetch('__id') }.each_slice(100) do |ids|
        check!(token)
        count = table.delete_many(ids)
        check!(token)
        # Another compactor may already have retired the same old snapshots.
        raise Unavailable, 'Invalid Darts compaction response' unless count.is_a?(Integer) && count.between?(0, ids.length)
      end
    end

    def read_records(table, token, public:)
      records, rows, cursor = {}, [], 0
      highest = GameRoomDarts::Difficulty::BASE_HIGHEST
      loop do
        check!(token)
        page = table.select(where: {'__insertion_user'=>@user, '__id'=>{'gte'=>cursor + 1}},
          order: [['__id', 'asc']], include_access: true, limit: @limit)
        check!(token)
        raise Unavailable, 'Invalid Darts personal record page' unless page.is_a?(Array) && page.length <= @limit
        break if page.empty?
        page.each do |row|
          document = validate_record_document!(row, public: public, access: true, author: true)
          raise Unavailable, 'Unordered Darts personal record page' unless row['__id'] > cursor
          cursor = row['__id']
          records = merge_records(records, document.records)
          highest = GameRoomDarts::Difficulty.highest(highest, document_unlocked_difficulty(document)) unless public
          rows << row
          raise Unavailable, 'Darts personal records are too large' if rows.length > MAX_PERSONAL_ROWS
        end
      end
      [records, rows, highest]
    end

    def records_for(payload)
      difficulty = payload.fetch('difficulty')
      {difficulty=>CATEGORIES.to_h { |category| [category, [record_candidate(payload, category)]] }}
    end

    def record_candidate(payload, category)
      common = {'key'=>payload.fetch('result_key'), 'played_at'=>payload.fetch('played_at')}
      if category == 'triple'
        common.merge('score'=>payload.fetch('best_round_score'), 'time_ms'=>payload.fetch('best_round_time_ms'))
      else
        common.merge('total_score'=>payload.fetch('total_score'), 'throw_count'=>payload.fetch('throw_count'),
          'total_time_ms'=>payload.fetch('total_time_ms'))
      end
    end

    def merge_records(current, incoming)
      merged = copy(current)
      incoming.each do |difficulty, scope|
        target = merged[difficulty] ||= {}
        scope.each do |category, candidates|
          values = Array(target[category]).map(&:dup)
          candidates.each do |candidate|
            previous = values.find { |entry| entry['key'] == candidate['key'] }
            raise InvalidResult, 'Conflicting Darts ranking result' if previous && previous != candidate
            values << candidate.dup unless previous
          end
          values.sort! { |left, right| compare_entries(left, right, category) }
          target[category] = values.first(RECORDS_PER_PLAYER)
        end
      end
      validate_record_set!(merged)
    end

    def validate_record_row!(row, public:, access:, author:)
      validate_record_document!(row, public:public, access:access, author:author).records
    end

    def validate_record_document!(row, public:, access:, author:)
      valid = row.is_a?(Hash) && row['__id'].is_a?(Integer) && row['__id'].positive? &&
        [LEGACY_RECORDS_VERSION, RECORDS_VERSION].include?(row['version']) && row['records_json'].is_a?(String) &&
        row['records_json'].bytesize <= Schema::RECORDS_BYTES
      raise Unavailable, 'Invalid Darts record row' unless valid
      if author
        user = row['__insertion_user']
        valid &&= valid_user?(user) && (!access || GameRoomParticipants.same?(user, @user))
      end
      valid &&= row.dig('__access', 'owner') == true if access
      raise Unavailable, public ? 'Invalid Darts public record' : 'Invalid Darts personal record' unless valid
      document = RecordCodec.decode_document(row['records_json'], version:row['version'])
      if row['version'] == RECORDS_VERSION &&
          (public ? !document.unlocked_level.nil? : document.unlocked_level.nil?)
        raise Unavailable, 'Invalid Darts progression scope'
      end
      validate_record_set!(document.records)
      document
    rescue JSON::ParserError, EncodingError, RecordCodec::Invalid
      raise Unavailable, public ? 'Invalid Darts public record data' : 'Invalid Darts personal record data'
    end

    def document_unlocked_difficulty(document)
      document.unlocked_level ? GameRoomDarts::Difficulty::IDS.fetch(document.unlocked_level) :
        GameRoomDarts::Difficulty::BASE_HIGHEST
    end

    def publish_progression(value)
      @on_progression&.call(GameRoomDarts::Difficulty.normalize_highest(value))
    end

    def validate_record_set!(records)
      unless records.is_a?(Hash) && (records.keys - Result::DIFFICULTIES).empty?
        raise Unavailable, 'Invalid Darts record data'
      end
      records.each_value do |scope|
        unless scope.is_a?(Hash) && (scope.keys - CATEGORIES).empty? && !scope.empty?
          raise Unavailable, 'Invalid Darts record scope'
        end
        scope.each do |category, entries|
          unless entries.is_a?(Array) && entries.length.between?(1, RECORDS_PER_PLAYER)
            raise Unavailable, 'Invalid Darts record list'
          end
          entries.each { |entry| validate_record_entry!(entry, category) }
          raise Unavailable, 'Duplicate Darts record' unless entries.map { |entry| entry['key'] }.uniq.length == entries.length
          unless entries.each_cons(2).all? { |left, right| compare_entries(left, right, category).negative? }
            raise Unavailable, 'Unordered Darts records'
          end
        end
      end
      records
    end

    def validate_record_entry!(record, category)
      base = record.is_a?(Hash) && record['key'].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(record['key']) &&
        Result.valid_epoch?(record['played_at'])
      valid = if category == 'triple'
        base && record.keys.sort == %w[key played_at score time_ms] &&
          Result.integer_between?(record['score'], 0, 300) && Result.integer_between?(record['time_ms'], 0, 1_800_000)
      else
        base && record.keys.sort == %w[key played_at throw_count total_score total_time_ms] &&
          record['throw_count'].is_a?(Integer) && record['throw_count'].between?(3, 300) &&
          (record['throw_count'] % 3).zero? &&
          Result.integer_between?(record['total_score'], 0, record['throw_count'] * 100) &&
          Result.integer_between?(record['total_time_ms'], 0, record['throw_count'] * 600_000)
      end
      raise Unavailable, 'Invalid Darts record entry' unless valid
    end

    def compare_entries(left, right, category)
      comparison = if category == 'triple'
        (right['score'] <=> left['score']).nonzero? || (left['time_ms'] <=> right['time_ms'])
      else
        (right['total_score'] * left['throw_count'] <=> left['total_score'] * right['throw_count']).nonzero? ||
          (left['total_time_ms'] * right['throw_count'] <=> right['total_time_ms'] * left['throw_count'])
      end
      comparison.nonzero? || (left['played_at'] <=> right['played_at']).nonzero? || (left['key'] <=> right['key'])
    end

    def public_rows(table, token)
      cursor, rows = 0, []
      loop do
        page = table.select(where: {'__id'=>{'gte'=>cursor + 1}}, columns: %w[version records_json __id __insertion_user],
          order: [['__id', 'asc']], limit: @limit)
        check!(token)
        unless page.is_a?(Array) && page.length <= @limit
          raise Unavailable, 'Invalid Darts public ranking page'
        end
        break if page.empty?
        page.each do |row|
          validate_record_row!(row, public: true, access: false, author: true)
          raise Unavailable, 'Darts public ranking pagination did not advance' unless row['__id'] > cursor
          cursor = row['__id']
        end
        rows.concat(page)
        raise Unavailable, 'Darts public ranking is too large to read safely' if rows.length > MAX_PUBLIC_ROWS
      end
      rows
    end

    def public_candidates(rows, difficulty, category)
      rows.group_by { |row| row.fetch('__insertion_user').downcase }.flat_map do |_user, snapshots|
        sources = {}
        records = snapshots.reduce({}) do |merged, row|
          value = validate_record_row!(row, public: true, access: false, author: true)
          value.dig(difficulty, category).to_a.each { |entry| sources[entry['key']] ||= row }
          merge_records(merged, value)
        end
        Array(records.dig(difficulty, category)).each_with_index.map do |entry, slot|
          public_candidate(entry, difficulty, category, sources.fetch(entry['key']), slot)
        end
      end
    end

    def public_candidate(entry, difficulty, category, row, slot)
      candidate = {'result_key'=>entry.fetch('key'), 'difficulty'=>difficulty,
        'played_at'=>entry.fetch('played_at'), 'user'=>row.fetch('__insertion_user'),
        '__id'=>row.fetch('__id'), '__slot'=>slot}
      if category == 'triple'
        candidate.merge('best_round_score'=>entry.fetch('score'), 'best_round_time_ms'=>entry.fetch('time_ms'))
      else
        candidate.merge('total_score'=>entry.fetch('total_score'), 'throw_count'=>entry.fetch('throw_count'),
          'total_time_ms'=>entry.fetch('total_time_ms'))
      end
    end

    def ranked_rows(rows, category)
      previous = nil
      place = 0
      rows.sort { |left, right| compare_public(left, right, category) }.each_with_index.map do |row, index|
        current = metric(row, category)
        place = index + 1 if previous != current
        previous = current
        row.reject { |key, _| key.start_with?('__') }.merge('place'=>place)
      end
    end

    def compare_public(left, right, category)
      comparison = if category == 'triple'
        (right['best_round_score'] <=> left['best_round_score']).nonzero? ||
          (left['best_round_time_ms'] <=> right['best_round_time_ms'])
      else
        (right['total_score'] * left['throw_count'] <=> left['total_score'] * right['throw_count']).nonzero? ||
          (left['total_time_ms'] * right['throw_count'] <=> right['total_time_ms'] * left['throw_count'])
      end
      comparison.nonzero? || (left['played_at'] <=> right['played_at']).nonzero? ||
        (left['__id'] <=> right['__id']).nonzero? || (left['__slot'] <=> right['__slot'])
    end

    def metric(row, category)
      if category == 'triple'
        [row['best_round_score'], row['best_round_time_ms']]
      else
        [Rational(row['total_score'], row['throw_count']), Rational(row['total_time_ms'], row['throw_count'])]
      end
    end

    def public_table_for(token)
      check!(token)
      client = GameRoomAnalyticsClient.new(@client, app_uuid: @app_uuid, tables: [Schema::TABLE],
        error: Unavailable, cancellation_token: token)
      definition = @api.schema(client, @app_uuid).dig('data', 'server', 'tables', Schema::TABLE)
      check!(token)
      permissions = definition.to_h.fetch('permissions', {}).to_h
      unless definition.is_a?(Hash) && definition['visibility'] == 'public' && definition['unique_per_user'] == false &&
          definition['columns'] == Schema::COLUMNS && %w[select insert delete].all? { |name| permissions[name] == true } &&
          %w[update creator_share guest_share].none? { |name| permissions[name] == true }
        raise Unavailable, 'Darts rankings are not available'
      end
      @limit = [[definition.dig('limits', 'max_select_limit').to_i, 1].max, 1000].min
      @api.table(client, @app_uuid, Schema::TABLE)
    end

    def personal_table_for(token)
      check!(token)
      client = GameRoomAnalyticsClient.new(@client, app_uuid: @app_uuid, tables: [Schema::PERSONAL_TABLE],
        error: Unavailable, cancellation_token: token)
      definition = @api.schema(client, @app_uuid).dig('data', 'server', 'tables', Schema::PERSONAL_TABLE)
      check!(token)
      permissions = definition.to_h.fetch('permissions', {}).to_h
      unless definition.is_a?(Hash) && definition['visibility'] == 'shared' && definition['unique_per_user'] == false &&
          definition['columns'] == Schema::PERSONAL_COLUMNS && %w[select insert delete].all? { |name| permissions[name] == true } &&
          %w[update creator_share guest_share].none? { |name| permissions[name] == true }
        raise Unavailable, 'Darts personal records are not available'
      end
      @limit = [[definition.dig('limits', 'max_select_limit').to_i, 1].max, 1000].min
      @api.table(client, @app_uuid, Schema::PERSONAL_TABLE)
    end

    def valid_user?(user)
      user.is_a?(String) && user.valid_encoding? && !user.strip.empty? && user == user.strip &&
        user.bytesize <= 64 && !GameRoomParticipants.bot?(user)
    end

    def copy(value); Marshal.load(Marshal.dump(value)); end

    def check!(token)
      token&.raise_if_cancelled!
      raise Unavailable, 'Darts server table access is unavailable' unless @enabled.call
      raise Unavailable, 'Darts ranking account changed' if @user.empty? ||
        !GameRoomParticipants.same?(@user, @current_user.call)
    end
  end
end
