require_relative "support/settings_widget"
require_relative "../lib/game_room_presence_collector"

assert(EltenGameRoom.room_presence_collector.nil?, "An inactive application runtime created a presence collector")

class AppPresenceStore
  attr_reader :writes
  def initialize; @writes = []; end
  def publish(rooms, cancellation_token: nil); @writes << rooms; true; end
end

store = AppPresenceStore.new
collector = GameRoomPresence::Collector.new(user: "Alice", store: store,
  current_user: -> { "Alice" }, synchronize_clock: -> {})
klass = Class.new(EltenGameRoom)
klass.define_singleton_method(:room_presence_collector) { collector }
app = klass.new
endpoint = Object.new
endpoint.define_singleton_method(:closed?) { false }
endpoint.define_singleton_method(:user) { "Alice" }
metadata = {"kind" => "elten_game_room_table", "table_id" => 22,
  "statistics_room_id" => "22222222-2222-4222-8222-222222222222"}
session = Struct.new(:metadata).new(metadata)
session.define_singleton_method(:closed?) { false }
endpoint.define_singleton_method(:sessions) { [session] }
transport = Object.new
transport.define_singleton_method(:start) { true }
reads = []
transport.define_singleton_method(:room_snapshot) do |id, force:, read_only:, timeout:, cancellation_token:|
  assert(read_only && timeout == 5, "Presence did not request a bounded read-only native snapshot")
  reads << [id, force]
  {table: {"__statistics_room_id" => metadata["statistics_room_id"], "game" => "tic_tac_toe", "private" => true,
    "status" => "waiting"}, members: %w[Alice Bob], bots: [], observers: ["Bob"]}
end
app.instance_variable_set(:@transport, transport)
app.define_singleton_method(:live_sessions) { endpoint }
managed = []
app.define_singleton_method(:manage) { |resource| managed << resource; resource }
app.send(:register_room_presence)
app.send(:register_room_presence)
assert(managed.length == 1, "Repeated initialization registered multiple room presence sources")
assert(collector.heartbeat && reads == [[22, true]], "Presence did not use the existing transport's fresh authorized room snapshot")
assert(store.writes.last.first.values_at("private_room", "people") == [true, 2], "Private room members or observers were omitted")
managed.first.close
collector.heartbeat
assert(store.writes.last == [], "Disposing the program did not clear its registered room")
app2 = klass.new
%w[server_tables game_room_users table_activity lobby games invitations invitation_notifications].each do |field|
  app2.instance_variable_set("@#{field}", Object.new)
end
app2.instance_variable_set(:@transport, transport)
app2.define_singleton_method(:live_sessions) { endpoint }
managed2 = []
app2.define_singleton_method(:manage) { |resource| managed2 << resource; resource }
app2.send(:initialize_services)
assert(managed2.length == 1, "Normal service initialization omitted presence registration")
managed2.first.close
GameRoomPresence::Schema::TABLES.each do |name, schema|
  assert(EltenGameRoom::SERVER_TABLES[name] == schema, "Current-room schema is not declared by the application")
end
original_menu = GameRoomScreens::MainMenu.method(:new)
choices = [GameRoomScreens::MenuResult.new(action: :room_activity, index: 2), GameRoomScreens::MenuResult.new(action: :exit, index: 2)]
indexes = []
GameRoomScreens::MainMenu.define_singleton_method(:new) do |**options|
  indexes << options[:index]
  raise "Main menu did not exit" if choices.empty?
  choice = choices.shift
  Object.new.tap { |screen| screen.define_singleton_method(:wait) { choice } }
end
opened = []
app.define_singleton_method(:show_room_activity) { opened << :presence }
app.define_singleton_method(:load_lobby_history) { [] }
app.define_singleton_method(:confirm) { |_message| true }
app.instance_variable_set(:@server_tables, Object.new.tap { |tables| tables.define_singleton_method(:available?) { false } })
begin
  app.send(:show_main_menu)
  assert(opened == [:presence] && indexes == [0, 2], "Current-room context action lost its dispatch or selected item")
ensure
  GameRoomScreens::MainMenu.define_singleton_method(:new, original_menu)
end
require_relative "../lib/game_room_presence_screen"
constructor = GameRoomPresenceScreen.method(:new)
viewed = []
token = Object.new
store.define_singleton_method(:report) do |cancellation_token:|
  assert(cancellation_token.equal?(token), "Current-room reader lost cancellation")
  {"public_rooms" => 0, "private_rooms" => 1, "people" => 2}
end
GameRoomPresenceScreen.define_singleton_method(:new) do |**options|
  Object.new.tap { |screen| screen.define_singleton_method(:run) { viewed << options[:reader].call } }
