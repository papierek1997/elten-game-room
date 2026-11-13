require_relative "../../support/room_interface"

game = GameRoomGames::Balut.new
sheet = GameRoomGames::BalutScoring::CATEGORIES.to_h { |category| [category, []] }
state = {players: %w[Alice Bob], sheets: {"Alice" => sheet, "Bob" => sheet.transform_values(&:dup)},
  current_player: "Alice", dice: [4, 4, 4, 4, 2], turn_rolls: 1}
replay = GameRoomGames::Replay.new(players: state[:players], current_player: "Alice", state: state)
surface = GameSurfaces.build(game.surface_spec(replay, "Alice"))
intent = nil
surface.on_action { |input| intent = input }
surface.fields.first.trigger(:select, [0])
raise "Enter did not open the grid" unless intent["action"] == "open_score_grid"
shortcut = game.surface_action_shortcut(intent, replay, "Alice")
screen = GameScreen.allocate
Form.driver = lambda do |form|
  grid = form.fields.first
  grid.trigger(:select, [0, 0])
  grid.trigger(:select, [6, 0])
end
action = screen.send(:activate_game_shortcut, shortcut)
raise "Wrong score action" unless action["category"] == "fours"
raise "Score action rejected" unless game.action_for(action, replay, "Alice").first == :ok
puts "PASS Balut: Enter opens score grid and submits Czwórki"

sheet[:fours].replace([16, 16, 12, 8])
shortcut = game.game_shortcuts(replay, "Alice").find { |key| key.key == "b" }
raise "Full row remains writable" if shortcut.default_value.row_actions.any? { |action| action['category'] == 'fours' }
readonly = game.send(:score_grid, state, 'Alice', writable: false)
row = readonly.cells.first
raise "Missing full row total or remaining threshold" unless row[5].include?("52") && row.last.end_with?("0")
inspector = GameSurfaces.build(readonly)
inspected_action = nil
inspector.on_action { |input| inspected_action = input }
inspector.fields.first.trigger(:select, [0, 0])
raise 'Inspecting a read-only sheet created a move' if inspected_action
raise 'A chat coordinate bypassed the read-only sheet' if inspector.movement_command(['A1']).action
raise "Wrong game total after row bonus" unless game.total_score(state, "Alice").zero?
puts "PASS Balut: full Czwórki row, total 52, two game points"

sheet[:fours].clear()
screen.instance_variable_set(:@session, {"__frozen" => true})
raise "Frozen table allowed a score" if screen.send(:activate_game_shortcut,
  game.surface_action_shortcut(intent, replay, "Alice"))
puts "PASS Balut: frozen table prevents grid submission"

screen.instance_variable_set(:@session, {})
parent_form = Object.new
def parent_form.game_room_pending_operation; true; end
def parent_form.open_game_room_background_help(form); form.wait; end
screen.instance_variable_set(:@layout, Struct.new(:form).new(parent_form))
shortcut = game.surface_action_shortcut(intent, replay, "Alice")
raise "Expected writable row before pending guard" unless shortcut.default_value.row_actions.any? { |action| action['category'] == 'fours' }
chat_surface = GameSurfaces.build(shortcut.default_value)
chat_action = chat_surface.movement_command(['G1']).action
raise 'Chat coordinates did not use the same declared row action' unless chat_action['kind']=='dice' && chat_action['category']=='fours' && chat_action.source=='chat_command'
raise "Pending write allowed another score" if screen.send(:activate_game_shortcut, shortcut)
puts "PASS Balut: pending write prevents grid submission"
