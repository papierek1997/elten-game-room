require "json"
require "digest"
require_relative "../lib/game_room_presence_store"

$presence_assertions = 0
$presence_tests = 0

def assert(value, message)
  $presence_assertions += 1
  raise message unless value
end

def assert_raises(error, message)
  $presence_assertions += 1
  begin
    yield
  rescue error => caught
    return caught
  end
  raise message
end

def assert_unavailable(message, &block)
  assert_raises(GameRoomPresence::Unavailable, message, &block)
end

def presence_test(name)
  return if ENV["PRESENCE_CASE"] && !name.include?(ENV["PRESENCE_CASE"])
  yield
  $presence_tests += 1
  puts "PASS #{name}"
end

class PresenceMemoryApi
  attr_accessor :policy, :after_call, :owner, :schema_result
  attr_reader :rows, :calls, :writes

  def initialize
    @policy = JSON.parse(JSON.generate(GameRoomPresence::Schema::TABLES.fetch("room_presence")))
    @policy["permissions"] = %w[select insert update].to_h { |permission| [permission, true] }
    @rows, @calls, @writes, @owner = [], [], [], true
  end

  def schema(_client, uuid)
    complete(:schema, @schema_result || {"data" => {"server" => {"tables" => {"room_presence" => @policy}}}}, uuid)
  end

  def table(_client, uuid, name)
    raise "Unexpected application table" unless uuid == "presence-app" && name == "room_presence"
    self
  end

  def insert(values)
    @writes << [:insert, values.dup]
    row = values.merge("__id" => (@rows.map { |item| item["__id"] }.max || 0) + 1)
    @rows << row
    complete(:insert, row.dup)
  end

  def update(id, values)
    @writes << [:update, values.dup, id]
    row = @rows.find { |item| item["__id"] == id }
    raise "Unknown row updated" unless row
    row.merge!(values)
    complete(:update, row.dup, id)
  end

  def select(where: {}, columns: nil, order: [], limit: 2000, offset: 0, include_access: false, group_by: nil, aggregates: nil)
    %w[reporter_key __id].each do |key|
      values = where[key]
      raise "Canonical lookup exceeds the supported key chunk" if values.is_a?(Hash) && values["in"] && values["in"].length > 100
    end
    raise "Where operator must be unambiguous" if where.values.any? { |value| value.is_a?(Hash) && value.length != 1 }
    selected = @rows.select do |row|
      where.all? do |key, value|
        if value.is_a?(Hash)
          value.all? do |operator, expected|
            case operator
            when "in" then expected.include?(row[key])
            when "lte" then row[key] <= expected
            when "gte" then row[key] >= expected
            else raise "Unsupported query operator: #{operator}"
            end
          end
        else
          row[key] == value
        end
      end
    end
    if aggregates
      raise "Unsupported aggregate" unless group_by == ["reporter_key"] &&
        aggregates == {"first_id" => {"function" => "min", "column" => "__id"}}
      selected = selected.group_by { |row| row["reporter_key"] }.map do |key, rows|
        {"reporter_key" => key, "first_id" => rows.map { |row| row["__id"] }.min}
      end
    end
    order.reverse_each do |key, direction|
      selected = selected.sort_by { |row| row[key] }
      selected.reverse! if direction == "desc"
    end
    selected = selected.drop(offset).first(limit).map do |row|
      values = row.merge(GameRoomPresence::Schema::HIDDEN.to_h { |key| [key, nil] })
      values["__access"] = {"owner" => @owner} if include_access
      columns ? values.select { |key, _| (columns + (aggregates || {}).keys).include?(key) } : values
    end
    complete(:select, selected, {where: where, columns: columns, order: order, limit: limit,
      offset: offset, include_access: include_access, group_by: group_by, aggregates: aggregates})
  end

  def complete(kind, value, options = nil)
    @calls << [kind, options]
    @after_call.call(kind, value, options) if @after_call
    value
  end
end

REPORTER_KEY = Digest::SHA256.hexdigest("random-installation-account-token")

def presence_room(**changes)
  {"room_key" => Digest::SHA256.hexdigest("unrelated-room-uuid"), "game" => "chess",
    "private_room" => false, "people" => 4, "playing" => true}.merge(changes.transform_keys(&:to_s))
end

def presence_fixture(current_user: -> { "Alice" }, clock: -> { 6000.25 }, user: "Alice", reporter_key: REPORTER_KEY, api: PresenceMemoryApi.new)
  store = GameRoomPresence::Store.new(app_uuid: "presence-app", user: user, reporter_key: reporter_key,
    client: Object.new, api: api, current_user: current_user, clock: clock)
  [store, api]
end

