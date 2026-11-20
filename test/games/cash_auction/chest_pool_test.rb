require_relative '../../support/cash_auction'
include GameRoomTest::Assertions
R = GameRoomCashAuction::Rules

def state_for(version)
  state = R.initial(%w[Alice Bob], 'auction_rules_version'=>version)
  state[:pot] = 500
  state
end

state = state_for(4)
assert(R.draw!(state, category:nil, chest:true, now:1000))
assert_equal([990, 990], state[:cash], 'Chest antes were not paid')
assert_equal(500, state[:pot], 'Chest antes increased the saved question pool')
assert(R.bid!(state, 0, 100, now:1001, revision:1))
assert(R.bid!(state, 1, 150, now:1002, revision:2))
assert(R.bid!(state, 0, 200, now:1003, revision:3))
assert_equal([790, 840], state[:cash], 'Chest bids refunded a loser or deducted a raised offer twice')
assert_equal(500, state[:pot], 'Chest bids increased the question pool')
assert(R.award!(state, now:state[:auction_deadline]))
assert_equal([1, 0], state[:chests])
assert_equal(500, state[:pot], 'Awarding a chest consumed the old question pool')
assert(R.draw!(state, category:{name:'Example'}, chest:false, now:2000))
assert_equal(520, state[:pot], 'The next question lost the carried pool or retained chest payments')
assert(R.bid!(state, 1, 20, now:2001, revision:4))
assert(R.award!(state, now:state[:auction_deadline]))
assert(R.start_question!(state, {correct_index:0}))
assert(R.answer!(state, 1, true, now:2010))
assert_equal(1350, state[:cash][1], 'A correct answer paid out chest money or omitted the prior pool')
assert_equal(0, state[:pot])

[false, true].each do |all_in|
  state = state_for(4)
  state[:pass_counts] = [0, 2]
  assert(R.draw!(state, category:nil, chest:true, now:1000))
  assert(R.bid!(state, 0, all_in ? 990 : 100, now:1001, revision:1, all_in:all_in))
  assert(R.award!(state, now:state[:auction_deadline])) unless all_in
  assert_equal(790, state[:cash][1], 'The third missed chest auction did not deduct its penalty')
  assert_equal(500, state[:pot], 'A chest-auction inactivity penalty increased the question pool')
end
state = state_for(4)
assert(R.draw!(state, category:nil, chest:true, now:1000))
assert(R.award!(state, now:state[:auction_deadline]))
assert_equal(500, state[:pot], 'An unsold chest increased the question pool')
assert_equal([0, 0], state[:chests])

# Fixed published v3 games retain their original reducer; a new ordinary
# table selects the current rules. Do not reinterpret already accepted payouts.
state = state_for(3)
assert(R.draw!(state, category:nil, chest:true, now:1000))
assert(R.bid!(state, 0, 100, now:1001, revision:1))
assert_equal(620, state[:pot], 'A fixed older game changed its recorded chest-payment meaning')
game = GameRoomGames::CashAuction.new
assert_equal(R::CURRENT_VERSION, game.table_creation_options('content_language_id'=>'en')['auction_rules_version'])

f = CashAuctionFixture::Match.new(rules_version:4, options:{'content_language_id'=>'en'})
3.times do
  f.begin_round(chest:true)
  f.bid('Alice', 1)
  f.close_auction
end
state = f.replay.state
assert_equal(0, state[:pot], 'The production replay added chest bids, antes or penalties to the pool')
penalty = f.replay.history.find { |entry| entry.text.include?('Bob made no bid in three consecutive') }
assert(penalty && !penalty.text.include?('into the pool'), 'Chest penalty speech falsely promised a pool contribution')
assert_equal(f.replay, game.replay(f.session, f.events, f.repository), 'Cold reconstruction changed chest settlement')
puts 'PASS chest payments: preserved prior pool, paid bids/antes, inactivity, all-in, empty auction, next payout and fixed-version replay'
