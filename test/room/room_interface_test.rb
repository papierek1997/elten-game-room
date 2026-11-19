require_relative "../support/room_interface"
require_relative '../support/server_table_access'

row = { "__id" => 7, "owner" => "Alice", "game" => "four_in_a_row", "status" => "waiting", "max_players" => 8, "name" => "Test room", "game_options" => "{}" }
room = LobbyRepository::TableSnapshot.new(table: row, members: ["Alice", "Bob"], bots: [])
game = GameRoomGames::FourInARow.new
repository = InterfaceGameRepository.new
session = { "__id" => 1, "options" => "{}" }
replay = game.replay(session, [], repository)
waiting = GameRoomLifecycle::State.new(room: room, game_snapshot: nil, game: game, replay: nil)
finished_replay = game.replay(session, [], repository)
finished_replay.winner = "Alice"
finished = GameRoomLifecycle::State.new(room: room, game_snapshot: Struct.new(:session).new(session), game: game, replay: finished_replay, players: %w[Alice Bob])
app = EltenGameRoom.allocate
app.instance_variable_set(:@server_tables, GameRoomTest::ServerTableAccess.new(:available))
lobby = LobbyRepository.allocate
app.instance_variable_set(:@lobby, lobby)
app.instance_variable_set(:@games, repository)
app.instance_variable_set(:@transport, Object.new)
tracker = Object.new
tracker.define_singleton_method(:observe) { |_members| [] }
app.define_singleton_method(:room_membership_tracker) { |_table| tracker }
app.define_singleton_method(:play_game_sounds) { |_sounds| }
app.define_singleton_method(:announce_new_table_activity) { |_entries, after_id:| after_id }
app.define_singleton_method(:room_history_items) { |_state, _entries| ["history"] }
app.define_singleton_method(:table_header) { |_snapshot| "Users" }
state = waiting
app.define_singleton_method(:load_room_state) { |_row, **_options| state }
starts = 0
visits = 0
original = nil
app.define_singleton_method(:start_new_game) do |_row, **_options|
  starts += 1
  state = finished
  session
end
app.define_singleton_method(:run_game_screen) do |_session, _game, table:, prepared_screen: nil|
  raise 'Unexpected covered screen in foreground fixture' unless prepared_screen.nil?
  layout = @table_layouts.fetch(7)
  assert(original == [layout.form, layout.users, layout.chat, layout.history], "table lifecycle rebuilt shared controls")
  assert(layout.phase == :finished, "finished table did not open its game screen")
  assert(!layout.form.fields.include?(layout.primary_button), "finished table exposes a review button")
  assert(layout.chat.text == "preserved draft", "ending a game lost chat")
  assert(starts == visits + 1, "restart bypassed the standard start operation")
  visits += 1
  visits < 3 ? :restart : :back
end
app.define_singleton_method(:leave_table_from_screen) { |_row| true }
Form.driver = lambda do |form|
  raise "unexpected waiting-room form" if original != nil
  layout = app.instance_variable_get(:@table_layouts).fetch(7)
  original = [form, layout.users, layout.chat, layout.history]
  assert(layout.focus_location == [:status, 0], "table entry focus is not on Start game")
  assert(form.fields.first == layout.primary_button, "Start game is not the first room field")
  assert(layout.surface == nil, "waiting room has a synthetic board")
  assert_global_invitation_menu(form, keys: %w[i I])
  layout.chat.text = "preserved draft"
  layout.chat.index = 5
  layout.chat.check = 2
  layout.primary_button.trigger(:press)
end
app.send(:show_table_screen, row)
assert(starts == 3 && visits == 3, "room did not finish its start/restart/restart/leave flow")
assert(original.first.instance_variable_get(:@timers).empty?, "room cleanup left a timer running")

