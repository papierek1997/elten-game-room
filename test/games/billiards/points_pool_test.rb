require_relative '../../support/billiards_rules'
require_relative '../../../lib/billiards/points_pool'

module BilliardsPointsPoolTest
  extend GameRoomTest::Assertions
  F = BilliardsRulesFixture
  B = GameRoomBilliards
  R = B::Rules

  def self.state(id = 'straight', point_target: 100, race_to: 1)
    value = F.state('eight', race_to: race_to)
    value[:options].merge!('discipline'=>id, 'point_target'=>point_target)
    R.setup(value)
    R.choose(value, 'pocket_2') if id == 'one_pocket'
    value
  end
  def self.normal(value)
    value[:breaking], value[:hand] = false, nil
    value
  end
  def self.apply(value, result, call: 1, pocket: 0, mode: 0, rails: [])
    before = Marshal.load(Marshal.dump(value))
    value[:balls] = result.balls.map(&:dup)
    data = {'call'=>call, 'pocket'=>pocket, 'mode'=>mode, 'rails'=>rails}
    R.resolve_shot(value, before, result, data)
    value
  end
  def self.bank_result(value, id: 1, pocket: 0, rails: [:top], extra: [])
    result = F.result(value, first: id, pots: [[id, pocket]])
    result.events = [result.events.first] + rails.each_with_index.map do |rail, i|
      {kind: :rail, a: id, rail: rail, t: 0.15 + i * 0.01, x: 1.0, y: 1.24}
    end + extra + [result.events.last]
    result
  end
  def self.leave(value, ids)
    value[:balls].each { |b| b.status = :potted unless ids.include?(b.id) || b.id == 0 }
    value
  end
  def self.ball(value, id); value[:balls].find { |b| b.id == id }; end
  def self.location(value, id, x, y)
    target = ball(value, id)
    target.x, target.y = x, y
  end

  def self.run
    straight_scoring_and_fouls
    straight_reracks
    one_pocket_scoring_and_debts
    kitchen_fouls
    bank_scoring_and_chronology
    rematches_and_stalemates
    puts 'Point pool: straight14.1 breaks/scoring/three-fouls/rerack exceptions, OnePocket pocket ownership/debts/simultaneous wins, BankPool ordered declared banks/kisses/kicks/debts/breaks, stable IDs and deterministic transitions passed.'
  end

  def self.straight_scoring_and_fouls
    value = state
    assert_equal((0..15).to_a, value[:balls].map(&:id))
    assert_equal(false, R.valid_declaration?(value, {'call'=>0, 'pocket'=>0, 'mode'=>0}))
    assert(B::StraightPool.declaration?(value, {'call'=>1, 'pocket'=>0, 'mode'=>0}))
    apply(value, F.result(value, rails: [0, 1, 2]), mode: 1, call: 0)
    assert_equal([0, 0], value[:scores], 'The straight break was tested against a four-ball spread')
    assert_equal(1, value[:turn])
    value = state
    value[:fouls][0] = 2
    apply(value, F.result(value, rails: [1, 2]), call: 0, mode: 1)
    assert_equal([-2, 0], value[:scores])
    assert_equal([2, 0], value[:fouls], 'Breaking fouls counted as standard fouls')
    assert_equal(%w[accept rack_other], value[:choices])
    R.choose(value, 'rack_other')
    assert_equal(0, value[:turn])
    assert_equal([-2, 0], value[:scores], 'A repeat break reset the score')
    assert(value[:breaking])
    apply(value, F.result(value, pots: [[1, 0], [2, 1]]), call: 1)
    assert_equal([0, 0], value[:scores], 'Additional balls on a called shot did not score')
    assert_equal([0, 0], value[:fouls])
    apply(value, F.result(value, first: 3, pots: [[3, 1]]), call: 3, pocket: 0)
    assert_equal([0, 0], value[:scores])
    assert(ball(value, 3).on_table?, 'An uncalled pot was not spotted')
    assert_equal(1, value[:turn])
    value = normal(state)
    3.times do |index|
      value[:turn] = 0
      apply(value, F.result(value, first: 1), call: 0, mode: 1)
      assert_equal(:two_fouls, value[:ruling][:notice]) if index == 1
    end
    assert_equal([-18, 0], value[:scores], 'Three standard fouls must cost1+1+16')
    assert_equal([0, 0], value[:fouls])
    assert_equal(0, value[:turn])
    assert(value[:breaking])
    assert_equal(:kitchen, value[:hand])
    assert_equal(15, B::StraightPool.targets(value).length)
    value = normal(state(point_target: 2, race_to: 2))
    apply(value, F.result(value, pots: [[1, 0], [2, 1]]), call: 1)
    assert_equal(:rack_end, value[:phase])
    assert_equal([2, 0], value[:scores])
    assert_equal([1, 0], value[:racks])
  end

  def self.straight_reracks
    # With one loose break ball, the fourteen scored balls occupy every
    # triangle position except the apex, without moving either live ball.
    value = leave(normal(state), [1, 15])
    location(value, 0, 0.4, 0.4)
    location(value, 15, 1.4, 0.8)
    before_cue, before_object = ball(value, 0).dup, ball(value, 15).dup
    apply(value, F.result(value, pots: [[1, 0]]))
    assert_equal(15, B::StraightPool.targets(value).length)
    assert_equal([before_cue.x, before_cue.y], [ball(value, 0).x, ball(value, 0).y])
    assert_equal([before_object.x, before_object.y], [ball(value, 15).x, ball(value, 15).y])
    foot = R.table(value[:options]).width * 0.75
    assert(value[:balls].none? { |b| b.id != 0 && (b.x - foot).abs < 1e-6 && (b.y - 0.635).abs < 1e-6 }, 'Fourteen-ball rerack filled the apex')
    assert_equal((0..15).to_a, value[:balls].map(&:id), 'A rerack changed physical IDs')

    # Only object interferes; a cue on the head spot forces center spotting.
    value = leave(normal(state), [1, 15])
    location(value, 0, 0.635, 0.635)
    location(value, 15, 2.0, 0.635)
    apply(value, F.result(value, pots: [[1, 0]]))
    assert_equal([1.27, 0.635], [ball(value, 15).x, ball(value, 15).y])
    assert_equal(nil, value[:hand])

    # Both balls interfere, giving a full rack and kitchen ball in hand.
    value = leave(normal(state), [1, 15])
    location(value, 0, 2.0, 0.6)
    location(value, 15, 2.05, 0.66)
    apply(value, F.result(value, pots: [[1, 0]]))
    assert_equal(:kitchen, value[:hand])
    assert_equal(15, B::StraightPool.targets(value).length)
    assert(value[:balls].any? { |b| b.id != 0 && (b.x - foot).abs < 1e-6 })
    assert_equal(false, value[:breaking], 'A continuous rerack acquired opening-break restrictions')

    # Cue only: break ball below the head string gives kitchen hand; above
    # it gives the head spot (or center if occupied).
    [[1.3, 0.8, :kitchen, nil], [0.4, 0.8, nil, 0.635], [0.635 - 0.01, 0.635, nil, 1.27]].each do |x, y, hand, cue_x|
      value = leave(normal(state), [1, 15])
      location(value, 0, 2.0, 0.635)
      location(value, 15, x, y)
      apply(value, F.result(value, pots: [[1, 0]]))
      assert_equal(hand, value[:hand])
      assert_equal(cue_x, ball(value, 0).x) if cue_x
    end
    value = leave(normal(state), [1, 15])
    location(value, 0, 0.4, 0.4)
    apply(value, F.result(value, pots: [[1, 0], [15, 1]]))
    assert_equal(15, B::StraightPool.targets(value).length)
    assert(value[:balls].any? { |b| b.id != 0 && (b.x - foot).abs < 1e-6 }, 'Pocketing the fifteenth ball did not produce a full rack')
  end

  def self.one_pocket_scoring_and_debts
    value = state('one_pocket')
    assert_equal([2, 5], value[:point_pockets])
    assert_equal([], value[:choices])
    # A normal one-pocket break requires a contact/rail, not four spread balls.
    apply(value, F.result(value, rails: [1]), call: 0)
    assert_equal(nil, value[:ruling][:foul])
    value = normal(state('one_pocket'))
    apply(value, F.result(value, pots: [[1, 2], [2, 5], [3, 1]]), call: 0)
    assert_equal([1, 1], value[:scores])
    assert_equal(0, value[:turn])
    assert_equal([3], value[:point_pending], 'Non-scoring pot was spotted before the inning ended')
    assert_equal(false, ball(value, 3).on_table?)
    apply(value, F.result(value, first: 4, rails: [4]), call: 0)
    assert_equal([], value[:point_pending])
    assert(ball(value, 3).on_table?)

    assert_equal(1, value[:turn])
    # Standard foul returns a previously scored physical ball, leaving cue
    # position unchanged if the cue did not scratch.
    value[:turn] = 0
    apply(value, F.result(value, first: 4), call: 0)
    assert_equal([0, 1], value[:scores])
    assert(ball(value, 1).on_table?)
    assert_equal(nil, value[:hand])
    value[:turn] = 0
    apply(value, F.result(value, pots: [[0, 0], [5, 5]]), call: 0)
    assert_equal([-1, 1], value[:scores], 'Opponent scored on a scratch-only foul')
    assert_equal([1, 0], value[:point_owed])
    assert(ball(value, 5).on_table?)
    assert_equal(:kitchen, value[:hand])
    value[:turn], value[:hand] = 0, nil
    apply(value, F.result(value, pots: [[6, 2]]), call: 0)
    assert_equal([0, 1], value[:scores])
    assert_equal([0, 0], value[:point_owed])
    assert_equal([6], value[:point_pending], 'An owed ball was retained as a scored marker')
    assert_equal(0, value[:turn], 'Repaying a debt incorrectly ended the inning')

    # Scratch plus another foul does not invoke the scratch-only exception.
    value = normal(state('one_pocket'))
    result = F.result(value, pots: [[0, 0], [2, 5]])
    ball_in_result = result.balls.find { |b| b.id == 3 }
    ball_in_result.status = :off
    result.events << {kind: :off, a: 3, t: 0.4}
    apply(value, result, call: 0)
    assert_equal([-1, 1], value[:scores])
    assert_equal(false, ball(value, 2).on_table?)
    assert(ball(value, 3).on_table?)

    # The scratch-only exemption is for a pocketed cue, not a cue driven off.
    value = normal(state('one_pocket'))
    result = F.result(value, pots: [[2, 5]])
    result.balls.first.status = :off
    result.events << {kind: :off, a: 0, t: 0.4}
    apply(value, result, call: 0)
    assert_equal([-1, 1], value[:scores], 'Cue-off-table incorrectly invoked the scratch-only exception')

    value = normal(state('one_pocket'))
    value[:scores] = [7, 7] # possible after a carried-score stalemate
    apply(value, F.result(value, pots: [[1, 5], [2, 2]]), call: 0)
    assert_equal(0, value[:winner], 'Chronology overrode the simultaneous-win shooter priority')
    value = normal(state('one_pocket'))
    value[:fouls][0] = 2
    apply(value, F.result(value, first: 1), call: 0)
    assert_equal(1, value[:winner])
    # If the table is cleared below eight, queued balls return immediately.
    value = leave(normal(state('one_pocket')), [1, 2])
    apply(value, F.result(value, pots: [[1, 2], [2, 1]]), call: 0)
    assert_equal(0, value[:turn])
    assert(ball(value, 2).on_table?)
    assert_equal([], value[:point_pending])
  end

  def self.bank_scoring_and_chronology
    value = normal(state('bank_short'))
    assert_equal((0..9).to_a, value[:balls].map(&:id))
    assert(B::BankPool.declaration?(value, {'call'=>1, 'pocket'=>0, 'mode'=>0, 'rails'=>[2]}))
    assert_equal(false, B::BankPool.declaration?(value, {'call'=>1, 'pocket'=>0, 'mode'=>0, 'rails'=>[]}))
    assert_equal(false, B::BankPool.declaration?(value, {'call'=>1, 'pocket'=>0, 'mode'=>0, 'rails'=>Array.new(13, 2)}))
    result = bank_result(value)
    apply(value, result, rails: [2])
    assert_equal([1, 0], value[:scores])
    assert_equal(0, value[:turn])
    # Rail order, second cue hit, combinations, kisses and pre-contact kicks
    # all refuse scoring while remaining ordinary non-foul missed banks.
    [
      {rails: [:top, :left], declared: [0, 2]},
      {extra: [{kind: :ball, a: 0, b: 1, t: 0.2}]},
      {extra: [{kind: :ball, a: 2, b: 1, t: 0.2}]},
      {extra: [{kind: :ball, a: 0, b: 2, t: 0.05}]},
      {extra: [{kind: :rail, a: 0, rail: :left, t: 0.05}]},
      {extra: [{kind: :rail, a: 1, rail: :jaw, x: 0.04, y: 0.04, t: 0.12}]},
      {extra: [{kind: :rail, a: 1, rail: :jaw, x: 2.5, y: 1.26, t: 0.2}]}
    ].each do |fixture|
      value = normal(state('bank_short'))
      result = bank_result(value, rails: fixture.fetch(:rails, [:top]), extra: fixture.fetch(:extra, []))
      apply(value, result, rails: fixture.fetch(:declared, [2]))
      assert_equal([0, 0], value[:scores], "Invalid bank scored: #{fixture.inspect}")
      assert(ball(value, 1).on_table?)
      assert_equal(1, value[:turn])
    end
    # A declared second cushion after the pocket is not a bank.
    value = normal(state('bank_short'))
    result = bank_result(value)
    result.events << {kind: :rail, a: 1, rail: :left, t: 0.4}
    apply(value, result, rails: [2, 0])
    assert_equal([0, 0], value[:scores])
    # Contacts indistinguishable in time favor the called-ball-first rule.
    value = normal(state('bank_short'))
    result = bank_result(value, extra: [{kind: :rail, a: 0, rail: :left, t: 0.1}])
    apply(value, result, rails: [2])
    assert_equal([1, 0], value[:scores])
    # Destination jaw cannot count as a bank or invalidate a genuine bank.
    value = normal(state('bank_short'))
    result = bank_result(value, extra: [{kind: :rail, a: 1, rail: :jaw, x: 0.04, y: 0.04, t: 0.25}])
    apply(value, result, rails: [2])
    assert_equal([1, 0], value[:scores])
    value = normal(state('bank_short'))
    result = bank_result(value, rails: [], extra: [{kind: :rail, a: 1, rail: :jaw, x: 0.04, y: 0.04, t: 0.25}])
    apply(value, result, rails: [2])
    assert_equal([0, 0], value[:scores])

    value = state('bank_short')
    apply(value, F.result(value, rails: [1, 2, 3]), call: 0)
    assert_equal(%w[accept rack_other], value[:choices])
    assert_equal([0, 0], value[:scores], 'An illegal spread itself cost a point')
    R.choose(value, 'rack_other')
    apply(value, F.result(value, pots: [[1, 0]]), call: 0)
    assert_equal([0, 0], value[:scores], 'A break pot scored as a bank')
    assert_equal(0, value[:turn])
    assert_equal([1], value[:point_pending])
    value = normal(state('bank_full'))
    apply(value, F.result(value, pots: [[0, 0]]), call: 0)
    assert_equal([-1, 0], value[:scores])
    assert_equal([1, 0], value[:point_owed])
    value[:turn], value[:hand] = 0, nil
    apply(value, bank_result(value), rails: [2])
    assert_equal([0, 0], value[:scores])
    assert_equal([0, 0], value[:point_owed])
    value = normal(state('bank_short'))
    value[:scores][0] = 4
    apply(value, bank_result(value), rails: [2])
    assert_equal(0, value[:winner])
    value = normal(state('bank_full'))
    value[:scores][0] = 4
    apply(value, bank_result(value), rails: [2])
    assert_equal(:playing, value[:phase], 'Full-rack bank pool used the short-rack goal')
    value[:scores][0] = 7
    apply(value, bank_result(value, id: 2), call: 2, rails: [2])
    assert_equal(0, value[:winner])
  end

  def self.kitchen_fouls
    %w[straight one_pocket bank_short].each do |id|
      value = normal(state(id))
      value[:hand] = :kitchen
      location(value, 1, 0.4, 0.8)
      result = F.result(value, rails: [1])
      apply(value, result, call: 0, mode: id == 'one_pocket' ? 0 : 1)
      assert_equal(:head_string_hand, value[:ruling][:foul])
      assert_equal(:kitchen, value[:hand], "#{id}: failure to leave kitchen did not give kitchen hand")

      value = normal(state(id))
      value[:hand] = :kitchen
      location(value, 1, 0.4, 0.8)
      result = F.result(value, rails: [1])
      result.events.unshift(kind: :crossing, a: 0, line: :head, direction: :right, t: 0.05)
      apply(value, result, call: 0, mode: id == 'one_pocket' ? 0 : 1)
      assert_equal(nil, value[:ruling][:foul], "#{id}: legal head-string return was refused")

      value = normal(state(id))
      value[:hand] = :kitchen
      location(value, 1, 0.4, 0.8)
      result = F.result(value, rails: [1])
      result.events << {kind: :crossing, a: 0, line: :head, direction: :right, t: 0.4}
      apply(value, result, call: 0, mode: id == 'one_pocket' ? 0 : 1)
      assert_equal(:head_string, value[:ruling][:foul], "#{id}: a late crossing authorized an earlier contact")
      assert_equal(nil, value[:hand], "#{id}: first-paragraph head-string foul incorrectly granted hand")
    end
  end

  def self.rematches_and_stalemates
    %w[straight one_pocket bank_short bank_full].each do |id|
      value = normal(state(id, race_to: 2))
      value[:scores], value[:point_owed], value[:point_scored] = [4, -1], [0, 1], [[1, 2, 3, 4], []]
      value[:offer_turn], value[:turn], value[:decision], value[:choices] = 0, 1, :stalemate, %w[agree decline]
      R.choose(value, 'agree')
      assert_equal(%w[rack_self rack_other], value[:choices])
      R.choose(value, 'rack_other')
      assert_equal([4, -1], value[:scores], "Stalemate reset #{id} points")
      assert_equal([0, 1], value[:point_owed], "Stalemate reset #{id} owed balls")
      assert_equal([[], []], value[:point_scored])
      assert_equal(0, value[:breaker])
      R.choose(value, 'pocket_5') if id == 'one_pocket'
      assert_equal([5, 2], value[:point_pockets]) if id == 'one_pocket'
      R.finish_rack(value, 0)
      R.choose(value, 'next')
      assert_equal([0, 0], value[:scores], "New #{id} rack kept old frame points")
      assert_equal([0, 0], value[:point_owed])
      assert_equal(1, value[:breaker])
    end
    # Exact copied inputs give identical outcomes without modifying the
    # accepted pre-shot ledger or retaining results across calls.
    value = normal(state('one_pocket'))
    value[:point_scored][0] << 7
    value[:scores][0] = 1
    ball(value, 7).status = :potted
    result = F.result(value, first: 1)
    old = Marshal.dump(value)
    first, second = Marshal.load(old), Marshal.load(old)
    before_first = first.merge(balls: first[:balls].map(&:dup), scores: first[:scores].dup, fouls: first[:fouls].dup)
    first[:balls] = result.balls.map(&:dup)
    R.resolve_shot(first, before_first, result, {'call'=>0, 'pocket'=>0, 'mode'=>0, 'rails'=>[]})
    apply(second, result, call: 0)
    assert_equal(Marshal.dump(second), Marshal.dump(first))
    assert_equal([[7], []], before_first[:point_scored], 'Reducer changed the pre-shot ledger')
    assert_equal(old, Marshal.dump(value))
  end
end
BilliardsPointsPoolTest.run if $PROGRAM_NAME == __FILE__
