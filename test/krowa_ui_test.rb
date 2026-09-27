require_relative "support/room_interface"
require_relative "support/krowa"
require_relative "../games/krowa_support/client"

# Drive the real screen wiring with deterministic native-control doubles.
run = KrowaTestGame.new
run.automatic
game = run.game
row = {"__id" => 2, "owner" => "Alice", "game" => "krowa", "max_players" => 8,
  "status" => "playing", "game_options" => run.session["options"]}
room = LobbyRepository::TableSnapshot.new(table: row, members: ["Alice"], bots: [])
controller = Object.new
controller.define_singleton_method(:cancel) { |_| }
screen = GameScreen.allocate
screen.define_singleton_method(:getkeychar) { "" }
{
  game: game, repository: run.repository, session: run.session, table: row,
  table_owner: "Alice", room_snapshot: room, surface_state: {},
  board_preferences: GameRoomBoardPreferences.new(run.program, game.id),
  history_navigator: GameRoomHistory::Navigator.new, bot_turn_controller: controller,
  turn_history_entries: {}, activity_entries: []
}.each { |key, value| screen.instance_variable_set("@#{key}", value) }
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
assert(layout.surface.fields.first.text.empty?, "answer not cleared")
layout.chat.text = "chat draft"
layout.chat.index = 3; layout.chat.check = 1

Form.driver = lambda do |form|
  layout.surface.fields.first.text = "xyz"
  layout.surface.fields.first.index = 2; layout.surface.fields.first.check = 1
  previous = screen.instance_variable_get(:@selected_surface_action)
  form.trigger(:key_d, [false, false, false])
  assert(screen.instance_variable_get(:@selected_surface_action) == previous, "plain d opens settings")
  form.trigger(:key_d, [false, true, false])
end
assert(screen.send(:wait_for_action, run.replay, {}) == :game_action, "Ctrl+D failed in active game")
assert(screen.instance_variable_get(:@selected_surface_action)["action"] == "krowa_audio", "settings routed to move")
Form.driver = lambda do |_form|
  assert([layout.surface.fields.first.text, layout.surface.fields.first.index, layout.surface.fields.first.check] == ["xyz", 2, 1], "settings lost typed answer/selection")
  assert([layout.chat.text, layout.chat.index, layout.chat.check] == ["chat draft", 3, 1], "settings lost chat")
  layout.surface.fields.find { |field| field.is_a?(Button) && field.label == "Add noun to dictionary and check" }.trigger(:press)
end
assert(screen.send(:wait_for_action, run.replay, {}) == :game_action, "custom noun button not wired")
selected = screen.instance_variable_get(:@selected_surface_action)
assert(selected["action"] == "add_word" && selected["answer"] == "xyz", "custom noun action malformed")

run.surrender("Alice"); run.automatic
Form.driver = lambda do |form|
  assert(!form.fields.include?(layout.restart_button), "solo immediate restart bypasses daily start rules")
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
%w[krowa_audio krowa_gallery].each do |action|
  assert(client.action({"kind" => "command", "action" => action}, run.replay, "Alice"), "local action rejected")
end
assert(client.action({"kind" => "command", "action" => "krowa_definition", "word" => "kot"}, run.replay, "Alice"), "definition rejected")
assert(local_calls == [:settings, :gallery, [:definition, "kot"]], "local services not dispatched")
client.close

waiting = GameRoomLayout::Screen.new(view_spec: game.waiting_view_spec("Alice"), history_items: [], user_items: [], users_header: "Users", phase: :waiting, own_table: true)
commands = []
waiting.begin_bindings
waiting.bind_status_commands { |name| commands << name }
app.send(:bind_game_room_shortcuts, waiting.form, game) { |name| commands << name }
waiting.form.trigger(:key_d, [false, false, false])
waiting.form.trigger(:key_d, [true, true, false])
assert(commands.empty?, "room modifiers ignored")
waiting.form.trigger(:key_d, [false, true, false])
waiting.form.fields.find { |field| field.is_a?(Button) && field.label == "Krowa gallery" }.trigger(:press)
assert(commands == %w[krowa_audio krowa_gallery], "waiting controls not dispatched")

assert(EltenGameRoom::GAME_REGISTRY.ids.count { |id| EltenGameRoom::GAME_REGISTRY.build(id).supports_leaderboards? } == 1, "legacy games queried for rankings")
assert(EltenGameRoom::MAIN_OPTIONS.include?("Leaderboards"), "rankings absent from main menu")
Form.driver = nil
puts "Krowa UI: Enter/custom nouns, active and waiting Ctrl+D, gallery after finish, local services, answer/chat focus and optional rankings OK"