# Both outgoing shortcuts use the waiting room's existing invite flow.
state = waiting
sent_invitations = []
opened_rules = []
app.define_singleton_method(:show_game_rules) { |selected_game, options:| opened_rules << [selected_game.id, options] }
app.define_singleton_method(:show_invite_users) { |_table, source:| sent_invitations << source }
waiting_step = 0
Form.driver = lambda do |form|
  current = app.instance_variable_get(:@table_layouts).fetch(7)
  assert_global_invitation_menu(form, keys: %w[i I])
  if waiting_step < 2
    menu = FakeMenu.new
    form.context(menu, false)
    key = %w[i I][waiting_step]
    menu.options.find { |option| option[2] == key }[3].call
  elsif waiting_step == 2
    form.index = form.fields.index(current.chat)
    menu = FakeMenu.new
    form.context(menu, false)
    menu.options.find { |option| option[0] == "Game rules" }[3].call
  else
    assert(current.focus_location == [:chat, 0], "returning from table rules lost the originating field")
    current.back_button.trigger(:press)
  end
  waiting_step += 1
end
app.send(:show_table_screen, row)
assert(waiting_step == 4 && sent_invitations == [:online, :contacts], "waiting-room invitation menus lost their invite source")
assert(opened_rules == [[game.id, game.options_from_json(row["game_options"])]], "waiting-room rules button did not open the current game rules")

# Drive the real active-game form twice, checking focus, menu dispatch and
# preservation of the shell across a game refresh.
screen = GameScreen.allocate
controller = Object.new
controller.define_singleton_method(:cancel) { |_lease| }
{
  game: game, repository: repository, session: session, table: row,
  table_owner: "Alice", room_snapshot: room, surface_state: {},
  board_preferences: GameRoomBoardPreferences.new(nil, game),
  history_navigator: GameRoomHistory::Navigator.new,
  bot_turn_controller: controller, invite_online: ->(_table) {}, invite_contacts: ->(_table) {},
  turn_history_entries: {}, activity_entries: [], game_services: {}
}.each { |key, value| screen.instance_variable_set("@#{key}", value) }
original_game_controls = nil
Form.driver = lambda do |form|
  layout = screen.instance_variable_get(:@layout)
  original_game_controls = [form, layout.users, layout.chat, layout.history]
  assert(layout.focus_location == [:game, 0], "new game did not focus its board")
  assert(form.fields.first == layout.surface.fields.first, "active board is not first")
  assert_global_invitation_menu(form, keys: %w[i I])
  menu = FakeMenu.new
  form.context(menu, false)
  menu.options.find { |item| item[2] == "i" }[3].call
end
assert(screen.send(:wait_for_action, replay, [0, 0]) == :invite_online, "active user menu did not dispatch invitation")
layout = screen.instance_variable_get(:@layout)
layout.chat.text = "live draft"
layout.chat.index = 4
layout.chat.check = 1
layout.form.index = layout.form.fields.index(layout.chat)
Form.driver = lambda do |form|
  assert(original_game_controls == [form, layout.users, layout.chat, layout.history], "game refresh replaced the shell")
  assert(layout.focus_location == [:chat, 0], "game refresh moved chat focus")
  assert([layout.chat.text, layout.chat.index, layout.chat.check] == ["live draft", 4, 1], "game refresh lost chat selection")
  layout.back_button.trigger(:press)
end
assert(screen.send(:wait_for_action, replay, [0, 0]) == :back, "game back action was lost")

Form.driver = lambda do |form|
  menu = FakeMenu.new
  form.context(menu, false)
  menu.options.find { |option| option[0] == "Game rules" }[3].call
end
assert(screen.send(:wait_for_action, replay, [0, 0]) == :rules, "active-game global menu did not dispatch rules")
assert(screen.instance_variable_get(:@focus_location) == [:chat, 0], "opening rules did not remember the originating field")
layout.form.index = layout.form.fields.index(layout.chat)