presence_test("cross-room privacy") do
  assert(GameRoomPresence::Store.public_instance_methods(false).sort == [:publish, :report], "A write helper bypasses the caller API privacy gate")
  assert(GameRoomPresence::Store.instance_method(:initialize).parameters == [[:keyreq, :app_uuid], [:keyreq, :user], [:keyreq, :reporter_key],
    [:key, :client], [:key, :api], [:key, :current_user], [:key, :clock]], "The constructor's caller API changed")
  store, api = presence_fixture
  room = presence_room(private_room: true, people: 2)
  other = presence_room(room_key: Digest::SHA256.hexdigest("other-private-room"), private_room: true)
  store.publish([room])
  known_reporter = api.rows.first["reporter_key"]
  assert(known_reporter != REPORTER_KEY, "The private installation secret was published as a linkable reporter identity")
  store.publish([other])
  known_rows = api.rows.select { |row| row["reporter_key"] == known_reporter }
  assert(!JSON.generate(known_rows).include?(other["room_key"]), "A known two-person room revealed the reporter's other private room")
  assert(api.rows.length == 2 && api.rows.map { |row| row["reporter_key"] }.uniq.length == 2,
    "Different rooms reused a public reporter key")
  assert(!JSON.generate([api.calls, api.writes]).include?(REPORTER_KEY), "The private installation secret reached an API request")
  assert(api.rows.all? { |row| row.keys.sort == %w[__id reporter_key room_key game private_room people playing seen_slot].sort },
    "Public rows exposed a room bundle or an extra identifying field")
  expected_columns = {"reporter_key" => "string:64", "room_key" => "string:64", "game" => "string:32",
    "private_room" => "integer", "people" => "integer", "playing" => "integer", "seen_slot" => "integer"}
  policy = GameRoomPresence::Schema::TABLES.fetch("room_presence")
  assert(policy["columns"] == expected_columns, "Presence did not use the scalar per-room schema")
  assert(policy["indexes"] == [["reporter_key"], ["room_key"], ["seen_slot"]], "Presence omitted a lookup/expiry index")
end

presence_test("multiroom lifecycle and duplicate sources") do
  store, api = presence_fixture
  rooms = [presence_room, presence_room(room_key: Digest::SHA256.hexdigest("second-room"), game: "uno", private_room: true, people: 3)]
  assert(store.publish(rooms + [presence_room(people: 6, playing: false)]), "Multiroom publication failed")
  assert(api.rows.length == 2 && api.writes.length == 2, "Duplicate sources caused additional writes")
  first = api.rows.find { |row| row["room_key"] == rooms.first["room_key"] }
  assert(first.values_at("people", "playing", "private_room") == [6, 1, 0], "Duplicate sources multiplied counts or lost playing state")
  ids = api.rows.map { |row| row["__id"] }
  store.publish(rooms)
  assert(api.rows.map { |row| row["__id"] } == ids, "Heartbeats appended rows")
  store.publish([rooms.last])
  assert(first.values_at("room_key", "game", "people", "private_room", "playing", "seen_slot") == ["", "", 0, 0, 0, 100],
    "Changing rooms did not clear every scalar field of the abandoned room")
  second, = presence_fixture(api: api, reporter_key: Digest::SHA256.hexdigest("second-installation"))
  second.publish(rooms)
  assert(api.rows.length == 4 && api.rows.map { |row| row["reporter_key"] }.uniq.length == 4,
    "Independent installations reused room reporters")
  assert(store.publish([]) && api.rows.first(2).all? { |row| row["people"] == 0 && row["room_key"] == "" }, "Empty publication did not clear this installation")
  assert(api.rows.last(2).all? { |row| row["people"] > 0 }, "A clear erased another installation")
  count = api.writes.length
  store.publish([])
  assert(api.writes.length == count, "An already empty installation wrote a synthetic empty row")
  restarted, = presence_fixture(api: api)
  restarted.publish(rooms)
  assert(api.rows.length == 4 && api.rows.first(2).map { |row| row["__id"] } == ids, "Rejoining rooms lost stable per-room identity")
  assert(api.calls.select { |kind, q| kind == :select && q[:include_access] }.all? { |_, q| q[:columns].nil? },
    "Owner verification projected away __access")
  api.writes.each do |_, values, id|
    assert(api.calls.any? { |kind, q| kind == :select && q[:include_access] && q[:where] == {"__id" => id || api.rows.find { |r| r["reporter_key"] == values["reporter_key"] }["__id"]} },
      "Publication omitted exact-ID ownership readback")
  end
end

def presence_row(id, room: presence_room, reporter: "reporter-#{id}", seen_slot: 100)
  values = room ? room.merge("private_room" => room["private_room"] ? 1 : 0, "playing" => room["playing"] ? 1 : 0) :
    {"room_key" => "", "game" => "", "people" => 0, "private_room" => 0, "playing" => 0}
  values.merge("__id" => id, "reporter_key" => Digest::SHA256.hexdigest(reporter), "seen_slot" => seen_slot)
end

