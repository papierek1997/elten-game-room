require "json"

$statistics_assertions = 0

def assert(value, message)
  $statistics_assertions += 1
  raise message unless value
end

def assert_raises(error, message)
  $statistics_assertions += 1
  begin
    yield
  rescue error => caught
    return caught
  end
  raise message
end

path = File.expand_path("../lib/game_statistics_store.rb", __dir__)
assert(File.file?(path), "Statistics storage is missing")
require path

class StatisticsApiDouble
  attr_accessor :schema_value, :after_schema
  attr_reader :calls

  def initialize
    @schema_value = {"data" => {"server" => {"tables" => {}}}}
    @calls = []
  end

  def schema(_client, app_uuid)
    @calls << [:schema, app_uuid]
    @after_schema.call if @after_schema
    @schema_value
  end

  def table(*)
    raise "An unsafe schema must not open an activity table"
  end
end

api = StatisticsApiDouble.new
store = GameRoomStatistics::Store.new(app_uuid: "statistics-app", user: "Alice", client: Object.new, api: api)
begin
  store.verify_schema!
  raise "Missing privacy configuration was accepted"
rescue GameRoomStatistics::Unavailable
end
assert(api.calls == [[:schema, "statistics-app"]], "Privacy inspection did not use the declared application")

api.schema_value = {"data" => {"server" => {"tables" => {
  "statistics_accounts" => {
    "visibility" => "shared", "unique_per_user" => true,
    "columns" => {"marker" => "integer"},
    "permissions" => {"select" => true, "insert" => true, "update" => true}
  },
  "statistics_events" => {
    "visibility" => "public", "filter_for" => "others",
    "filtered_columns" => %w[__insertion_user __last_update_user __insertion_time __last_update_time],
    "columns" => {"event_key" => "string:64", "kind" => "string:16", "game" => "string:32", "day_key" => "integer", "mode" => "string:8", "person" => "integer"},
    "permissions" => {"select" => true, "insert" => true}, "limits" => {"max_select_limit" => 2000}
  }
}}}}
begin
  store.verify_schema!
  raise "A schema that exposes the owner's identity was accepted"
rescue GameRoomStatistics::Unavailable
end
api.schema_value["data"]["server"]["tables"]["statistics_events"]["filter_for"] = "everyone"
account_policy = api.schema_value["data"]["server"]["tables"]["statistics_accounts"]
account_policy["filtered_columns"] = []
account_policy["filter_for"] = "others"
assert(store.verify_schema! == true, "The server-supported private identity and masked public events policy was rejected")
assert(!GameRoomStatistics::Schema::TABLES.fetch("statistics_accounts").key?("filtered_columns"),
  "The private identity schema uses filtering rejected by the real server")
api.schema_value["data"]["server"]["tables"]["statistics_accounts"]["unique_per_user"] = false
begin
  store.verify_schema!
  raise "Non-unique account identities were accepted"
rescue GameRoomStatistics::Unavailable
end
class StatisticsMemoryTable
  attr_reader :rows, :queries, :upserts
  attr_accessor :lose_ack, :after_upsert, :after_select, :after_insert

  def initialize(identity: false)
    @identity, @rows, @queries, @upserts = identity, [], [], 0
  end

  def upsert(values)
    @upserts += 1
    @rows << values.merge("__id" => 7, "__insertion_user" => "Alice") if @rows.empty?
    row = masked(@rows.first)
    @after_upsert.call(row) if @after_upsert
    row
  end

  def insert(values)
    row = values.merge("__id" => (@rows.map { |item| item["__id"] }.max || 0) + 1)
    @rows << row
    if @lose_ack
      @lose_ack = false
      raise IOError, "acknowledgement lost"
    end
    result = row.dup
    @after_insert.call(result) if @after_insert
    result
  end

  def select(where: {}, columns: nil, aggregates: nil, group_by: nil, order: [], limit: 2000, offset: 0, distinct: false, include_access: false)
    @queries << {where: where, columns: columns, aggregates: aggregates, limit: limit, offset: offset,
      distinct: distinct, include_access: include_access}
    @queries.last[:group_by] = group_by if group_by
    @queries.last[:order] = order unless order.empty?
    %w[event_key __id].each do |key|
      values = where[key]
      raise "Canonical lookup exceeds the supported key chunk" if values.is_a?(Hash) && values["in"] && values["in"].length > 100
    end
    selected = @rows.map { |row| masked(row) }.select do |row|
      where.all? do |key, value|
        if value.is_a?(Hash)
          value.all? do |operator, expected|
            case operator
            when "in" then expected.include?(row[key])
            when "lte" then row[key] <= expected
            when "gte" then row[key] >= expected
            else raise "Unexpected operator #{operator}"
            end
          end
        else
          row[key] == value
        end
      end
    end
    if aggregates
      groups = group_by ? selected.group_by { |row| group_by.map { |key| row[key] } } : {[] => selected}
      selected = groups.map do |keys, rows|
        values = aggregates.to_h do |name, spec|
          raise "Unsupported aggregate #{spec.inspect}" unless spec["function"] == "min"
          [name, rows.map { |row| row[spec["column"]] }.compact.min]
        end
        (group_by || []).zip(keys).to_h.merge(values)
      end
    end
    order.reverse_each do |key, direction|
      selected = selected.sort_by { |row| row[key] }
      selected.reverse! if direction == "desc"
    end
    selected = selected.map { |row| columns ? row.select { |key, _| (columns + (aggregates || {}).keys).include?(key) } : row.dup }
    selected = selected.uniq if distinct
    selected = selected.drop(offset).first(limit)
    selected.each { |row| row["__access"] = {"owner" => true} } if include_access && !columns
    @after_select.call(@queries.last, selected) if @after_select
    selected
  end

  def masked(row)
    return row.dup unless @identity
    row.merge(GameRoomStatistics::Schema::HIDDEN.to_h { |key| [key, nil] })
  end