# A remotely started session may replace an active game while chat is focused.
# Preserve the active chat editor across the remote match boundary as well.
next_session = session.merge("__id" => 2)
repository.define_singleton_method(:session_for_table) { |_table, **_options| next_session }
controller.define_singleton_method(:switch_session) { |_id| }
new_session_sync = Object.new
new_session_sync.define_singleton_method(:recovery_pending?) { false }
new_session_sync.define_singleton_method(:update_session) { |_id, **_options| self }
new_session_sync.define_singleton_method(:synchronized!) { self }
new_session_sync.define_singleton_method(:synchronize) { |**_options, &operation| operation.call }
screen.instance_variable_set(:@synchronizer, new_session_sync)
screen.instance_variable_set(:@new_session_id, 2)
screen.define_singleton_method(:network_task) { |_title, **_options, &operation| operation.call }
screen.send(:switch_to_new_session)
Form.driver = lambda do |form|
  assert(screen.instance_variable_get(:@session) == next_session, "new session was not opened")
  assert(layout.focus_location == [:chat, 0], "remote game start stole chat focus")
  assert([layout.chat.text, layout.chat.index, layout.chat.check] == ["live draft", 4, 1], "remote game start lost the chat draft")
  form.index = form.fields.index(layout.chat)
  layout.back_button.trigger(:press)
end
assert(screen.send(:wait_for_action, replay, [0, 0]) == :back, "new-session view did not return")
Form.driver = lambda do |_form|
  assert(layout.focus_location == [:chat, 0], "a later game refresh focused the board again")
  layout.back_button.trigger(:press)
end
screen.send(:wait_for_action, replay, [0, 0])

# The table and game share their announcement cursor: returning from a game
# must not speak the same room activity a second time.
activity = Struct.new(:id, :kind, :actor).new(10, "joined", "Carol")
activity_provider = Object.new
activity_provider.define_singleton_method(:text_for) { |entry, **_options| "activity #{entry.id}" }
screen.instance_variable_set(:@activity_repository, activity_provider)
screen.instance_variable_set(:@activity_entries, [activity])
screen.instance_variable_set(:@history_follows_tail, false)
screen.send(:event_presenter).instance_variable_set(:@last_seen_activity_id, nil)
layout.activity_cursor = 10
spoken_before = $spoken_messages.length
screen.send(:process_new_table_activity, replay)
assert($spoken_messages.length == spoken_before, "game repeated an event already announced by its table")
activity.id = 11
screen.send(:process_new_table_activity, replay)
assert(layout.activity_cursor == 11 && $spoken_messages.last == "activity 11", "game did not share its newest announcement cursor")
screen.send(:event_presenter).instance_variable_set(:@last_seen_activity_id, nil)
screen.send(:process_new_table_activity, replay)
assert($spoken_messages.length == spoken_before + 1, "reopening the game repeated its latest announcement")

# The finished board stays in the same screen. Ending focuses Restart once;
# Tab reaches the board and rejected actions retain the game's message.
layout.focus_game
screen.instance_variable_set(:@activity_repository, nil)
screen.instance_variable_set(:@activity_entries, [])
alerts = []
screen.define_singleton_method(:alert) { |message| alerts << message }
screen.define_singleton_method(:getkeychar) { "" }
repository.define_singleton_method(:append_events) { |**_options| raise "finished game wrote an event" }
Form.driver = lambda do |form|
  assert(layout.focus_location == [:status, 0], "ending a game did not focus Restart game")
  assert(!form.fields.include?(layout.primary_button), "finished game exposes a review button")
  assert(form.fields.first == layout.restart_button, "Restart game is not the first finished-game field")
  assert_global_invitation_menu(form, keys: %w[i I])
  form.index += 1
  assert(layout.focus_location == [:game, 0], "Tab did not reach the finished board")
  layout.surface.fields.first.trigger(:select, [0, 0])
end
assert(screen.send(:wait_for_action, finished_replay, [0, 0]) == :game_action, "finished board swallowed an action")
assert(screen.send(:submit_action, finished_replay) == false, "finished game accepted a move")
assert(alerts == ["The game has already ended."], "finished game lost its validation message")
# Action shortcuts use the same validation as native surface selection.
game.define_singleton_method(:game_shortcuts) do |_replay, _viewer|
  [GameRoomGames::GameShortcut.new(key: "x", label: "drop a piece", kind: :action,
    action_kind: "grid", action_name: "select", payload: { "x" => 0, "y" => 0 })]
