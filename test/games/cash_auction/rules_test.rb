require_relative '../../support/assertions'
require_relative '../../../lib/cash_auction/rules'

module CashAuctionRulesTest
  extend GameRoomTest::Assertions
  R = GameRoomCashAuction::Rules
  PLAYERS = %w[Alice Bob Carol Dan].freeze
  module_function

  def state(options = {}); R.initial(PLAYERS, options); end
  def wealth(model); model[:cash].sum + model[:pot]; end
  def draw(model, now: model[:round] * 20, chest: false)
    assert(R.draw!(model, category: 'history', chest: chest, now: now))
  end
  def award(model)
    assert(R.award!(model, now: model[:auction_deadline]))
  end
  def question(model)
    assert(R.start_question!(model, {'id'=>'question-1', 'question'=>'Which?', 'answers'=>%w[A B C D], 'correct'=>0}))
  end
  def refused(model)
    before = Marshal.dump(model)
    assert_equal(false, yield, 'Invalid transition was accepted')
    assert_equal(before, Marshal.dump(model), 'Refused transition changed state')
  end

  def run
    setup_and_owned_values
    bidding_and_deadline
    pass_penalties
    ante_failure_and_no_bid
    carryover_and_answer_authority
    all_in_and_permanent_elimination
    regular_limit_and_tiebreaks
    chests_before_result
    chest_rewards_and_refusals
    puts 'Cash auction pure rules: totals/ante/pot conservation, out-of-turn bidding, deadlines, every-third-pass fines, carryover, all-in elimination, eight rounds/tiebreaks and chest settlement passed.'
  end

  def setup_and_owned_values
    players = PLAYERS.map(&:dup)
    options = {'starting_points'=>500, 'ante'=>5, 'extra'=>{'names'=>['original']}}
    model = R.initial(players, options)
    players[0].replace('Changed')
    options['extra']['names'][0].replace('Changed')
    assert_equal('Alice', model[:players][0])
    assert_equal('original', model[:options]['extra']['names'][0])
    assert_equal([500] * 4, model[:cash])
    assert_equal([false] * 4, model[:eliminated])
    assert_equal([0] * 4, model[:pass_counts])
    assert_equal([0] * 4, model[:chests])
    assert_equal([0, 0, :drawing, 0, 0, nil, 0, 0, nil, nil, false], model.values_at(
      :round, :completed_rounds, :phase, :pot, :highest, :leader, :auction_deadline, :bid_revision, :question, :winner, :draw))
    assert_equal([0, 1, 2, 3], R.active_seats(model))
    assert(!R.finished?(model))
    assert_raises(ArgumentError) { R.initial([], {}) }
    assert_raises(ArgumentError) { R.initial(PLAYERS, nil) }
    assert_raises(ArgumentError) { state('count_interval'=>0) }
    assert_raises(ArgumentError) { state('ante'=>1.0) }
    refused(model) { R.draw!(model, category: {bad: -> {}}, chest: false, now: 1) }
    refused(model) { R.draw!(model, category: 'history', chest: false, now: 1.5) }
    refused(model) { R.draw!(model, category: 'history', chest: nil, now: 1) }
    model[:phase] = :spinning
    draw(model, now: 100)
    assert_equal([495] * 4, model[:cash])
    assert_equal(20, model[:pot])
    assert_equal(106, model[:auction_deadline])
    refused(model) { R.draw!(model, category: 'science', chest: true, now: 101) }
  end

  def bidding_and_deadline
    model = state
    draw(model, now: 100)
    assert_equal(40, model[:pot])
    assert_equal([0] * 4, model[:contributions], 'Ante leaked into bid totals')
    assert(R.bid!(model, 2, 100, now: 101, revision: 7), 'A non-first seat could not bid')
    assert_equal([2, 100, 107, 7], model.values_at(:leader, :highest, :auction_deadline, :bid_revision))
    assert_equal(890, model[:cash][2])
    refused(model) { R.bid!(model, 1, 100, now: 102, revision: 8) }
    refused(model) { R.bid!(model, 1, 1000, now: 102, revision: 8) }
    refused(model) { R.bid!(model, 1, 101.0, now: 102, revision: 8) }
    refused(model) { R.bid!(model, -1, 101, now: 102, revision: 8) }
    refused(model) { R.bid!(model, '1', 101, now: 102, revision: 8) }
    refused(model) { R.bid!(model, 1, 101, now: 102, revision: -1) }
    refused(model) { R.pass!(model, 2) }
    assert(R.bid!(model, 1, 150, now: 106, revision: 8))
    assert_equal(112, model[:auction_deadline], 'A new bid did not restart all three counts')
    refused(model) { R.award!(model, now: 107) }
    assert(R.bid!(model, 2, 200, now: 111, revision: 9))
    assert_equal(790, model[:cash][2], 'A repeat bid paid its full total instead of the difference')
    assert_equal(390, model[:pot])
    assert_equal(4000, wealth(model))
    assert(R.pass!(model, 0))
    refused(model) { R.bid!(model, 0, 250, now: 112, revision: 10) }
    refused(model) { R.bid!(model, 3, 250, now: 117, revision: 10) }
    refused(model) { R.award!(model, now: '117') }
    award(model)
    assert_equal(:question_pending, model[:phase])
    refused(model) { R.award!(model, now: 118) }
    refused(model) { R.bid!(model, 3, 250, now: 118, revision: 10) }
  end

  def pass_penalties
    model = state
    6.times do |index|
      draw(model)
      assert(R.pass!(model, 0))
      refused(model) { R.pass!(model, 0) }
      award(model)
      assert_equal(4000, wealth(model))
      penalty = ((index + 1) / 3) * 200
      assert_equal(1000 - (index + 1) * 10 - penalty, model[:cash][0])
    end
    assert_equal(6, model[:pass_counts][0], 'Pass counts reset between rounds')
    assert_equal(640, model[:pot])
    model = state('starting_points'=>35)
    3.times do
      draw(model)
      assert(R.pass!(model, 0))
      award(model)
    end
    assert_equal(0, model[:cash][0], 'An unaffordable pass fine did not stop at zero')
    assert_equal(false, model[:eliminated][0], 'A pass fine immediately eliminated a seat')
    assert_equal(140, wealth(model))
    draw(model)
    assert_equal([true] * 4, model[:eliminated], 'Next ante did not eliminate seats below the full ante')
    assert_equal(140, wealth(model), 'Ante failure confiscated remaining cash')
    assert_equal([:finished, nil, true], model.values_at(:phase, :winner, :draw))
  end

  def ante_failure_and_no_bid
    model = state
    model[:cash][0] = 5
    total = wealth(model)
    draw(model)
    assert_equal(5, model[:cash][0])
    assert_equal([true, false, false, false], model[:eliminated])
    assert_equal(30, model[:pot])
    refused(model) { R.bid!(model, 0, 1, now: 1, revision: 1) }
    refused(model) { R.pass!(model, 0) }
    award(model)
    assert_equal([1, :drawing], model.values_at(:completed_rounds, :phase))
    assert_equal(total, wealth(model))
    model = state('starting_points'=>10)
    draw(model)
    assert_equal([0] * 4, model[:cash])
    award(model)
    draw(model)
    assert(R.finished?(model))
    assert_equal(true, model[:draw])
    assert_equal(nil, model[:winner])
    assert_equal(40, model[:pot])
    model = state
    model[:cash] = [5, 5, 5, 10]
    draw(model)
    assert_equal([:finished, 'Dan', nil], model.values_at(:phase, :winner, :leader), 'Sole survivor was left to bid against nobody')
    assert_equal(25, wealth(model))
    refused(model) { R.bid!(model, 3, 1, now: 1, revision: 1) }
    model = state
    model[:cash], model[:chests] = [5, 5, 5, 100], [1, 0, 0, 0]
    draw(model)
    assert_equal([:opening_chests, nil], model.values_at(:phase, :winner), 'Ante settlement skipped an eliminated owner\'s chest')
    assert(R.open_chest!(model, 0, 10_000, now: 1))
    assert_equal([:finished, 'Dan'], model.values_at(:phase, :winner))
    assert_equal(true, model[:eliminated][0], 'Chest reward revived an ante-eliminated seat')
  end

  def carryover_and_answer_authority
    model = state
    draw(model)
    assert(R.bid!(model, 0, 100, now: 1, revision: 1))
    award(model)
    refused(model) { R.start_question!(model, nil) }
    refused(model) { R.start_question!(model, {}) }
    refused(model) { R.start_question!(model, {'bad'=>-> {}}) }
    submitted = {'id'=>'one', 'answers'=>%w[A B C D], 'correct'=>0}
    assert(R.start_question!(model, submitted))
    submitted['answers'][0].replace('Changed')
    assert_equal('A', model[:question]['answers'][0], 'Question aliases its caller')
    refused(model) { R.answer!(model, 1, true, now: 8) }
    refused(model) { R.answer!(model, 0, 1, now: 8) }
    refused(model) { R.answer!(model, 0, false, now: -1) }
    assert(R.answer!(model, 0, false, now: 8))
    assert_equal([140, 1, :drawing], model.values_at(:pot, :completed_rounds, :phase))
    assert_equal(false, model[:eliminated][0])
    refused(model) { R.answer!(model, 0, true, now: 9) }
    draw(model)
    assert_equal(180, model[:pot])
    assert(R.bid!(model, 1, 200, now: 21, revision: 5))
    award(model)
    question(model)
    assert(R.answer!(model, 1, true, now: 28))
    assert_equal(1160, model[:cash][1])
    assert_equal(0, model[:pot])
    assert_equal(4000, wealth(model))
  end

  def all_in_and_permanent_elimination
    model = state
    draw(model)
    assert(R.bid!(model, 0, 100, now: 1, revision: 1))
    assert(R.bid!(model, 0, 990, now: 2, revision: 2))
    assert_equal([0, 990, 1030], [model[:cash][0], model[:contributions][0], model[:pot]])
    award(model)
    question(model)
    assert(R.answer!(model, 0, false, now: 9))
    assert_equal(true, model[:eliminated][0])
    assert_equal([1, 2, 3], R.active_seats(model))
    draw(model)
    assert_equal(1060, model[:pot], 'Eliminated all-in seat paid another ante')
    refused(model) { R.bid!(model, 0, 1, now: 21, revision: 5) }
    assert_equal(4000, wealth(model))
  end

  def regular_limit_and_tiebreaks
    model = state
    8.times do
      draw(model)
      award(model)
    end
    assert_equal([8, :drawing], model.values_at(:completed_rounds, :phase), 'An eight-round tie did not enter an extra round')
    assert_equal([0, 1, 2, 3], R.active_seats(model), 'Tiebreak narrowed the roster')
    draw(model)
    assert_equal(9, model[:round])
    assert(R.bid!(model, 0, 1, now: 161, revision: 20))
    award(model)
    question(model)
    assert(R.answer!(model, 0, true, now: 168))
    assert_equal([:finished, 'Alice', false, 9], model.values_at(:phase, :winner, :draw, :completed_rounds))
    assert_equal(4000, wealth(model))
    refused(model) { R.draw!(model, category: 'history', chest: false, now: 180) }
    model = state
    draw(model)
    assert(R.bid!(model, 0, 1, now: 1, revision: 1))
    award(model)
    question(model)
    assert(R.answer!(model, 0, true, now: 8))
    7.times { draw(model); award(model) }
    assert_equal([:finished, 'Alice', 8], model.values_at(:phase, :winner, :completed_rounds), 'Unique leader did not finish at the regular limit')
    model = state('rounds'=>1)
    model[:cash] = [100, 100, 50, 10]
    draw(model)
    award(model)
    assert_equal(:drawing, model[:phase])
    draw(model)
    assert_equal(false, model[:eliminated][2], 'A lower-balance active seat was excluded from the tiebreak')
    assert_equal(30, model[:cash][2])
  end

  def chests_before_result
    model = state('rounds'=>1)
    draw(model, chest: true)
    assert(R.bid!(model, 0, 100, now: 1, revision: 1))
    award(model)
    assert_equal([1, :opening_chests, nil], model.values_at(:completed_rounds, :phase, :winner))
    assert_equal([1, 0, 0, 0], model[:chests])
    assert_equal(140, model[:pot], 'Chest auction consumed the carried pot')
    refused(model) { R.start_question!(model, {'id'=>'no-question'}) }
    assert(R.open_chest!(model, 0, 2500, now: 8))
    assert_equal([:finished, 'Alice', 3390], [model[:phase], model[:winner], model[:cash][0]])
    assert_equal(6500, wealth(model))
    model = state('rounds'=>1)
    draw(model, chest: true)
    assert(R.bid!(model, 0, 100, now: 1, revision: 1))
    award(model)
    assert(R.open_chest!(model, 0, 100, now: 8))
    assert_equal(:drawing, model[:phase], 'Chest settlement did not precede tiebreak selection')
    assert_equal([0] * 4, model[:chests])
    model = state('rounds'=>1)
    model.merge!(phase: :opening_chests, cash: [2000, 1000, 500, 500], chests: [1, 1, 0, 0], completed_rounds: 1, round: 1)
    assert(R.open_chest!(model, 0, 100, now: 1))
    assert_equal([:opening_chests, nil], model.values_at(:phase, :winner), 'Result announced before every chest was open')
    assert(R.open_chest!(model, 1, -100, now: 2))
    assert_equal('Alice', model[:winner])
    model = state('rounds'=>1)
    model.merge!(phase: :opening_chests, cash: [2000, 1000, 0, 0], eliminated: [false, false, true, true], chests: [1, 0, 0, 0])
    assert(R.open_chest!(model, 0, 'bankrupt', now: 3))
    assert_equal([:finished, 'Bob'], model.values_at(:phase, :winner), 'Bankrupt chest did not change the winner')
    assert_equal([true, false, true, true], model[:eliminated])
  end

  def chest_rewards_and_refusals
    R::CHEST_REWARDS.each do |reward|
      model = state('rounds'=>1)
      model.merge!(phase: :opening_chests, chests: [1, 0, 0, 0])
      expected = reward == 'bankrupt' ? 0 : [1000 + reward, 0].max
      assert(R.open_chest!(model, 0, reward, now: 1))
      assert_equal(expected, model[:cash][0])
      assert_equal(3000 + expected, wealth(model), 'Chest reward/penalty did not conserve the expected external delta')
      assert_equal(reward == 'bankrupt', model[:eliminated][0])
    end
    model = state('rounds'=>1)
    refused(model) { R.open_chest!(model, 0, 100, now: 1) }
    model.merge!(phase: :opening_chests, chests: [1, 0, 0, 0])
    refused(model) { R.open_chest!(model, 1, 100, now: 1) }
    refused(model) { R.open_chest!(model, -1, 100, now: 1) }
    refused(model) { R.open_chest!(model, 0, 100.0, now: 1) }
    refused(model) { R.open_chest!(model, 0, '100', now: 1) }
    refused(model) { R.open_chest!(model, 0, :bankrupt, now: 1) }
    refused(model) { R.open_chest!(model, 0, 100, now: nil) }
    model[:eliminated][0] = true
    assert(R.open_chest!(model, 0, 10_000, now: 1), 'Eliminated seat could not open its owned chest')
    assert_equal(true, model[:eliminated][0], 'A reward revived a permanently eliminated seat')
    assert_equal(nil, model[:winner], 'Eliminated rich seat was declared winner')
    assert_equal(:drawing, model[:phase])
    refused(model) { R.finish_round!(model) }
  end
end
CashAuctionRulesTest.run if $PROGRAM_NAME == __FILE__
