require_relative '../../support/cash_auction'
require_relative '../../../lib/game_bots'

include GameRoomTest::Assertions
f = CashAuctionFixture::Match.new(rules_version: 2, options: {'content_language_id'=>'en', 'starting_points'=>1000, 'ante'=>10})
f.begin_round
before = f.replay
selection = {'kind'=>'question', 'action'=>'pass', 'question_id'=>f.game.surface_spec(before, 'Bob').id}
assert_equal([], f.game.surface_spec(before, 'Bob').extra_commands.to_a)
assert(f.game.legal_actions(before, 'Bob', context: f.context).none? { |action| action['action'] == 'pass' })
assert_equal(:invalid, f.plan(selection, actor: 'Bob').first, 'A retained withdrawal callback still writes a move')
candidate = Marshal.load(Marshal.dump(before.state))
assert_equal(false, GameRoomCashAuction::Rules.pass!(candidate, 1))
assert_equal(before.state, candidate, 'Refused withdrawal mutated the reducer')
f.append_raw(action: 'pass', value: before.state[:round].to_s, actor: 'Bob')
assert_equal(before, f.replay, 'A crafted current-format withdrawal was accepted')

f.bid('Alice', 900)
view = f.replay
coordinator = GameRoomBots::Coordinator.new
count = f.events.length
decision = coordinator.decide_next(game: f.game, replay: view, context: f.context, controlled_actors: ['Bob'])
assert_equal(nil, decision, 'An unwilling bot withdrew or made an overpriced bid')
assert_equal(count, f.events.length, 'A waiting bot wrote a server event')
assert_equal(false, f.replay.state[:passed][1], 'Waiting silently withdrew the bot')
assert_equal(:ok, f.plan(f.bid_selection('Bob', 901), actor: 'Bob').first, 'An idle player lost the right to change their mind')
f.close_auction
assert_equal(:question_pending, f.replay.state[:phase], 'Silent bots blocked the normal auction deadline')
assert_equal(1, f.replay.state[:pass_counts][1], 'No-bid tracking disappeared with withdrawal')
assert_equal('Alice', f.replay.players[f.replay.state[:leader]])

puts 'PASS removed Cash Auction withdrawal: no control/action, refused retained callback/native event, silent bot waiting, later human raise, deadline and unchanged no-bid accounting'