end
Form.driver = lambda do |form|
  assert(layout.focus_location == [:game, 0], "finished-game refresh interrupted board inspection")
  form.trigger(:key_x, {})
end
assert(screen.send(:wait_for_action, finished_replay, [0, 0]) == :game_action, "finished game swallowed an action shortcut")
assert(screen.send(:submit_action, finished_replay) == false, "finished game accepted a shortcut move")
assert(alerts == ["The game has already ended."] * 2, "action shortcut lost the finished-game message")
game.singleton_class.remove_method(:game_shortcuts)
Form.driver = lambda do |_form|
  assert(layout.focus_location == [:game, 0], "finished-game refresh moved focus back to users")
  layout.restart_button.trigger(:press)
end
assert(screen.send(:wait_for_action, finished_replay, [0, 0]) == :restart, "restart did not return to the room controller")
# The same outgoing menu remains usable after the game finishes.
Form.driver = lambda do |form|
  menu = FakeMenu.new
  form.context(menu, false)
  menu.options.find { |option| option[2] == "I" }[3].call
end
assert(screen.send(:wait_for_action, finished_replay, [0, 0]) == :invite_contacts, "finished game lost invitations from contacts")

# Reopening an active room after cancelling Leave preserves the board cursor
# too; starting a new game from the finished room clears the old selection.
layout.update(view_spec: game.game_view_spec(replay, "Alice"), history_items: [], user_items: [], users_header: "Users", phase: :active)
layout.session_id = repository.session_id(session)
layout.surface.fields.first.x = 2
layout.form.index = layout.form.fields.index(layout.chat)
repository.define_singleton_method(:bot_turn_controller) { |_id| controller }
arguments = {
  program: app, repository: repository, game: game, session: session,
  table: row, table_owner: "Alice", room_snapshot_provider: -> { room },
  synchronizer: Object.new, layout: layout
}
reopened = GameScreen.new(**arguments)
assert(reopened.instance_variable_get(:@surface_state) == layout.surface.state, "reopening an active table reset its board cursor")
assert(reopened.instance_variable_get(:@chat_control).equal?(layout.chat), "reopening an active table detached its chat editor")
assert(reopened.instance_variable_get(:@focus_location) == [:chat, 0], "reopening an active table lost its input focus")
layout.update(view_spec: game.game_view_spec(finished_replay, "Alice"), history_items: [], user_items: [], users_header: "Users", phase: :finished)
finished_reopened = GameScreen.new(**arguments)
assert(finished_reopened.instance_variable_get(:@surface_state) == layout.surface.state, "reopening a finished table reset its board cursor")
next_game = GameScreen.new(**arguments.merge(session: next_session))
assert(next_game.instance_variable_get(:@surface_state).empty?, "new game inherited the old board selection")
# Run the actual screen through a winning move, an attempt on the final board
# and restart. Only the winning move may reach repository storage.
match_repository = InterfaceGameRepository.new
match_events = [1, 7, 2, 7, 3, 6].each_with_index.map do |column, index|
  { "id" => index + 1, "actor" => %w[Alice Bob][index % 2], "action" => "drop", "value" => column.to_s }
end
match_controller = GameRoomBots::TurnController.new
match_repository.define_singleton_method(:bot_turn_controller) { |_id| match_controller }
match_repository.define_singleton_method(:snapshot_for) do |current, **_options|
  GameRepository::GameSnapshot.new(session: current, events: match_events.dup)
end
match_repository.define_singleton_method(:confirmed_event_ids) { |_current| match_events.map { |event| event["id"] } }
match_repository.define_singleton_method(:events_revision) { |events| [events.length, events.last.to_h["id"].to_i] }
match_repository.define_singleton_method(:next_sequence) { |_current, events| events.length + 1 }
writes = 0
match_repository.define_singleton_method(:append_events) do |session:, sequence:, events:, recipients:, actor:, controller: false|
  assert(!controller, "human interface action used the computer controller")
  writes += 1
  inserted = events.map.with_index do |event, index|
    { "id" => sequence + index, "actor" => actor, "action" => event.action, "value" => event.value }
  end
  match_events.concat(inserted)
  inserted