presence_test("expiry and member report deduplication") do
  now = 6059.999
  store, api = presence_fixture(clock: -> { now })
  private_room = presence_room(room_key: Digest::SHA256.hexdigest("private"), game: "uno", private_room: true, people: 5, playing: false)
  api.rows.concat([presence_row(1, seen_slot: 99), presence_row(2, room: private_room, seen_slot: 99),
    presence_row(3), presence_row(4, room: presence_room(people: 99), seen_slot: 98),
    presence_row(5, room: private_room, seen_slot: 101), presence_row(6, room: nil)])
  assert(store.report == {"public_rooms" => 1, "private_rooms" => 1, "people" => 9, "games" => [
    {"id" => "chess", "public_rooms" => 1, "private_rooms" => 0, "people" => 4, "playing_rooms" => 1},
    {"id" => "uno", "public_rooms" => 0, "private_rooms" => 1, "people" => 5, "playing_rooms" => 0}
  ]}, "Scalar reports did not deduplicate all members and include public/private rooms")
  now = 6060
  assert(store.report["people"] == 9, "Minute boundary did not advance the two-slot window")
  now = 6120
  assert(store.report.values_at("public_rooms", "private_rooms", "people") == [0, 1, 5], "Expired reports remained in the census")
  empty, = presence_fixture
  assert(empty.report == {"public_rooms" => 0, "private_rooms" => 0, "people" => 0, "games" => []}, "An empty table did not produce a genuine zero census")
  competing = [presence_row(1, room: presence_room(people: 20), seen_slot: 99),
    presence_row(2, room: presence_room(people: 4, playing: false)), presence_row(3, room: presence_room(people: 6))]
  competing.permutation.each do |reports|
    store, api = presence_fixture
    api.rows.concat(reports.each_with_index.map { |row, i| row.merge("__id" => i + 1) })
    report = store.report
    assert(report.values_at("public_rooms", "people") == [1, 6], "Room counts were summed or an older member count won")
    assert(report["games"].first["playing_rooms"] == 1, "Same-slot playing state was lost")
  end
  store, api = presence_fixture
  api.rows.concat(competing.first(2))
  assert(store.report["games"].first.values_at("people", "playing_rooms") == [4, 0], "An older playing flag survived the latest slot")
  [{game: "uno"}, {private_room: true}].each do |conflict|
    store, api = presence_fixture
    api.rows.concat([presence_row(1), presence_row(2, room: presence_room(**conflict))])
    assert_unavailable("Stable room fields disagreed without an error") { store.report }
  end
end

presence_test("canonical clear defeats duplicate initial inserts") do
  store, api = presence_fixture
  store.publish([presence_room])
  api.rows << api.rows.first.merge("__id" => 2)
  store.publish([])
  assert(api.rows.first.values_at("room_key", "people") == ["", 0], "Clear updated a higher duplicate instead of the lowest canonical ID")
  assert(api.rows.last["people"] == 4 && store.report["people"] == 0, "A higher-ID stale active duplicate resurrected a cleared report")
  [98, 99, 100, 101].each do |slot|
    [nil, presence_room].each do |canonical_room|
      next if canonical_room && [99, 100].include?(slot)
      reader, memory = presence_fixture
      memory.rows.concat([presence_row(1, room: canonical_room, reporter: "same", seen_slot: slot),
        presence_row(2, reporter: "same"), presence_row(3, room: presence_room(people: 2))])
      assert(reader.report["people"] == 2, "A cleared or expired canonical row lost to an active duplicate (slot #{slot})")
      queries = memory.calls.select { |kind, _| kind == :select }.map(&:last)
      assert(queries.any? { |q| q[:group_by] == ["reporter_key"] && !q[:where].key?("seen_slot") &&
        q[:aggregates] == {"first_id" => {"function" => "min", "column" => "__id"}} }, "Canonical identity was chosen after filtering expiry")
      assert(queries.any? { |q| q[:where]["__id"].is_a?(Hash) && q[:where]["__id"]["in"]&.include?(1) },
        "Canonical data was not read by exact ID")
    end
  end
  reader, memory = presence_fixture
  memory.rows.concat([presence_row(1, room: presence_room(people: 2), reporter: "same", seen_slot: 99),
    presence_row(2, room: presence_room(people: 99), reporter: "same")])
  assert(reader.report["people"] == 2, "A newer duplicate slot overrode its canonical reporter row")
  store, api = presence_fixture
  injected = false
  api.after_call = ->(kind, rows, query) do
    if kind == :select && query[:where].key?("reporter_key") && !injected
      injected = true
      api.rows << presence_row(1, room: nil).merge("reporter_key" => query[:where]["reporter_key"])
    end
  end
  assert(store.publish([presence_room]), "A racing initial insertion could not converge")
  assert(api.rows.length == 2 && api.rows.first["people"] == 4, "A racing insert did not reconcile to the lower ID")
  api.after_call = nil
  store.publish([])
  assert(store.report["people"] == 0, "A racing insertion survived a canonical clear")
