require "json"
require "thread"
require "timeout"
require_relative "../lib/game_room_presence_store"
require_relative "../lib/game_statistics_store"

require_relative "support/host_source"
%w[eltenlink/error eltenlink/client eltenlink/apps eapi/tasks].each { |source| require EltenTestHost.file("src/#{source}.rb") }

module Log
  def self.debug(*) = nil
  def self.warning(*) = nil
  def self.error(*) = nil
end

module EltenAPI::HTTPClient
  class << self
    attr_accessor :transport
    def ejrequest(method, path, params, data = nil, headers: nil, cancellation_token: nil, protocol: nil, &callback)
      transport.dispatch(method, path, params, cancellation_token, callback)
    end
  end
end

$analytics_assertions, $analytics_scenarios, $analytics_failures = 0, 0, []
def assert(value, message)
  $analytics_assertions += 1
  raise message unless value
end

def assert_raises(type, message)
  $analytics_assertions += 1
  begin
    yield
  rescue type => error
    return error
  end
  raise message
end

def analytics_test(name)
  return if ENV["ANALYTICS_CASE"] && !name.include?(ENV["ANALYTICS_CASE"])
  $analytics_scenarios += 1
  yield
  puts "PASS #{name}"
rescue StandardError => error
  $analytics_failures << "#{name}: #{error.class}: #{error.message}"
  warn "FAIL #{$analytics_failures.last}"
end

class AnalyticsHttp
  attr_reader :rows, :requests
  attr_accessor :override, :after_request

  def initialize
    @rows = %w[room_presence statistics_events statistics_accounts].to_h { |name| [name, []] }
    @requests = []
  end

  def dispatch(method, path, params, token, callback)
    uri = URI.parse(path)
    query = URI.decode_www_form(uri.query.to_s).to_h.merge(params)
    %w[where order].each { |key| query[key] = JSON.parse(query[key]) if query[key].is_a?(String) }
    %w[limit offset].each { |key| query[key] = query[key].to_i if query.key?(key) }
    request = {method: method, path: uri.path, query: query, token: token, callback: callback}
    @requests << request
    result = @override ? @override.call(request) : nil
    return if result == :held
    result = response(request) if result.nil?
    @after_request.call(request, result) if @after_request
    callback.call(JSON.generate("success" => true, "data" => result), nil)
  end

  def response(request)
    method, path, query = request.values_at(:method, :path, :query)
    root = "/api/v1/apps/analytics-app"
    if method == "GET" && path == "#{root}/schema"
      tables = JSON.parse(JSON.generate(GameRoomPresence::Schema::TABLES.merge(GameRoomStatistics::Schema::TABLES)))
      tables.each_value { |table| table["permissions"] = table["permissions"].to_h { |key| [key, true] } }
      return {"app" => {"data" => {"server" => {"tables" => tables}}}}
    end
    match = /\A#{Regexp.escape(root)}\/tables\/(room_presence|statistics_events|statistics_accounts)\/rows(?:\/(query|[1-9][0-9]*))?\z/.match(path)
    raise "Unexpected HTTP request: #{method} #{path}" unless match
    rows, suffix = @rows.fetch(match[1]), match[2]
    if (method == "GET" && !suffix) || (method == "POST" && suffix == "query")
      selected = rows.select do |row|
        query.fetch("where", {}).all? do |key, value|
          !value.is_a?(Hash) ? row[key] == value : value.all? do |operator, bound|
            case operator
            when "in" then bound.include?(row[key])
            when "lte" then row[key] <= bound
            when "gte" then row[key] >= bound
            else raise "Unknown comparison #{operator}"
            end
          end
        end
      end
      aggregates = query["aggregates"] || {}
      unless aggregates.empty?
        columns = query["group_by"] || []
        groups = columns.empty? ? {[] => selected} : selected.group_by { |row| row.values_at(*columns) }
        selected = groups.map do |keys, group|
          columns.zip(keys).to_h.merge(aggregates.to_h do |name, spec|
            raise "Unexpected aggregate" unless spec["function"] == "min"
            [name, group.map { |row| row[spec["column"]] }.min]
          end)
        end
      end
      query.fetch("order", []).reverse_each do |key, direction|
        selected = selected.sort_by { |row| row[key] }
        selected.reverse! if direction == "desc"
      end
      selected = selected.map do |row|
        if query["columns"]
          row.slice(*(query["columns"] + aggregates.keys))
        elsif query["include_access"]
          row.merge("__access" => {"owner" => true})
        else
          row.dup
        end
      end
      selected = selected.uniq if query["distinct"]
      return {"rows" => selected.drop(query.fetch("offset", 0)).first(query.fetch("limit", 2000))}
    end
    values = query.fetch("values")
    row = if method == "PATCH"
      rows.find { |item| item["__id"] == suffix.to_i }.tap { |item| item.merge!(values) }
    elsif method == "PUT" && !rows.empty?
      rows.first.tap { |item| item.merge!(values) }
    elsif ["POST", "PUT"].include?(method) && !suffix
      values.merge("__id" => (rows.map { |item| item["__id"] }.max || 0) + 1).tap { |item| rows << item }
    else
      raise "Unexpected write: #{method} #{path}"
    end
    {"row" => row.dup}
  end
