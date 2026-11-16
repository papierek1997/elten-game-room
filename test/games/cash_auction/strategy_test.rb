require_relative '../../support/cash_auction'
include GameRoomTest::Assertions

def bot_choice(match, actor, replay: match.replay)
  game = match.game
  actions = game.legal_actions(replay, actor, context: match.context)
  game.bot_strategy.choose(actions: actions, actor: actor, game: game, replay: replay, context: match.context, random_source: nil)
end

match = CashAuctionFixture::Match.new(players: %w[Alice Bob])
match.begin_round
match.bid('Alice', 30)
view = match.replay
choice = bot_choice(match, 'Bob')
old_budget = [view.state[:cash][1] / 3, view.state[:pot] / 2 + view.state[:options]['ante']].min
assert(40 > old_budget, 'Counterexample no longer represents the previous early pass')
assert_equal('40', choice['answer'], 'Bot still gives up a cheap opening auction')
assert_equal(:ok, match.plan(choice, actor: 'Bob').first)
snapshot = Marshal.dump(view)
match.game.legal_actions(view, 'Bob', context: match.context).each { |action| match.game.bot_action_score(view, 'Bob', action) }
assert_equal(snapshot, Marshal.dump(view), 'Auction planning mutated the public replay')

expensive = CashAuctionFixture::Match.new(players: %w[Alice Bob])
expensive.begin_round
expensive.bid('Alice', 950)
assert_equal('pass', bot_choice(expensive, 'Bob')['action'], 'Bot blindly chases an expensive opening bid')

public_view = match.replay
public_view.state[:pass_counts][1] = 2
raise_bid = match.game.legal_actions(public_view, 'Bob', context: match.context).find { |action| action['answer'] == '40' }
public_view.state[:highest] = 150
raise_bid = raise_bid.merge('answer'=>'160')
assert(match.game.bot_action_score(public_view, 'Bob', raise_bid) > 0, 'Bot ignored the larger imminent pass penalty')
public_view.state[:completed_rounds] = 7
public_view.state[:cash][0] = 1500
all_in = raise_bid.merge('answer'=>'A')
assert(match.game.bot_action_score(public_view, 'Bob', all_in) > 0, 'Trailing bot passed away its last chance')

# No unrevealed answer, category or future random outcome is an input to bidding.
reference = match.game.bot_action_score(public_view, 'Bob', all_in)
public_view.state[:question] = {correct_index: 3, prompt: 'Different hidden question'}
public_view.state[:drawn_category] = 999
assert_equal(reference, match.game.bot_action_score(public_view, 'Bob', all_in))
public_view.state[:completed_rounds] = 0
public_view.state[:cash][1] = 20
public_view.state[:contributions][1] = 0
public_view.state[:options]['ante'] = 10
assert(match.game.bot_action_score(public_view, 'Bob', raise_bid.merge('answer'=>'10')) > 0,
  'An unaffordable future reserve prevented every small bid')

# Under the new rules, even a bid subsequently beaten by another player resets
# the no-bid streak. Its owner has no impending fine to justify overspending.
revised = CashAuctionFixture::Match.new(players: %w[Alice Bob], rules_version: 2,
  options: {'starting_points'=>1000, 'ante'=>10})
revised.begin_round
revised.bid('Bob', 10)
revised.bid('Alice', 150)
lost_bid = revised.replay
lost_bid.state[:pass_counts][1] = 2
assert_equal(980, lost_bid.state[:cash][1])
assert_equal(10, lost_bid.state[:contributions][1])
assert_equal(nil, bot_choice(revised, 'Bob', replay: lost_bid),
  'A losing bid did not remove the nonexistent v2 no-bid penalty from the budget')
before = Marshal.dump(lost_bid)
revised.game.legal_actions(lost_bid, 'Bob', context: revised.context).each do |action|
  revised.game.bot_action_score(lost_bid, 'Bob', action)
end
assert_equal(before, Marshal.dump(lost_bid), 'V2 budget calculation changed its public position')

closed = Marshal.load(Marshal.dump(lost_bid.state))
cash = closed[:cash][1]
assert_equal(false, GameRoomCashAuction::Rules.pass!(closed, 1), 'The removed withdrawal is still a current rule action')
assert(GameRoomCashAuction::Rules.award!(closed, now: closed[:auction_deadline]))
assert_equal(0, closed[:pass_counts][1], 'The production reducer did not reset the losing bidder streak')
assert_equal(cash, closed[:cash][1], 'The production reducer fined a losing bidder')

