require_relative '../../support/cash_auction'

module CashAuctionRevisedRoundsTest
  extend GameRoomTest::Assertions
  F = CashAuctionFixture::Match
  module_function

  def match
    F.new(rules_version: 2, options: {'starting_points'=>1000, 'content_language_id'=>'en'})
  end

  def question_round(f, bidder: 'Alice')
    f.begin_round
    yield if block_given?
    f.bid(bidder, f.replay.state[:highest] + 1)
    f.close_auction
    f.reveal_question
    f.answer_correct(bidder)
  end

  def run
    inactive_rounds_and_reset
    strict_all_in
    question_limit_and_chests
    extra_question_after_tie
    puts 'Cash Auction revised rounds: consecutive inactivity, lost bids, strict all-in, eight questions and deferred chest results passed.'
  end

  def inactive_rounds_and_reset
    f = match
    2.times { question_round(f) { f.pass('Bob') } }
    assert_equal(2, f.replay.state[:pass_counts][1])
    question_round(f)
    assert_equal(770, f.replay.state[:cash][1], 'Silence without Pass did not incur the third-round fine')
    assert_equal(0, f.replay.state[:pass_counts][1])
    question_round(f) { f.bid('Bob', 1) }
    assert_equal(0, f.replay.state[:pass_counts][1], 'A losing bidder was treated as inactive')
    question_round(f) { f.bid('Bob', 1); f.bid('Carol', 2); f.pass('Bob') }
    assert_equal(0, f.replay.state[:pass_counts][1], 'Passing after a bid was treated as inactivity')
    2.times { question_round(f) }
    assert_equal(2, f.replay.state[:pass_counts][1], 'Inactivity did not restart after a lost bid')
    assert_equal(728, f.replay.state[:cash][1], 'A losing bidder paid an extra fine')
    assert_equal(4000, f.replay.state[:cash].sum + f.replay.state[:pot])
    assert_equal(f.replay, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
  end

  def strict_all_in
    f = match
    question_round(f) { f.bid('Bob', 400) }
    f.begin_round
    f.bid('Alice', 700)
    before = f.replay
    maximum = before.state[:cash][1]
    ['A', maximum.to_s].each do |amount|
      assert_equal(:invalid_bet, f.plan(f.bid_selection('Bob', amount), actor: 'Bob').first)
    end
    assert(f.game.legal_actions(before, 'Bob', context: f.context).none? { |action| action['action'] == 'submit' })
    f.append_raw(action: 'all_in', value: "2|#{maximum}", actor: 'Bob')
    assert_equal(before, f.replay, 'Native all-in below the leading bid changed the auction')
    g = match
    g.begin_round
    g.bid('Bob', 'A')
    assert_equal([:question_pending, 1, 990], g.replay.state.values_at(:phase, :leader, :highest))
    assert_equal(:invalid, g.plan(g.bid_selection('Alice', 'A'), actor: 'Alice').first)
    g.reveal_question(seed: g.question_seed_for_index(3))
    assert_equal(3, g.replay.state[:question][:correct_index], 'The pooled source lost the native answer permutation')
  end

  def question_limit_and_chests
    f = match
    2.times do |index|
      f.begin_round(chest: true)
      f.bid(index.zero? ? 'Alice' : 'Bob', 1)
      f.close_auction
      assert_equal([:drawing, 0], f.replay.state.values_at(:phase, :completed_rounds))
    end
    8.times { question_round(f) }
    assert_equal([10, 8, :opening_chests, nil], f.replay.state.values_at(:round, :completed_rounds, :phase, :winner))
    assert_equal(8, f.events.count { |row| row['action'] == 'question' })
    assert_equal(nil, f.game.automatic_action(f.replay, 'Alice', context: f.context), 'Wheel restarted before the chests were opened')
    balances = f.replay.state[:cash].dup
    f.open_chest('Alice', reward: 100)
    assert_equal([:opening_chests, nil], f.replay.state.values_at(:phase, :winner))
    f.open_chest('Bob', reward: 10_000)
    assert_equal([:finished, 'Alice'], f.replay.state.values_at(:phase, :winner))
    assert_equal(balances, f.replay.state[:cash], 'Additional prizes changed the match score')
    assert_equal([100, 10_000, 0, 0], f.replay.state[:bonus_prizes])
    assert_equal(nil, f.game.automatic_action(f.replay, 'Alice', context: f.context), 'Wheel restarted after the final result')
    assert_equal(f.replay, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
  end

  def extra_question_after_tie
    f = F.new(rules_version: 2, players: %w[Alice Bob], options: {'content_language_id'=>'en'})
    8.times { |index| question_round(f, bidder: index.even? ? 'Alice' : 'Bob') }
    assert_equal([:drawing, 8, 9], f.replay.state.values_at(:phase, :completed_rounds, :question_target))
    f.begin_round(chest: true)
    f.bid('Alice', 1)
    f.close_auction
    assert_equal([:drawing, 8, nil], f.replay.state.values_at(:phase, :completed_rounds, :winner), 'A chest consumed the extra question')
    assert_equal(1, f.replay.history.count { |entry| entry.key.to_s.end_with?(':tie') }, 'Every chest repeated the tie announcement')
    question_round(f, bidder: 'Bob')
    assert_equal([:opening_chests, 9, nil], f.replay.state.values_at(:phase, :completed_rounds, :winner))
    f.open_chest('Alice', reward: 100)
    assert_equal([:finished, 'Bob'], f.replay.state.values_at(:phase, :winner))
  end
end

CashAuctionRevisedRoundsTest.run