end

ROOM = {"room_key" => "a" * 64, "game" => "chess", "private_room" => false, "people" => 4, "playing" => true}.freeze
EVENT = {"event_key" => "b" * 64, "kind" => "completed", "game" => "chess", "day_key" => 20260925, "mode" => "humans", "person" => 0}.freeze
PERIOD = Struct.new(:from_day, :to_day).new(20260925, 20260925)

def analytics_fixture(kind, current_user: -> { "Alice" })
  http = EltenAPI::HTTPClient.transport = AnalyticsHttp.new
  client = EltenLink::Client.new
  common = {app_uuid: "analytics-app", user: "Alice", client: client, current_user: current_user}
  store = if kind == :presence
    http.rows["room_presence"] << ROOM.merge("private_room" => 0, "playing" => 1,
      "reporter_key" => "c" * 64, "seen_slot" => 100, "__id" => 1)
    GameRoomPresence::Store.new(**common, reporter_key: "d" * 64, clock: -> { 6059.999 })
  else
    http.rows["statistics_events"] << EVENT.merge("__id" => 1)
    GameRoomStatistics::Store.new(**common)
  end
  [store, http, client]
end

def analytics_report(store, token = nil)
  if store.is_a?(GameRoomPresence::Store)
    store.report(cancellation_token: token)
  else
    store.report(PERIOD, cancellation_token: token)
  end
end

[:presence, :history].each do |kind|
  error = kind == :presence ? GameRoomPresence::Unavailable : GameRoomStatistics::Unavailable
  [{}, {"rows" => nil}, {"rows" => {}}].each_with_index do |invalid, index|
    analytics_test("raw #{kind} envelope #{index} cannot become a zero report") do
      store, http, = analytics_fixture(kind)
      http.override = ->(request) { invalid if request[:path].end_with?("/query") }
      assert_raises(error, "The real SDK coerced #{invalid.inspect} to an empty report") { analytics_report(store) }
      assert(http.requests.length == 2, "A malformed snapshot triggered later requests")
    end
  end
end

def analytics_operation(store, operation, token)
  case operation
  when :report then analytics_report(store, token)
  when :years then store.years(today: Date.new(2026, 9, 25), cancellation_token: token)
  when :insert, :update then store.publish([ROOM], cancellation_token: token)
  when :clear then store.publish([], cancellation_token: token)
  when :batch
    store.write_batch([{"kind" => "visit", "day_key" => 20260925},
      {"kind" => "started", "game" => "chess", "mode" => "humans", "day_key" => 20260925,
        "match" => "11111111-1111-4111-8111-111111111111"}], cancellation_token: token)
  end
