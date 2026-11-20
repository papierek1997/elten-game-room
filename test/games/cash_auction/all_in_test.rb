require_relative '../../support/cash_auction'

module CashAuctionAllInTest
  extend GameRoomTest::Assertions
  F = CashAuctionFixture::Match
  module_function

  def run
    immediate_question
    immediate_chest
    short_stack('A')
    short_stack(:numeric)
    rejected_all_in
    historical_all_in_bid
    puts 'Cash Auction all-in: immediate question/chest award, shorter stack and numeric maximum, stale/invalid refusal, sound/clock scope and historical replay passed.'
  end

  def immediate_question
    f = F.new
    f.begin_round
    old = f.replay
    later = f.bid_selection('Bob', 1000, view: old)
    f.bid('Alice', 'A')
    awarded = f.replay
    assert_equal(:question_pending, awarded.state[:phase], 'All-in left time for another bidder')
    assert_equal('all_in', f.events.last['action'])
    assert_equal([], f.game.timer_announcements(awarded, 'Alice', now: f.now))
    assert_equal([], f.game.legal_actions(awarded, 'Bob', context: f.context))
    assert_equal(:invalid, f.plan(later, actor: 'Bob').first)
    assert_equal('question', f.game.automatic_action(awarded, 'Alice', context: f.context)['action'])
    assert_equal('auction_gavel', f.game.event_speech_tail_sound(event: f.events.last,
      before_replay: old, after_replay: awarded, viewer: 'Alice'))
    assert_equal('Alice goes all-in for 990 and wins the auction.', awarded.history.last.text)
    assert_equal('poker_all_in', f.game.event_sound_cues(event: f.events.last, before_replay: old,
      after_replay: awarded, history: awarded.history, viewer: 'Alice', random_variant: ->(*) { raise 'Unexpected sound RNG' }))
    f.append_raw(action: 'all_in', value: '1|990', actor: 'Bob')
    assert_equal(awarded, f.replay, 'A second native all-in changed the winning auction')
    f.reveal_question
    assert_equal(:answering, f.replay.state[:phase])
    assert_equal(0, f.replay.state[:leader])
    assert_equal(0, f.events.count { |event| event['action'] == 'auction_closed' })
    f.answer_correct('Alice')
    assert_equal(4000, f.replay.state[:cash].sum + f.replay.state[:pot])
    assert_equal(f.replay, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
  end

  def immediate_chest
    f = F.new
    f.begin_round(chest: true)
    f.bid('Bob', 'a')
    assert_equal([:drawing, 1, 1], [f.replay.state[:phase], f.replay.state[:completed_rounds], f.replay.state[:chests][1]])
    assert_equal([], f.game.legal_actions(f.replay, 'Bob', context: f.context), 'Chest could be opened before final settlement')
    assert_equal(0, f.events.count { |event| %w[question auction_closed].include?(event['action']) })
    assert_equal(4000, f.replay.state[:cash].sum + f.replay.state[:pot])
    assert_equal(f.replay, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
  end

  def short_stack(input)
    f = F.new(players: %w[Alice Bob])
    f.begin_round
    f.bid('Bob', 500)
    f.bid('Alice', 800)
    f.close_auction
    f.reveal_question
    f.answer_correct('Alice')
    f.begin_round
    f.bid('Alice', 1000)
    later = f.bid_selection('Alice', 1200)
    maximum = f.replay.state[:cash][1] + f.replay.state[:contributions][1]
    assert(maximum < f.replay.state[:highest], 'Fixture did not create a poorer bidder')
    assert_equal('Enter 480 or A to go all-in.', f.game.move_error_for(:invalid_bet, replay: f.replay, actor: 'Bob'))
    assert(f.game.legal_actions(f.replay, 'Bob', context: f.context).any? { |action| action['answer'] == 'A' })
    f.bid('Bob', input == :numeric ? maximum : input)
    assert_equal([:question_pending, 1, maximum, 0],
      f.replay.state.values_at(:phase, :leader, :highest).push(f.replay.state[:cash][1]))
    assert_equal(:invalid, f.plan(later, actor: 'Alice').first, 'A richer bidder raised after all-in')
    f.reveal_question
    f.answer('Bob', (f.replay.state[:question][:correct_index] + 1) % 4)
    assert(f.replay.state[:eliminated][1], 'A wrong immediate all-in answer did not eliminate its owner')
  end

  def rejected_all_in
    f = F.new
    f.begin_round
    before = f.replay
    f.append_raw(action: 'all_in', value: '1|1', actor: 'Alice')
    assert_equal(before, f.replay, 'A forged partial all-in was accepted')
    f.pass('Bob')
    assert_equal(:invalid, f.plan(f.bid_selection('Bob', 'A'), actor: 'Bob').first)
    f.now = f.replay.state[:auction_deadline]
    assert_equal(:invalid, f.plan(f.bid_selection('Alice', 'A'), actor: 'Alice').first)
  end

  def historical_all_in_bid
    f = F.new
    f.begin_round
    f.append_raw(action: 'bid', value: '1|990', actor: 'Alice')
    assert_equal(:auction, f.replay.state[:phase], 'An old bid was reinterpreted as the new terminal action')
    f.close_auction
    f.reveal_question
    assert_equal(f.events, f.replay.accepted_events, 'Historical accepted closure was lost')
  end
end

CashAuctionAllInTest.run
