require_relative '../../support/billiards_native'
require_relative '../../../lib/game_screen'

module BilliardsObjectPredictionTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.run
    driver, match = BilliardsNativeDriver.new, BilliardsFixture::Match.new
    replay = match.replay
    replay.state[:balls].first.x, replay.state[:balls].first.y = 1.27, 0.4
    replay.state[:balls][1].x, replay.state[:balls][1].y = 1.27, 0.16
    snapshot = Marshal.dump(replay)
    shot = {'angle'=>27000, 'power'=>180, 'top'=>0, 'side'=>0}
    result = B::Physics.simulate(B::Table.new, replay.state[:balls], shot)
    message = B::Presentation.object_prediction(result, 1)
    assert(message.start_with?('Ball 1, yellow:'))
    assert(message.include?('Pocket 2'))
    weak = B::Physics.simulate(B::Table.new, replay.state[:balls], shot.merge('power'=>1))
    assert(B::Presentation.object_prediction(weak, 1).include?('will not reach'))
    surface = GameSurfaces.build(match.game.surface_spec(replay, 'Alice'), state: {'game_id'=>'billiards-test', 'shot'=>shot})
    surface.on_action { raise 'Prediction wrote a move' }
    surface.action_guard = -> { true }
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    surface.attach_form(form)
    screen = GameScreen.allocate
    GameRoomShortcutBindings.bind(form, surface.fields, match.game.game_shortcuts(replay, 'Alice'), consume: ->(_key) {}) do |shortcut|
      screen.send(:activate_game_shortcut, shortcut, surface, replay: replay)
    end
    comma = match.game.game_shortcuts(replay, 'Alice').find { |key| key.key == 'comma' }
    assert_equal(',', GameRoomShortcutBindings.key_label(comma))
    SpeechOutput.reset
    driver.frame(form, [0xbc])
    driver.frame(form)
    assert_equal(message, SpeechOutput.calls.last.first)
    assert_equal(0, form.index)
    assert_equal(snapshot, Marshal.dump(replay))
    assert_equal([], match.events)
    balls = [B::Ball.new(id: 0, x: 0.3, y: 0.4), B::Ball.new(id: 1, x: 0.7, y: 0.4), B::Ball.new(id: 2, x: 1.1, y: 0.4)]
    result = B::Physics.simulate(B::Table.new, balls, shot.merge('angle'=>0, 'power'=>350, 'side'=>20, 'top'=>30))
    assert(B::Presentation.object_prediction(result, 1).include?('Ball 2'))
    puts 'Aimed-ball prediction: actual pocket/collision trajectory, weak shot, angle/power/spin, native comma, spoken output and no modal/focus change/writes passed.'
  end
end
BilliardsObjectPredictionTest.run if $PROGRAM_NAME == __FILE__
