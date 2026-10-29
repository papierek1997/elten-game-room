require 'thread'
require_relative 'result'
require_relative 'personal'
require_relative '../game_room_analytics_client'

module GameRoomSportsRankings
  module Schema
    TABLE = 'sports_match_results'.freeze
    COLUMNS = {'match_key'=>'string:64', 'game'=>'string:32', 'mode'=>'string:8',
      'finished_at'=>'integer', 'day_key'=>'integer', 'result_json'=>'string:4096'}.freeze
    TABLES = {TABLE=>{'visibility'=>'public', 'columns'=>COLUMNS,
      'permissions'=>%w[select insert], 'indexes'=>[['match_key'], ['game', 'mode', 'day_key']],
      'limits'=>{'max_select_limit'=>1000}}}.freeze
  end

  class Store
    CACHE_SECONDS = 15
    MAX_CACHED_MATCHES = 4096
    attr_reader :app_uuid

    def initialize(app_uuid:, user:, client: nil, api: nil, current_user: -> { Session.name },
      monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @app_uuid, @user, @current_user = app_uuid.to_s, user.to_s.dup.freeze, current_user
      @client, @api = client || EltenLink::Client.new, api || EltenLink::Apps
      @monotonic, @lock = monotonic, Mutex.new
    end

    def write_batch(payloads, cancellation_token: nil)
      @lock.synchronize do
        @cache = nil # Also invalidate an uncertain write.
        table = table_for(cancellation_token)
        accepted_count, started = 0, @monotonic.call
        payloads.first(25).each do |payload|
          break if accepted_count.positive? && @monotonic.call - started >= 1.0
          payload = payload.slice(*Result::FIELDS)
          check!(cancellation_token)
          Result.parse(payload)
          previous = table.select(where: {'match_key'=>payload.fetch('match_key')},
            columns: Result::FIELDS + ['__id'], order: [['__id', 'asc']], limit: 1)
          check!(cancellation_token)
          validate_rows!(previous, limit: 1)
          if previous.any?
            raise InvalidResult, 'Conflicting ranked match' unless (Result::FIELDS - %w[finished_at day_key]).all? { |field| previous.first[field] == payload[field] }
            accepted_count += 1
            next
          end
          accepted = table.insert(payload)
          check!(cancellation_token)
          validate_rows!([accepted], limit: 1)
          raise Unavailable, 'Ranked match write was not confirmed' unless Result::FIELDS.all? { |field| accepted[field] == payload[field] }
          accepted_count += 1
        end
        accepted_count
      end
    end

    def report(game:, mode:, from_day: nil, to_day:, cancellation_token: nil, fresh: false)
      raise ArgumentError, 'Invalid leaderboard scope' unless Result::GAMES.include?(game) && %w[singles doubles].include?(mode)
      raise ArgumentError, 'Invalid leaderboard dates' unless to_day.is_a?(Integer) && (from_day.nil? || from_day.is_a?(Integer) && from_day <= to_day)
      cached([:report, game, mode, from_day, to_day], cancellation_token, fresh) do |table|
        totals, count = {}, 0
        each_match(table, game, mode, from_day, to_day, cancellation_token) do |outcome|
          outcome.fetch('sides').each_with_index do |side, index|
            scored, conceded = side.fetch('goals'), outcome.fetch('sides').fetch(1 - index).fetch('goals')
            won = outcome.fetch('winner') == index
            side.fetch('players').each do |name|
              total = totals[name.downcase] ||= {'user'=>name, 'won'=>0, 'lost'=>0, 'scored'=>0, 'conceded'=>0}
              total[won ? 'won' : 'lost'] += 1
              total['scored'] += scored
              total['conceded'] += conceded
            end
          end
          count += 1
        end
        [totals.values.sort_by { |row| row.fetch('user').downcase }, count]
      end
    end

    # A player's own counts and head-to-head counts per period (see Personal).
    def personal(game:, mode:, today:, player: @user, cancellation_token: nil, fresh: false)
      raise ArgumentError, 'Invalid leaderboard scope' unless Result::GAMES.include?(game) && %w[singles doubles].include?(mode)
      to_day = today.strftime('%Y%m%d').to_i
      cached([:personal, game, mode, to_day, player.to_s.downcase], cancellation_token, fresh) do |table|
        matches = []
        each_match(table, game, mode, nil, to_day, cancellation_token) do |outcome, day|
          matches << outcome.merge('day_key'=>day)
        end
        [Personal.summary(matches, user: player.to_s, today: today), matches.size]
      end
    end

    private

    # The block returns [value, match count]; large reads are not cached. A few
    # scopes are kept, so the report and its head-to-head list do not evict each other.
    CACHED_SCOPES = 4
    def cached(scope, token, fresh)
      @lock.synchronize do
        @cache = nil if fresh
        table = table_for(token)
        entry = @cache&.[](scope)
        return Marshal.load(Marshal.dump(entry[:value])) if entry && entry[:at] + CACHE_SECONDS > @monotonic.call
        value, count = yield table
        if count <= MAX_CACHED_MATCHES
          @cache ||= {}
          @cache.delete(scope)
          @cache.shift while @cache.size >= CACHED_SCOPES
          @cache[scope] = {at: @monotonic.call, value: Marshal.load(Marshal.dump(value))}
        end
        value
      end
    end

    # Yields each canonical match in the period once, with its Warsaw day, from
    # a snapshot bounded by the highest server ID at the start of the read.
    def each_match(table, game, mode, from_day, to_day, token)
      high = table.select(columns: ['__id'], order: [['__id', 'desc']], limit: 1)
      check!(token)
      unless high.is_a?(Array) && high.size <= 1 && high.all? { |row| positive_id?(row['__id']) }
        raise Unavailable, 'Invalid leaderboard snapshot'
      end
      snapshot = high.empty? ? 0 : high.first.fetch('__id')
      cursor = 0
      while cursor < snapshot
        where = {'game'=>game, 'mode'=>mode, '__id'=>{'gte'=>cursor + 1}}
        where['day_key'] = day_scope(from_day,to_day)
        # Dates are inclusive in Europe/Warsaw; use server-backed match time.
        rows = table.select(where: where, columns: Result::FIELDS + ['__id'], order: [['__id', 'asc']], limit: @limit)
        check!(token)
        validate_rows!(rows, limit: @limit)
        break if rows.empty?
        raise Unavailable, 'Leaderboard pagination did not advance' unless rows.map { |row| row['__id'] }.each_cons(2).all? { |a, z| z > a } &&
          rows.first['__id'] > cursor
        rows = rows.take_while { |row| row['__id'] <= snapshot }
        break if rows.empty?
        # Canonical IDs are looked up in batches, never once per player.
        first_ids = canonical_ids(table, rows.map { |row| row.fetch('match_key') }.uniq, token, snapshot)
        rows.each do |row|
          next unless row['__id'] == first_ids.fetch(row['match_key'])
          day = Result.day(row.fetch('finished_at'))
          next if day > to_day || from_day && day < from_day
          yield Result.parse(row), day
        end
        cursor = rows.last.fetch('__id')
      end
    end

    def positive_id?(value); value.is_a?(Integer) && value.positive?; end

    def day_scope(first,last)
      last_date = Date.strptime(last.to_s,'%Y%m%d')
      return {'lte'=>last} unless first
      first_date = Date.strptime(first.to_s,'%Y%m%d')
      raise ArgumentError, 'Invalid leaderboard period' unless (last_date-first_date).between?(0,366)
      {'in'=>(first_date..last_date).map { |date| date.strftime('%Y%m%d').to_i }}
    end

    def check!(token)
      token&.raise_if_cancelled!
      raise Unavailable, 'Leaderboard account changed' if @user.empty? || !GameRoomParticipants.same?(@user, @current_user.call)
    end

    def table_for(token)
      check!(token)
      client = GameRoomAnalyticsClient.new(@client, app_uuid: @app_uuid, tables: [Schema::TABLE], error: Unavailable, cancellation_token: token)
      definition = @api.schema(client, @app_uuid).dig('data', 'server', 'tables', Schema::TABLE)
      check!(token)
      unless definition.is_a?(Hash) && definition['visibility'] == 'public' && definition['unique_per_user'] == false && definition['columns'] == Schema::COLUMNS &&
          %w[select insert].all? { |permission| definition.fetch('permissions').to_h[permission] == true }
        raise Unavailable, 'Sports player statistics are not available'
      end
      @limit = [[definition.dig('limits', 'max_select_limit').to_i, 1].max, 1000].min
      @api.table(client, @app_uuid, Schema::TABLE)
    end

    def validate_rows!(rows, limit:)
      raise Unavailable, 'Invalid leaderboard rows' unless rows.is_a?(Array) && rows.size <= limit
      rows.each do |row|
        raise Unavailable, 'Invalid leaderboard record ID' unless row.is_a?(Hash) && positive_id?(row['__id'])
        Result.parse(row)
      end
    end

    def canonical_ids(table, keys, token, snapshot)
      keys.each_slice([100, @limit].min).each_with_object({}) do |chunk, all|
        check!(token)
        found, offset = {}, 0
        while found.size < chunk.size
          rows = table.select(where: {'match_key'=>{'in'=>chunk}, '__id'=>{'lte'=>snapshot}}, columns: ['match_key'],
            group_by: ['match_key'], aggregates: {'first_id'=>{'function'=>'min', 'column'=>'__id'}},
            order: [['match_key', 'asc']], limit: chunk.size, offset: offset)
          check!(token)
          unless rows.is_a?(Array) && !rows.empty? && rows.size <= chunk.size - found.size &&
              rows.all? { |row| row.is_a?(Hash) && chunk.include?(row['match_key']) && !found.key?(row['match_key']) &&
                positive_id?(row['first_id']) && row['first_id'] <= snapshot } &&
              rows.map { |row| row['match_key'] }.uniq.size == rows.size
            raise Unavailable, 'Invalid canonical leaderboard identities'
          end
          rows.each { |row| found[row.fetch('match_key')] = row.fetch('first_id') }
          offset += rows.size
        end
        all.merge!(found)
      end
    end
  end
end
