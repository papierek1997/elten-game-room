require_relative '../../support/cash_auction'
include GameRoomTest::Assertions

def bot_choice(match, actor)
  game, replay = match.game, match.replay
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
puts 'PASS Cash Auction fixed public positions: cheap bid, excessive cost, pass penalty, reserve, final-round urgency and hidden-input independence'
