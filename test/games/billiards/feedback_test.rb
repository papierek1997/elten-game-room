require_relative '../../support/billiards_native'

module BilliardsFeedbackTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  def self.run
    table = B::Table.new
    table.pockets.each_with_index do |(x,y), id|
      cue = B::Ball.new(id: 0, x: table.width / 2, y: table.height / 2)
      hit = B::Geometry.trace(table, [cue], 0, B::Geometry.angle(x-cue.x, y-cue.y))
      assert_equal([:pocket, id], hit.values_at(:kind, :id), 'Pocket numbering does not follow the actual opening')
      assert_equal(3000, B::AimAudio.frequency(hit))
      assert(B::Presentation.pocket(id).start_with?("Pocket #{id+1},"))
    end
    assert_equal('Ball 8, black', B::Presentation.ball(8))
    assert_equal('Ball 9, yellow, striped', B::Presentation.ball(9))
    assert_equal('Ball 15, maroon, striped', B::Presentation.ball(15))
    jaw = [B::Ball.new(id: 0, x: 1.309, y: 0.3)]
    hit = B::Geometry.trace(table, jaw, 0, 270)
    assert_equal([:rail, :jaw], hit.values_at(:kind, :id), 'Bed crossing hid an outside pocket jaw')
    assert_equal(nil, B::AimAudio.frequency(hit), 'Jaw falsely played the pocket tone')
    result = B::Physics.simulate(table, jaw, {'angle'=>27000,'power'=>170,'top'=>0,'side'=>0})
    assert(result.events.any? { |e| e[:kind] == :rail && e[:rail] == :jaw })
    driver, match = BilliardsNativeDriver.new, BilliardsFixture::Match.new
    pointer = match.replay
    pointer.state[:balls].first.x, pointer.state[:balls].first.y = 1.27, 0.3
    pointer.state[:balls][1].x, pointer.state[:balls][1].y = 1.8, 0.3
    surface = GameSurfaces.build(match.game.surface_spec(pointer, 'Alice'))
    surface.action_guard = -> { true }
    SpeechOutput.reset
    surface.send(:adjust, 'angle', 9000)
    assert_equal(1, SpeechOutput.calls.size)
    assert_equal('Pocket 5', SpeechOutput.calls.last.first)
    surface.send(:adjust, 'angle', 1)
    assert_equal(1, SpeechOutput.calls.size, 'Pocket entry repeated speech on every adjustment')
    driver.frame(surface.fields.first, [0x25])
    driver.frame(surface.fields.first)
    assert_equal(1, SpeechOutput.calls.size, 'Release repeated the pocket or appended an unwanted angle')
    SpeechOutput.reset
    surface.send(:adjust, 'angle', -100)
    surface.send(:adjust, 'angle', 200)
    surface.send(:adjust, 'angle', -201)
    assert_equal(1, SpeechOutput.calls.size, 'Re-entering a pocket was not announced')
    surface.send(:adjust, 'angle', -9000)
    SpeechOutput.reset
    driver.frame(surface.fields.first, [0x25])
    driver.frame(surface.fields.first)
    assert(SpeechOutput.calls.last.first.start_with?('Ball 1, yellow'), 'Released aim starts with an angle instead of ball identity')
    assert(match.game.game_shortcuts(match.replay, 'Alice').any? { |s| s.key == 's' && s.kind == :announcement })
    assert(match.game.game_shortcuts(match.replay, 'Alice').any? { |s| s.key == 'v' && s.kind == :surface })

    position = match.replay
    position.state[:balls].first.x, position.state[:balls].first.y = 0.7, 0.3
    position.state[:balls][1].x, position.state[:balls][1].y = 1.2, 0.3
    shot = {'angle'=>18000, 'power'=>400, 'top'=>0, 'side'=>0}
    bank = GameSurfaces.build(match.game.surface_spec(position, 'Alice'), state: {'game_id'=>'billiards-test', 'shot'=>shot})
    bank.action_guard = -> { true }
    bank.on_action { raise 'Rebound preview wrote a move' }
    before = Marshal.dump(position)
    bank.handle_command('rebound')
    assert(SpeechOutput.calls.last.first.include?('left cushion') && SpeechOutput.calls.last.first.include?('Ball 1, yellow'), 'Bank prediction differs from the physical left-cushion contact')
    assert_equal(before, Marshal.dump(position), 'Bank preview changed the model')
    bank.send(:adjust, 'power', -390)
    bank.handle_command('rebound')
    assert(SpeechOutput.calls.last.first.include?('stops before reaching'), 'Weak shot falsely promises a rebound')
    bank.send(:adjust, 'angle', 18000)
    bank.handle_command('rebound')
    assert(SpeechOutput.calls.last.first.include?('Aim at a cushion'), 'Direct aim was described as a bank')
    weak = B::Physics.simulate(table, [B::Ball.new(id: 0,x: 1.27,y: 0.0286)],
      {'angle'=>27000,'power'=>21,'top'=>0,'side'=>0})
    assert(weak.balls.first.on_table? && weak.balls.first.y < 0, 'Weak-mouth fixture did not stop outside the bed')
    position.state[:balls] = weak.balls
    outside = GameSurfaces.build(match.game.surface_spec(position, 'Alice'), state: {'game_id'=>'billiards-test', 'shot'=>shot.merge('angle'=>27000)})
    outside.handle_command('rebound')
    assert(SpeechOutput.calls.last.first.include?('Aim at a cushion'))
    outside.define_singleton_method(:shot_line) { nil }
    outside.handle_command('rebound')
    assert(SpeechOutput.calls.last.first.include?('Aim at a cushion'), 'Missing ray crashed the rebound hint')
    assert_equal([], match.events)
    puts 'Billiards feedback: six numbered pockets, 3000 Hz, deduplicated entry speech, number/colour first, shared S, V physical rebound/weak/direct aim and read-only previews passed.'
  end
end
BilliardsFeedbackTest.run if $PROGRAM_NAME == __FILE__
