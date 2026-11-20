require_relative "../../support/background_help_native"
require EltenTestHost.file("src/ui/controls/grid_box.rb")
require_relative "../../../lib/game_surfaces"
require_relative "../../../games/balut"

game = GameRoomGames::Balut.new
sheet = GameRoomGames::BalutScoring::CATEGORIES.to_h { |category| [category, []] }
state = {sheets: {"Alice" => sheet}, dice: [4, 4, 4, 4, 2]}
surface = GameSurfaces.build(game.send(:score_grid, state, "Alice", writable: true))
control = surface.fields.first
driver = BackgroundHelpNativeDriver.new
root = Object.new
root.instance_variable_set(:@wait, true)
driver.root = root
driver.keys = [[39], [], [40], [], [37], [], [38], [], [13]]
positions = [[1, 0], [1, 1], [0, 1], [0, 0]]
selected = nil
surface.on_action { |action| selected = action.to_h }
9.times do |index|
  driver.tick(root)
  control.update
  next unless index.even? && index < 8

  x, y = positions[index / 2]
  expected = game.send(:score_grid, state, "Alice", writable: true).cells[y][x]
  spoken = SpeechOutput.calls.last&.first.to_s
  raise "Missing speech for #{expected.inspect}: #{spoken.inspect}" unless spoken.include?(expected)
  raise "Wrong grid position: #{surface.state.inspect}" unless surface.state.values_at("x", "y") == positions[index / 2]
end
raise "Native Enter did not select the focused row" unless selected == {"kind" => "dice", "action" => "score", "category" => "fours"}
puts "PASS Balut: all four native arrow bindings and Enter"

# A proposed entry is not a final game-point award. Read the same native
# status cell that previously promised points after the target was impossible.
sheet[:fours] = [0, 0]
state[:dice] = [1, 1, 1, 1, 2]
surface = GameSurfaces.build(game.send(:score_grid, state, 'Alice', writable: true))
control = surface.fields.first
control.focus
raise 'Native label confuses the entry with game points' unless SpeechOutput.calls.last.first.include?('Fours: enter 0')
SpeechOutput.reset
driver.keys = Array.new(6) { [[39], []] }.flatten(1) + [[13]]
selected = nil
surface.on_action { |action| selected = action.to_h }
13.times do |index|
  driver.tick(root)
  control.update
  if index == 10
    raise 'Native row still promises an impossible bonus' unless SpeechOutput.calls.last.first.include?('No game points can be earned in this category.')
  end
end
raise 'Row navigation reread the table header' if SpeechOutput.calls.any? { |call| call.first.include?('Score sheet: Alice') }
raise 'The status cell cannot confirm its zero entry' unless selected && selected['category'] == 'fours'
puts 'PASS Balut native entry/status: clear label, impossible points, quiet navigation and Enter from the status cell'