end

class StatisticsApiDouble
  attr_reader :tables
  def table(_client, _uuid, name)
    @tables ||= {}
    @tables[name] ||= StatisticsMemoryTable.new(identity: name == "statistics_accounts")
  end
end

api.schema_value["data"]["server"]["tables"]["statistics_accounts"]["unique_per_user"] = true
STATISTICS_SAFE_SCHEMA = JSON.generate(api.schema_value)

def statistics_fixture(current_user: -> { "Alice" })
  api = StatisticsApiDouble.new
  api.schema_value = JSON.parse(STATISTICS_SAFE_SCHEMA)
  store = GameRoomStatistics::Store.new(app_uuid: "statistics-app", user: "Alice", client: Object.new,
    api: api, current_user: current_user)
  [store, api, api.table(nil, nil, "statistics_accounts"), api.table(nil, nil, "statistics_events")]
end

class StatisticsCancelled < StandardError; end

class StatisticsCancellation
  attr_accessor :cancelled

  def raise_if_cancelled!
    raise StatisticsCancelled, "Statistics cancelled" if @cancelled
  end
end

cancelled_store, cancelled_api, cancelled_accounts, cancelled_events = statistics_fixture
token = StatisticsCancellation.new
token.cancelled = true
assert_raises(StatisticsCancelled, "An already cancelled write was accepted") do
  cancelled_store.write_batch([{"kind" => "visit", "day_key" => 20260925}], cancellation_token: token)
end
assert(cancelled_api.calls.empty? && cancelled_accounts.upserts == 0 && cancelled_events.queries.empty? &&
  cancelled_events.rows.empty?, "An already cancelled write contacted the server")

write_interruptions = []
[:cancel, :account_change].each do |interruption|
  [:schema, :upsert, :identity, :lookup, :ack].each do |stage|
    user = "Alice"
    interrupted_store, interrupted_api, private_table, public_table = statistics_fixture(current_user: -> { user })
    token = StatisticsCancellation.new
    interrupt = ->(*) { interruption == :cancel ? token.cancelled = true : user = "Bob" }
    case stage
    when :schema then interrupted_api.after_schema = interrupt
    when :upsert then private_table.after_upsert = interrupt
    when :identity then private_table.after_select = interrupt
    when :lookup then public_table.after_select = interrupt
    when :ack then public_table.after_insert = interrupt
    end
    error = interruption == :cancel ? StatisticsCancelled : GameRoomStatistics::Unavailable
    begin
      assert_raises(error, "The interrupted batch was acknowledged") do
        interrupted_store.write_batch([
          {"kind" => "visit", "day_key" => 20260925}, {"kind" => "visit", "day_key" => 20260926}
        ], cancellation_token: token)
      end
      assert(private_table.upserts == (stage == :schema ? 0 : 1), "Identity creation continued after interruption")
      assert(private_table.queries.length == ([:schema, :upsert].include?(stage) ? 0 : 1), "Identity verification continued after interruption")
      assert(public_table.queries.length == ([:lookup, :ack].include?(stage) ? 1 : 0), "Public lookup continued after interruption")
      assert(public_table.rows.length == (stage == :ack ? 1 : 0), "Public writes continued after interruption")
    rescue StandardError => failure
      write_interruptions << "#{interruption}/#{stage}: #{failure.message}"
    end
  end
