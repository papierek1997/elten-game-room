require_relative "support/settings_widget"

assert(defined?(GameRoomStatistics::Service), "Application did not load its statistics service")

ranking = EltenGameRoom::MAIN_OPTIONS.index("Leaderboards")
statistics = EltenGameRoom::MAIN_OPTIONS.index("Statistics")
assert(statistics == ranking + 1, "Statistics is not directly below leaderboards")
app = EltenGameRoom.new
opened = []
app.define_singleton_method(:show_statistics) { opened << :statistics }
app.define_singleton_method(:show_settings) { opened << :settings }
app.define_singleton_method(:show_changelog) { opened << :changelog }
app.send(:open_main_option, statistics)
app.send(:open_main_option, statistics + 1)
app.send(:open_main_option, statistics + 2)
assert(opened == [:statistics, :settings, :changelog], "Adding statistics shifted another menu action")
GameRoomStatistics::Schema::TABLES.each do |name, schema|
  assert(EltenGameRoom::SERVER_TABLES[name] == schema, "Statistics schema missing from application declaration")
end
assert(EltenGameRoom.statistics_service.nil?, "An unloaded test runtime created a statistics service")
spy = Object.new
visits = []
spy.define_singleton_method(:visit) { visits << :visit }
original_service = EltenGameRoom.method(:statistics_service)
EltenGameRoom.define_singleton_method(:statistics_service) { spy }
begin
  transport = Object.new
  transport.define_singleton_method(:start) { true }
  lobby = Object.new
  lobby.define_singleton_method(:current_table_for) { |_user| nil }
  app.instance_variable_set(:@transport, transport)
  app.instance_variable_set(:@lobby, lobby)
  app.define_singleton_method(:initialize_services) { nil }
  app.define_singleton_method(:show_update_changelog) { nil }
  app.define_singleton_method(:check_server_table_access) { nil }
  app.define_singleton_method(:register_game_room_user) { nil }
  app.define_singleton_method(:run_network_task) { |*_args, **_options, &operation| operation.call }
  app.define_singleton_method(:run_program_interface) { |_row| nil }
  app.program_main
  assert(visits.length == 1, "Normal program entry did not record a visit")
  app.send(:prepare_widget_program)
  app.send(:prepare_widget_program)
  assert(visits.length == 3, "Repeated explicit widget actions lost their entry hook")
  assert(app.notification_action(:not_game_room, nil) == false && visits.length == 3, "Unrelated notification counted as a visit")
  transport.define_singleton_method(:start) { false }
  app.notification_action(:open_invitation, nil)
  assert(visits.length == 4, "Opening an invitation did not record entry before connection failure")
  transport.define_singleton_method(:start) { true }
  receiver = Object.new
  receiver.define_singleton_method(:visible?) { |_notification| false }
  original_receiver = EltenGameRoom.method(:table_watch_receiver)
  EltenGameRoom.define_singleton_method(:table_watch_receiver) { receiver }
  app.define_singleton_method(:alert) { |_message| nil }
  begin
    app.send(:open_new_table_notification, Object.new)
    assert(visits.length == 5, "An explicitly opened expired table notification lost its visit")
  ensure
    EltenGameRoom.define_singleton_method(:table_watch_receiver, original_receiver)
  end
  observed = []
  spy.define_singleton_method(:observe) { |**values| observed << values }
  game = Struct.new(:id).new("tic_tac_toe")
  session = {"__id" => 42, "__players" => %w[Alice Bob]}
  replay = Object.new
  observer = app.send(:statistics_observer_for, game)
  observer.call(session, replay)
  assert(observed.last == {session: session, replay: replay, game_id: "tic_tac_toe", viewer: "Alice", participants: %w[Alice Bob]},
    "The game observer lost its viewer, game or current participants")
  spy.define_singleton_method(:observe) { |**_values| raise IOError, "statistics disk unavailable" }
  observer.call(session, replay)
  started = []
  spy.define_singleton_method(:started) { |**values| started << values; raise IOError, "statistics disk unavailable" }
  app.send(:record_statistics_start, session, game)
  assert(started == [{session: session, game_id: "tic_tac_toe"}], "The start observer lost the confirmed session")
  spy.define_singleton_method(:visit) { raise IOError, "statistics disk unavailable" }
  entry_error = begin
    app.program_main
    nil
  rescue StandardError => error
    error
  end
  assert(entry_error.nil?, "A failed statistics visit prevented normal program entry")
  original_warning = Log.method(:warning)
  Log.define_singleton_method(:warning) { |_message| raise IOError, "log unavailable" }
  begin
    callback_errors = [-> { app.send(:record_statistics_start, session, game) }, -> { observer.call(session, replay) }].filter_map do |callback|
      begin
        callback.call
        nil
      rescue StandardError => error
        error
      end
    end
    assert(callback_errors.empty?, "Statistics error logging leaked a failure into gameplay")
  ensure
    Log.define_singleton_method(:warning, original_warning)
  end
