require_relative '../support/dice_games'
include DiceGamesSupport

game = GameRoomGames::DicePoker.new
repository = Repository.new(%w[Alice Bob])
session = dice_session(game, throws: 2, round_limit: 2)
events = [dice_event(1, 'Alice', 'roll', '6,6,6,6,6'), dice_event(2, 'Alice', 'stand', '1'),
  dice_event(3, 'Bob', 'roll', '5,5,5,5,5'), dice_event(4, 'Bob', 'stand', '1'),
  dice_event(5, 'Bob', 'roll', '3,4,5,6,6'), dice_event(6, 'Bob', 'stand', '2'),
  dice_event(7, 'Alice', 'roll', '3,4,5,6,6')]
replay = game.replay(session, events, repository)
check(replay.accepted_events == events, 'Rejected the ordinary two-round fixture')
choice = GameRoomBots.choose(game.bot_strategy, actions: game.legal_actions(replay, 'Alice'), actor: 'Alice',
  random_source: GameRoomRandom::SeededSource.new(3), game: game, replay: replay)
check(choice['action'] == 'score', 'Point-mode bot risks a guaranteed full tie point and match win')
finished = game.replay(session, events + [dice_event(8, 'Alice', 'stand', '2')], repository)
check(finished.finished? && finished.winner == 'Alice' && finished.state[:scores] == { 'Alice' => 2, 'Bob' => 1 },
  'Tie-point strategy does not match actual round/match settlement')

rank = GameRoomDicePokerHands.rank([3, 4, 5, 6, 6], 'classic')
point = GameRoomDicePokerStrategy::Plan.new('classic', GameRoomDicePokerStrategy.contest_value('classic', [rank], 0, split_ties: false))
chips = GameRoomDicePokerStrategy::Plan.new('classic', GameRoomDicePokerStrategy.contest_value('classic', [rank], 0, split_ties: true))
check(point.stand([3, 4, 5, 6, 6]) == 1 && chips.stand([3, 4, 5, 6, 6]) == 0.5,
  'Points and divided-chip ties have the same value')
point_pending = GameRoomDicePokerStrategy.contest_value('classic', [], 1, split_ties: false)
chip_pending = GameRoomDicePokerStrategy.contest_value('classic', [], 1, split_ties: true)
check(point_pending.call(rank) > chip_pending.call(rank), 'Pending point ties still count as half a point')
distribution = GameRoomDicePokerStrategy.random_outcomes('classic')
check(GameRoomDicePokerStrategy.random_outcomes('classic').equal?(distribution), 'Utility construction replaced the bounded distribution')
puts 'PASS Dice Poker point-tie utility, real final-round choice and distinct bounded chip/point caches'