end
match_sync = Object.new
match_sync.define_singleton_method(:waiting?) { false }
match_sync.define_singleton_method(:recovery_pending?) { false }
match_sync.define_singleton_method(:reconciled?) { false }
match_sync.define_singleton_method(:synchronize) { |**_options, &operation| operation.call }
app.define_singleton_method(:play_sound_from_asset) { |_name| }
match_screen = GameScreen.new(**arguments.merge(repository: match_repository, synchronizer: match_sync, layout: nil))
match_screen.define_singleton_method(:network_task) { |_title, **_options, &operation| operation.call }
match_alerts = []
match_screen.define_singleton_method(:alert) { |message| match_alerts << message }
match_step = 0
match_controls = nil
match_rules_opened = 0
match_speech_waits = $speech_wait_calls
Form.driver = lambda do |form|
  current = match_screen.instance_variable_get(:@layout)
  if !form.equal?(current.form)
    expected_sections = game.rule_book(options: {}).documents.map(&:title)
    assert(form.fields.first.options == expected_sections, "rules button opened an unrelated dialog")
    match_rules_opened += 1
    form.cancel_button.trigger(:press)
    next
  end
  match_controls ||= [form, current.users, current.chat, current.history]
  assert(match_controls == [form, current.users, current.chat, current.history], "finishing rebuilt the game shell")
  case match_step
  when 0
    assert(current.phase == :active && current.focus_location == [:game, 0], "match did not open on the board")
    current.chat.text = "endgame draft"
    current.surface.fields.first.trigger(:select, [3, 0])
  when 1
    assert(current.phase == :finished && current.focus_location == [:status, 0], "winning move did not focus Restart game")
    assert(
      $speech_wait_calls == match_speech_waits + 1 &&
        form.wait_entry_state == [true, true] &&
        current.restart_button.last_focus_spoken == true,
      "ending did not queue the Restart game focus after final announcements"
    )
    assert(current.chat.text == "endgame draft", "winning move lost the chat draft")
    form.index += 1
    current.surface.fields.first.trigger(:select, [4, 0])
  when 2
    assert(current.focus_location == [:game, 0], "rejected action interrupted board inspection")
    assert(form.wait_announced == false, "finished-game update repeated the form announcement")
    menu = FakeMenu.new
    form.context(menu, false)
    menu.options.find { |option| option[0] == "Game rules" }[3].call
  when 3
    assert(current.focus_location == [:game, 0], "returning from finished-game rules lost the board focus")
    help = form.game_room_background_help_form
    assert(help && help.fields.first.options == game.rule_book(options: {}).documents.map(&:title), "rules did not open the nonblocking rules panel")
    match_rules_opened += 1
    help.cancel_button.trigger(:press)
    assert(current.chat.text == "endgame draft", "reading rules lost the chat draft")
    current.restart_button.trigger(:press)
  else
    raise "finished game did not handle restart"
  end
  match_step += 1
end
assert(match_screen.run == :restart && match_step == 4, "game exited immediately after the winning move")
assert(match_rules_opened == 1, "the global rules action opened its dialog more than once")
assert(writes == 1 && match_events.length == 7, "a finished-game action wrote extra events")
assert(match_alerts == ["The game has already ended."], "finished-game action did not announce its rejection")
assert(match_controls.first.instance_variable_get(:@timers).empty?, "finished game left a timer running")

# The UI keeps a valid row as slots contract. Named seats use the same path.
bot_table = row.merge("game" => "farkle", "bot_count" => 3, "__discovery_protocol" => GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL)
bot_updates = []
bot_transport = Object.new
bot_transport.define_singleton_method(:live_store?) { true }
bot_transport.define_singleton_method(:room_snapshot) do |_table|
  { table: bot_table.dup, members: ["Alice"], bots: GameRoomParticipants.bots_for(7, bot_table["bot_count"], names: bot_table["bot_names"]) }