end

def analytics_operation_fixture(kind, operation, **options)
  store, http, client = analytics_fixture(kind, **options)
  store.publish([ROOM]) if [:update, :clear].include?(operation)
  http.requests.clear
  [store, http, client]
end

{presence: [:report, :insert, :update, :clear], history: [:report, :years, :batch]}.each do |kind, operations|
  operations.each do |operation|
    analytics_test("in-flight #{kind} #{operation} cancels every native HTTP boundary") do
      store, http, = analytics_operation_fixture(kind, operation)
      analytics_operation(store, operation, EltenAPI::Tasks::CancellationToken.new)
      count = http.requests.length
      (1..count).each do |boundary|
        store, http, = analytics_operation_fixture(kind, operation)
        token = EltenAPI::Tasks::CancellationToken.new
        entered = ::Queue.new
        held, worker = nil, nil
        http.override = ->(request) do
          if http.requests.length == boundary
            request[:token]&.on_cancel { request[:cancelled] = true }
            entered << request
            :held
          end
        end
        begin
          worker = Thread.new do
            analytics_operation(store, operation, token)
          rescue StandardError => error
            error
          end
          held = Timeout.timeout(2) { entered.pop }
          token.cancel
          stopped = !!worker.join(0.5)
          assert(stopped, "#{kind}/#{operation}/#{boundary} waited for HTTP after native cancellation")
          assert(worker.value.is_a?(EltenAPI::Tasks::Cancelled), "Cancellation did not propagate from the real Client")
          assert(held[:token].equal?(token) && held[:cancelled], "The HTTP transport did not receive cancellation")
          assert(http.requests.length == boundary, "Cancellation issued another request")
          held[:callback].call(JSON.generate("success" => true, "data" => {}), nil)
          http.override = nil
          http.requests.clear
          next_token = EltenAPI::Tasks::CancellationToken.new
          assert(analytics_operation(store, operation, next_token), "A cancelled operation prevented reuse of the store")
          assert(http.requests.all? { |request| request[:token].equal?(next_token) }, "A table retained a previous operation's token")
        ensure
          held[:callback].call(:error, nil) if held && worker&.alive?
          worker&.join(1)
          worker.kill if worker&.alive?
        end
      end
    end
  end
end

analytics_test("bounded timeout reaches the real Client for every SDK request") do
  captured = []
  trace = TracePoint.new(:call) do |point|
    if point.defined_class == EltenLink::Client && point.method_id == :api_data
      captured << [point.binding.local_variable_get(:timeout), point.binding.local_variable_get(:cancellation_token)]
    end
  end
  token = EltenAPI::Tasks::CancellationToken.new
  trace.enable do
    store, = analytics_fixture(:presence)
    store.publish([ROOM], cancellation_token: token)
    store.report(cancellation_token: token)
    store.publish([], cancellation_token: token)
    store, = analytics_fixture(:history)
    analytics_operation(store, :batch, token)
    analytics_operation(store, :report, token)
    analytics_operation(store, :years, token)
  end
  assert(!captured.empty? && captured.all? { |timeout, actual| timeout > 0 && timeout <= 5 && actual.equal?(token) },
    "SDK requests retained default timeout/token: #{captured.map { |timeout, actual| [timeout, actual.nil?] }.uniq.inspect}")
end