end
assert(write_interruptions.empty?, write_interruptions.join("\n"))

bad_identities = [
  {"__id" => 8}, {"marker" => 2}, {"marker" => nil}, {"__access" => nil}, {"__access" => []},
  {"__access" => {}}, {"__access" => {"owner" => false}}, {"__access" => {"owner" => "true"}},
  {"__access" => {"owner" => 1}}
]
bad_identities.each do |override|
  identity_store, _identity_api, private_table, public_table = statistics_fixture
  private_table.after_select = ->(_query, rows) { rows.first.merge!(override) }
  assert_raises(GameRoomStatistics::Unavailable, "An unowned or mismatched private identity was accepted: #{override.inspect}") do
    identity_store.write_batch([{"kind" => "visit", "day_key" => 20260925}])
  end
  assert(public_table.rows.empty? && public_table.queries.empty?, "An unverified identity reached the public table")
  private_table.after_select = nil
  assert(identity_store.write_batch([{"kind" => "visit", "day_key" => 20260925}]), "A rejected identity was cached")
  assert(private_table.queries.length == 2 && public_table.rows.first["person"] == 7, "Identity recovery skipped verification")
end
[nil, 0, -1, "7", "7invalid", 7.5, false].each do |id|
  identity_store, _identity_api, private_table, public_table = statistics_fixture
  private_table.after_upsert = ->(row) { row["__id"] = id }
  assert_raises(GameRoomStatistics::Unavailable, "An invalid private upsert ID was accepted: #{id.inspect}") do
    identity_store.write_batch([{"kind" => "visit", "day_key" => 20260925}])
  end
  assert(private_table.queries.empty? && public_table.rows.empty?, "An invalid identity was used in a query/write")
end
identity_store, identity_api, private_table, public_table = statistics_fixture
identity_store.write_batch([{"kind" => "visit", "day_key" => 20260925}])
second_store = GameRoomStatistics::Store.new(app_uuid: "statistics-app", user: "Alice", client: Object.new,
  api: identity_api, current_user: -> { "Alice" })
second_store.write_batch([{"kind" => "visit", "day_key" => 20260925}])
assert(private_table.upserts == 2 && private_table.rows.length == 1 && public_table.rows.length == 1,
  "A fresh store changed the per-account identity or duplicated a visit")

current_user = "Alice"
store = GameRoomStatistics::Store.new(app_uuid: "statistics-app", user: "Alice", client: Object.new, api: api,
  current_user: -> { current_user })
visit = {"kind" => "visit", "day_key" => 20260925}
assert(store.write_batch([visit, visit]), "A visit batch was not accepted")
events = api.tables.fetch("statistics_events")
accounts = api.tables.fetch("statistics_accounts")
assert(events.rows.length == 1 && events.rows.first["person"] == 7, "Repeated visits created duplicate people/events")
assert(accounts.upserts == 1, "The account identity was recreated within one store")
assert(accounts.queries == [{where: {"__id" => 7}, columns: nil, aggregates: nil,
  limit: 1, offset: 0, distinct: false, include_access: true}], "The private identity was not verified by exact ID and access")
assert(events.rows.first.keys.sort == (GameRoomStatistics::Schema::FIELDS + ["__id"]).sort, "Public activity contains extra fields")
assert(!JSON.generate(events.rows).include?("Alice"), "A nickname leaked into activity records")
assert(store.write_batch([visit]) && events.rows.length == 1, "A retried batch duplicated a visit")
next_visit = {"kind" => "visit", "day_key" => 20260926}
events.lose_ack = true
begin
  store.write_batch([next_visit])
  raise "Lost acknowledgement was reported as success"
rescue IOError
end
assert(store.write_batch([next_visit]) && events.rows.length == 2, "An uncertain write was inserted twice")
current_user = "Bob"
begin
  store.write_batch([visit])
  raise "An old account's batch was sent after login changed"