end

presence_test("uncertain writes remain clearable on retry") do
  [:insert, :update, :readback].each do |boundary|
    store, api = presence_fixture
    store.publish([presence_room]) if boundary == :update
    api.after_call = ->(kind, _, query) do
      if kind == boundary || (boundary == :readback && kind == :select && query[:where]["__id"].is_a?(Integer))
        raise IOError, "lost acknowledgement"
      end
    end
    assert_raises(IOError, "An uncertain #{boundary} was acknowledged") { store.publish([presence_room(people: 7)]) }
    api.after_call = nil
    assert(store.publish([]) && api.rows.length == 1, "Retry after #{boundary} lost track of a possibly published room")
    assert(api.rows.first.values_at("room_key", "people") == ["", 0] && store.report["people"] == 0,
      "Empty retry after #{boundary} left stale activity")
    store.publish([presence_room])
    assert(api.rows.length == 1 && store.report["people"] == 4, "Retry appended a heartbeat row")
  end
  store, api = presence_fixture
  rooms = [presence_room, presence_room(room_key: Digest::SHA256.hexdigest("partial-second"))]
  api.after_call = ->(kind, _, _) { raise IOError, "partial insertion" if kind == :insert && api.rows.length == 2 }
  assert_raises(IOError, "Partial publication was acknowledged") { store.publish(rooms) }
  api.after_call = nil
  assert(store.publish([]) && api.rows.length == 2 && store.report["people"] == 0, "Partial multiroom publication was not fully cleared")
  store.publish(rooms)
  api.after_call = ->(kind, _, _) { raise IOError, "uncertain clear" if kind == :update }
  assert_raises(IOError, "Uncertain clear was acknowledged") { store.publish([]) }
  api.after_call = nil
  assert(store.publish([]) && api.rows.length == 2 && store.report["people"] == 0, "A failed clear dropped its retry state")
end

INVALID_ROOMS = [presence_room(people: 0), presence_room(people: -1), presence_room(people: 2.0),
  presence_room(private_room: 1), presence_room(playing: "true"), presence_room(game: ""),
  presence_room(game: "chess rooms"), presence_room(game: "g" * 33), presence_room(room_key: "native-session-id"),
  presence_room(room_key: "A" * 64), presence_room(username: "Alice"), presence_room(roster: ["Alice"]),
  presence_room(seen_slot: 10), presence_room.reject { |key, _| key == "playing" }, presence_room.transform_keys(&:to_sym), nil]

UNSAFE_POLICIES = [
  ->(p) { p["visibility"] = "shared" }, ->(p) { p["unique_per_user"] = true },
  ->(p) { p["filter_for"] = "others" }, ->(p) { p["filtered_columns"].pop },
  ->(p) { p["columns"]["username"] = "string:32" }, ->(p) { p["columns"].delete("room_key") },
  ->(p) { p["permissions"]["delete"] = true }, ->(p) { p["permissions"]["creator_share"] = true },
  ->(p) { p["permissions"]["guest_share"] = true }, ->(p) { p["permissions"]["update"] = false },
  ->(p) { p["permissions"] = %w[select insert update] }, ->(p) { p["limits"]["max_select_limit"] = 0 }
]

presence_test("strict payload and privacy gates") do
  policy = GameRoomPresence::Schema::TABLES.fetch("room_presence")
  assert(GameRoomPresence::Schema::TABLES.keys == ["room_presence"], "Presence added unrelated tables")
  assert(policy["visibility"] == "public" && policy["unique_per_user"] == false, "Installations share an account-unique row")
  assert(policy["filtered_columns"].sort == %w[__insertion_user __last_update_user __insertion_time __last_update_time].sort &&
    policy["filter_for"] == "everyone", "Presence exposes identity or exact timestamps")
  assert(policy["permissions"].sort == %w[select insert update].sort && policy.dig("limits", "max_select_limit") == 2000,
    "Presence enabled deletion/sharing or lost its page bound")
  (INVALID_ROOMS.map { |room| [room] } + [nil, {}, false]).each do |payload|
    store, api = presence_fixture
    assert_raises(ArgumentError, "An invalid or identifying payload was accepted") { store.publish(payload) }
    assert(api.calls.empty?, "Invalid presence data contacted the server")
  end
  [nil, "Alice", "A" * 64, 7].each do |key|
    assert_raises(ArgumentError, "An invalid installation secret was accepted") { presence_fixture(reporter_key: key) }
  end
  [nil, "6000", false, 0, -1, Float::NAN, Float::INFINITY, -Float::INFINITY].each do |time|
    store, api = presence_fixture(clock: -> { time })
    assert_unavailable("An invalid clock was accepted") { store.publish([]) }
    assert(api.calls.empty?, "Presence used an invalid clock")
  end
  [[5999.999, 99], [6000, 100], [Time.at(6000.25), 100]].each do |time, slot|
    store, api = presence_fixture(clock: -> { time })
    store.publish([presence_room])
    assert(api.rows.first["seen_slot"] == slot, "Minute expiry was stamped incorrectly")
  end
  UNSAFE_POLICIES.each do |weaken|
    [:publish, :report].each do |operation|
      store, api = presence_fixture
      weaken.call(api.policy)
      assert_unavailable("Weakened privacy was accepted by #{operation}") { operation == :publish ? store.publish([]) : store.report }
      assert(api.calls.map(&:first) == [:schema], "Presence accessed rows before validating privacy")
    end
  end
  [{}, [], {"data" => {"tables" => GameRoomPresence::Schema::TABLES}}].each do |schema|
    store, api = presence_fixture
    api.schema_result = schema
    assert_unavailable("Missing normalized schema was accepted") { store.publish([]) }
  end
  store, api = presence_fixture
  store.publish([presence_room])
  api.policy["filtered_columns"] = []
  assert_unavailable("A cached safe policy bypassed weakened masks") { store.publish([]) }
  assert(api.writes.length == 1, "Presence wrote after privacy protections were removed")
  [{game: "uno"}, {private_room: true}].each do |conflict|
    store, api = presence_fixture
    assert_unavailable("Conflicting local sources produced a partial publication") { store.publish([presence_room, presence_room(**conflict)]) }
    assert(api.calls.empty?, "Conflicting local sources contacted the server")
  end
