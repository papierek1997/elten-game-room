require_relative '../../support/billiards_rules'

module BilliardsPoolRulesTest
  extend GameRoomTest::Assertions
  F = BilliardsRulesFixture
  R = GameRoomBilliards::Rules
  def self.run
    state = F.state
    F.apply(state, F.result(state, pots: [[1, 0]]), call: 0)
    assert_equal(nil, state[:groups], 'Break assigned a group')
    assert_equal(0, state[:turn])
    F.apply(state, F.result(state, first: 2, pots: [[2, 3]]), call: 2, pocket: 3)
    assert_equal([0, 1], state[:groups])
    F.apply(state, F.result(state, first: 3, pots: [[0, 1], [3, 0]]), call: 3)
    assert_equal(:scratch, state[:ruling][:foul])
    assert_equal(1, state[:turn])
    assert_equal(:any, state[:hand])
    assert(!state[:balls].find { |b| b.id == 3 }.on_table?, 'Ordinary ball returned after a scratch')
    preserved = Marshal.dump(state[:balls].drop(1))
    assert(R.placement?(state, 0, 0.5, 0.5))
    assert(!R.placement?(state, 3, 0.5, 0.5))
    assert_equal(preserved, Marshal.dump(state[:balls].drop(1)))
    early = F.state
    early[:breaking] = false
    F.apply(early, F.result(early, pots: [[8, 0]]), call: 1)
    assert_equal(1, early[:winner])
    win = F.state
    win[:breaking], win[:groups] = false, [0, 1]
    win[:balls].each { |b| b.status = :potted if R.group(b.id) == 0 }
    F.apply(win, F.result(win, first: 8, pots: [[8, 5]]), call: 8, pocket: 5)
    assert_equal(0, win[:winner])
    break_eight = F.state
    F.apply(break_eight, F.result(break_eight, pots: [[8, 0]]), call: 0)
    assert_equal(%w[accept rack_self], break_eight[:choices])
    assert(break_eight[:balls].find { |b| b.id == 8 }.on_table?)
    R.choose(break_eight, 'accept')
    assert_equal(false, break_eight[:breaking])
    illegal = F.state
    F.apply(illegal, F.result(illegal, rails: [1, 2, 3]), call: 0)
    assert_equal(%w[accept rack_self rack_other], illegal[:choices])
    R.choose(illegal, 'rack_other')
    assert_equal(0, illegal[:turn])
    assert(illegal[:breaking])

    nine = F.state('nine')
    F.apply(nine, F.result(nine, pots: [[9, 0]]), call: 0)
    assert_equal(0, nine[:winner], 'Legal nine-ball combination failed to win')
    nine = F.state('nine')
    F.apply(nine, F.result(nine, rails: [1, 2, 3, 4]), call: 0)
    assert(nine[:push_available])
    F.apply(nine, F.result(nine, first: nil, pots: [[9, 2]]), call: 0, mode: 2)
    assert_equal(%w[accept return], nine[:choices])
    assert(nine[:balls].find { |b| b.id == 9 }.on_table?)
    assert_equal(nil, nine[:winner])
    R.choose(nine, 'return')
    assert_equal(1, nine[:turn])
    assert(!nine[:push_available])
    three = F.state('nine')
    F.apply(three, F.result(three, rails: [1, 2, 3, 4], crossings: [1]), call: 0)
    assert_equal(:illegal_nine_break, three[:decision])
    R.choose(three, 'return')
    assert(three[:push_available])
    assert_equal(0, three[:turn])
    fouls = F.state('nine', race_to: 2)
    fouls[:breaking] = false
    2.times do
      F.apply(fouls, F.result(fouls, first: 2, rails: [2]), call: 0)
      F.apply(fouls, F.result(fouls, first: 1, rails: [1]), call: 0)
    end
    assert_equal([2, 0], fouls[:fouls])
    F.apply(fouls, F.result(fouls, first: 2, rails: [2]), call: 0)
    assert_equal([0, 1], fouls[:racks])
    assert_equal(:rack_end, fouls[:phase])
    R.choose(fouls, 'next')
    assert_equal([0, 0], fouls[:fouls])
    assert_equal(1, fouls[:breaker])
    assert_equal([0, 1], fouls[:racks])
    puts 'Pool rules: groups/calls, continuation, cue-only scratch, eight loss/win/spot, break choices, nine combinations, push-out, three-ball break, three fouls and match racks passed.'
  end
end
BilliardsPoolRulesTest.run if $PROGRAM_NAME == __FILE__
