require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

table = GameRoomTest::DealtCardTable.new('hearts', count: 4, seed: 317)
table.play_strategy while table.state[:phase] != :playing
12.times { table.play_strategy }
game, replay, actor = table.game, table.replay, table.replay.current_player
view = game.send(:hearts_bot_view, replay, actor)
assert_equal(table.state[:play_count], view[:played].size, 'Public current-deal play chronology is incomplete')
assert_equal(13 - view[:played].count { |seat, _| seat == view[:seat] }, view[:hand].size)
before = Marshal.dump(view)
choice = GameRoomGames::HeartsBot::Position.new(view).choose(game.send(:legal_cards, replay.state, actor).map { |card| GameRoomGames::HeartsCards.decode(card) })
assert_equal(before, Marshal.dump(view), 'Hearts forecast changed its observation')
assert(game.send(:legal_cards, replay.state, actor).include?(GameRoomGames::HeartsCards.encode(choice)))

poisoned = Marshal.load(Marshal.dump(replay))
poisoned.state[:hands].each_key { |player| poisoned.state[:hands][player] = ['hidden'] * poisoned.state[:hands][player].size if player != actor }
assert_equal(view, game.send(:hearts_bot_view, poisoned, actor), 'Actual foreign hands enter the planner')

rules, bot = GameRoomGames::HeartsRules, GameRoomGames::HeartsBot
captured = [[], [[:spades, 12]], [], []]
cards = [[:hearts, 10], [:hearts, 14]]
assert_equal([:hearts, 14], bot.play(cards, [[:hearts, 12], [:hearts, 2], [:hearts, 3]],
  captured: captured, seat: 0, owners: [1, 2, 3]), 'Bot did not interrupt the sole remaining moon candidate')
assert_equal(3, bot.pass(rules::DECK.first(13)).uniq.size)
assert_equal([:hearts, 2], bot.play([[:hearts, 2], [:hearts, 14]], [[:hearts, 12]],
  captured: [[[:spades, 12]], [], [], []], seat: 0, hand: [[:hearts, 2], [:hearts, 14]], owners: [1]),
  'Merely taking the queen does not justify chasing every remaining penalty')
puts 'PASS Hearts current-deal observations, legal bounded forecast, moon defence and hidden-hand isolation'
