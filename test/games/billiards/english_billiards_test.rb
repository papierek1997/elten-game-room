require_relative '../../support/billiards_english'
require_relative '../../../lib/billiards/english_billiards'

module BilliardsEnglishTest
  extend GameRoomTest::Assertions
  F = BilliardsEnglishFixture
  E = GameRoomBilliards::EnglishBilliards
  def self.run
    state = F.state
    assert_equal([0, 2], state[:balls].select(&:on_table?).map(&:id))
    assert_equal(:d, state[:hand])
    state[:balls][1].status = :table
    state[:balls][1].x = 1.7
    F.apply(state, [F.hit(0, 2), F.hit(0, 1), F.pot(2), F.pot(0)])
    assert_equal([8, 0], state[:scores], 'Cannon, red pot and red in-off must all score')
    assert_equal(8, state[:break_points])
    assert_equal(:d, state[:hand])
    assert(state[:balls][2].on_table?)
    assert_equal(0, state[:turn])

    simultaneous = F.state
    simultaneous[:hand] = nil
    simultaneous[:balls][1].status = :table
    F.apply(simultaneous, [F.hit(0, 2, t: 0.1), F.hit(0, 1, t: 0.1), F.pot(0)])
    assert_equal([4, 0], simultaneous[:scores], 'Simultaneous in-off is worth two, plus cannon')

    red = F.state
    red[:hand] = nil
    2.times { F.apply(red, [F.hit(0, 2), F.pot(2)]) }
    assert_equal(GameRoomBilliards::Rules.table(red[:options]).width / 2, red[:balls][2].x)
    F.apply(red, [F.hit(0, 2), F.pot(2)])
    assert_equal(GameRoomBilliards::Rules.table(red[:options]).width - 0.324, red[:balls][2].x)

    foul = F.state
    foul[:hand] = nil
    F.apply(foul, [F.pot(0), F.pot(2)])
    assert_equal([0, 2], foul[:scores])
    assert_equal(%w[english_accept english_reset], foul[:choices])
    assert(E.choose(foul, 'english_reset'))
    assert_equal(1, E.cue_id(foul))
    assert_equal(:d, foul[:hand])
    assert_equal([], foul[:choices])
    assert_equal(GameRoomBilliards::Rules.table(foul[:options]).width / 2, foul[:balls][0].x)

    limits = F.state
    limits[:hand] = nil
    limits[:english_hazards] = 15
    F.apply(limits, [F.hit(0, 2), F.pot(2)])
    assert_equal(:hazard_limit, limits[:ruling][:foul])
    assert_equal([0, 2], limits[:scores])
    cannon = F.state
    cannon[:hand] = nil
    cannon[:balls][1].status = :table
    cannon[:english_cannons] = 75
    F.apply(cannon, [F.hit(0, 2), F.hit(0, 1)])
    assert_equal(:cannon_limit, cannon[:ruling][:foul])

    miss = F.state
    miss[:balls][2].x = 0.4
    F.apply(miss, [F.rail(0, :right, x: 3.54)], positions: {0=>[1.0, 0.889]})
    assert_equal(:english_miss, miss[:ruling][:notice])
    assert_equal([0, 2], miss[:scores])
    assert_equal([], miss[:choices], 'English Miss must not offer the foul reset')

    finish = F.state(point_target: 5)
    finish[:hand] = nil
    finish[:scores][0] = 4
    F.apply(finish, [F.hit(0, 2), F.pot(2)])
    assert_equal(:finished, finish[:phase])
    assert_equal(0, finish[:winner])
    assert_equal(5, finish[:scores][0], 'Winning score is capped, full break is retained')
    assert_equal(3, finish[:break_points])
    clock = F.state(english_limit: 'time')
    assert(!E.expire(clock, elapsed_ms: 59_999))
    assert(E.expire(clock, elapsed_ms: 60_000))
    assert_equal(:finished, clock[:phase])
    assert_equal(nil, clock[:winner])
    assert_equal([0, 0], clock[:racks])
    boundary = F.state(baulk_crossing: true)
    boundary[:hand], boundary[:break_points] = nil, 99
    F.apply(boundary, [F.hit(0, 2), F.pot(2)])
    assert_equal(:baulk_crossing, boundary[:ruling][:foul])
    assert_equal([0, 2], boundary[:scores])
    crossed = F.state(baulk_crossing: true)
    crossed[:hand], crossed[:break_points] = nil, 99
    crossed[:balls][0].x = 1.0
    F.apply(crossed, [F.hit(0, 2), {kind: :crossing, a: 0, line: :baulk, direction: :left}, F.pot(2)])
    assert_equal(nil, crossed[:ruling][:foul])
    assert_equal(1, crossed[:english_baulk_window])

    pure = F.state
    pure[:hand], pure[:turn] = nil, 1
    pure[:balls][0].status = :potted
    pure[:balls][1].status = :table
    pure[:balls][1].x, pure[:balls][1].y = 1.7845, 0.4
    pure[:balls][2].x, pure[:balls][2].y = 1.7845, 0.16
    before = Marshal.load(Marshal.dump(pure))
    shot = {'angle'=>27000, 'power'=>180, 'top'=>0, 'side'=>0}
    result = GameRoomBilliards::Physics.simulate(GameRoomBilliards::Rules.table(pure[:options]), pure[:balls], shot, cue_id: 1)
    assert(result.events.any? { |event| event[:kind] == :pocket && event[:a] == 2 }, 'Real yellow-cue shot failed to pot red')
    pure[:balls] = result.balls.map(&:dup)
    E.resolve(pure, before, result, {'shot'=>shot, 'cue'=>1, 'call'=>0, 'mode'=>0, 'pocket'=>0})
    assert_equal([0,3], pure[:scores], 'Real yellow-cue score was assigned to white or treated as scratch')
    opponent = F.state
    opponent[:hand] = nil
    opponent[:balls][1].status = :table
    opponent[:balls][1].x = 1.5
    F.apply(opponent, [F.hit(0, 1), F.pot(1)])
    assert_equal([2,0], opponent[:scores])
    assert(!opponent[:balls][1].on_table?, 'Potting opponent incorrectly returned that ball immediately')
    assert_equal(0, opponent[:turn])
    absent = F.state
    absent[:hand], absent[:english_hazards] = nil, 14
    absent[:english_off_by][1] = 1
    F.apply(absent, [F.hit(0, 2), F.pot(2)])
    assert(absent[:balls][1].on_table?)
    assert_equal(0.737, absent[:balls][1].x)
    assert_equal(GameRoomBilliards::Rules.table(absent[:options]).height / 2, absent[:balls][1].y)
    extra = F.state(english_limit: 'time')
    extra[:scores] = [11,14]
    assert(E.expire(extra, elapsed_ms: 60_000))
    assert_equal(1, extra[:winner])
    multi = F.state(english_limit: 'time', race_to: 2)
    E.expire(multi, elapsed_ms: 60_000)
    assert_equal(:rack_end, multi[:phase])
    assert_equal(['next'], multi[:choices])
    assert_equal([0,0], multi[:racks])
    immutable = F.state
    immutable[:hand] = nil
    immutable[:balls][1].status = :table
    F.apply(immutable, [F.hit(0, 1), F.pot(1)], preserve_before: true)
    assert_equal(0, immutable[:english_off_by][1])
    puts 'English billiards: opening, combined/simultaneous scores, red spots, foul decisions, limits, English Miss, target and authoritative time expiry passed.'
  end
end
BilliardsEnglishTest.run if $PROGRAM_NAME == __FILE__