ensure
  EltenGameRoom.define_singleton_method(:statistics_service, original_service)
end
factory = Class.new(EltenGameRoom)
factory.define_singleton_method(:app_runtime) { :runtime }
original_constructor = GameRoomStatistics::Service.method(:new)
original_name = Session.method(:name)
account = "Alice"
Session.define_singleton_method(:name) { account }
constructions = []
GameRoomStatistics::Service.define_singleton_method(:new) do |**options|
  constructions << options
  Struct.new(:last_error).new(nil)
end
begin
  first = factory.statistics_service
  account = "ALICE"
  assert(factory.statistics_service.equal?(first) && constructions.length == 1,
    "Account capitalization created a second statistics queue")
  assert(constructions.first[:user] == "alice", "Local statistics storage does not use a normalized account namespace")
  account = "Bob"
  failure = IOError.new("statistics storage unavailable")
  attempts = 0
  GameRoomStatistics::Service.define_singleton_method(:new) do |**_options|
    attempts += 1
    raise failure if attempts == 1
    Struct.new(:last_error).new(attempts == 2 ? failure : nil)
  end
  result = begin
    factory.statistics_service
  rescue StandardError => error
    error
  end
  assert(result.nil?, "Statistics construction failure escaped into gameplay")
  assert(factory.statistics_service.nil?, "A partially initialized statistics service was cached")
  recovered = factory.statistics_service
  assert(recovered && !recovered.equal?(first) && attempts == 3,
    "Statistics construction failure poisoned the new account cache")
  assert(factory.statistics_service.equal?(recovered), "A recovered account service was not reused")
  account = ""
  assert(factory.statistics_service.nil?, "Logged-out statistics reused another account")
ensure
  Session.define_singleton_method(:name, original_name)
  GameRoomStatistics::Service.define_singleton_method(:new, original_constructor)
end
require_relative "support/host_source"
module Programs
  class ProgramError < StandardError; end
end
require File.join(EltenTestHost.root, "src/eapi/scheduler")
require File.join(EltenTestHost.root, "src/eapi/extensions")
require File.join(EltenTestHost.root, "src/eapi/tasks")

scheduled_app = Class.new(EltenGameRoom)
scheduled_app.define_singleton_method(:app_runtime) { :runtime }
definitions = []
triggers = []
handle = Object.new
handle.define_singleton_method(:trigger) { |key| triggers << key }
scheduled_app.define_singleton_method(:extension) do |name, &registration|
  definition = Programs::Extensions::Definition.new(name)
  registration.call(definition)
  definitions << definition.finalize!
  handle
end
background_visits = []
flushes = []
service = Object.new
service.define_singleton_method(:visit) { background_visits << :visit }
service.define_singleton_method(:flush) { |token| flushes << token }
scheduled_app.define_singleton_method(:statistics_service) { service }
scheduled_app.activate
scheduled_app.activate
assert(definitions.map(&:name) == ["game_room_main_tab"], "Statistics replaced or duplicated the existing extension")
assert(definitions.first.main_tabs.map(&:key) == ["tables"], "Statistics removed the table widget")
schedule = definitions.first.schedules.find { |definition| definition.key == "statistics_upload" }
assert(schedule, "Statistics uploads were not registered with the host scheduler")
assert(schedule.interval == 30 && schedule.autorun && !schedule.persistent && schedule.first == :after_interval,
  "Statistics upload schedule has the wrong lifecycle")
assert(scheduled_app.instance_variable_get(:@statistics_extension).equal?(handle), "Statistics did not retain its extension handle")
token = EltenAPI::Tasks::CancellationToken.new
schedule.callback.call(Struct.new(:token).new(token))
assert(flushes == [token], "The scheduled upload lost its cancellation token")
presence_schedule = definitions.first.schedules.find { |definition| definition.key == "room_presence" }
assert(presence_schedule && presence_schedule.interval == 30 && presence_schedule.autorun &&
  !presence_schedule.persistent && presence_schedule.first == :after_interval, "Current-room reporting is not on the native bounded scheduler")
