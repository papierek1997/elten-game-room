require_relative '../../support/cash_auction'

include GameRoomTest::Assertions
f = CashAuctionFixture::Match.new(rules_version: 2, options: {'content_language_id'=>'en'})
f.begin_round
f.bid('Bob', 100)
old = f.replay
deadline = old.state[:auction_deadline]
interval = old.state[:options]['count_interval']
f.now = deadline - interval
calls = f.game.timer_announcements(old, 'Alice', now: f.now)
assert(calls.one? && calls.first[1].include?('three times'), 'The third call is not made while bidding is open')
assert_equal(:auction, f.replay.state[:phase])
assert_equal(nil, f.game.automatic_action(old, 'Alice', context: f.context))
f.now += 1
f.bid('Alice', 125)
assert_equal(0, f.replay.state[:leader], 'A bid after the third call was lost')
assert_equal(f.now + 4 * interval, f.replay.state[:auction_deadline])
assert_equal([], f.game.timer_announcements(f.replay, 'Alice', now: f.now))
f.now = deadline
before = f.replay
f.append_raw(action: 'auction_closed', value: [before.state[:round], old.state[:bid_revision], deadline].join('|'))
assert_equal(before, f.replay, 'A close prepared for the previous bidder overruled a valid raise')
f.pass('Bob')
assert_equal(before.state[:auction_deadline], f.replay.state[:auction_deadline], 'Withdrawing changed the advertised deadline')
assert_equal(:invalid, f.plan(f.bid_selection('Bob', 150), actor: 'Bob').first)
f.close_auction
assert_equal('Alice', f.replay.players[f.replay.state[:leader]])
assert(f.replay.history.last.text.start_with?('Sold to Alice'), 'Closing repeated the third call')
f.reveal_question
state = f.replay.state
id = f.game.surface_spec(f.replay, 'Alice').id
selection = {'kind'=>'question', 'action'=>'hint', 'question_id'=>id}
price = (state[:cash][0] + 9) / 10
assert_equal(:invalid, f.plan(selection, actor: 'Bob').first)
cash, pot = state[:cash].dup, state[:pot]
f.submit(selection)
assert_equal(cash[0] - price, f.replay.state[:cash][0])
assert_equal(pot, f.replay.state[:pot], 'Hint payment was awarded back as part of the pool')
assert_equal(:invalid, f.plan(selection).first, 'A hint could be bought twice')
surface = f.game.surface_spec(f.replay, 'Alice')
assert_equal(2, surface.options.length)
assert(surface.options.any? { |option| option.id == state[:question][:correct_index].to_s })
assert_equal([], surface.extra_commands)
f.answer_correct('Alice')
assert(f.replay.history.last.text.include?(state[:question][:choices][state[:question][:correct_index]]), 'A correct answer was not named')
assert_equal(f.replay, GameRoomGames::CashAuction.new.replay(f.session, f.events, f.repository))
puts 'PASS auction third-call grace, raising/reset and stale close; withdrawal, authenticated paid hint, stable answers and correct-answer feedback'