end

presence_test("exact write and ownership confirmation") do
  [:insert, :update, :readback].each do |boundary|
    ["__id", *GameRoomPresence::Schema::FIELDS].each do |field|
      store, api = presence_fixture
      store.publish([presence_room]) if boundary == :update
      api.after_call = ->(kind, value, query) do
        value[field] = nil if kind == boundary
        value.first[field] = nil if boundary == :readback && kind == :select && query[:where]["__id"].is_a?(Integer)
      end
      assert_unavailable("Mismatching #{boundary} #{field} was acknowledged") { store.publish([presence_room]) }
    end
    %w[people playing private_room seen_slot].each do |field|
      store, api = presence_fixture
      store.publish([presence_room]) if boundary == :update
      api.after_call = ->(kind, value, query) do
        value[field] = value[field].to_f if kind == boundary
        if boundary == :readback && kind == :select && query[:where]["__id"].is_a?(Integer)
          value.first[field] = value.first[field].to_f
        end
      end
      assert_unavailable("Type-corrupted #{boundary} #{field} was acknowledged") { store.publish([presence_room]) }
    end
  end
  [false, nil, "true", 1].each do |owner|
    store, api = presence_fixture
    store.publish([presence_room])
    api.owner = owner
    assert_unavailable("An unowned room reporter was updated") { store.publish([presence_room]) }
    assert(api.writes.length == 1, "An unowned reporter row was modified")
    store, api = presence_fixture
    api.owner = owner
    assert_unavailable("An insert was acknowledged without owner verification") { store.publish([presence_room]) }
  end
  store, api = presence_fixture
  store.publish([presence_room])
  api.after_call = ->(kind, value, _) { value["__id"] = 9 if kind == :update }
  assert_unavailable("A different row's acknowledgement was accepted") { store.publish([]) }
  assert(api.calls.last.first == :update, "The wrong row ID was used for readback")
  store, api = presence_fixture
  api.after_call = ->(kind, _, _) { api.rows.clear if kind == :insert }
  assert_unavailable("A disappeared insert was acknowledged") { store.publish([presence_room]) }
end

def presence_read_stage(kind, query)
  return :schema if kind == :schema
  return :snapshot if query[:order] == [["__id", "desc"]]
  return :canonical_ids if query[:aggregates]
  return :canonical_rows if query.dig(:where, "__id").is_a?(Hash) && query[:where]["__id"].key?("in")
  :page
end

