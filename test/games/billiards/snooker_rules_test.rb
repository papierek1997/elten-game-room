require_relative '../../support/billiards_rules'

module BilliardsSnookerRulesTest
  extend GameRoomTest::Assertions
  F = BilliardsRulesFixture
  B = GameRoomBilliards
  R = B::Rules
  def self.run
    state = F.state('snooker')
    F.apply(state, F.result(state, pots: [[1, 0], [2, 0]]))
    assert_equal([2, 0], state[:scores])
    assert_equal(:colour, state[:on])
    F.apply(state, F.result(state, first: 21, pots: [[21, 5]]), call: 21)
    assert_equal([9, 0], state[:scores])
    assert_equal(9, state[:break_points])
    assert(state[:balls].find { |b| b.id == 21 }.on_table?)
    assert_equal(:red, state[:on])
    F.apply(state, F.result(state, first: 3, pots: [[0, 0]]), call: 3)
    assert_equal([9, 4], state[:scores])
    assert_equal(:d, state[:hand])
    assert_equal(:scratch, state[:ruling][:foul])
    assert_equal(%w[accept return], state[:choices])
    before = Marshal.dump(state[:balls].drop(1))
    R.choose(state, 'accept')
    assert(!R.placement?(state, 0, 1.0, 0.889))
    assert(R.placement?(state, 0, 0.55, 0.889))
    assert_equal(before, Marshal.dump(state[:balls].drop(1)), 'Scratch reracked snooker')

    last = F.state('snooker')
    last[:balls].each { |b| b.status = :potted if b.id.between?(2, 15) }
    F.apply(last, F.result(last, pots: [[1, 0]]))
    assert_equal(:colour, last[:on], 'No colour allowed after the last red')
    F.apply(last, F.result(last, first: 21, pots: [[21, 0]]), call: 21)
    assert_equal(16, last[:on])
    F.apply(last, F.result(last, first: 16, pots: [[16, 0]]), call: 16)
    assert_equal(17, last[:on])
    assert(!last[:balls].find { |b| b.id == 16 }.on_table?)
    F.apply(last, F.result(last, first: 17, pots: [[21, 0]]), call: 17)
    assert_equal(7, last[:ruling][:points])
    assert(last[:balls].find { |b| b.id == 21 }.on_table?)
    assert_equal(17, last[:on])

    tie = F.state('snooker')
    tie[:balls].each { |b| b.status = :potted unless [0, 21].include?(b.id) }
    tie[:on], tie[:scores] = 21, [0, 7]
    F.apply(tie, F.result(tie, first: 21, pots: [[21, 0]]), call: 21)
    assert_equal([7, 7], tie[:scores])
    assert_equal(:respotted_black, tie[:decision])
    assert_equal(:d, tie[:hand])
    R.choose(tie, 'accept')
    winner = tie[:turn]
    tie[:balls].first.status = :table
    F.apply(tie, F.result(tie, first: 21, pots: [[21, 0]]), call: 21)
    assert_equal(winner, tie[:winner])

    miss = F.state('snooker')
    miss[:breaking], miss[:hand] = false, nil
    miss[:balls].each { |b| b.status = :potted unless [0, 1, 21].include?(b.id) }
    miss[:balls].first.x, miss[:balls].first.y = 0.5, 0.5
    red = miss[:balls].find { |b| b.id == 1 }
    red.x, red.y = 1.0, 0.5
    original = Marshal.dump(miss[:balls])
    2.times do |i|
      F.apply(miss, F.result(miss, first: nil))
      assert(miss[:ruling][:miss])
      assert(miss[:choices].include?('restore'))
      R.choose(miss, 'restore')
      assert_equal(original, Marshal.dump(miss[:balls]))
      assert_equal(i + 1, miss[:miss_chain])
    end
    F.apply(miss, F.result(miss, first: nil))
    assert_equal(:third_miss, miss[:ruling][:foul])
    assert_equal(1, miss[:winner])
    assert_equal([0, 12], miss[:scores])

    t = B::Table.new(discipline: 'snooker')
    balls = [B::Ball.new(id: 0, x: 0.5, y: 0.5), B::Ball.new(id: 1, x: 1.5, y: 0.5), B::Ball.new(id: 21, x: 1.0, y: 0.5)]
    assert(B::Visibility.snookered?(t, balls, [1]))
    assert(!B::Visibility.direct?(t, balls, [1]))
    balls[2].y += 0.06
    assert(B::Visibility.snookered?(t, balls, [1]), 'A single visible edge incorrectly cleared a snooker')
    assert(B::Visibility.direct?(t, balls, [1]))
    balls[2].y += 0.04
    assert(!B::Visibility.snookered?(t, balls, [1]))
    # A red blocking another red is not an off-ball snooker.
    balls[2].id, balls[2].y = 2, 0.5
    assert(!B::Visibility.snookered?(t, balls, [1, 2]))
    free = F.state('snooker')
    free[:free_ball], free[:breaking], free[:hand] = true, false, nil
    F.apply(free, F.result(free, first: 21, pots: [[21, 0], [1, 0]]), call: 21, mode: 3)
    assert_equal([2, 0], free[:scores])
    assert(free[:balls].find { |b| b.id == 21 }.on_table?)
    assert_equal(:colour, free[:on])
    puts 'Snooker rules: red/colour breaks, last red, ordered clearance, penalties, cue-only D placement, colour spotting, respotted black, visibility/free ball, restored Miss sequence and frame award passed.'
  end
end
BilliardsSnookerRulesTest.run if $PROGRAM_NAME == __FILE__