heartbeats = []
presence_collector = Object.new
presence_collector.define_singleton_method(:heartbeat) { |value| heartbeats << value }
scheduled_app.define_singleton_method(:room_presence_collector) { presence_collector }
presence_schedule.callback.call(Struct.new(:token).new(token))
assert(heartbeats == [token], "The room heartbeat did not receive cancellation")
lifecycle_callbacks = []
%i[table_watch_start contacts_tick table_watch_tick table_watch_stop contacts_stop].each do |name|
  scheduled_app.define_singleton_method(name) { lifecycle_callbacks << name }
end
original_outbox_tick = InvitationResponseOutbox.method(:tick_default)
InvitationResponseOutbox.define_singleton_method(:tick_default) { lifecycle_callbacks << :outbox }
begin
  definitions.first.start_callback.call
  definitions.first.tick_callback.call
  definitions.first.stop_callback.call
  assert(lifecycle_callbacks == %i[table_watch_start contacts_tick table_watch_tick outbox table_watch_stop contacts_stop],
    "Statistics changed the existing extension lifecycle")
ensure
  InvitationResponseOutbox.define_singleton_method(:tick_default, original_outbox_tick)
end
assert(background_visits.empty?, "Extension activation or background upload counted as a visit")
factory.instance_variable_set(:@statistics_extension, handle)
constructions.first[:trigger].call
assert(triggers == ["statistics_upload"], "Enqueued statistics did not trigger the host upload task")
lifecycle_class = Class.new(EltenGameRoom)
lifecycle_app = lifecycle_class.new
lifecycle_game = GameRoomGames::TicTacToe.new
lifecycle_table = {"__id" => 7, "owner" => "Alice", "game" => lifecycle_game.id, "game_options" => "{}"}
lifecycle_room = Struct.new(:table, :game_participants, :members).new(lifecycle_table, %w[Alice Bob], %w[Alice Bob])
lifecycle_state = GameRoomLifecycle::State.new(room: lifecycle_room, game_snapshot: nil, game: lifecycle_game, replay: nil)
lifecycle_session = {"__id" => 42, "game" => lifecycle_game.id, "__players" => %w[Alice Bob], "options" => "{}"}
lifecycle_repository = GameRepository.allocate
lifecycle_lobby = Object.new
lifecycle_lobby.define_singleton_method(:owner_of) { |row| row["owner"] }
lifecycle_lobby.define_singleton_method(:table_id) { |row| row["__id"] }
lifecycle_lobby.define_singleton_method(:snapshot_for) { |_row, **_options| lifecycle_room }
lifecycle_lobby.define_singleton_method(:playing?) { |_row| false }
lifecycle_transport = Object.new
lifecycle_transport.define_singleton_method(:connected_users) { |_id| %w[Alice Bob] }
lifecycle_app.instance_variable_set(:@lobby, lifecycle_lobby)
lifecycle_app.instance_variable_set(:@games, lifecycle_repository)
lifecycle_app.instance_variable_set(:@transport, lifecycle_transport)
lifecycle_app.define_singleton_method(:alert) { |message| raise message }
start_order = []
start_calls = []
lifecycle_service = Object.new
lifecycle_service.define_singleton_method(:started) do |**values|
  start_calls << values
  start_order << :recorded
end
other_service = Object.new
other_service.define_singleton_method(:started) { |**_values| raise "Start was attributed to the new account" }
selected_service = lifecycle_service
lifecycle_class.define_singleton_method(:statistics_service) { selected_service }
lifecycle_repository.define_singleton_method(:start_session) do |**_options|
  start_order << :confirmed
  lifecycle_session
end
lifecycle_lobby.define_singleton_method(:set_game_active) do |*_args, **_options|
  start_order << :lobby
  raise IOError, "lobby write failed after confirmed start"
end
lifecycle_app.define_singleton_method(:run_network_task) do |title, **_options, &operation|
  selected_service = other_service if title == "Starting game"
  operation.call
rescue IOError
  nil
end
assert(lifecycle_app.send(:start_new_game, lifecycle_table, state: lifecycle_state).nil?, "The fixture did not fail its lobby write")
assert(start_order == [:confirmed, :recorded, :lobby] && start_calls == [{session: lifecycle_session, game_id: lifecycle_game.id}],
  "A confirmed start was not recorded by the pinned service before a later lobby failure")
selected_service = lifecycle_service
lifecycle_service.define_singleton_method(:started) do |**values|
  start_calls << values
  raise IOError, "statistics unavailable"
end
lobby_updates = []
lifecycle_lobby.define_singleton_method(:set_game_active) { |*_args, **_options| lobby_updates << :updated }
assert(lifecycle_app.send(:start_new_game, lifecycle_table, state: lifecycle_state).equal?(lifecycle_session),
  "A statistics recording failure changed the successful game start")