rescue GameRoomStatistics::Unavailable
end
assert(events.rows.length == 2, "Account switching changed activity")
current_user = "Alice"
match_one = "11111111-1111-4111-8111-111111111111"
match_two = "22222222-2222-4222-8222-222222222222"
match_old = "33333333-3333-4333-8333-333333333333"
store.write_batch([
  {"kind" => "player", "game" => "tic_tac_toe", "mode" => "humans", "day_key" => 20260925},
  {"kind" => "player", "game" => "tic_tac_toe", "mode" => "humans", "day_key" => 20260926},
  {"kind" => "started", "game" => "tic_tac_toe", "mode" => "humans", "day_key" => 20260925, "match" => match_one},
  {"kind" => "completed", "game" => "tic_tac_toe", "mode" => "humans", "day_key" => 20260926, "match" => match_one},
  {"kind" => "started", "game" => "tic_tac_toe", "mode" => "bots", "day_key" => 20260926, "match" => match_two},
  {"kind" => "started", "game" => "krowa", "mode" => "solo", "day_key" => 20260924, "match" => match_old},
  {"kind" => "completed", "game" => "krowa", "mode" => "solo", "day_key" => 20260926, "match" => match_old},
  {"kind" => "player", "game" => "krowa", "mode" => "solo", "day_key" => 20260926}
])
other_visit = events.rows.find { |row| row["kind"] == "visit" }.reject { |key, _| key == "__id" }.merge("person" => 8, "event_key" => "b" * 64)
other_player = events.rows.find { |row| row["kind"] == "player" }.reject { |key, _| key == "__id" }.merge("person" => 8, "event_key" => "c" * 64)
events.insert(other_visit)
events.insert(other_player)
events.insert(events.rows.find { |row| row["kind"] == "completed" }.reject { |key, _| key == "__id" })
api.schema_value["data"]["server"]["tables"]["statistics_events"]["limits"]["max_select_limit"] = 2
period = Struct.new(:from_day, :to_day).new(20260925, 20260926)
report = store.report(period)
assert(report.values_at("visitors", "players", "started", "completed") == [2, 2, 2, 2], "Range totals duplicated people or matches")
games = report.fetch("games").to_h { |row| [row.fetch("id"), row] }
assert(games.fetch("tic_tac_toe").values_at("players", "started", "completed") == [2, 2, 1], "Per-game totals are wrong")
assert(games.fetch("tic_tac_toe").fetch("modes").fetch("bots") == {"started" => 1, "completed" => 0}, "Bot mode is not separated")
assert(games.fetch("krowa").values_at("started", "completed") == [0, 1], "A completion inherited its start date")
assert(report["first_day"] == 20260924 && report["partial"] == false, "Collection boundaries are wrong")
assert(events.queries.any? { |query| query[:offset] > 0 && query[:limit] == 2 }, "Statistics did not read every page")
assert(store.report(Struct.new(:from_day, :to_day).new(20260923, 20260926))["partial"], "Partial coverage was not marked")
assert(store.report(Struct.new(:from_day, :to_day).new(nil, 20260926))["started"] == 3, "All-time omitted earlier starts")
assert(store.report(Struct.new(:from_day, :to_day).new(20250101, 20251231))["visitors"] == 0, "An empty range included another year")
assert(store.years(today: Date.new(2027, 1, 1)) == [2027, 2026], "Calendar year choices were hard-coded")
before = events.rows.length
begin
  store.write_batch([{"kind" => "visit", "day_key" => 20260230}])
  raise "Invalid calendar day accepted"
rescue ArgumentError
end
begin
  store.write_batch([{"kind" => "visit", "day_key" => 20260925, "username" => "Alice"}])
  raise "Private payload field accepted"
rescue ArgumentError
end
assert(events.rows.length == before, "Rejected payload wrote public data")
read_interruptions = []
[:report, :years].each do |operation|
  [:cancel, :account_change].each do |interruption|
    stages = operation == :report ? [:before, :schema, :snapshot, :collection, :page] : [:before, :schema, :snapshot, :collection]
    stages.each do |stage|
      user = "Alice"
      reading_store, reading_api, private_table, public_table = statistics_fixture(current_user: -> { user })
      public_table.insert("event_key" => "a" * 64, "kind" => "visit", "game" => "", "mode" => "", "person" => 7, "day_key" => 20260925)
      token = StatisticsCancellation.new
      interrupt = ->(*) { interruption == :cancel ? token.cancelled = true : user = "Bob" }
      interrupt.call if stage == :before
      reading_api.after_schema = interrupt if stage == :schema
      public_table.after_select = lambda do |query, _rows|
        reached = if query[:columns] == ["__id"] then :snapshot
        elsif query[:aggregates] then :collection
        elsif query[:distinct] then :page
        end
        interrupt.call if reached == stage
      end
      error = interruption == :cancel ? StatisticsCancelled : GameRoomStatistics::Unavailable
      begin
        assert_raises(error, "An interrupted read returned a report") do
          if operation == :report
            reading_store.report(period, cancellation_token: token)
          else
            reading_store.years(today: Date.new(2026, 9, 25), cancellation_token: token)
          end
        end
        assert(reading_api.calls.length == (stage == :before ? 0 : 1), "An already interrupted read inspected the schema")
        expected_queries = {before: 0, schema: 0, snapshot: 1, collection: 2, page: 3}.fetch(stage)
        assert(public_table.queries.length == expected_queries, "A read made another request after interruption")
        assert(private_table.upserts == 0 && public_table.rows.length == 1, "A cancelled read wrote statistics")
      rescue StandardError => failure
        read_interruptions << "#{operation}/#{interruption}/#{stage}: #{failure.message}"
      end
    end
  end