no_bid = Marshal.load(Marshal.dump(lost_bid))
no_bid.state[:cash][1] += no_bid.state[:contributions][1]
no_bid.state[:pot] -= no_bid.state[:contributions][1]
no_bid.state[:contributions][1] = 0
assert_equal('160', bot_choice(revised, 'Bob', replay: no_bid)['answer'],
  'The v2 budget ignored a real impending third no-bid penalty')

legacy = CashAuctionFixture::Match.new(players: %w[Alice Bob])
legacy.begin_round
legacy.bid('Bob', 10)
legacy.bid('Alice', 150)
legacy_lost = legacy.replay
legacy_lost.state[:pass_counts][1] = 2
assert_equal('160', bot_choice(legacy, 'Bob', replay: legacy_lost)['answer'],
  'The original per-pass penalty was incorrectly changed by the v2 policy')

scaled = CashAuctionFixture::Match.new(players: %w[Alice Bob], rules_version: 2, options: {'ante'=>10})
scaled.begin_round
scaled.bid('Alice', 10)
assert_equal(9990, scaled.replay.state[:cash][1])
assert_equal('110', bot_choice(scaled, 'Bob')['answer'], 'The default v2 table still uses tiny fixed raises')
scaled.bid('Bob', 11)
assert_equal(11, scaled.replay.state[:highest], 'Representative bot raises restricted a valid manually entered amount')
assert_equal(9979, scaled.replay.state[:cash][1])

edge = CashAuctionFixture::Match.new(players: %w[Alice Bob], rules_version: 2,
  options: {'starting_points'=>2010, 'ante'=>10})
edge.begin_round
edge.bid('Alice', 245)
# Bob's maximum is 2000 and his budget is 250. The preferred 265 is too
# expensive, while the legal 246 still fits and must remain a candidate.
assert_equal('246', bot_choice(edge, 'Bob')['answer'], 'Scaled raises skipped a cheaper affordable legal bid')
edge.bid('Alice', 250)
assert_equal(nil, bot_choice(edge, 'Bob'), 'Scaled raises exceeded the bid budget when no affordable raise remained')

crowded = CashAuctionFixture::Match.new(players: %w[Alice Bob Carol Dan Eve Frank Grace Heidi], rules_version: 2,
  options: {'starting_points'=>1000, 'ante'=>10, 'content_language_id'=>'en'})
crowded.begin_round
crowded.bid('Alice', 124)
assert_equal(nil, bot_choice(crowded, 'Bob'), 'Bob did not decline a bid above the fixed auction budget')
%w[Carol Dan Eve Frank Grace Heidi].each_with_index { |actor, index| crowded.bid(actor, 150 + index * 10) }
assert_equal(nil, bot_choice(crowded, 'Bob'), 'Other players inflated the pot and brought an unwilling bot back into bidding')

old_scale = CashAuctionFixture::Match.new(players: %w[Alice Bob])
old_scale.begin_round
old_scale.bid('Alice', 10)
assert_equal('20', bot_choice(old_scale, 'Bob')['answer'], 'The v1 representative bid changed with the new scale')

chest = CashAuctionFixture::Match.new(players: %w[Alice Bob], rules_version: 3,
  options: {'starting_points'=>10000, 'ante'=>10, 'content_language_id'=>'en'})
chest.begin_round(chest: true)
chest.bid('Alice', 340)
assert_equal('341', bot_choice(chest, 'Bob')['answer'], 'Bot ignored an affordable percentage chest')
chest.bid('Alice', 347)
assert_equal(nil, bot_choice(chest, 'Bob'), 'Bot overpaid the expected value of the percentage chest')
view = chest.replay
view.state[:completed_rounds] = 7
view.state[:cash][0] = 100000
assert_equal(nil, bot_choice(chest, 'Bob', replay: view), 'Final-round urgency caused a chest all-in')
view.state[:question] = {correct_index: 3, prompt: 'Not available during bidding'}
view.state[:last_chest_reward] = 35
before = Marshal.dump(view)
assert_equal(nil, bot_choice(chest, 'Bob', replay: view), 'Hidden chest information changed the bidding budget')
assert_equal(before, Marshal.dump(view))

puts 'PASS Cash Auction public bidding: scaled raises, budget edges, legacy choices, fixed auction budgets, percentage chest value and hidden-input independence'
