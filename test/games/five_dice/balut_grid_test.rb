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
row = shortcut.default_value.cells.first
raise "Full row remains writable" if shortcut.payload.fetch("cells").key?("6,0")
raise "Missing full row total" unless row[5].include?("52") && row.last.end_with?("2")
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
raise "Expected writable cell before pending guard" unless shortcut.payload.fetch("cells").key?("6,0")
raise "Pending write allowed another score" if screen.send(:activate_game_shortcut, shortcut)
puts "PASS Balut: pending write prevents grid submission"