end
assert(read_interruptions.empty?, read_interruptions.join("\n"))

snapshot_store, snapshot_api, _private_table, snapshot_events = statistics_fixture
snapshot_api.schema_value["data"]["server"]["tables"]["statistics_events"]["limits"]["max_select_limit"] = 2
snapshot_row = {"event_key" => "c" * 64, "kind" => "visit", "game" => "", "mode" => "", "person" => 7, "day_key" => 20260925}
snapshot_events.insert(snapshot_row)
snapshot_events.insert(snapshot_row.merge("event_key" => "e" * 64, "person" => 8))
snapshot_events.after_select = lambda do |query, _rows|
  if query[:distinct] && query[:offset] == 0
    snapshot_events.after_select = nil
    snapshot_events.insert(snapshot_row.merge("event_key" => "f" * 64, "person" => 9, "day_key" => 20260924))
  end
end
snapshot_period = Struct.new(:from_day, :to_day).new(20260923, 20260926)
first_snapshot = snapshot_store.report(snapshot_period)
assert(first_snapshot["visitors"] == 2, "A row inserted during pagination leaked into the current snapshot")
assert(first_snapshot["first_day"] == 20260925, "A concurrent row changed the collection boundary of an existing snapshot")
assert(snapshot_events.queries.select { |query| query[:distinct] }.all? { |query| query[:where]["__id"] == {"lte" => 2} },
  "Report pages did not share one snapshot bound")
next_snapshot = snapshot_store.report(snapshot_period)
assert(next_snapshot["visitors"] == 3 && next_snapshot["first_day"] == 20260924,
  "The next report did not include the row inserted during the previous report")

weakened_policies = [
  ["statistics_accounts", "visibility", "public"], ["statistics_accounts", "unique_per_user", false],
  ["statistics_accounts", "permissions", {"select" => true, "insert" => true, "update" => true, "creator_share" => true}],
  ["statistics_events", "filter_for", "others"], ["statistics_events", "filtered_columns", []],
  ["statistics_events", "permissions", {"select" => true, "insert" => true, "update" => true}],
  ["statistics_events", "permissions", {"select" => true, "insert" => true, "delete" => true}]
]
weakened_policies.each do |table_name, field, value|
  policy_store, policy_api, private_table, public_table = statistics_fixture
  policy_store.write_batch([{"kind" => "visit", "day_key" => 20260925}])
  queries_before = public_table.queries.length
  policy_api.schema_value["data"]["server"]["tables"][table_name][field] = value
  assert_raises(GameRoomStatistics::Unavailable, "A cached identity bypassed a weakened #{table_name}/#{field} policy") do
    policy_store.write_batch([{"kind" => "visit", "day_key" => 20260926}])
  end
  assert(public_table.rows.length == 1 && public_table.queries.length == queries_before && private_table.upserts == 1,
    "A weakened policy allowed statistics traffic after identity caching")
  policy_api.schema_value = JSON.parse(STATISTICS_SAFE_SCHEMA)
  assert(policy_store.write_batch([{"kind" => "visit", "day_key" => 20260926}]) && public_table.rows.length == 2,
    "Restoring the privacy policy did not allow a retry")
end

[nil, 0, -1, "2", "broken", false, 1.5].each do |id|
  invalid_store, _invalid_api, _private_table, public_table = statistics_fixture
  public_table.insert(snapshot_row)
  public_table.after_select = lambda do |query, rows|
    rows.first["__id"] = id if query[:columns] == ["__id"]
  end
  assert_raises(GameRoomStatistics::Unavailable, "An invalid snapshot ID became an empty or partial report: #{id.inspect}") do
    invalid_store.report(snapshot_period)
  end
  assert(public_table.queries.length == 1, "A malformed snapshot was used for subsequent queries")
end

