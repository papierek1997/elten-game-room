require "date"
require "digest"
require "thread"
require_relative "game_room_analytics_client"

module GameRoomStatistics
  class Unavailable < StandardError; end
  class UnsafeReport < Unavailable; end

  module Schema
    ACCOUNTS = "statistics_accounts".freeze
    EVENTS = "statistics_events".freeze
    HIDDEN = %w[__insertion_user __last_update_user __insertion_time __last_update_time].freeze
    FIELDS = %w[event_key kind game day_key mode person].freeze
    TABLES = {
      ACCOUNTS => {
        "visibility" => "shared", "unique_per_user" => true,
        "columns" => {"marker" => "integer"},
        "permissions" => ["select", "insert", "update"],
        "limits" => {"max_select_limit" => 1}
      },
      EVENTS => {
        "visibility" => "public", "filtered_columns" => HIDDEN, "filter_for" => "everyone",
        "columns" => {"event_key" => "string:64", "kind" => "string:16", "game" => "string:32",
          "day_key" => "integer", "mode" => "string:8", "person" => "integer"},
        "permissions" => ["select", "insert"],
        "indexes" => [["event_key"], ["day_key", "kind"], ["game", "day_key"]],
        "limits" => {"max_select_limit" => 2000}
      }
    }.freeze
  end

  class Store
    KINDS = %w[visit player started completed].freeze
    MODES = %w[humans bots solo].freeze
    PAYLOAD_FIELDS = %w[kind game day_key mode match].freeze
    UPLOAD_CHUNK = 25
    UPLOAD_SECONDS = 1.0
    READ_SNAPSHOT_SECONDS = 15.0
    CANONICAL_CACHE_LIMIT = 4096

    def initialize(app_uuid:, user:, client: nil, api: nil, current_user: nil,
      monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @app_uuid, @user = app_uuid.to_s, user.to_s
      @client = client || EltenLink::Client.new
      @api = api || EltenLink::Apps
      @current_user = current_user || -> { Session.name }
      @monotonic = monotonic
      @mutex = Mutex.new
    end

    def write_batch(payloads, cancellation_token: nil)
      @mutex.synchronize do
        # Even an uncertain write invalidates the dialog's short read snapshot.
        @read_snapshot = nil
        check_context!(cancellation_token)
        raise ArgumentError, "Statistics batch must be an array" unless payloads.is_a?(Array)
        return 0 if payloads.empty?
        deadline = @monotonic.call + UPLOAD_SECONDS
        client = operation_client(cancellation_token)
        verify_schema_with_client!(client)
        table = @api.table(client, @app_uuid, Schema::EVENTS)
        confirmed = 0
        payloads.each_slice([UPLOAD_CHUNK, @page_limit].min) do |payload_chunk|
          check_context!(cancellation_token)
          values = payload_chunk.map { |payload| write_values(payload, cancellation_token, client) }
          unique = {}
          values.each do |value|
            assert_equivalent!(unique[value["event_key"]], value) if unique.key?(value["event_key"])
            unique[value["event_key"]] ||= value
          end
          existing = existing_records(table, unique.keys, cancellation_token)
          check_context!(cancellation_token)
          missing = unique.values.reject do |value|
            row = existing[value["event_key"]]
            assert_equivalent!(row, value) if row
            row != nil
          end
          unless missing.empty?
            rows = table.insert_many(missing)
            check_context!(cancellation_token)
            expected = missing.to_h { |value| [value["event_key"], value] }
            unless rows.is_a?(Array) && rows.length == missing.length && rows.all? { |row|
                row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"] > 0 &&
                  expected.key?(row["event_key"]) && expected[row["event_key"]].all? { |key, value| row[key] == value }
              } && rows.map { |row| row["event_key"] }.uniq.length == rows.length &&
                rows.map { |row| row["__id"] }.uniq.length == rows.length
              raise Unavailable, "Statistics bulk write was not confirmed"
            end
          end
          confirmed += payload_chunk.length
          # Yield between confirmed chunks, never half-acknowledge an HTTP
          # operation. A single slow chunk still makes progress on the retry.
          break if @monotonic.call >= deadline
        end
        check_context!(cancellation_token)
        confirmed
      end
    end

    private def assert_equivalent!(row, values)
      fields = %w[started completed].include?(values["kind"]) ? Schema::FIELDS - ["day_key"] : Schema::FIELDS
      unless valid_record?(row) && fields.all? { |key| row[key] == values[key] }
        raise UnsafeReport, "A statistics record conflicts with its original report"
      end
    end

    private def existing_records(table, keys, token)
      if keys.length == 1
        rows = table.select(where: {"event_key" => keys.first}, columns: Schema::FIELDS,
          order: [["__id", "asc"]], limit: 1)
        check_context!(token)
        raise Unavailable, "Invalid statistics lookup" unless rows.is_a?(Array) && rows.length <= 1 &&
          rows.all? { |row| valid_record?(row) && row["event_key"] == keys.first }
        return rows.empty? ? {} : {keys.first => rows.first}
      end
      first_records(table, keys, token: token, require_all: false)
    end

    def verify_schema!
      verify_schema_with_client!(operation_client(nil))
    end

    private def verify_schema_with_client!(client)
      tables = @api.schema(client, @app_uuid).dig("data", "server", "tables").to_h
      accounts, events = tables[Schema::ACCOUNTS].to_h, tables[Schema::EVENTS].to_h
      account_permissions = accounts["permissions"].to_h
      event_permissions = events["permissions"].to_h
      safe = accounts["visibility"] == "shared" && accounts["unique_per_user"] == true &&
        accounts["columns"].to_h.keys.sort == ["marker"] &&
        %w[select insert update].all? { |key| account_permissions[key] == true } &&
        %w[delete creator_share guest_share].none? { |key| account_permissions[key] == true } &&
        events["visibility"] == "public" && events["filter_for"] == "everyone" &&
        events["filtered_columns"].to_a.sort == Schema::HIDDEN.sort &&
        events["columns"].to_h.keys.sort == Schema::FIELDS.sort &&
        %w[select insert].all? { |key| event_permissions[key] == true } &&
        %w[update delete].none? { |key| event_permissions[key] == true }
      raise UnsafeReport, "Statistics have not been configured with the required privacy protections" unless safe
      @page_limit = [[events.dig("limits", "max_select_limit").to_i, 1].max, 1000].min
      true
    end

    def report(period, cancellation_token: nil, reuse_snapshot: false)
      @mutex.synchronize do
        check_context!(cancellation_token)
        client = operation_client(cancellation_token)
        verify_schema_with_client!(client)
        table = @api.table(client, @app_uuid, Schema::EVENTS)
        check_context!(cancellation_token)
        metadata = read_metadata(table, cancellation_token, reuse: reuse_snapshot)
        snapshot, first_day = metadata.values_at(:id, :first_day)
        people, visitors, game_people, games, seen = {}, {}, {}, {}, {}
        totals = {"started" => 0, "completed" => 0}
        each_record(table, period, snapshot, cancellation_token) do |row|
          raise Unavailable, "Invalid statistics record" unless valid_record?(row)
          next if seen[row["event_key"]]
          seen[row["event_key"]] = true
          kind = row["kind"]
          if kind == "visit"
            visitors[row["person"]] = true
            next
          end
          game = games[row["game"]] ||= {"id" => row["game"].dup, "players" => 0, "started" => 0, "completed" => 0,
            "modes" => MODES.to_h { |mode| [mode, {"started" => 0, "completed" => 0}] }}
          if kind == "player"
            people[row["person"]] = true
            (game_people[row["game"]] ||= {})[row["person"]] = true
          else
            totals[kind] += 1
            game[kind] += 1
            game["modes"][row["mode"]][kind] += 1
          end
        end
        games.each { |id, row| row["players"] = game_people.fetch(id, {}).length }
        check_context!(cancellation_token)
        {"visitors" => visitors.length, "players" => people.length, "started" => totals["started"],
          "completed" => totals["completed"], "games" => games.values,
          "first_day" => first_day, "partial" => !!(first_day && period.from_day && period.from_day < first_day)}
      end
    end

    def years(today:, cancellation_token: nil)
      @mutex.synchronize do
        check_context!(cancellation_token)
        client = operation_client(cancellation_token)
        verify_schema_with_client!(client)
        table = @api.table(client, @app_uuid, Schema::EVENTS)
        check_context!(cancellation_token)
        # Explicit Refresh calls years first and always replaces this snapshot.
        first_day = read_metadata(table, cancellation_token, reuse: false)[:first_day]
        first_year = first_day ? first_day / 10000 : today.year
        check_context!(cancellation_token)
        first_year <= today.year ? (first_year..today.year).to_a.reverse : [today.year]
      end
    end

    private

    def check_context!(token)
      token.raise_if_cancelled! if token
      ensure_user!
    end

    def read_metadata(table, token, reuse:)
      if reuse && @read_snapshot && @monotonic.call < @read_snapshot[:at] + READ_SNAPSHOT_SECONDS
        return @read_snapshot
      end
      @read_snapshot = nil
      id = snapshot_id(table)
      check_context!(token)
      first_day = collection_start(table, id)
      check_context!(token)
      @read_snapshot = {id: id, first_day: first_day, at: @monotonic.call, canonical: {}}
    end

    def snapshot_id(table)
      rows = table.select(columns: ["__id"], order: [["__id", "desc"]], limit: 1)
      return 0 if rows.empty?
      row = rows.first
      unless row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"] > 0
        raise Unavailable, "Invalid statistics snapshot"
      end
      row["__id"]
    end

    def collection_start(table, snapshot)
      return nil if snapshot <= 0
      value = table.select(where: {"__id" => {"lte" => snapshot}},
        aggregates: {"first_day" => {"function" => "min", "column" => "day_key"}}, limit: 1).first.to_h["first_day"]
      raise Unavailable, "Invalid statistics collection date" unless valid_day?(value)
      value
    end

    def each_record(table, period, snapshot, token)
      where = period_scope(period).merge("__id" => {"lte" => snapshot})
      return if snapshot <= 0
      offset, previous = 0, nil
      loop do
        check_context!(token)
        rows = table.select(where: where, columns: Schema::FIELDS, distinct: true,
          order: [["event_key", "asc"], ["day_key", "asc"]], limit: @page_limit, offset: offset)
        check_context!(token)
        raise Unavailable, "Invalid statistics page" unless rows.is_a?(Array) && rows.length <= @page_limit
        break if rows.empty?
        raise Unavailable, "Statistics pagination did not advance" if rows == previous
        rows.each { |row| raise Unavailable, "Invalid statistics record" unless valid_record?(row) }
        keys = rows.select { |row| %w[started completed].include?(row["kind"]) }.map { |row| row["event_key"] }.uniq
        canonical = canonical_records(table, keys, snapshot, token)
        rows.each do |row|
          row = canonical.fetch(row["event_key"], row)
          yield row if row["day_key"] <= period.to_day && (!period.from_day || row["day_key"] >= period.from_day)
        end
        # The endpoint may shorten a nonempty page below the schema/request
        # limit. Only an empty response proves that this snapshot is exhausted.
        offset += rows.length
        previous = rows
      end
    end

    def canonical_records(table, keys, snapshot, token)
      cache = @read_snapshot && @read_snapshot[:id] == snapshot ? @read_snapshot[:canonical] : {}
      records = keys.each_with_object({}) { |key, found| found[key] = cache[key] if cache.key?(key) }
      (keys - records.keys).each_slice([@page_limit, 100].min) do |chunk|
        found = first_records(table, chunk, token: token, snapshot: snapshot, require_all: true)
        raise Unavailable, "Invalid canonical match kind" unless found.values.all? { |row| %w[started completed].include?(row["kind"]) }
        records.merge!(found)
        found.each { |key, row| cache[key] = row.freeze }
        cache.shift while cache.length > CANONICAL_CACHE_LIMIT
      end
      records
    end

    def first_records(table, keys, token:, require_all:, snapshot: nil)
      check_context!(token)
      scope = {"event_key" => {"in" => keys}}
      scope["__id"] = {"lte" => snapshot} if snapshot
      first = table.select(where: scope,
        columns: ["event_key"], group_by: ["event_key"],
        aggregates: {"first_id" => {"function" => "min", "column" => "__id"}}, limit: keys.length)
      check_context!(token)
      unless first.is_a?(Array) && (require_all ? first.length == keys.length : first.length <= keys.length) && first.all? { |row|
          row.is_a?(Hash) && keys.include?(row["event_key"]) && row["first_id"].is_a?(Integer) && row["first_id"] > 0 &&
            (!snapshot || row["first_id"] <= snapshot)
        } && first.map { |row| row["event_key"] }.uniq.length == first.length
        raise Unavailable, "Invalid canonical statistics identities"
      end
      expected = first.to_h { |row| [row["event_key"], row["first_id"]] }
      return {} if expected.empty?
      rows = table.select(where: {"__id" => {"in" => expected.values}}, columns: Schema::FIELDS + ["__id"], limit: expected.length)
      check_context!(token)
      unless rows.is_a?(Array) && rows.length == expected.length && rows.all? { |row|
          valid_record?(row) && expected[row["event_key"]] == row["__id"]
        } && rows.map { |row| row["event_key"] }.sort == expected.keys.sort
        raise Unavailable, "Invalid canonical statistics records"
      end
      rows.to_h { |row| [row["event_key"], row] }
    end

    def period_scope(period)
      raise ArgumentError, "Invalid statistics period" unless valid_day?(period.to_day)
      return {"day_key" => {"lte" => period.to_day}} if period.from_day == nil
      raise ArgumentError, "Invalid statistics period" unless valid_day?(period.from_day)
      first = Date.strptime(period.from_day.to_s, "%Y%m%d")
      last = Date.strptime(period.to_day.to_s, "%Y%m%d")
      raise ArgumentError, "Invalid statistics period length" unless (last - first).between?(0, 365)
      {"day_key" => {"in" => (first..last).map { |day| day.strftime("%Y%m%d").to_i }}}
    end

    def valid_record?(row)
      return false unless row.is_a?(Hash) && row["event_key"].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(row["event_key"]) &&
        KINDS.include?(row["kind"]) && valid_day?(row["day_key"]) && row["person"].is_a?(Integer)
      if row["kind"] == "visit"
        row["game"] == "" && row["mode"] == "" && row["person"] > 0
      else
        /\A[a-z][a-z0-9_]{0,31}\z/.match?(row["game"].to_s) && MODES.include?(row["mode"]) &&
          (row["kind"] == "player" ? row["person"] > 0 : row["person"] == 0)
      end
    end

    def ensure_user!
      raise Unavailable, "The account changed while statistics were being processed" if @user.empty? || !@current_user.call.to_s.casecmp?(@user)
    end

    def operation_client(token)
      GameRoomAnalyticsClient.new(@client, app_uuid: @app_uuid,
        tables: [Schema::ACCOUNTS, Schema::EVENTS], error: Unavailable, cancellation_token: token)
    end

    def person_id(token, client)
      check_context!(token)
      return @person_id if @person_id
      table = @api.table(client, @app_uuid, Schema::ACCOUNTS)
      row = table.upsert("marker" => 1)
      check_context!(token)
      unless row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"] > 0
        raise Unavailable, "The private statistics identity could not be verified"
      end
      id = row["__id"]
      verified = table.select(where: {"__id" => id}, include_access: true, limit: 1).first
      check_context!(token)
      unless verified.is_a?(Hash) && verified["__id"] == id && verified["marker"] == 1 &&
          verified["__access"].is_a?(Hash) && verified["__access"]["owner"] == true
        raise Unavailable, "The private statistics identity could not be verified"
      end
      @person_id = id
    end

    def write_values(payload, token, client)
      unless payload.is_a?(Hash) && (payload.keys - PAYLOAD_FIELDS).empty?
        raise ArgumentError, "Invalid statistics payload"
      end
      kind, game, mode = payload["kind"].to_s, payload["game"].to_s, payload["mode"].to_s
      day = payload["day_key"]
      raise ArgumentError, "Invalid statistics day" unless valid_day?(day)
      raise ArgumentError, "Invalid statistics kind" unless KINDS.include?(kind)
      if kind == "visit"
        raise ArgumentError, "A visit must not contain a game" unless game.empty? && mode.empty? && payload["match"].to_s.empty?
      else
        raise ArgumentError, "Invalid statistics game or mode" unless /\A[a-z][a-z0-9_]{0,31}\z/.match?(game) && MODES.include?(mode)
      end
      person = %w[visit player].include?(kind) ? person_id(token, client) : 0
      identity = if person > 0
        raise ArgumentError, "A personal activity must not identify a match" unless payload["match"].to_s.empty?
        [kind, person, day, game, mode]
      else
        match = payload["match"].to_s
        raise ArgumentError, "Invalid statistics match identity" unless /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.match?(match)
        [kind, match]
      end
      {"event_key" => Digest::SHA256.hexdigest(identity.join("\0")), "kind" => kind, "game" => game,
        "day_key" => day, "mode" => mode, "person" => person}
    end

    def valid_day?(day)
      day.is_a?(Integer) && day.between?(19700101, 99991231) && Date.strptime(day.to_s, "%Y%m%d").strftime("%Y%m%d").to_i == day
    rescue Date::Error
      false
    end
  end
end