presence_test("malformed reads never produce fake zeros") do
  stages = [:snapshot, :page, :canonical_ids, :canonical_rows]
  stages.each do |stage|
    [nil, {}, [nil], [false], [{"__id" => 0}], [{"__id" => "1"}]].each do |replacement|
      store, api = presence_fixture
      api.rows << presence_row(1)
      original = api.method(:select)
      api.define_singleton_method(:select) do |**query|
        result = original.call(**query)
        presence_read_stage(:select, query) == stage ? replacement : result
      end
      assert_unavailable("Malformed #{stage} became a report") { store.report }
    end
    store, api = presence_fixture
    api.policy["limits"]["max_select_limit"] = 1
    api.rows << presence_row(1)
    api.after_call = ->(kind, rows, query) do
      rows << rows.first.dup if presence_read_stage(kind, query) == stage
    end
    assert_unavailable("An oversized #{stage} response became a report") { store.report }
  end
  [:canonical_ids, :canonical_rows].each do |stage|
    [:missing, :duplicate, :foreign_key, :wrong_id].each do |corruption|
      store, api = presence_fixture
      api.rows.concat([presence_row(1), presence_row(2)])
      api.after_call = ->(kind, rows, query) do
        if presence_read_stage(kind, query) == stage
          case corruption
          when :missing then rows.pop
          when :duplicate then rows[-1] = rows.first.dup
          when :foreign_key then rows.first["reporter_key"] = Digest::SHA256.hexdigest("foreign")
          when :wrong_id then rows.first[stage == :canonical_ids ? "first_id" : "__id"] = 3
          end
        end
      end
      assert_unavailable("#{corruption} #{stage} silently produced a partial census") { store.report }
    end
  end
  bad_fields = {"reporter_key" => ["native-user", nil, "A" * 64], "room_key" => [nil, "room-uuid", "A" * 64],
    "game" => [nil, "", "chess rooms", "g" * 33], "people" => [nil, 0, -1, 4.0, "4"],
    "private_room" => [nil, false, "0", 0.0, 2], "playing" => [nil, true, "1", 1.0, 2],
    "seen_slot" => [nil, 100.0, "100", -1], "__id" => [nil, 0, 1.0]}
  [:page, :canonical_rows].each do |stage|
    bad_fields.each do |field, values|
      values.each do |value|
        store, api = presence_fixture
        api.rows << presence_row(1)
        api.after_call = ->(kind, rows, query) { rows.first[field] = value if presence_read_stage(kind, query) == stage }
        assert_unavailable("Malformed #{stage} #{field}=#{value.inspect} became a report") { store.report }
      end
    end
  end
  [98, 101].each do |value|
    store, api = presence_fixture
    api.rows << presence_row(1)
    api.after_call = ->(kind, rows, query) { rows.first["seen_slot"] = value if presence_read_stage(kind, query) == :page }
    assert_unavailable("An initial page escaped its expiry window") { store.report }
  end
  [{"game" => "chess"}, {"people" => 0.0}, {"people" => 2}, {"playing" => 1}, {"private_room" => 1}].each do |fields|
    store, api = presence_fixture
    api.rows << presence_row(1, room: nil).merge(fields)
    assert_unavailable("A malformed cleared row became a report") { store.report }
  end
  ([:schema] + stages).each do |stage|
    store, api = presence_fixture
    api.rows << presence_row(1)
    api.after_call = ->(kind, _, query) { raise IOError, "offline transport failure" if presence_read_stage(kind, query) == stage }
    assert_raises(IOError, "Unavailable #{stage} became a zero census") { store.report }
  end
end

presence_test("mutable expiry eligibility does not skip or repeat later IDs") do
  [:shrinking, :growing].each do |change|
    store, api = presence_fixture(clock: -> { 6059.999 })
    api.policy["limits"]["max_select_limit"] = 2
    api.rows.concat((1..6).map do |id|
      presence_row(id, room: presence_room(room_key: Digest::SHA256.hexdigest("mutable-#{id}"), people: id),
        seen_slot: change == :growing && id == 1 ? 98 : 100)
    end)
    pages = []
    api.after_call = ->(kind, rows, query) do
      if presence_read_stage(kind, query) == :page
        pages << rows.map { |row| row["__id"] }
        api.rows.first["seen_slot"] = change == :shrinking ? 101 : 100 if pages.length == 1
      end
    end
    report = store.report
    assert(report.values_at("public_rooms", "people") == [5, 20],
      "#{change} expiry eligibility skipped an always-eligible room")
    assert(pages.flatten == (change == :shrinking ? [1, 2, 3, 4, 5, 6] : [2, 3, 4, 5, 6]),
      "#{change} expiry eligibility repeated or skipped a later ID")
  end
end