end
bot_transport.define_singleton_method(:update_room) do |_table, changes, actor:|
  assert(actor == "Alice", "computer update lost its owner")
  bot_updates << changes
  bot_table.merge(changes)
end
bot_lobby = LobbyRepository.new(nil, transport: bot_transport, server_tables: {})
bot_manager = EltenGameRoom.allocate
bot_manager.instance_variable_set(:@lobby, bot_lobby)
bot_game = GameRoomGames::Farkle.new
bot_game_active = false
bot_manager.define_singleton_method(:load_room_state) do |_table, **_options|
  GameRoomLifecycle::State.new(
    room: bot_lobby.snapshot_for(bot_table), game: bot_game,
    game_snapshot: bot_game_active ? Struct.new(:session).new(session) : nil,
    replay: bot_game_active ? replay : nil
  )
end
bot_manager.define_singleton_method(:run_network_task) { |_title, &operation| operation.call }
rows_for_bots = lambda do
  bot_manager.send(:room_user_rows, bot_manager.send(:load_room_state, bot_table))
end
bot_layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new, user_items: rows_for_bots.call, phase: :waiting, own_table: true)
bot_layout.users.index = 2
GameRoomParticipantMenu.bind(bot_layout, available: -> { [:add_bot, :remove_bot] }) do |action, participant|
  bot_manager.send(:change_room_computer, bot_table, action, participant)
end
bot_delete_menu = FakeMenu.new
bot_layout.users.context(bot_delete_menu, false)
bot_global_menu = FakeMenu.new
bot_layout.form.context(bot_global_menu, false)
bot_delete_menu.options.find { |option| option[2] == :del }[3].call
assert(bot_updates == [{ "bot_count" => 2, "bot_names" => [nil, nil] }], "Delete did not update computer slots atomically")
bot_layout.update_users(rows_for_bots.call)
assert(bot_layout.users.index == 2 && bot_layout.selected_participant == "bot:7:2", "middle-computer Delete moved the list position")
bot_manager.send(:change_room_computer, bot_table, :remove_bot, "bot:7:2")
bot_layout.update_users(rows_for_bots.call)
assert(bot_table["bot_count"] == 1 && bot_layout.selected_participant == "bot:7:1", "last-computer Delete left an invalid list selection")
bot_global_menu.options.find { |option| option[2] == "o" }[3].call
assert(bot_table["bot_count"] == 2, "UI could not add a computer using the original repository API")
write_count = bot_updates.length
bot_manager.send(:change_room_computer, bot_table, :remove_bot, "Alice")
bot_manager.send(:change_room_computer, bot_table, :remove_bot, "bot:7:99")
bot_game_active = true
bot_manager.send(:change_room_computer, bot_table, :remove_bot, "bot:7:1")
bot_global_menu.options.find { |option| option[2] == "o" }[3].call
bot_game_active = false
bot_table["bot_count"] = 7
bot_global_menu.options.find { |option| option[2] == "o" }[3].call
bot_table["bot_count"] = 2
bot_table["owner"] = "Bob"
bot_manager.send(:change_room_computer, bot_table, :remove_bot, "bot:7:1")
bot_global_menu.options.find { |option| option[2] == "o" }[3].call
assert(bot_updates.length == write_count, "UI bypassed current participant, phase, capacity or owner checks")
# A control anchor arrives as table_changed without another game move. The
# native screen must leave its old replay even when event IDs are unchanged.
match_screen.define_singleton_method(:fetch_room_snapshot) { [:updated, room, []] }
[:refresh, :new_session].each do |next_action|
  match_sync.define_singleton_method(:next_event) { |**_options| GameRoomSync::Event.new(kind: :table_changed) }
  match_screen.define_singleton_method(:remote_game_update) do |revision, **_options|
    assert(revision == [6, 6], 'Table control changed the known move revision')
    [next_action, next_action == :new_session ? 44 : nil]
  end
  current = match_screen.instance_variable_get(:@layout)
  current.form.index = current.form.fields.index(current.chat)
  current.chat.text = 'replacement draft'
  Form.driver = ->(form) { form.instance_variable_get(:@timers).each(&:fire) }
  result = match_screen.send(:wait_for_action, replay, [6, 6])
  assert(result == next_action, 'Table-only control change left the old hand/turn on screen')
  assert(current.focus_location == [:chat, 0] && current.chat.text == 'replacement draft', 'Participant refresh stole the chat focus or draft')
  assert(match_screen.instance_variable_get(:@new_session_id) == 44, 'Table wake-up lost the next game') if next_action == :new_session