[nil, 0, -1, "7invalid", false, 1.5].each do |id|
  invalid_store, _invalid_api, _private_table, public_table = statistics_fixture
  public_table.after_insert = ->(row) { row["__id"] = id }
  assert_raises(GameRoomStatistics::Unavailable, "A malformed public write acknowledgement was accepted: #{id.inspect}") do
    invalid_store.write_batch([{"kind" => "visit", "day_key" => 20260925}])
  end
  public_table.after_insert = nil
  assert(invalid_store.write_batch([{"kind" => "visit", "day_key" => 20260925}]) && public_table.rows.length == 1,
    "Retrying a malformed acknowledgement duplicated its event")
end

[nil, false, "20260925", 20260230].each do |day|
  invalid_store, _invalid_api, _private_table, public_table = statistics_fixture
  public_table.insert(snapshot_row)
  public_table.after_select = ->(query, rows) { rows.first["first_day"] = day if query[:aggregates] }
  assert_raises(GameRoomStatistics::Unavailable, "A malformed collection date became valid report coverage: #{day.inspect}") do
    invalid_store.report(snapshot_period)
  end
end
empty_store, _empty_api, _private_table, _public_table = statistics_fixture
empty_report = empty_store.report(snapshot_period)
assert(empty_report.values_at("visitors", "players", "started", "completed", "first_day", "partial") == [0, 0, 0, 0, nil, false],
  "An actually empty table was confused with malformed collection metadata")
assert(empty_store.years(today: Date.new(2026, 9, 25)) == [2026], "An empty table lost the current calendar year")

bad_records = GameRoomStatistics::Schema::FIELDS.map { |field| snapshot_row.reject { |key, _| key == field } }
bad_records.concat([
  nil, {}, snapshot_row.merge("event_key" => "not-a-digest"), snapshot_row.merge("event_key" => 1),
  snapshot_row.merge("kind" => "unknown"), snapshot_row.merge("day_key" => 20260230),
  snapshot_row.merge("day_key" => "20260925"), snapshot_row.merge("person" => "7"),
  snapshot_row.merge("person" => 0), snapshot_row.merge("person" => 1.5),
  snapshot_row.merge("kind" => "player", "game" => {}, "mode" => "solo"),
  snapshot_row.merge("kind" => "player", "game" => "chess", "mode" => "unknown"),
  snapshot_row.merge("kind" => "started", "game" => "chess", "mode" => "humans")
])
bad_records.each do |record|
  invalid_store, _invalid_api, _private_table, public_table = statistics_fixture
  public_table.insert(snapshot_row)
  public_table.after_select = ->(query, rows) { rows.replace([record]) if query[:distinct] }
  assert_raises(GameRoomStatistics::Unavailable, "A malformed public row became report data: #{record.inspect}") do
    invalid_store.report(snapshot_period)
  end
end

large_store, _large_api, _private_table, large_events = statistics_fixture
4001.times do |index|
  large_events.rows << snapshot_row.merge("__id" => index + 1, "event_key" => format("%064x", index + 1), "person" => index + 1)
end
large_report = large_store.report(snapshot_period)
assert(large_report["visitors"] == 4001, "The report silently truncated activity beyond the first two pages")
assert(large_events.queries.select { |query| query[:distinct] }.map { |query| query[:offset] } == [0, 2000, 4000],
  "The report did not exhaust the default-size pages")
large_events.after_select = ->(query, _rows) { raise IOError, "later page unavailable" if query[:distinct] && query[:offset] > 0 }
assert_raises(IOError, "A later-page failure returned a partial report as success") { large_store.report(snapshot_period) }

repeated_store, repeated_api, _private_table, repeated_events = statistics_fixture
repeated_api.schema_value["data"]["server"]["tables"]["statistics_events"]["limits"]["max_select_limit"] = 2
repeated_events.rows.concat(large_events.rows.first(3).map(&:dup))
first_page, page_calls = nil, 0
repeated_events.after_select = lambda do |query, rows|
  if query[:distinct]
    page_calls += 1
    raise "The store kept reading repeated pages" if page_calls > 2
    first_page ||= rows.map(&:dup)
    rows.replace(first_page.map(&:dup))
  end
end
assert_raises(GameRoomStatistics::Unavailable, "A repeated page was silently truncated or accepted") do
  repeated_store.report(snapshot_period)
end
assert(page_calls == 2, "Pagination did not stop immediately on the repeated page")

