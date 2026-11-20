require_relative '../../support/billiards_pyramid'

module BilliardsPyramidTest
  extend GameRoomTest::Assertions
  F = BilliardsPyramidFixture
  E = F::E
  R = F::B::Rules
  def self.contact(a = 0, b = 1, **values); F.event(:ball, a, {b: b}.merge(values)); end
  def self.rail(a = 1, name = :right, **values); F.event(:rail, a, {rail: name}.merge(values)); end
  def self.cross(a = 1); F.event(:crossing, a, line: :middle, direction: :left); end
  def self.pot(a); F.event(:pocket, a, pocket: 0); end

  def self.run
    layout_and_declaration
    legal_completion
    scoring_and_fouls
    penalty_and_rerack
    actual_dynamic_cue
    puts 'Free Pyramid: IPC2025 completion, dynamic cue, legal breaks, all-pot scoring, selected penalty, return/rerack, conservation and stable IDs passed.'
  end

  def self.layout_and_declaration
    state = F.state(breaking: true)
    assert_equal((0..15).to_a, state[:balls].map(&:id))
    t = R.table(state[:options])
    assert_equal([3.55, 1.775, 0.034], [t.width, t.height, t.radius])
    assert(E.declaration?(state, F.data))
    assert(!E.declaration?(state, F.data(1)), 'Break accepted an ivory cue')
    state[:breaking] = false
    assert(E.declaration?(state, F.data(9)), 'Ivory cue was refused in ordinary play')
    state[:balls][9].status = :potted
    assert(!E.declaration?(state, F.data(9)), 'Pocketed cue was accepted')
    assert(!E.declaration?(state, F.data.merge('mode'=>1)))
  end

  def self.legal_completion
    good = [
      [contact, pot(0)],
      [contact, rail, rail(1, :top)],
      [contact, cross, rail],
      [contact, rail, cross],
      [contact, rail(1, :right, x: 3.516), contact(1, 2, bx: 1.0, by: 0.4)],
      [contact, cross, contact(1, 2, bx: 3.516, by: 0.4)],
      [contact, rail(1, :right, x: 3.516), contact(1, 2, bx: 2.8, by: 0.4), rail(2, :top)],
      [contact, rail(1, :right, x: 3.516), contact(1, 2, bx: 2.8, by: 0.4), cross(2)]
    ]
    good.each do |events|
      state = F.state
      assert_equal(nil, E.foul(state, F.result(state, events), F.data), "Refused valid completion #{events}")
    end
    bad = [[], [contact], [contact, rail], [contact, rail, rail], [contact, cross], [rail, contact],
      [contact, rail(1, :right, x: 3.516), contact(1, 2, bx: 2.8, by: 0.4)]]
    bad.each do |events|
      state = F.state
      assert(E.foul(state, F.result(state, events), F.data), "Accepted incomplete stroke #{events}")
    end
    state = F.state(breaking: true)
    [[contact, pot(1)], [contact, rail(1), rail(2), rail(3)], [contact, rail(1), rail(2), cross(3)]].each do |events|
      assert_equal(nil, E.foul(state, F.result(state, events), F.data))
    end
    assert_equal(:break_spread, E.foul(state, F.result(state, [contact, rail(1), rail(2)]), F.data))
    assert_equal(:off_table, E.foul(state, F.result(state, [contact, pot(1), F.event(:off, 0)]), F.data))
  end

  def self.scoring_and_fouls
    state = F.state
    before, = F.apply(state, [contact(5, 1), pot(5), pot(1)], cue: 5)
    assert_equal([2, 0], state[:scores], 'Pocketed cue was not counted')
    assert_equal(0, state[:turn])
    assert(F.conserved?(state))
    assert_equal([[], []], before[:pyramid_scored], 'Reducer changed pre-shot ledger')
    assert(state[:balls].find { |b| b.id == E.cue_id(state) }.on_table?)
    state = F.state
    F.apply(state, [contact, rail, rail(1, :top)])
    assert_equal(1, state[:turn])
    state = F.state
    F.apply(state, [pot(1), pot(0)])
    assert_equal([0, 0], state[:scores])
    assert_equal(:pyramid_penalty, state[:decision])
    assert_equal(16, state[:choices].length)
    assert_equal(16, state[:balls].count(&:on_table?), 'Illegal pots were not respotted')
    assert(E.choose(state, 'pyramid_penalty_7'))
    assert_equal([0, 1], state[:scores], 'Foul deducted from offender instead of crediting opponent')
    assert_equal(:potted, state[:balls][7].status)
    assert(F.conserved?(state))
    assert(E.choose(state, 'pyramid_return'))
    assert_equal(0, state[:turn])
    assert_equal([], state[:choices])
  end

  def self.penalty_and_rerack
    state = F.state(breaking: true)
    F.apply(state, [contact, rail(1)])
    assert(E.choose(state, 'pyramid_penalty_0'))
    assert_equal(4, state[:choices].length)
    assert(E.choose(state, 'pyramid_rack_self'))
    assert_equal(1, state[:turn])
    assert_equal([0, 1], state[:scores])
    assert_equal(15, state[:balls].count(&:on_table?))
    assert_equal(true, state[:breaking])
    assert_equal(0, E.cue_id(state))
    assert_equal(:kitchen, state[:hand])
    assert(state[:balls][0].on_table?, 'Rerack did not restore required coloured cue')
    assert(!state[:pyramid_scored][1].include?(0), 'Shelf identity did not follow the colour exchange')
    assert(F.conserved?(state))
    table = R.table(state[:options])
    state[:balls].select(&:on_table?).combination(2).each do |a, b|
      assert(Math.hypot(a.x - b.x, a.y - b.y) >= table.radius * 2, 'Partial rerack overlaps balls')
    end
    state = F.state
    state[:scores] = [0, 7]
    state[:pyramid_scored] = [[], (9..15).to_a]
    state[:balls].each { |b| b.status = :potted if b.id >= 9 }
    F.apply(state, [])
    E.choose(state, 'pyramid_penalty_1')
    assert_equal(:finished, state[:phase])
    assert_equal(1, state[:winner], 'Eighth penalty point did not win immediately')
    assert(F.conserved?(state))
    state = F.state
    state[:scores], state[:pyramid_scored] = [7, 0], [(9..15).to_a, []]
    state[:balls].each { |b| b.status = :potted if b.id >= 9 }
    F.apply(state, [contact(3, 1), pot(3)], cue: 3)
    assert_equal(:finished, state[:phase])
    assert_equal(0, state[:winner])
    assert(F.conserved?(state))
  end

  def self.actual_dynamic_cue
    state = F.state
    state[:balls] = [F::B::Ball.new(id: 0, x: 0.3, y: 0.3), F::B::Ball.new(id: 5, x: 1.0, y: 0.8),
      F::B::Ball.new(id: 8, x: 1.5, y: 0.8)]
    result = F::B::Physics.simulate(R.table(state[:options]), state[:balls], F.data['shot'], cue_id: 5)
    assert_equal(5, result.events.first[:a])
    assert_equal(0.3, result.balls.first.x, 'Dynamic cue simulation moved physical ID0')
    assert_equal([0, 5, 8], result.balls.map(&:id), 'Dynamic cue reordered physical IDs')
    assert(result.events.any? { |event| event[:kind] == :ball && [event[:a], event[:b]].sort == [5, 8] })
  end
end
BilliardsPyramidTest.run if $PROGRAM_NAME == __FILE__