end
match_screen.instance_variable_set(:@new_session_id, nil)

# Realtime games do not have a SessionRunner. A member leaving is only a
# table notification: no move/control epoch has been written yet. It must
# wake the normal replacement path even when the move revision is unchanged.
departed_room = LobbyRepository::TableSnapshot.new(table: row, members: ['Alice'], bots: [])
match_screen.instance_variable_set(:@table_owner, 'Alice')
match_screen.instance_variable_set(:@session, session)
replacement_transport = Object.new
replacement_transport.define_singleton_method(:set_seat_controller) do |*_, **_options|
  raise 'Replacement must run through the outer network task, not a UI callback'
end
match_screen.instance_variable_get(:@game_services)[:transport] = replacement_transport
match_screen.define_singleton_method(:fetch_room_snapshot) { [:updated, departed_room, []] }
match_screen.define_singleton_method(:remote_game_update) { |_revision, **_options| [nil, nil] }
[:table_changed, :recovery].each do |kind|
  match_sync.define_singleton_method(:next_event) { |**_options| GameRoomSync::Event.new(kind: kind) }
  current = match_screen.instance_variable_get(:@layout)
  current.form.index = current.form.fields.index(current.chat)
  current.chat.text = 'departure draft'
  waits = 0
  Form.driver = lambda do |form|
    waits += 1
    raise 'Departure refreshed only the player list, leaving the bot replacement asleep' if waits > 1
    form.instance_variable_get(:@timers).each(&:fire)
  end
  assert(match_screen.send(:wait_for_action, replay, [6, 6]) == :refresh,
    'A confirmed departure did not wake the replacement path')
  assert(current.focus_location == [:chat, 0] && current.chat.text == 'departure draft',
    'Departure stole the chat focus or draft')
end
match_screen.instance_variable_set(:@room_snapshot, room)

