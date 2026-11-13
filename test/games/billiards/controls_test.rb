require_relative '../../support/ui'
require_relative '../../../lib/game_surfaces'
require_relative '../../support/billiards'

def loop_update; Thread.pass; end

module BilliardsControlsTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.run
    assert_equal(35999, B::Controls.decimal('359,99', scale: 100, range: 0..359.99))
    assert_equal(1, B::Controls.decimal('0.1', scale: 10, range: 0.1..100))
    %w[NaN Infinity 1e2 1.0001 360].each do |value|
      assert_equal(nil, B::Controls.decimal(value, scale: 100, range: 0..359.99))
    end
    match = BilliardsFixture::Match.new
    surface = GameSurfaces.build(match.game.surface_spec(match.replay, 'Alice'))
    actions = []
    surface.on_action { |a| actions << a }
    surface.action_guard = -> { true }
    surface.send(:adjust, 'angle', -1)
    assert_equal(35999, surface.state['shot']['angle'])
    surface.send(:adjust, 'power', 1)
    assert_equal(351, surface.state['shot']['power'])
    surface.send(:submit, 'shot', 'shot'=>surface.state['shot'])
    assert_equal(:ok, match.game.action_for(actions.last, match.replay, 'Alice').first)
    surface.action_guard = -> { false }
    surface.send(:submit, 'shot', 'shot'=>surface.state['shot'])
    assert_equal(1, actions.size, 'Frozen view emitted a shot')
    restored = GameSurfaces.build(match.game.surface_spec(match.replay, 'Alice'), state: surface.state)
    assert_equal(surface.state, restored.state)
    changed = match.session.merge('__id'=>'new-practice')
    next_game = match.game.replay(changed, [], match.repository)
    reset = GameSurfaces.build(match.game.surface_spec(next_game, 'Alice'), state: surface.state)
    assert_equal(0, reset.state['shot']['angle'], 'New session inherited old aim')
    observer = GameSurfaces.build(match.game.surface_spec(match.replay, 'Observer'))
    observer.on_action { raise 'Observer emitted an action' }
    observer.send(:submit, 'finish')
    thin = match.replay
    thin.state[:balls][1].y += 0.06
    spin = {'angle'=>0, 'power'=>300, 'top'=>0, 'side'=>-100}
    surface = GameSurfaces.build(match.game.surface_spec(thin, 'Alice'), state: {'game_id'=>'billiards-test', 'shot'=>spin})
    assert(B::Geometry.trace(B::Table.new, thin.state[:balls], 0, 0)[:kind] != :ball, 'Fixture must miss without side-spin deflection')
    assert_equal(1, surface.send(:shot_line)[:id], 'Aim ignored the launch deflection')
    result = B::Physics.simulate(B::Table.new, thin.state[:balls], spin)
    assert_equal(1, result.events.find { |e| e[:kind] == :ball }&.fetch(:b), 'Predicted first contact differs from executed physics')
    surface.handle_command('line')
    assert($spoken_messages.last.start_with?('Ball 1, yellow, '), 'Spoken aim differs from actual side-spin contact or omits its colour')
    assert(!$spoken_messages.last.include?('shot line'), 'Aim retained the verbose preface')
    assert(B::Controls.shortcuts.map { |key, modifiers, *_| [key, modifiers] }.uniq.length == B::Controls.shortcuts.length)
    puts 'Billiards controls: decimal comma, precision, bounds, guarded action, spectator, draft retention and new-session reset passed.'
  end
end
BilliardsControlsTest.run if $PROGRAM_NAME == __FILE__
