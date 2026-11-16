require_relative '../../support/cash_auction'
include GameRoomTest::Assertions
R = GameRoomCashAuction::Rules

[0, 1, 19, 20, 21, 99, 100, 1000, 10000].zip([0, 1, 1, 1, 2, 5, 5, 50, 500]).each do |cash, expected|
  state = R.initial(%w[Alice Bob], 'auction_rules_version'=>5)
  state[:cash][1] = cash
  assert_equal(expected, R.inactivity_penalty(state, 1), "Wrong rounded 5% deduction from #{cash}")
  assert(R.inactivity_penalty(state, 1) <= cash, 'The penalty exceeded the remaining balance')
end

[false, true].product([false, true]).each do |chest, all_in|
  state = R.initial(%w[Alice Bob], 'auction_rules_version'=>5, 'starting_points'=>1010, 'pass_penalty'=>0)
  state[:pot], state[:pass_counts][1] = 700, 2
  assert(R.draw!(state, category:nil, chest:chest, now:1000))
  assert(R.bid!(state, 0, all_in ? 1000 : 10, now:1001, revision:1, all_in:all_in))
  assert(R.award!(state, now:state[:auction_deadline])) unless all_in
  assert_equal(950, state[:cash][1], 'The third missed auction did not deduct 5% after the ante')
  assert_equal(50, state[:round_penalties][1])
  assert_equal(0, state[:pass_counts][1])
  assert_equal(chest ? 700 : 700 + 20 + (all_in ? 1000 : 10) + 50, state[:pot])
  before = Marshal.dump(state)
  assert_equal(false, R.award!(state, now:state[:auction_deadline]))
  assert_equal(before, Marshal.dump(state), 'Repeated closure charged the penalty again')
end

state = R.initial(%w[Alice Bob], 'auction_rules_version'=>5)
state[:pass_counts] = [2, 2]
assert(R.draw!(state, category:nil, chest:false, now:1000))
assert(R.bid!(state, 1, 1, now:1001, revision:1))
assert(R.bid!(state, 0, 2, now:1002, revision:2))
assert(R.award!(state, now:state[:auction_deadline]))
assert_equal([0, 0], state[:round_penalties], 'A losing bidder received a no-bid penalty')
assert_equal([0, 0], state[:pass_counts])

# Versioned replays retain their fixed penalty and v4's separate chest pool.
[2, 3, 4].each do |version|
  state = R.initial(%w[Alice Bob], 'auction_rules_version'=>version, 'pass_penalty'=>200)
  state[:pass_counts][1] = 2
  assert(R.draw!(state, category:nil, chest:true, now:1000))
  assert(R.award!(state, now:state[:auction_deadline]))
  assert_equal(790, state[:cash][1], 'An accepted older game changed its penalty')
  assert_equal(version == 4 ? 0 : 220, state[:pot], 'An older chest-pool rule changed')
end

game = GameRoomGames::CashAuction.new
[0, 1, 200, 1000000].each do |former_setting|
  options = game.table_creation_options('content_language_id'=>'en', 'pass_penalty'=>former_setting)
  state = R.initial(%w[Alice Bob], options)
  assert_equal(500, R.inactivity_penalty(state, 1), 'A saved former setting changed the fixed 5% rate')
  definition = game.effective_option_definitions(options).find { |entry| entry.key == 'pass_penalty' }
  assert_equal(false, game.option_visible?(definition, options))
  assert_equal(false, game.rules_options_text(options).include?(definition.label))
end

f = CashAuctionFixture::Match.new(rules_version:5, options:{'content_language_id'=>'en'})
2.times do
  f.begin_round(chest:true)
  f.bid('Alice', 1)
  f.close_auction
  assert_equal(0, f.replay.state[:round_penalties][1], 'Fewer than three auctions caused a penalty')
end
f.begin_round(chest:true)
f.bid('Alice', 1)
cash = f.replay.state[:cash][1]
f.close_auction
assert_equal((cash * 5 + 99) / 100, f.replay.state[:round_penalties][1])
assert_equal(0, f.replay.state[:pot])
assert_equal(f.replay, game.replay(f.session, f.events, f.repository), 'Cold replay changed the percentage penalty')

[4, 5].each do |version|
  f = CashAuctionFixture::Match.new(rules_version:version, players:%w[Alice Bob],
    options:{'content_language_id'=>'en', 'starting_points'=>1010, 'ante'=>10})
  f.begin_round
  f.bid('Alice', 170)
  replay = f.replay
  replay.state[:pass_counts][1] = 2
  actions = f.game.legal_actions(replay, 'Bob', context:f.context)
  before = Marshal.dump(replay)
  choice = f.game.bot_strategy.choose(actions:actions, actor:'Bob', game:f.game, replay:replay,
    context:f.context, random_source:nil)
  assert_equal(version == 4 ? '180' : nil, choice&.fetch('answer'), 'Bot did not use the actual imminent penalty')
  assert_equal(before, Marshal.dump(replay), 'Penalty planning changed the game')
end
puts 'PASS fixed 5% inactivity penalty: rounding, third auction, losing bids, all-in, question/chest pools, replay, settings and bot budget'