[GameRoomGames::AudioBall.new, GameRoomGames::AxelPong.new].each do |realtime_game|
  # Exercise run itself, not only its wake-up predicate. The native screen
  # receives the transport through game_services; it has no @transport field.
  # Stop at the external write boundary, without pretending to execute a bot.
  departure_repository = InterfaceGameRepository.new
  departure_repository.define_singleton_method(:bot_turn_controller) { |_id| GameRoomBots::TurnController.new }
  departure_repository.define_singleton_method(:snapshot_for) do |current, **_options|
    GameRepository::GameSnapshot.new(session: current, events: [])
  end
  departure_guard = ->(*) { raise 'This UI fixture stops before the guarded external write' }
  departure_repository.define_singleton_method(:control_change_guard) do |**options|
    assert(options == {table: row, game: realtime_game, session: session, player: 'Bob'},
      'Replacement guard received the wrong room/game/player')
    departure_guard
  end
  write_context = nil
  replacement_calls = []
  departure_transport = Object.new
  departure_transport.define_singleton_method(:set_seat_controller) do |target, **options|
    assert(write_context == :none, 'Replacement bypassed its outer network task')
    replacement_calls << [target, options]
    throw :departure_write, :observed
  end
  departure_screen = GameScreen.new(**arguments.merge(
    repository: departure_repository, game: realtime_game, layout: nil,
    room_snapshot_provider: -> { departed_room }, synchronizer: match_sync,
    game_services: { transport: departure_transport }
  ))
  departure_screen.define_singleton_method(:start_game_client) { true }
  # This test covers the fallback screen executor, not the native runner.
  departure_transport.define_singleton_method(:live_store?) { false }
  departure_screen.define_singleton_method(:network_task) do |_title, **options, &operation|
    write_context = options[:ui]
    begin
      operation.call
    ensure
      write_context = nil
    end
  end
  Form.driver = ->(_form) { raise 'Screen waited for input instead of replacing the departed player' }
  assert(!departure_screen.instance_variable_defined?(:@transport), 'Test invented a transport absent from the real screen')
  assert(catch(:departure_write) { departure_screen.run } == :observed, 'Realtime run did not use the supplied transport')
  assert(replacement_calls == [[row, {session_id: departure_repository.session_id(session), seat: 'Bob', bot: true,
    control_guard: departure_guard}]],
    'Realtime run replaced the wrong seat or wrote more than once')

  gate = GameScreen.allocate
  gate.instance_variable_set(:@game, realtime_game)
  gate.instance_variable_set(:@repository, repository)
  gate.instance_variable_set(:@game_services, { transport: replacement_transport })
  gate.instance_variable_set(:@session, session)
  gate.instance_variable_set(:@table_owner, 'Alice')
  assert(gate.send(:departed_players_for_replacement, replay, departed_room) == ['Bob'], 'Realtime game lost its absent player')
  assert(gate.send(:departed_players_for_replacement, replay, room).empty?, 'Present human would be replaced')
  assert(gate.send(:departed_players_for_replacement, replay, nil).empty?, 'A failed read would replace a human')
  assert(gate.send(:departed_players_for_replacement, finished_replay, departed_room).empty?, 'Finished game would gain a bot')
  [{ '__frozen' => true }, { '__control_ready' => false }, { '__controllers' => { 'Bob' => 'bot' } }].each do |guard|
    gate.instance_variable_set(:@session, session.merge(guard))
    assert(gate.send(:departed_players_for_replacement, replay, departed_room).empty?, "Ignored replacement guard #{guard}")
  end
  gate.instance_variable_set(:@session, session)
  gate.instance_variable_set(:@table_owner, 'Bob')
  assert(gate.send(:departed_players_for_replacement, replay, departed_room).empty?, 'Guest attempted a replacement')
  gate.instance_variable_set(:@table_owner, 'Alice')
  gate.instance_variable_set(:@session_runner, Object.new)
  assert(gate.send(:departed_players_for_replacement, replay, departed_room).empty?, 'UI duplicated the session runner')
  gate.instance_variable_set(:@session_runner, nil)
  gate.instance_variable_set(:@game, GameRoomGames::Scrabble.new)
  assert(gate.send(:departed_players_for_replacement, replay, departed_room).empty?, 'A game without bots gained one')
end
match_screen.instance_variable_get(:@game_services).delete(:transport)

# Remote closure is not Escape: neither active nor finished games may open
# the voluntary-leave confirmation, or loop back into the closed room.
match_screen.define_singleton_method(:fetch_room_snapshot) { [:closed, nil, []] }
match_screen.define_singleton_method(:remote_game_update) { |_revision, **_options| [nil, nil] }
completed_events = match_events.dup
[:table_changed, :recovery].product([:active, :finished]).each do |kind, phase|
  match_events.replace(phase == :active ? completed_events.first(6) : completed_events)
  match_sync.define_singleton_method(:next_event) { |**_options| GameRoomSync::Event.new(kind: kind) }
  Form.driver = ->(form) { form.instance_variable_get(:@timers).each(&:fire) }
  assert(match_screen.run == :room_closed, "#{kind}/#{phase} mapped remote closure to a voluntary leave")
end
state = finished
forgotten = false
app.define_singleton_method(:run_game_screen) { |*_args, **_options| :room_closed }
app.define_singleton_method(:leave_table_from_screen) { |_table| raise "remote closure asked to leave again" }
app.define_singleton_method(:forget_room_membership) { |_table| forgotten = true }
app.send(:show_table_screen, row)
assert(forgotten && app.instance_variable_get(:@table_layouts).empty?, "remote closure retained the room UI")
Form.driver = nil
puts "Room interface lifecycle tests passed"