presence_test("bounded indexed pagination and concurrent snapshots") do
  store, api = presence_fixture
  api.rows.concat((1..2005).map { |id| presence_row(id, room: presence_room(room_key: Digest::SHA256.hexdigest("room-#{id}"), people: 1)) })
  assert(store.report.values_at("public_rooms", "people") == [2005, 2005], "Presence truncated the census at one page")
  queries = api.calls.select { |kind, _| kind == :select }.map(&:last)
  assert(queries.first.values_at(:columns, :order, :limit) == [["__id"], [["__id", "desc"]], 1], "Missing ID snapshot")
  pages = queries.select { |q| presence_read_stage(:select, q) == :page }
  assert(pages.map { |q| q[:where]["__id"]["gte"] } == [1, 2001] && pages.all? { |q| q[:offset] == 0 },
    "Presence did not use bounded ID-keyset pages")
  assert(pages.all? { |q| q[:where]["seen_slot"] == {"in" => [99, 100]} && q[:where]["__id"].keys == ["gte"] &&
    q[:order] == [["__id", "asc"]] && q[:limit] == 2000 && q[:columns].sort == (GameRoomPresence::Schema::FIELDS + ["__id"]).sort },
    "Pagination leaked metadata or escaped its snapshot")
  groups = queries.select { |q| q[:aggregates] }
  assert(groups.map { |q| q[:where]["reporter_key"]["in"].length }.sum == 2005, "Canonical resolution lost reporters")
  assert(groups.all? { |q| q[:limit] <= 100 && q[:limit] == q[:where]["reporter_key"]["in"].length &&
    q[:where].keys.sort == %w[__id reporter_key].sort && q[:where]["__id"] == {"lte" => 2005} },
    "Canonical resolution scanned history or exceeded the supported key chunk")
  exact = queries.select { |q| presence_read_stage(:select, q) == :canonical_rows }
  assert(exact.length == groups.length && exact.all? { |q| q[:where].keys == ["__id"] && q[:limit] <= 100 &&
    q[:where]["__id"]["in"].length == q[:limit] }, "Canonical records were not read by bounded exact IDs")
  assert(queries.length == 1 + pages.length + groups.length + exact.length, "Unexpected full-history reads occurred")
  [1, 2].each do |limit|
    store, api = presence_fixture
    api.policy["limits"]["max_select_limit"] = limit
    api.rows.concat((1..3).map { |id| presence_row(id) })
    api.after_call = ->(kind, _, _) { api.rows << presence_row(api.rows.length + 1, room: presence_room(people: 50)) if kind == :select }
    assert(store.report["people"] == 4, "Concurrent inserts entered the ID snapshot")
    assert(api.calls.select { |kind, _| kind == :select }.all? { |_, q| q[:limit] <= limit }, "Canonical reads ignored the server limit")
  end
  store, api = presence_fixture
  api.policy["limits"]["max_select_limit"] = 2
  api.rows.concat((1..3).map { |id| presence_row(id) })
  first_page = nil
  api.after_call = ->(kind, values, query) do
    if presence_read_stage(kind, query) == :page
      first_page ? values.replace(first_page) : first_page = values.map(&:dup)
    end
  end
  assert_unavailable("A repeated page produced a partial census") { store.report }
  assert(api.calls.count { |kind, q| presence_read_stage(kind, q) == :page } == 2, "Repeated pages were not rejected immediately")
  store, api = presence_fixture
  api.policy["limits"]["max_select_limit"] = 2
  api.rows.concat((1..3).map { |id| presence_row(id, room: presence_room(room_key: Digest::SHA256.hexdigest("parallel-#{id}"), people: 1)) })
  published = false
  api.after_call = ->(kind, _, query) do
    if presence_read_stage(kind, query) == :page && !published
      published = true
      api.policy["limits"]["max_select_limit"] = 2000
      store.publish([])
    end
  end
  assert(store.report["people"] == 3, "Overlapping publication changed a report's local page limit")
end

class PresenceCancelled < StandardError; end
class PresenceCancellation
  attr_accessor :cancelled
  def raise_if_cancelled!
    raise PresenceCancelled, "Presence cancelled" if @cancelled
  end
end

def presence_scenario(operation, current_user: -> { "Alice" })
  store, api = presence_fixture(current_user: current_user)
  store.publish([presence_room, presence_room(room_key: Digest::SHA256.hexdigest("other"))]) if [:update, :clear].include?(operation)
  api.calls.clear
  api.writes.clear
  if operation == :race
    injected = false
    api.after_call = ->(kind, _, query) do
      if kind == :select && query[:where].key?("reporter_key") && !injected
        injected = true
        api.rows << presence_row(1, room: nil).merge("reporter_key" => query[:where]["reporter_key"])
      end
    end
  elsif operation == :report
    api.policy["limits"]["max_select_limit"] = 2
    api.rows.concat((1..3).map { |id| presence_row(id) })
  end
  [store, api]
end

def presence_operation(store, operation, token = nil)
  return store.report(cancellation_token: token) if operation == :report
  rooms = operation == :clear ? [] : [presence_room, presence_room(room_key: Digest::SHA256.hexdigest("other"))]
  store.publish(rooms, cancellation_token: token)
end

