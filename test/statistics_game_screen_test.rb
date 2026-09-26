require_relative "support/background_help_game_screen"

assert(GameScreen.instance_method(:initialize).parameters.include?([:key, :statistics_observer]),
  "GameScreen has no statistics observer contract")
[false, true].each do |finished|
  h, screen = screen_fixture(GameRoomGames::FourInARow.new)
  if finished
    %w[Alice Bob Alice Bob Alice Bob Alice].each do |actor|
      h.write(actor, [GameRoomGames::EventCommand.new(action: "drop", value: actor == "Alice" ? "1" : "2")])
    end
    assert(h.replay("Alice").finished?, "The screen fixture did not complete a real game")
  end
  seen = []
  screen.instance_variable_set(:@statistics_observer, ->(session, replay) { seen << [session["__id"], replay.finished?] })
  Form.driver = ->(_form) { screen.instance_variable_get(:@layout).back_button.trigger(:press) }
  result = h.as("Alice") { screen.run }
  assert(result == :back, "Statistics changed normal screen navigation")
  assert(seen.include?([h.session["__id"], finished]), "The non-runner screen missed its confirmed replay")
end
puts "PASS statistics observes real non-runner start and finished replay without changing UI exit"