end
app3 = klass.new
app3.define_singleton_method(:read_statistics) { |&operation| operation.call(token) }
begin
  app3.send(:show_room_activity)
  assert(viewed == [{"public_rooms" => 0, "private_rooms" => 1, "people" => 2}], "The current-room screen was not connected to the real reader contract")
ensure
  GameRoomPresenceScreen.define_singleton_method(:new, constructor)
end
factory = Class.new(EltenGameRoom)
factory.define_singleton_method(:app_runtime) { :runtime }
factory.define_singleton_method(:server_app_uuid) { "presence-app" }
storage_calls, constructor_calls = 0, 0
storage_available, backend_available = false, false
client_state = {"version" => 1, "accounts" => {}}
factory.define_singleton_method(:update_json) do |_path, default:, &operation|
  storage_calls += 1
  raise IOError, "presence storage unavailable" unless storage_available
  operation.call(client_state)
  client_state
end
original_store = GameRoomPresence::Store.method(:new)
recovered_store = AppPresenceStore.new
GameRoomPresence::Store.define_singleton_method(:new) do |**options|
  constructor_calls += 1
  raise IOError, "presence backend unavailable" unless backend_available
  assert(options[:user] == "alice" && options[:reporter_key] == client_state["accounts"]["alice"],
    "Recovered presence lost its account or persisted reporter identity")
  recovered_store
end
begin
  recovering_app = factory.new
  %w[server_tables game_room_users table_activity lobby games invitations invitation_notifications].each do |field|
    recovering_app.instance_variable_set("@#{field}", Object.new)
  end
  recovering_app.instance_variable_set(:@transport, transport)
  recovering_app.define_singleton_method(:live_sessions) { endpoint }
  recovering_sources = []
  recovering_app.define_singleton_method(:manage) { |resource| recovering_sources << resource; resource }
  recovering_app.send(:initialize_services)
  assert(recovering_sources.length == 1, "Transient presence storage failure permanently lost the open program's source")
  assert(storage_calls == 0 && constructor_calls == 0, "Presence registration performed storage or backend I/O")
  recovering_collector = factory.room_presence_collector
  assert(!recovering_collector.heartbeat && recovering_collector.last_error.is_a?(IOError),
    "Unavailable reporter storage was not isolated in the heartbeat")
  storage_available = true
  assert(!recovering_collector.heartbeat && constructor_calls == 1, "A failed backend factory was cached or not attempted")
  backend_available = true
  assert(recovering_collector.heartbeat && recovered_store.writes.last.first["people"] == 2,
    "Presence did not recover its original source without reopening the program")
  calls = [storage_calls, constructor_calls]
  assert(recovering_collector.store.equal?(recovered_store) && factory.room_presence_collector.equal?(recovering_collector),
    "Recovered presence did not retain its collector and store")
  assert(recovering_collector.heartbeat && [storage_calls, constructor_calls] == calls,
    "A successful presence store was not cached")
  recovering_sources.first.close
  assert(recovering_collector.heartbeat && recovered_store.writes.last == [], "Recovered presence lost managed cleanup")
ensure
  GameRoomPresence::Store.define_singleton_method(:new, original_store)
end
runtime_available = false
factory.define_singleton_method(:app_runtime) { runtime_available ? :runtime : nil }
report_reads = 0
recovered_store.define_singleton_method(:report) do |cancellation_token:|
  report_reads += 1
  assert(cancellation_token.equal?(token), "Recovered screen lost cancellation")
  {"public_rooms" => 0, "private_rooms" => 1, "people" => 2}
end
screen_app = factory.new
screen_app.define_singleton_method(:read_statistics) { |&operation| operation.call(token) }
original_wait, original_name = Form.instance_method(:wait), Session.method(:name)
account = "Alice"
Session.define_singleton_method(:name) { account }
Form.define_method(:wait) do
  summary, refresh = fields
  assert(summary.text.include?("unavailable"), "Unavailable factory was not shown as unavailable")
  runtime_available = true
  refresh.trigger(:press)
  assert(summary.text.include?("People in rooms: 2") && report_reads == 1,
    "Refresh retained the failed factory result instead of recovering in the open screen")
  account = "Bob"
  refresh.trigger(:press)
  assert(summary.text.include?("unavailable") && report_reads == 1,
    "An old presence screen read through a new account")
  account = "ALICE"
  refresh.trigger(:press)
  assert(summary.text.include?("People in rooms: 2") && report_reads == 2,
    "Original-account capitalization prevented screen recovery")
  cancel_button.trigger(:press)
end
begin
  screen_app.send(:show_room_activity)
ensure
  Form.define_method(:wait, original_wait)
  Session.define_singleton_method(:name, original_name)
end
puts "PASS room presence initialization, managed sources, schema, menu, screen reader and lazy storage/backend recovery"
