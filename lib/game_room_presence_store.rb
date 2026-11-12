require "digest"
require_relative "game_room_analytics_client"

module GameRoomPresence
  class Unavailable < StandardError; end
  class UnsafeReport < Unavailable; end

  module Schema
    TABLE = "room_presence".freeze
    HIDDEN = %w[__insertion_user __last_update_user __insertion_time __last_update_time].freeze
    FIELDS = %w[reporter_key room_key game private_room people playing seen_slot].freeze
    TABLES = {
      TABLE => {
        "visibility" => "public", "unique_per_user" => false,
        "filtered_columns" => HIDDEN, "filter_for" => "everyone",
        "columns" => {"reporter_key" => "string:64", "room_key" => "string:64", "game" => "string:32",
          "private_room" => "integer", "people" => "integer", "playing" => "integer", "seen_slot" => "integer"},
        "permissions" => %w[select insert update delete],
        "indexes" => [["reporter_key"], ["room_key"], ["seen_slot"]], "limits" => {"max_select_limit" => 2000}
      }
    }.freeze
  end

  class Store
    PAYLOAD_FIELDS = %w[room_key game private_room people playing].freeze
    CLEANUP_PAGE = 64
    LIVE_PREVIOUS_SLOTS = 5
    CLEANUP_INTERVAL = 900

    def initialize(app_uuid:, user:, reporter_key:, client: nil, api: nil, current_user: -> { Session.name }, clock: -> { GameRoomClock.now },
      monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      raise ArgumentError, "Invalid room presence reporter key" unless digest?(reporter_key)
      @app_uuid, @user = app_uuid.to_s.dup.freeze, user.to_s.dup.freeze
      @installation_key = reporter_key.dup.freeze
      @client, @api = client || EltenLink::Client.new, api || EltenLink::Apps
      @current_user, @clock = current_user, clock
      @monotonic = monotonic
      @published_keys = {}
      @cleanup_cursor = 0
    end

    def publish(data, cancellation_token: nil)
      check_context!(cancellation_token)
      slot = current_slot
      values = write_values(data, slot)
      client = operation_client(cancellation_token)
      verify_schema!(cancellation_token, client)
      table = @api.table(client, @app_uuid, Schema::TABLE)
      (@published_keys.keys - values.map { |row| row["reporter_key"] }).each do |key|
        write_row(table, {"reporter_key" => key, "room_key" => "", "game" => "",
          "private_room" => 0, "people" => 0, "playing" => 0, "seen_slot" => slot}, cancellation_token)
        @published_keys.delete(key)
      end
      values.each do |row|
        @published_keys[row["reporter_key"]] = true
        write_row(table, row, cancellation_token)
      end
      if !@cleanup_at || @monotonic.call >= @cleanup_at
        prune_expired(table, slot, cancellation_token)
        @cleanup_at = @monotonic.call + CLEANUP_INTERVAL
      end
      check_context!(cancellation_token)
      true
    end

    def report(cancellation_token: nil)
      check_context!(cancellation_token)
      slot = current_slot
      client = operation_client(cancellation_token)
      page_limit = verify_schema!(cancellation_token, client)
      table = @api.table(client, @app_uuid, Schema::TABLE)
      totals = {"public_rooms" => 0, "private_rooms" => 0, "people" => 0}
      rooms, games = {}, {}
      each_record(table, slot, page_limit, cancellation_token) do |row|
        room = read_room(row)
        merge_room!(rooms, room) if room
      end
      rooms.each_value do |row|
        game = games[row["game"]] ||= {"id" => row["game"], "public_rooms" => 0, "private_rooms" => 0,
          "people" => 0, "playing_rooms" => 0}
        field = row["private_room"] ? "private_rooms" : "public_rooms"
        totals[field] += 1
        game[field] += 1
        totals["people"] += row["people"]
        game["people"] += row["people"]
        game["playing_rooms"] += 1 if row["playing"]
      end
      check_context!(cancellation_token)
      totals.merge("games" => games.keys.sort.map { |id| games[id] })
    end

    private

    # At most one bounded page per 15 minutes of publishing, not a separate job.
    # Keep a full slot of grace beyond the reader's six-slot window. Access flags
    # are supplied by ELTEN, not by public payloads. Never remove others' rows
    # (the developer account may have broader server-side rights).
    def prune_expired(table, slot, token)
      expired = slot - LIVE_PREVIOUS_SLOTS - 2
      rows = select_rows(table, token, where: {"seen_slot" => {"lte" => expired},
        "__id" => {"gte" => @cleanup_cursor + 1}}, order: [["__id", "asc"]],
        include_access: true, limit: CLEANUP_PAGE)
      rows.each do |row|
        @cleanup_cursor = row["__id"]
        next unless row.dig("__access", "owner") == true && row["seen_slot"].is_a?(Integer) && row["seen_slot"] <= expired
        fresh = select_rows(table, token, where: {"__id" => row["__id"]}, include_access: true, limit: 1).first
        next unless fresh && fresh.dig("__access", "owner") == true &&
          fresh["seen_slot"] == row["seen_slot"] && fresh["reporter_key"] == row["reporter_key"]
        network(token) { table.delete(row["__id"]) }
      end
      # The server may shorten a page; only an empty tail completes the scan.
      @cleanup_cursor = 0 if rows.empty?
    end

    def write_row(table, values, cancellation_token)
      existing = reporter_row(table, values["reporter_key"], cancellation_token)
      row = network(cancellation_token) { existing ? table.update(existing["__id"], values) : table.insert(values) }
      unless matches?(row, values) && (!existing || row["__id"] == existing["__id"])
        raise Unavailable, "Room presence write was not confirmed"
      end
      unless existing
        canonical = reporter_row(table, values["reporter_key"], cancellation_token)
        raise Unavailable, "Room presence insert disappeared" unless canonical && canonical["__id"] <= row["__id"]
        if canonical["__id"] != row["__id"]
          row = network(cancellation_token) { table.update(canonical["__id"], values) }
          unless matches?(row, values) && row["__id"] == canonical["__id"]
            raise Unavailable, "Room presence write was not confirmed"
          end
        end
      end
      rows = network(cancellation_token) { table.select(where: {"__id" => row["__id"]}, include_access: true, limit: 1) }
      verified = rows.first if rows.is_a?(Array) && rows.length == 1
      unless matches?(verified, values) && verified["__id"] == row["__id"] &&
          verified["__access"].is_a?(Hash) && verified["__access"]["owner"] == true
        raise Unavailable, "Room presence ownership could not be verified"
      end
      check_context!(cancellation_token)
      true
    end

    def reporter_row(table, reporter_key, token)
      rows = network(token) do
        table.select(where: {"reporter_key" => reporter_key}, order: [["__id", "asc"]], include_access: true, limit: 1)
      end
      raise Unavailable, "Invalid room presence lookup" unless rows.is_a?(Array) && rows.length <= 1
      return nil if rows.empty?
      row = rows.first
      unless row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"] > 0 && row["reporter_key"] == reporter_key &&
          row["__access"].is_a?(Hash) && row["__access"]["owner"] == true
        raise Unavailable, "Room presence lookup is not owned by this reporter"
      end
      row
    end

    # Inserts are pinned by ID; in-place updates make the slot-filtered census approximate, not transactional.
    def each_record(table, slot, page_limit, token)
      snapshot = select_rows(table, token, columns: ["__id"], order: [["__id", "desc"]], limit: 1)
      return if snapshot.empty?
      upper = snapshot.first["__id"]
      previous_id = 0
      loop do
        rows = select_rows(table, token, where: {"seen_slot" => {"in" => live_slots(slot)},
          "__id" => {"gte" => previous_id + 1}},
          columns: Schema::FIELDS + ["__id"], order: [["__id", "asc"]], limit: page_limit)
        break if rows.empty?
        unless rows.each_cons(2).all? { |first, second| first["__id"] < second["__id"] }
          raise Unavailable, "Room presence pagination is not ordered"
        end
        beyond_snapshot = rows.any? { |row| row["__id"] > upper }
        rows = rows.take_while { |row| row["__id"] <= upper }
        rows.each do |row|
          id = row["__id"]
          unless id.is_a?(Integer) && id > previous_id && id <= upper
            raise Unavailable, "Room presence pagination did not advance within its snapshot"
          end
          previous_id = id
          unless row["seen_slot"].is_a?(Integer) && live_slots(slot).include?(row["seen_slot"])
            raise Unavailable, "Room presence escaped its expiry window"
          end
          read_room(row)
        end
        keys = rows.map { |row| row["reporter_key"] }.uniq
        canonical_records(table, keys, upper, page_limit, token).each do |row|
          yield row if live_slots(slot).include?(row["seen_slot"])
        end
        # Short pages are not EOF: the endpoint can cap them below our limit.
        break if beyond_snapshot || previous_id >= upper
      end
    end

    def canonical_records(table, keys, upper, page_limit, token)
      keys.each_slice([page_limit, 100].min).flat_map do |chunk|
        first = network(token) do
          table.select(where: {"reporter_key" => {"in" => chunk}, "__id" => {"lte" => upper}},
            columns: ["reporter_key"], group_by: ["reporter_key"],
            aggregates: {"first_id" => {"function" => "min", "column" => "__id"}}, limit: chunk.length)
        end
        unless first.is_a?(Array) && first.length == chunk.length && first.all? { |row|
            row.is_a?(Hash) && chunk.include?(row["reporter_key"]) && row["first_id"].is_a?(Integer) && row["first_id"].between?(1, upper)
          } && first.map { |row| row["reporter_key"] }.sort == chunk.sort
          raise Unavailable, "Invalid canonical room presence identities"
        end
        expected = first.to_h { |row| [row["reporter_key"], row["first_id"]] }
        rows = select_rows(table, token, where: {"__id" => {"in" => expected.values}},
          columns: Schema::FIELDS + ["__id"], limit: chunk.length)
        unless rows.length == chunk.length && rows.all? { |row| expected[row["reporter_key"]] == row["__id"] } &&
            rows.map { |row| row["reporter_key"] }.sort == chunk.sort
          raise Unavailable, "Invalid canonical room presence records"
        end
        rows.each { |row| read_room(row) }
        rows
      end
    end

    def select_rows(table, token, **query)
      rows = network(token) { table.select(**query) }
      unless rows.is_a?(Array) && rows.length <= query.fetch(:limit) &&
          rows.all? { |row| row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"] > 0 }
        raise Unavailable, "Invalid room presence response"
      end
      rows
    end

    def read_room(row)
      unless digest?(row["reporter_key"]) && row["seen_slot"].is_a?(Integer) && row["seen_slot"] >= 0 &&
          %w[private_room playing].all? { |key| row[key].is_a?(Integer) && [0, 1].include?(row[key]) }
        raise Unavailable, "Invalid room presence record"
      end
      if row["room_key"] == ""
        unless row["game"] == "" && row["people"].eql?(0) && row["private_room"] == 0 && row["playing"] == 0
          raise Unavailable, "Invalid cleared room presence"
        end
        return nil
      end
      room = row.slice(*PAYLOAD_FIELDS).merge("private_room" => row["private_room"] == 1, "playing" => row["playing"] == 1)
      raise Unavailable, "Invalid room presence payload" unless valid_room?(room)
      room.merge("seen_slot" => row["seen_slot"])
    end

    def merge_room!(rooms, row)
      previous = rooms[row["room_key"]]
      if previous && previous.values_at("game", "private_room") != row.values_at("game", "private_room")
        raise Unavailable, "Conflicting room presence reports"
      end
      if !previous || row["seen_slot"] > previous["seen_slot"]
        rooms[row["room_key"]] = row.dup
      elsif row["seen_slot"] == previous["seen_slot"]
        previous["people"] = [previous["people"], row["people"]].max
        previous["playing"] ||= row["playing"]
      end
    end

    def check_context!(token)
      token.raise_if_cancelled! if token
      unless !@user.strip.empty? && @current_user.call.to_s.casecmp?(@user)
        raise Unavailable, "The account changed while processing room presence"
      end
    end

    def network(token)
      check_context!(token)
      result = yield
      check_context!(token)
      result
    end

    def matches?(row, values)
      row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"] > 0 &&
        values.all? { |key, value| row[key].eql?(value) }
    end

    def current_slot
      value = @clock.call
      value = value.to_f if value.is_a?(Time)
      unless (value.is_a?(Integer) || value.is_a?(Float)) && value.finite? && value > 0
        raise Unavailable, "Room presence requires a valid clock"
      end
      (value / 60).floor
    end

    def live_slots(slot)
      ((slot - LIVE_PREVIOUS_SLOTS)..slot).to_a
    end

    def write_values(data, slot)
      raise ArgumentError, "Invalid room presence payload" unless data.is_a?(Array) && data.all? { |room| valid_room?(room) }
      rooms = {}
      data.each { |room| merge_room!(rooms, room.merge("seen_slot" => slot)) }
      rooms.values.map do |room|
        key = Digest::SHA256.hexdigest(["elten-game-room/room-presence/reporter/v1", @installation_key, room["room_key"]].join("\0"))
        room.merge("reporter_key" => key, "private_room" => room["private_room"] ? 1 : 0,
          "playing" => room["playing"] ? 1 : 0, "seen_slot" => slot)
      end
    end

    def valid_room?(row)
      row.is_a?(Hash) && row.keys.length == PAYLOAD_FIELDS.length && (PAYLOAD_FIELDS - row.keys).empty? &&
        digest?(row["room_key"]) && row["game"].is_a?(String) && row["game"].ascii_only? &&
        /\A[a-z][a-z0-9_]{0,31}\z/.match?(row["game"]) && row["people"].is_a?(Integer) && row["people"] > 0 &&
        [true, false].include?(row["private_room"]) && [true, false].include?(row["playing"])
    end

    def digest?(value)
      value.is_a?(String) && value.ascii_only? && /\A[0-9a-f]{64}\z/.match?(value)
    end

    def operation_client(token)
      GameRoomAnalyticsClient.new(@client, app_uuid: @app_uuid, tables: [Schema::TABLE],
        error: Unavailable, cancellation_token: token)
    end

    def verify_schema!(token, client)
      result = network(token) { @api.schema(client, @app_uuid) }
      policy = %w[data server tables room_presence].reduce(result) { |value, key| value.is_a?(Hash) ? value[key] : nil }
      policy = {} unless policy.is_a?(Hash)
      permissions, columns, masks = policy.values_at("permissions", "columns", "filtered_columns")
      limit = policy["limits"]["max_select_limit"] if policy["limits"].is_a?(Hash)
      safe = policy["visibility"] == "public" && policy["unique_per_user"] == false &&
        policy["filter_for"] == "everyone" && masks.is_a?(Array) &&
        masks.length == Schema::HIDDEN.length && (Schema::HIDDEN - masks).empty? &&
        columns.is_a?(Hash) && columns.keys.sort == Schema::FIELDS.sort &&
        permissions.is_a?(Hash) && %w[select insert update delete].all? { |key| permissions[key] == true } &&
        permissions.all? { |key, value| %w[select insert update delete].include?(key) || value == false } &&
        limit.is_a?(Integer) && limit > 0
      raise UnsafeReport, "Room presence lacks the required privacy protections" unless safe
      [limit, 1000].min
    end
  end
end
