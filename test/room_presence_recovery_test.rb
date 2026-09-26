require_relative "support/settings_widget"
require_relative "support/host_source"

%w[eltenlink/error eltenlink/client eltenlink/apps eapi/tasks eapi/live_sessions eapi/scheduler].each do |source|
  require File.join(EltenTestHost.root, "src", source)
end

class PresenceOfflineClient
  attr_accessor :hold
  attr_reader :requests

  def initialize
    @requests = Queue.new
  end

  def e_json_request(method, path, params, cancellation_token:, &callback)
    raise "Presence mutated its shared native session" unless method == "GET" && path.include?("/stack?")
    @requests << {token: cancellation_token, callback: callback, path: path}
    callback.call(JSON.generate("success" => true, "data" => {"entries" => [], "cursor" => 0, "has_more" => false}), nil) unless @hold
  end
end

class PresenceRecoveryStore
  attr_reader :writes
  def initialize; @writes = []; end
  def publish(rooms, cancellation_token: nil)
    cancellation_token&.raise_if_cancelled!
    @writes << rooms
    true
  end
end

def presence_wait(endpoint, seconds: 2)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  until yield
    endpoint.send(:tick_stack_requests)
    raise "Native presence test did not reach its expected state" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.005
  end
end

def presence_native_call(endpoint, &operation)
  worker = Thread.new(&operation)
  worker.report_on_exception = false
  presence_wait(endpoint) { !worker.alive? }
  worker.value
end

client = PresenceOfflineClient.new
endpoint = EltenAPI::LiveSessions::Endpoint.new(app_id: "11111111-1111-4111-8111-111111111111",
  client: client, user: "Alice", token: "offline-fixture")
metadata = {"kind" => GameRoomLiveSessionStore::KIND, "protocol" => GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL,
  "table_id" => 22, "game" => "tic_tac_toe", "owner" => "Alice", "status" => "waiting", "private" => true,
  "statistics_room_id" => "22222222-2222-4222-8222-222222222222", "game_options" => "{}", "created_at" => 1000}
session = endpoint.send(:store_session, {"id" => "native-presence-room", "metadata" => metadata,
  "participant_id" => "alice-participant", "owner_id" => "alice-participant", "visibility" => "private", "capacity" => 8,
  "participants" => [{"id" => "alice-participant", "user" => "Alice"}, {"id" => "bob-participant", "user" => "Bob"}],
  "limits" => {"stack" => true, "max_stack_entries" => 4096}})
store = PresenceRecoveryStore.new
collector = GameRoomPresence::Collector.new(user: "Alice", store: store, synchronize_clock: -> {})
klass = Class.new(EltenGameRoom)
klass.define_singleton_method(:room_presence_collector) { collector }
app = klass.new
app.define_singleton_method(:live_sessions) { endpoint }
managed = []
app.define_singleton_method(:manage) { |resource| managed << resource; resource }
transport = GameRoomTransport.new(app)
app.instance_variable_set(:@transport, transport)
assert(presence_native_call(endpoint) { transport.start }, "Initial gameplay attachment failed")
client.requests.clear
app.send(:register_room_presence)

scheduler_store = Object.new
scheduler_store.define_singleton_method(:delete) { |*_args| true }
EltenAPI::Scheduler.instance_variable_set(:@core_store, scheduler_store)
client.hold = true
results, tokens = Queue.new, Queue.new
handle = EltenAPI::Scheduler.every("presence_cancellation", seconds: 30, autorun: false, persistent: false) do |context|
  tokens << context.token
  results << collector.heartbeat(context.token)