def statistics_cross_day_race(kind, accepted_day, replayed_day)
  store, api, _accounts, events = statistics_fixture
  other = GameRoomStatistics::Store.new(app_uuid: "statistics-app", user: "Alice", client: Object.new,
    api: api, current_user: -> { "Alice" })
  payload = {"kind" => kind, "game" => "four_in_a_row", "mode" => "humans",
    "match" => "44444444-4444-4444-8444-444444444444"}
  entered, releases = ::Queue.new, [::Queue.new, ::Queue.new]
  events.after_select = lambda do |query, _rows|
    if query[:where]["event_key"].is_a?(String)
      index = Thread.current[:statistics_writer]
      entered << index
      releases[index].pop
    end
  end
  threads = [store, other].each_with_index.map do |writer, index|
    Thread.new do
      Thread.current[:statistics_writer] = index
      writer.write_batch([payload.merge("day_key" => [accepted_day, replayed_day][index])])
    end
  end
  2.times { entered.pop }
  releases[0] << true
  assert(threads[0].value, "The first concurrent writer did not finish")
  releases[1] << true
  assert(threads[1].value, "The second concurrent writer did not finish")
  events.after_select = nil
  assert(events.rows.length == 2 && events.rows.map { |row| row["event_key"] }.uniq.length == 1,
    "The race was not reproduced: both clients must select before either inserts")
  accepted = events.rows.min_by { |row| row["__id"] }
  assert(accepted["day_key"] == accepted_day, "The race did not fix the intended first server row")
  dates = Struct.new(:from_day, :to_day)
  assert(store.report(dates.new(accepted_day, accepted_day))[kind] == 1, "The first accepted #{kind} day was lost")
  assert(store.report(dates.new(replayed_day, replayed_day))[kind] == 0,
    "A concurrent #{kind} replay was counted on another day")
  assert(store.report(dates.new(20260925, 20260926))[kind] == 1, "The interval counted a raced #{kind} twice")
  assert(store.report(dates.new(nil, 20260926))[kind] == 1, "All-time counted a raced #{kind} twice")
ensure
  releases&.each { |release| release << true }
  threads&.each(&:join)
end

%w[started completed].each do |kind|
  statistics_cross_day_race(kind, 20260925, 20260926)
  statistics_cross_day_race(kind, 20260926, 20260925)
end

%w[started completed].each do |kind|
  canonical_store, _api, _accounts, canonical_events = statistics_fixture
  payload = {"kind" => kind, "game" => "four_in_a_row", "mode" => "humans", "day_key" => 20260926,
    "match" => "55555555-5555-4555-8555-555555555555"}
  canonical_store.write_batch([payload])
  original = canonical_events.rows.first.dup
  canonical_events.insert(original.reject { |key, _| key == "__id" }.merge("game" => "war", "mode" => "bots", "day_key" => 20260925))
  canonical_events.rows.reverse!
  assert(canonical_store.write_batch([payload.merge("day_key" => 20260927)]), "A retry did not acknowledge the first accepted #{kind} row")
  %w[game mode].each do |field|
    changed = payload.merge(field => {"game" => "war", "mode" => "bots"}.fetch(field))
    assert_raises(GameRoomStatistics::Unavailable, "A changed #{field} was treated as a date-only replay") do
      canonical_store.write_batch([changed])
    end
  end
  assert(canonical_events.rows.length == 2 && canonical_events.rows.last == original, "A retry rewrote canonical match data")
end

canonical_failures = [
  [:first, ->(rows) { rows.clear }],
  [:first, ->(rows) { rows << rows.first.dup }],
  [:first, ->(rows) { rows.first["event_key"] = "f" * 64 }],
  [:first, ->(rows) { rows.first["first_id"] = nil }],
  [:first, ->(rows) { rows.first["first_id"] = "1" }],
  [:first, ->(rows) { rows.first["first_id"] = 0 }],
  [:first, ->(rows) { rows.first["first_id"] = 3 }],
  [:records, ->(rows) { rows.clear }],
  [:records, ->(rows) { rows << rows.first.dup }],
  [:records, ->(rows) { rows.first["__id"] = 2 }],
  [:records, ->(rows) { rows.first["event_key"] = "f" * 64 }],
  [:records, ->(rows) { rows.first["day_key"] = 20260230 }]
]
canonical_failures.each do |stage, corrupt|
  canonical_store, _api, _accounts, canonical_events = statistics_fixture
  row = {"event_key" => "d" * 64, "kind" => "completed", "game" => "war", "mode" => "humans", "person" => 0}
  canonical_events.insert(row.merge("day_key" => 20260925))
  canonical_events.insert(row.merge("day_key" => 20260926))
  canonical_events.after_select = lambda do |query, rows|
    reached = query[:group_by] ? :first : (query[:where].dig("__id", "in") ? :records : nil)
    corrupt.call(rows) if reached == stage
  end
  assert_raises(GameRoomStatistics::Unavailable, "Incomplete or malformed canonical #{stage} returned a report") do
    canonical_store.report(Struct.new(:from_day, :to_day).new(20260926, 20260926))
  end