assert(lobby_updates == [:updated], "A statistics recording failure skipped the game status update")
confirmed_count = start_calls.length
lifecycle_repository.define_singleton_method(:start_session) { |**_options| nil }
selected_service = lifecycle_service
assert(lifecycle_app.send(:start_new_game, lifecycle_table, state: lifecycle_state).nil?, "A missing start was accepted")
lifecycle_repository.define_singleton_method(:start_session) { |**_options| raise IOError, "game start failed" }
selected_service = lifecycle_service
assert(lifecycle_app.send(:start_new_game, lifecycle_table, state: lifecycle_state).nil?, "A failed start was accepted")
assert(start_calls.length == confirmed_count && lobby_updates == [:updated], "Statistics counted an unconfirmed start")
events = [["Alice", "1,1"], ["Bob", "1,2"], ["Alice", "2,1"], ["Bob", "2,2"], ["Alice", "3,1"]].each_with_index.map do |(actor, value), index|
  {"__id" => index + 1, "actor" => actor, "action" => "place", "value" => value}
end
game_snapshot = Struct.new(:session, :events).new(lifecycle_session, events)
lifecycle_repository.define_singleton_method(:session_for_table) { |_table, **_options| lifecycle_session }
lifecycle_repository.define_singleton_method(:snapshot_for) { |_session, **_options| game_snapshot }
activity = Object.new
activity.define_singleton_method(:entries_for) { |_table, viewer:| [] }
lifecycle_app.instance_variable_set(:@table_activity, activity)
lifecycle_app.define_singleton_method(:game_definition) { |_id| lifecycle_game }
observations = []
lifecycle_service.define_singleton_method(:observe) { |**values| observations << values }
other_service.define_singleton_method(:observe) { |**_values| raise "Replay was attributed to a different account" }
selected_service = lifecycle_service
account = "Alice"
Session.define_singleton_method(:name) { account }
lifecycle_app.define_singleton_method(:run_network_task) do |_title, **_options, &operation|
  account.replace("Bob")
  selected_service = other_service
  operation.call
end
begin
  loaded = lifecycle_app.send(:load_room_state, lifecycle_table, title: "Loading fixture")
  assert(loaded.replay.finished? && loaded.replay.state.nil?, "The fixture did not replay the actual finished board game")
  assert(observations == [{session: lifecycle_session, replay: loaded.replay, game_id: lifecycle_game.id,
    viewer: "Alice", participants: %w[Alice Bob]}], "Room replay was not observed using its pre-network account and viewer")
ensure
  Session.define_singleton_method(:name, original_name)
end
selected_service = lifecycle_service
lifecycle_app.define_singleton_method(:run_network_task) { |_title, **_options, &operation| operation.call }
lifecycle_service.define_singleton_method(:observe) { |**_values| raise IOError, "statistics unavailable" }
recovered_state = lifecycle_app.send(:load_room_state, lifecycle_table, title: "Loading fixture")
assert(recovered_state.finished? && recovered_state.replay.winner == "Alice", "Statistics failure prevented loading the replay")
lifecycle_service.define_singleton_method(:observe) { |**values| observations << values }
observations.clear
lifecycle_repository.define_singleton_method(:session_for_table) { |_table, **_options| nil }
empty_state = lifecycle_app.send(:load_room_state, lifecycle_table, title: "Loading fixture")
assert(empty_state.waiting? && observations.empty?, "A waiting room was observed as a game replay")
selected_service = lifecycle_service
lifecycle_transport.define_singleton_method(:consume_game_change) { |_id| nil }
lifecycle_repository.define_singleton_method(:bot_turn_controller) { |_id| Object.new }
account = "Alice"
Session.define_singleton_method(:name) { account }
begin
  screen = lifecycle_app.send(:build_game_screen, lifecycle_session, lifecycle_game, table: lifecycle_table, layout: nil)
  assert(screen.is_a?(GameScreen), "Application did not construct the actual game screen")
  screen_observer = screen.instance_variable_get(:@statistics_observer)
  assert(screen_observer.respond_to?(:call), "The application did not wire statistics into the game screen")
  selected_service = other_service
  account.replace("Bob")
  observations.clear
  screen_observer.call(lifecycle_session, loaded.replay)
  assert(observations == [{session: lifecycle_session, replay: loaded.replay, game_id: lifecycle_game.id,
    viewer: "Alice", participants: %w[Alice Bob]}], "The game screen observer did not retain its account and replay context")
ensure
  Session.define_singleton_method(:name, original_name)
end
puts "PASS statistics application integration"
