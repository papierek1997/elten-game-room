require_relative '../../support/cash_auction'
include GameRoomTest::Assertions
R = GameRoomCashAuction::Rules

def opening_match(chest: false, starting_points: 10_000, ante: 300, version: R::CURRENT_VERSION)
  match = CashAuctionFixture::Match.new(players:%w[Alice Bob], rules_version:version,
    options:{'content_language_id'=>'en', 'starting_points'=>starting_points, 'ante'=>ante})
  match.begin_round(chest:chest)
  match
end

[false, true].each do |chest|
  match = opening_match(chest:chest)
  assert_equal(R::CURRENT_VERSION, match.game.table_creation_options['auction_rules_version'])
  [0, 1, 10, 299].each do |amount|
    before = match.replay
    status, plan = match.plan(match.bid_selection('Alice', amount))
    assert_equal(:invalid_bet, status, "An opening bid of #{amount} bypassed the 300-point ante")
    assert_equal(nil, plan, 'An invalid opening prepared a write')
    state = Marshal.load(Marshal.dump(before.state))
    saved = Marshal.dump(state)
    assert_equal(false, R.bid!(state, 0, amount, now:match.now, revision:999), 'The reducer admitted an invalid opening')
    assert_equal(saved, Marshal.dump(state), 'Refusing an opening changed money, deadline or participation')
    match.append_raw(action:'bid', value:"#{before.state[:round]}|#{amount}")
    assert_equal(before, match.replay, 'An injected sub-ante opening changed the accepted replay')
  end
  assert_equal(:ok, match.plan(match.bid_selection('Alice', 301)).first, 'Opening above the ante was refused')
  match.bid('Bob', 300)
  assert_equal([1, 300], match.replay.state.values_at(:leader, :highest))
  match.bid('Alice', 301)
  assert_equal(301, match.replay.state[:highest], 'The opening minimum also imposed a new raise increment')
  assert_equal(match.replay, match.game.build_session_game.replay(match.session, match.events, match.repository),
    'Cold replay disagrees after refused openings and a one-point raise')
end

# A and its numeric equivalent share the same first-offer floor. Exactly the
# ante remains a legal all-in; a short balance cannot bypass the floor.
%w[A 299].each do |text|
  match = opening_match(starting_points:599)
  before = match.replay
  assert_equal(:invalid_bet, match.plan(match.bid_selection('Alice', text)).first, 'Short all-in bypassed the opening minimum')
  state = Marshal.load(Marshal.dump(before.state))
  assert_equal(false, R.bid!(state, 0, 299, now:match.now, revision:999, all_in:true))
  match.append_raw(action:'all_in', value:'1|299')
  assert_equal(before, match.replay, 'An injected short all-in closed the auction')
end
%w[A 300].each do |text|
  match = opening_match(starting_points:600)
  match.bid('Alice', text)
  assert_equal([:question_pending, 300, 0], match.replay.state.values_at(:phase, :highest, :leader))
end

[1, 100, 300, 1000].each do |ante|
  match = opening_match(ante:ante)
  view = match.replay
  actions = match.game.legal_actions(view, 'Alice', context:match.context)
  actions.each do |action|
    amount = action['answer'] == 'A' ? view.state[:cash][0] : action['answer'].to_i
    assert(amount >= ante, 'A generated bot action starts below the ante')
    assert_equal(:ok, match.plan(action).first, 'A generated opening fails normal validation')
  end
end
match = opening_match(starting_points:1000)
view = match.replay
choice = match.game.bot_strategy.choose(actions:match.game.legal_actions(view, 'Alice', context:match.context),
  actor:'Alice', random_source:nil, game:match.game, replay:view, context:match.context)
assert_equal(nil, choice, 'An unwilling bot used a tiny opening to evade its budget')
match = opening_match(starting_points:599)
assert_equal([], match.game.legal_actions(match.replay, 'Alice', context:match.context), 'A short balance still exposes a generated opening')

# The floor returns for each auction, not each bidder. An accepted all-in
# still closes bidding even when a different participant has a larger stack.
match = opening_match
match.bid('Alice', 300)
match.bid('Bob', 301)
match.close_auction
match.reveal_question
match.answer_correct('Bob')
match.begin_round
assert_equal(:invalid_bet, match.plan(match.bid_selection('Alice', 299)).first, 'The next auction lost its opening minimum')
view = match.replay
assert(view.state[:cash][1] > view.state[:cash][0], 'The all-in opponent must have more money')
match.bid('Alice', 'A')
closed = match.replay
assert_equal(:question_pending, closed.state[:phase])
assert_equal([], match.game.legal_actions(closed, 'Bob', context:match.context))
assert_equal(:invalid, match.plan(match.bid_selection('Bob', closed.state[:highest] + 1, view:view), actor:'Bob').first)
match.append_raw(action:'bid', value:"2|#{closed.state[:highest] + 1}", actor:'Bob')
assert_equal(closed, match.replay, 'A wealthier opponent raised after an accepted all-in')
assert_equal(closed, match.game.build_session_game.replay(match.session, match.events, match.repository))

# Already bound histories keep their accepted bids and existing settlement
# policies; a new-game marker must not silently change v5's percentage rules.
(1...R::CURRENT_VERSION).each do |version|
  match = opening_match(version:version)
  match.bid('Alice', 1)
  assert_equal(1, match.replay.state[:highest], "Published v#{version} opening was reinterpreted")
  assert_equal(match.replay, match.game.build_session_game.replay(match.session, match.events, match.repository))
end
[5, R::CURRENT_VERSION].each do |version|
  state = R.initial(%w[Alice Bob], 'auction_rules_version'=>version)
  assert(R.revised?(state) && R.percentage_chests?(state) && R.percentage_penalty?(state[:options]), 'A rules bump dropped an earlier policy')
  assert_equal(50, R.inactivity_penalty(state, 0))
  assert_equal(false, R.question_pool_auction?(state, chest:true))
end
puts 'PASS Cash Auction first bids: ante floor in planning/reducer/raw replay, ordinary and chest auctions, all-in/balance limits, bot candidates/budgets, unchanged later raises and fixed histories'