end

bounded_store, _api, _accounts, bounded_events = statistics_fixture
4001.times do |index|
  bounded_events.rows << snapshot_row.merge("__id" => index + 1, "event_key" => format("%064x", index + 1), "day_key" => 20200101)
end
canonical_rows = 205.times.map do |index|
  row = {"event_key" => Digest::SHA256.hexdigest("bounded-match-#{index}"), "kind" => "completed",
    "game" => "war", "mode" => "humans", "person" => 0, "day_key" => index.even? ? 20260925 : 20260926}
  canonical = bounded_events.insert(row)
  bounded_events.insert(row.merge("day_key" => index.even? ? 20260926 : 20260925))
  canonical
end
snapshot = bounded_events.rows.last["__id"]
today = Struct.new(:from_day, :to_day).new(20260926, 20260926)
bounded_events.after_select = lambda do |query, _rows|
  if query[:group_by]
    bounded_events.after_select = nil
    bounded_events.insert(canonical_rows.last.reject { |key, _| key == "__id" }.merge("day_key" => 20260926, "event_key" => "0" * 64))
  end
end
expected = canonical_rows.count { |row| row["day_key"] == today.to_day }
bounded_report = bounded_store.report(today)
assert(bounded_report["completed"] == expected, "Today used later replay dates or rows inserted during reconciliation")
assert(bounded_report["games"].map { |row| [row["id"], row["completed"]] } == [["war", expected]], "Canonical game totals differ from the overall report")
queries = bounded_events.queries
groups = queries.select { |query| query[:group_by] }
assert(groups.length == 3 && groups.map { |query| query[:where]["event_key"]["in"].length }.sort == [5, 100, 100],
  "Canonical match lookups were not batched into supported key chunks")
assert(groups.all? { |query| query[:where]["__id"] == {"lte" => snapshot} && !query[:where].key?("day_key") &&
  query[:columns] == ["event_key"] && query[:group_by] == ["event_key"] &&
  query[:aggregates] == {"first_id" => {"function" => "min", "column" => "__id"}} && query[:limit] <= 100 },
  "Canonical identities lost the snapshot bound or used a date-filtered/unsupported aggregate")
records = queries.select { |query| query[:where].dig("__id", "in") }
assert(records.length == 3 && records.all? { |query| query[:where]["__id"]["in"].length <= 100 &&
  query[:where]["__id"]["in"].all? { |id| id <= snapshot } && query[:limit] <= 100 },
  "Canonical row reads escaped their bounded snapshot IDs")
assert(records.flat_map { |query| query[:where]["__id"]["in"] }.sort == canonical_rows.map { |row| row["__id"] }.sort,
  "The canonical reader downloaded history other than the first candidate match rows")
assert(queries.all? { |query| query[:columns] == ["__id"] || query[:aggregates] ||
  query[:where].dig("__id", "in") || query[:where]["day_key"] == {"in" => [today.to_day]} },
  "Today downloaded unrelated historical events")
assert(queries.length == 9, "Today made unbounded/per-match historical reads")
assert(bounded_store.report(today)["completed"] == expected + 1, "The next snapshot did not include the concurrent new match")

[:cancel, :account_change].each do |interruption|
  [:first, :records].each do |stage|
    user, token = "Alice", StatisticsCancellation.new
    reading_store, _api, _accounts, reading_events = statistics_fixture(current_user: -> { user })
    reading_events.insert("event_key" => "e" * 64, "kind" => "completed", "game" => "war", "mode" => "humans", "person" => 0, "day_key" => 20260926)
    reading_events.after_select = lambda do |query, _rows|
      reached = query[:group_by] ? :first : (query[:where].dig("__id", "in") ? :records : nil)
      interruption == :cancel ? token.cancelled = true : user = "Bob" if reached == stage
    end
    error = interruption == :cancel ? StatisticsCancelled : GameRoomStatistics::Unavailable
    assert_raises(error, "Canonical #{stage} continued after #{interruption}") { reading_store.report(today, cancellation_token: token) }
    assert(reading_events.queries.length == (stage == :first ? 4 : 5), "Canonical reconciliation made another query after interruption")
  end
end

puts "PASS statistics storage: #{$statistics_assertions} assertions (privacy, retries, pagination and cross-day races)"