analytics_test("raw validation covers every native read without treating schema or writes as rows") do
  {presence: [:report, :insert, :update, :clear], history: [:report, :years, :batch]}.each do |kind, operations|
    operations.each do |operation|
      store, http, = analytics_operation_fixture(kind, operation)
      analytics_operation(store, operation, nil)
      boundaries = http.requests.each_index.select { |index| http.requests[index][:path].end_with?("/query") }
      boundaries.each do |index|
        [{}, {"rows" => nil}, {"rows" => {}}, {"rows" => false}, {"rows" => "invalid"}].each do |invalid|
          store, http, = analytics_operation_fixture(kind, operation)
          http.override = ->(_request) { invalid if http.requests.length == index + 1 }
          error = kind == :presence ? GameRoomPresence::Unavailable : GameRoomStatistics::Unavailable
          assert_raises(error, "Malformed #{kind}/#{operation}/#{index} escaped SDK validation") do
            analytics_operation(store, operation, nil)
          end
          assert(http.requests.length == index + 1, "A malformed read triggered another request")
        end
      end
    end
  end
  _store, http, client = analytics_fixture(:presence)
  names = %w[room_presence statistics_events statistics_accounts]
  adapter = GameRoomAnalyticsClient.new(client, app_uuid: "analytics-app", tables: names, error: GameRoomPresence::Unavailable)
  http.override = ->(*) { {} }
  names.each do |name|
    table = EltenLink::Apps.table(adapter, "analytics-app", name)
    assert_raises(GameRoomPresence::Unavailable, "Plain GET rows was coerced") { table.select }
    assert_raises(GameRoomPresence::Unavailable, "POST query rows was coerced") { table.select(columns: ["__id"]) }
  end
  root = "/api/v1/apps/analytics-app"
  [["GET", "#{root}/schema"], ["POST", "#{root}/tables/room_presence/rows"],
    ["GET", "#{root}/tables/room_presence/rows/1"], ["POST", "#{root}/tables/room_presence/rows/query/extra"],
    ["POST", "#{root}/tables/other/rows/query"], ["GET", "#{root}-other/tables/room_presence/rows"]].each do |method, path|
    assert(adapter.api_data(method, path) == {}, "Raw row validation escaped its exact URL/method scope")
  end
  http.override = ->(*) { {"rows" => []} }
  names.each do |name|
    table = EltenLink::Apps.table(adapter, "analytics-app", name)
    assert(table.select == [] && table.select(columns: ["__id"]) == [], "Legitimate empty rows were rejected")
  end
  [:presence, :history].each do |kind|
    store, http, = analytics_fixture(kind)
    http.rows.each_value(&:clear)
    report = analytics_report(store)
    assert(report[kind == :presence ? "people" : "completed"] == 0, "An actually empty table was not accepted")
  end
end

analytics_test("real SDK keyset survives shrinking and growing eligibility") do
  [:shrinking, :growing].each do |change|
    store, http, = analytics_fixture(:presence)
    template = http.rows["room_presence"].first
    http.rows["room_presence"].replace((1..4).map do |id|
      template.merge("__id" => id, "reporter_key" => format("%064x", id), "room_key" => format("%064x", id),
        "people" => id, "seen_slot" => change == :growing && id == 1 ? 98 : 100)
    end)
    pages = []
    http.after_request = ->(request, result) do
      if request[:path].end_with?("/schema")
        result["app"]["data"]["server"]["tables"]["room_presence"]["limits"]["max_select_limit"] = 2
      elsif request[:query].fetch("where", {}).key?("seen_slot")
        pages << result["rows"].map { |row| row["__id"] }
        http.rows["room_presence"].first["seen_slot"] = change == :shrinking ? 101 : 100 if pages.length == 1
      end
    end
    assert(store.report.values_at("public_rooms", "people") == [3, 9], "The real SDK lost later eligible rooms after #{change}")
    assert(pages.flatten == (change == :shrinking ? [1, 2, 3, 4] : [2, 3, 4]), "The native cursor skipped/repeated IDs")
    queries = http.requests.map { |request| request[:query] }.select { |query| query.fetch("where", {}).key?("seen_slot") }
    assert(queries.all? { |query| query["where"]["__id"].keys == ["gte"] && !query.key?("offset") },
      "The actual host serializer did not forward the verified single-operator cursor")
  end
end