presence_test("cancellation and account pinning at every boundary") do
  [:insert, :update, :clear, :race, :report].each do |operation|
    store, api = presence_scenario(operation)
    presence_operation(store, operation)
    call_count = api.calls.length
    [:cancel, :account_change].each do |interruption|
      (0..call_count).each do |boundary|
        user = "Alice"
        interrupted, memory = presence_scenario(operation, current_user: -> { user })
        token = PresenceCancellation.new
        interrupt = -> { interruption == :cancel ? token.cancelled = true : user = "Bob" }
        old_hook = memory.after_call
        memory.after_call = ->(kind, value, query) do
          old_hook.call(kind, value, query) if old_hook
          interrupt.call if memory.calls.length == boundary
        end
        interrupt.call if boundary == 0
        error = interruption == :cancel ? PresenceCancelled : GameRoomPresence::Unavailable
        assert_raises(error, "Interrupted #{operation} returned success at #{boundary}") { presence_operation(interrupted, operation, token) }
        assert(memory.calls.length == boundary, "#{operation} continued network calls after #{interruption}/#{boundary}")
      end
    end
  end
  user = "Alice"
  store, api = presence_fixture(user: user, current_user: -> { user })
  store.publish([presence_room])
  api.calls.clear
  user.replace("Bob")
  assert_unavailable("A mutable account name changed the pinned installation") { store.publish([]) }
  assert(api.calls.empty?, "An account-switch clear contacted the server")
  store, = presence_fixture(current_user: -> { "aLiCe" })
  assert(store.publish([presence_room]), "Case-only account spelling was rejected")
  key = REPORTER_KEY.dup
  store, api = presence_fixture(reporter_key: key)
  store.publish([presence_room])
  original = api.rows.first["reporter_key"]
  key.replace(Digest::SHA256.hexdigest("other installation"))
  store.publish([presence_room])
  assert(api.rows.length == 1 && api.rows.first["reporter_key"] == original, "Mutable input changed the pinned private secret")
end

presence_test("real host Apps/AppTable offline transport") do
  host = ENV.fetch("ELTEN_HOST_SOURCE", File.expand_path("../../elten3", __dir__))
  require File.join(host, "src/eltenlink/apps")

  class PresenceSdkClient
    attr_reader :memory, :requests

    def initialize
      @memory, @requests = PresenceMemoryApi.new, []
    end

    def api_data(method, path, options = nil)
      @requests << [method, path, options]
      root = "/api/v1/apps/presence-app"
      rows_path = "#{root}/tables/room_presence/rows"
      if method == "GET" && path == "#{root}/schema"
        {"app" => @memory.schema(self, "presence-app")}
      elsif method == "POST" && path == "#{rows_path}/query"
        {"rows" => @memory.select(**options.transform_keys(&:to_sym))}
      elsif method == "POST" && path == rows_path
        {"row" => @memory.insert(options.fetch("values"))}
      elsif method == "PATCH" && /\A#{Regexp.escape(rows_path)}\/[1-9][0-9]*\z/.match?(path)
        {"row" => @memory.update(path.split("/").last.to_i, options.fetch("values"))}
      else
        raise "Unexpected native SDK contract: #{method} #{path}"
      end
    end
  end

  client = PresenceSdkClient.new
  native = GameRoomPresence::Store.new(app_uuid: "presence-app", user: "Alice", reporter_key: REPORTER_KEY,
    client: client, api: EltenLink::Apps, current_user: -> { "Alice" }, clock: -> { 6000 })
  rooms = [presence_room, presence_room(room_key: Digest::SHA256.hexdigest("sdk-private"), private_room: true, people: 5)]
  assert(native.publish(rooms), "The real host SDK rejected multiroom insertion")
  assert(native.report.values_at("public_rooms", "private_rooms", "people") == [1, 1, 9], "The real host SDK report failed")
  assert(native.publish(rooms) && client.memory.rows.length == 2, "The real host SDK heartbeat appended rows")
  assert(native.publish([]) && native.report["people"] == 0, "The real host SDK clear failed")
  assert(client.requests.count { |method, path, _| method == "POST" && path.end_with?("/rows") } == 2 &&
    client.requests.count { |method, _, _| method == "PATCH" } == 4, "The real host SDK did not insert once per room then update")
  client.memory.rows << client.memory.rows.first.merge("__id" => 3, "room_key" => rooms.first["room_key"], "game" => "chess", "people" => 4)
  client.memory.rows.first["seen_slot"] = 98
  assert(native.report["people"] == 0, "The actual SDK lost an expired canonical clear behind its recent duplicate")
  queries = client.requests.select { |_, path, _| path.end_with?("/query") }.map(&:last)
  assert(queries.any? { |q| q["group_by"] == ["reporter_key"] && q["aggregates"] == {"first_id" => {"function" => "min", "column" => "__id"}} },
    "The actual SDK did not forward indexed grouped min queries")
  assert(queries.any? { |q| q.dig("where", "__id").is_a?(Hash) && q["where"]["__id"].key?("in") },
    "The actual SDK did not forward exact-ID canonical reads")
  assert(client.requests.none? { |method, _, _| %w[PUT DELETE].include?(method) }, "Presence used unsupported upsert/delete semantics")
  assert(queries.select { |q| q["include_access"] }.all? { |q| !q.key?("columns") }, "Actual SDK requests projected away owner flags")
  assert(!JSON.generate(client.requests).include?(REPORTER_KEY), "The private secret leaked through actual SDK serialization")
end

puts "Room presence store: #{$presence_tests} scenarios, #{$presence_assertions} assertions passed (including real host Apps/AppTable with offline transport)"
