require_relative "../../support/room_interface"
require_relative "../../support/krowa"
require_relative "../../../games/krowa_support/client"

# Drive the real screen wiring with deterministic native-control doubles.
run = KrowaTestGame.new
run.automatic
game = run.game
row = {"__id" => 2, "owner" => "Alice", "game" => "krowa", "max_players" => 8,
  "status" => "playing", "game_options" => run.session["options"]}
room = LobbyRepository::TableSnapshot.new(table: row, members: ["Alice"], bots: [])
controller = GameRoomBots::TurnController.new
run.repository.define_singleton_method(:bot_turn_controller) { |_table_id| controller }
screen = GameScreen.new(program: run.program, repository: run.repository, game: game,
  session: run.session, table: row, table_owner: "Alice",
  room_snapshot_provider: -> { room }, synchronizer: nil)
screen.define_singleton_method(:getkeychar) { "" }
screen.instance_variable_set(:@room_snapshot, room)
screen.instance_variable_set(:@activity_entries, [])
Form.driver = lambda do |form|
  layout = screen.instance_variable_get(:@layout)
  answer = layout.surface.fields.first
  assert(answer.is_a?(EditBox), "solo has no editable answer")
  answer.text = "las"
  answer.trigger(:select)
end
assert(screen.send(:wait_for_action, run.replay, {}) == :game_action, "Enter not submitted by answer control")
selected = screen.instance_variable_get(:@selected_surface_action)
assert(selected["answer"] == "las" && selected["action"] == "submit", "Enter lost typed word")
layout = screen.instance_variable_get(:@layout)
assert(layout.surface.fields.first.text == "las", "answer cleared before the move was accepted")
layout.surface.action_accepted(selected)
assert(layout.surface.fields.first.text.empty?, "accepted answer not cleared")
layout.chat.text = "chat draft"
layout.chat.index = 3; layout.chat.check = 1
settings_opened = 0
settings_client = Object.new
settings_client.define_singleton_method(:show_settings) { settings_opened += 1 }
settings_client.define_singleton_method(:context_data) { {} }
screen.instance_variable_set(:@game_client, settings_client)

Form.driver = lambda do |form|
  layout.surface.fields.first.text = "xyz"
  layout.surface.fields.first.index = 2; layout.surface.fields.first.check = 1
  previous = screen.instance_variable_get(:@selected_surface_action)
  form.trigger(:key_d, [false, false, false])
  assert(screen.instance_variable_get(:@selected_surface_action) == previous, "plain d opens settings")
  form.trigger(:key_d, [false, true, false])
  assert(screen.instance_variable_get(:@selected_surface_action) == previous, "old Ctrl+D still opens settings")
  menu = FakeMenu.new
  form.context(menu)
  settings = menu.options.find { |item| item.first == "Krowa settings" }
  assert(settings && settings[2] == "p", "shared table menu has no Ctrl+P")
  settings.last.call
  assert(settings_opened == 1, "shared settings did not open the active client")
  assert([layout.surface.fields.first.text, layout.surface.fields.first.index, layout.surface.fields.first.check] == ["xyz", 2, 1], "settings lost typed answer/selection")
  assert([layout.chat.text, layout.chat.index, layout.chat.check] == ["chat draft", 3, 1], "settings lost chat")
  layout.surface.fields.find { |field| field.is_a?(Button) && field.label == "Add noun to dictionary and check" }.trigger(:press)
end
assert(screen.send(:wait_for_action, run.replay, {}) == :game_action, "custom noun button not wired")
selected = screen.instance_variable_get(:@selected_surface_action)
assert(selected["action"] == "add_word" && selected["answer"] == "xyz", "custom noun action malformed")

run.surrender("Alice"); run.automatic
Form.driver = lambda do |form|
  assert(form.fields.include?(layout.restart_button) && layout.restart_button.label == "Start game", "random game cannot restart at the same table")
  form.fields.find { |field| field.is_a?(Button) && field.label == "Krowa gallery" }.trigger(:press)
end
assert(screen.send(:wait_for_action, run.replay, {}) == :game_action, "finished gallery not wired")
assert(screen.instance_variable_get(:@selected_surface_action)["action"] == "krowa_gallery", "wrong finished status action")

app = EltenGameRoom.allocate
app.define_singleton_method(:game_room_server_tables) { raise "private accessor must be injected" }
client = game.build_client(run.program, server_tables: Object.new)
assert(client.start, "client initialization called private server accessor")
local_calls = []
client.define_singleton_method(:settings_dialog) { local_calls << :settings }
client.define_singleton_method(:gallery_dialog) { local_calls << :gallery }
client.define_singleton_method(:definition_dialog) { |word| local_calls << [:definition, word] }
client.show_settings
%w[krowa_gallery].each do |action|
  assert(client.action({"kind" => "command", "action" => action}, run.replay, "Alice"), "local action rejected")
end
assert(client.action({"kind" => "command", "action" => "krowa_definition", "word" => "kot"}, run.replay, "Alice"), "definition rejected")
assert(local_calls == [:settings, :gallery, [:definition, "kot"]], "local services not dispatched")
client.close

waiting = GameRoomLayout::Screen.new(view_spec: game.waiting_view_spec("Alice"), history_items: [], user_items: [], users_header: "Users", phase: :waiting, own_table: true)
commands = []
waiting.begin_bindings
waiting.bind_status_commands { |name| commands << name }
app.define_singleton_method(:show_krowa_settings) { commands << "settings" }
GameRoomParticipantMenu.bind(waiting, available: -> { [] }, game: game,
  settings: GameRoomParticipantMenu.settings_callback(game, program: app)) { raise "settings became a game action" }
waiting.form.trigger(:key_d, [false, false, false])
waiting.form.trigger(:key_d, [true, true, false])
assert(commands.empty?, "room modifiers ignored")
waiting.form.trigger(:key_d, [false, true, false])
assert(commands.empty?, "old Ctrl+D remains in the waiting room")
menu = FakeMenu.new
waiting.form.context(menu)
menu.options.find { |item| item.first == "Krowa settings" }.last.call
waiting.form.fields.find { |field| field.is_a?(Button) && field.label == "Krowa gallery" }.trigger(:press)
assert(commands == %w[settings krowa_gallery], "waiting controls not dispatched")

daily = KrowaTestGame.new(variant: "daily")
daily.automatic; daily.surrender("Alice"); daily.automatic
assert(!daily.game.game_view_spec(daily.replay, "Alice").restartable, "daily restart bypasses one-start restriction")
active = KrowaTestGame.new
active.automatic
assert(active.game.local_action({"kind" => "command", "action" => "krowa_gallery"}, active.replay, "Alice") == :gallery_unavailable,
  "hidden gallery remains callable during a game")
assert(active.game.game_view_spec(active.replay, "Alice").status_commands.empty?, "active gallery remains visible")

ranking_games = EltenGameRoom::GAME_REGISTRY.ids.select { |id| EltenGameRoom::GAME_REGISTRY.build(id).supports_leaderboards? }
assert(ranking_games == %w[krowa], "retired sports rankings remain in the shared leaderboard menu")
assert(EltenGameRoom::MAIN_OPTIONS.include?("Leaderboards"), "rankings absent from main menu")
Form.driver = nil
puts "Krowa UI: Enter/custom nouns, shared Ctrl+P menu, gallery phases, same-table restart, answer/chat focus and rankings OK"