end
unregister = nil
begin
  handle.trigger
  EltenAPI::Scheduler.tick
  presence_wait(endpoint) { !client.requests.empty? }
  pending = client.requests.pop
  native_request = endpoint.instance_variable_get(:@stack_pending)
  assert(handle.running? && results.empty?, "Cancellation was not tested during a native blocking read")
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  unregister = Thread.new { handle.unregister }
  presence_wait(endpoint) { !tokens.empty? }
  token = tokens.pop
  presence_wait(endpoint) { token.cancelled? }
  assert(unregister.join(1), "Native scheduler unregister stayed blocked inside the presence stack read after cancellation")
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  assert(results.pop == false && collector.last_error.is_a?(EltenAPI::Tasks::Cancelled), "Native cancellation did not reach the collector")
  assert(pending[:token].cancelled? && native_request[:abandoned], "The native request was not cancelled and abandoned")
  assert(native_request[:deadline] - started <= 5.1, "Presence kept the native 120-second read deadline")
  assert(!endpoint.closed? && !session.closed? && store.writes.empty?, "Telemetry cancellation closed gameplay or published stale presence")
  client.hold = false
  assert(presence_native_call(endpoint) { collector.heartbeat }, "Presence did not recover on the same open program after cancellation")
  assert(store.writes.last.first.values_at("private_room", "people") == [true, 2], "Recovery lost private room membership")
  assert(managed.length == 1, "Native recovery required another source registration")
  endpoint.send(:store_session, {"id" => "unattached-presence-room", "metadata" => metadata.merge("table_id" => 33),
    "participant_id" => "alice-participant", "owner_id" => "alice-participant",
    "participants" => [{"id" => "alice-participant", "user" => "Alice"}],
    "limits" => {"stack" => true, "max_stack_entries" => 4096}})
  client.requests.clear
  assert(presence_native_call(endpoint) { collector.heartbeat }, "Attached room refresh failed beside a new native membership")
  requests = []
  requests << client.requests.pop until client.requests.empty?
  assert(requests.length == 1 && requests.first[:path].include?("/native-presence-room/stack?"),
    "Telemetry bootstrapped an unattached gameplay session through an unbounded native read")
  live_store = transport.instance_variable_get(:@live_store)
  side_effects = []
  %i[reconcile_control_owner publish_discovery].each do |name|
    original = live_store.method(name)
    live_store.define_singleton_method(name) { |*args| side_effects << name; original.call(*args) }
  end
  assert(presence_native_call(endpoint) { collector.heartbeat }, "Read-only presence refresh failed")
  assert(side_effects.empty?, "Presence entered unbounded gameplay control/discovery writes after its cancellable read")
  read_options = []
  native_read = session.method(:stack_read)
  session.define_singleton_method(:stack_read) { |**options| read_options << options; native_read.call(**options) }
  assert(presence_native_call(endpoint) { transport.room_snapshot(22, force: true) }, "Default gameplay snapshot failed")
  assert(read_options.last == {after: 0, limit: GameRoomLiveSessionStore::STACK_PAGE_SIZE},
    "Telemetry options changed the default gameplay native read call shape")
  assert(side_effects == %i[reconcile_control_owner publish_discovery], "Read-only telemetry disabled normal gameplay reconciliation")
  client.hold = true
  timed_out = presence_native_call(endpoint) do
    begin
      transport.room_snapshot(22, force: true, read_only: true, timeout: 0.05)
      nil
    rescue EltenAPI::LiveSessions::TimeoutError => error
      error
    end
  end
  assert(timed_out && !endpoint.closed? && !session.closed?, "Native timeout did not bound the read without closing gameplay")
  client.hold = false
  assert(presence_native_call(endpoint) { collector.heartbeat }, "Presence did not recover after a native read timeout")
  puts "PASS native Scheduler cancellation during LiveSessions stack_read (#{format('%.3f', elapsed)}s), request abandonment, timeout, read-only isolation and same-program recovery"
ensure
  native_request&.dig(:result)&.push([nil, IOError.new("offline test cleanup")]) if unregister&.alive?
  unregister&.join(2)
  handle.unregister
  managed.each(&:close)
  EltenAPI::LiveSessions.unregister(endpoint)
end