analytics_test("overlapping native report and publish keep their own cancellation tokens") do
  store, http, = analytics_fixture(:presence)
  reader_token, writer_token = 2.times.map { EltenAPI::Tasks::CancellationToken.new }
  entered, held, worker = ::Queue.new, nil, nil
  http.override = ->(request) do
    if request[:token].equal?(reader_token) && request[:query].fetch("where", {}).key?("seen_slot") && !held
      entered << request
      :held
    end
  end
  begin
    worker = Thread.new { store.report(cancellation_token: reader_token) }
    worker.report_on_exception = false
    held = Timeout.timeout(2) { entered.pop }
    first_write = http.requests.length
    assert(store.publish([ROOM], cancellation_token: writer_token), "Publication could not overlap a report")
    assert(http.requests.drop(first_write).all? { |request| request[:token].equal?(writer_token) }, "Report token leaked into publication")
    writer_token.cancel
    next_read = http.requests.length
    held[:callback].call(JSON.generate("success" => true, "data" => http.response(held)), nil)
    assert(worker.join(1) && worker.value["people"] == 4, "Cancelling a finished publisher cancelled its overlapping report")
    assert(http.requests.drop(next_read).all? { |request| request[:token].equal?(reader_token) }, "Publisher replaced the report's token")
  ensure
    reader_token.cancel
    held[:callback].call(:error, nil) if held && worker&.alive?
    worker&.join(1)
    worker.kill if worker&.alive?
  end
end

analytics_test("real user and pre-cancellation guards stop every native operation boundary") do
  {presence: [:report, :insert, :update, :clear], history: [:report, :years, :batch]}.each do |kind, operations|
    operations.each do |operation|
      store, http, = analytics_operation_fixture(kind, operation)
      analytics_operation(store, operation, nil)
      count = http.requests.length
      (0..count).each do |boundary|
        user = "Alice"
        store, http, = analytics_operation_fixture(kind, operation, current_user: -> { user })
        http.after_request = ->(*) { user = "Bob" if http.requests.length == boundary }
        user = "Bob" if boundary == 0
        error = kind == :presence ? GameRoomPresence::Unavailable : GameRoomStatistics::Unavailable
        assert_raises(error, "Account change was ignored by native #{kind}/#{operation}/#{boundary}") do
          analytics_operation(store, operation, EltenAPI::Tasks::CancellationToken.new)
        end
        assert(http.requests.length == boundary, "The native SDK dispatched after an account change")
      end
      store, http, = analytics_operation_fixture(kind, operation)
      token = EltenAPI::Tasks::CancellationToken.new
      token.cancel
      assert_raises(EltenAPI::Tasks::Cancelled, "Pre-cancelled native operation ran") { analytics_operation(store, operation, token) }
      assert(http.requests.empty?, "Pre-cancelled native operation contacted HTTP")
    end
  end
end

analytics_test("real Client times out held HTTP without a cancellation token and recovers") do
  store, http, = analytics_fixture(:presence)
  entered, held, worker = ::Queue.new, nil, nil
  http.override = ->(request) { entered << request; :held }
  begin
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    worker = Thread.new do
      store.report
    rescue StandardError => error
      error
    end
    held = Timeout.timeout(2) { entered.pop }
    assert(worker.join(6.5), "Analytics still used the host's unbounded/default request wait")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert(worker.value.is_a?(EltenLink::Error) && worker.value.code == "timeout", "Held HTTP did not produce a native timeout")
    assert(elapsed >= 5 && elapsed < 6.5 && http.requests.length == 1, "The real timeout did not bound schema dispatch")
    held[:callback].call(JSON.generate("success" => true, "data" => {}), nil)
    http.override = nil
    assert(store.report["people"] == 4, "The store did not recover after a native timeout/late response")
  ensure
    held[:callback].call(:error, nil) if held && worker&.alive?
    worker&.join(1)
    worker.kill if worker&.alive?
  end
end

puts "Analytics real host: #{$analytics_scenarios} scenarios, #{$analytics_assertions} assertions, #{$analytics_failures.length} failures"
raise $analytics_failures.join("\n") unless $analytics_failures.empty?
