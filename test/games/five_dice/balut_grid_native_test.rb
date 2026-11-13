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
surface.on_action { |action| selected = [action["x"], action["y"]] }
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
raise "Native Enter did not select the focused cell" unless selected == [0, 0]
puts "PASS Balut: all four native arrow bindings and Enter"
