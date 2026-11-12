require_relative '../../support/dice_games'
include DiceGamesSupport

def poker_replay(game, session, repository, moves)
  events = moves.each_with_index.map { |(who, action, value), index| dice_event(index + 1, who, action, value) }
  replay = game.replay(session, events, repository)
  check(replay.accepted_events == events, 'Ordinary poker fixture rejected an event')
  [replay, events]
end

def poker_choice(game, replay)
  GameRoomBots.choose(game.bot_strategy, actions: game.legal_actions(replay, replay.current_player), actor: replay.current_player,
    random_source: GameRoomRandom::SeededSource.new(17), game: game, replay: replay)
end

def poker_settle(game, session, repository, events, actor, round, dice = nil)
  events = events.dup
  events << dice_event(events.size + 1, actor, 'roll', dice.sort.join(',')) if dice
  events << dice_event(events.size + 1, actor, 'stand', round.to_s)
  8.times do
    replay = game.replay(session, events, repository)
    check(replay.accepted_events == events, 'Poker settlement rejected an ordinary action')
    return replay if replay.finished?
    check(replay.state[:phase] == :betting, 'Expected the ordinary final betting phase')
    events << dice_event(events.size + 1, replay.current_player, 'bet', 'check|0')
  end
  raise 'Poker settlement did not finish within its player bound'
end

game = GameRoomGames::DicePoker.new
repository = Repository.new(%w[Alice Bob Carol])
session = { 'options' => JSON.generate(game.normalize_options('scoring' => 'chips', 'stake' => 10,
  'starting_chips' => 100, 'throws' => 2, 'round_limit' => 1)) }
moves = [['Alice', 'ante', '1'], ['Alice', 'bet', 'check|0'], ['Bob', 'bet', 'check|0'], ['Carol', 'bet', 'check|0'],
  ['Alice', 'roll', '1,1,1,1,5'], ['Alice', 'stand', '1'], ['Bob', 'roll', '1,1,1,1,5'], ['Bob', 'stand', '1'],
  ['Carol', 'roll', '1,1,1,1,5']]
replay, events = poker_replay(game, session, repository, moves)
choice = poker_choice(game, replay)
check(choice['action'] == 'roll' && choice['die_ids'] == 'd4', 'Bot overvalues a tie with two completed co-leaders')
standing = poker_settle(game, session, repository, events, 'Carol', 1)
draws = (1..6).map { |face| poker_settle(game, session, repository, events, 'Carol', 1, [1, 1, 1, 1, face]).state[:chips]['Carol'] }
check(standing.state[:chips]['Carol'] == 100 && draws.sum.fdiv(6) > 100, 'Improved tie decision has no actual payout advantage')

session = { 'options' => JSON.generate(game.normalize_options('scoring' => 'chips', 'stake' => 1,
  'starting_chips' => 100, 'throws' => 2, 'round_limit' => 2)) }
moves = [['Alice', 'ante', '1'], ['Alice', 'bet', 'raise|98'], ['Bob', 'bet', 'call|98'], ['Carol', 'bet', 'call|98'],
  ['Alice', 'roll', '6,6,6,6,6'], ['Alice', 'stand', '1'], ['Bob', 'roll', '1,1,1,1,1'], ['Bob', 'stand', '1'],
  ['Carol', 'roll', '6,6,6,6,6'], ['Carol', 'stand', '1'], ['Alice', 'bet', 'check|0'], ['Bob', 'bet', 'check|0'],
  ['Carol', 'bet', 'check|0'], ['Alice', 'ante', '2'], ['Carol', 'bet', 'raise|98'], ['Alice', 'bet', 'call|98'],
  ['Bob', 'roll', '6,6,6,6,6'], ['Bob', 'stand', '2'], ['Carol', 'roll', '1,1,1,1,6'], ['Carol', 'stand', '2'],
  ['Alice', 'roll', '5,5,5,5,6']]
replay, events = poker_replay(game, session, repository, moves)
check(poker_choice(game, replay)['action'] == 'score', 'Short-stack hand makes the bot risk a guaranteed side pot')
standing = poker_settle(game, session, repository, events, 'Alice', 2)
check(standing.state[:chips]['Alice'] == 247, 'Guaranteed side-pot result no longer matches the reducer')

strategy = GameRoomDicePokerStrategy
rank = GameRoomDicePokerHands.rank([1, 1, 1, 1, 5], 'classic')
utility = strategy.contest_value('classic', [rank, rank], 0, split_ties: true)
check((utility.call(rank) - 1.0 / 3).abs < 1e-12, 'Two known co-leaders are not counted separately')
plan = strategy::Plan.new('classic', utility)
check((plan.roll([1, 1, 1, 1], 1) - 7.0 / 18).abs < 1e-12, 'Reroll utility does not match the exact six outcomes')

# Independent weighted-outcome oracle for pending opponents. Point ties retain
# a full point; chip ties divide with both known and future co-leaders.
[[], [rank], [rank, rank]].each do |known|
  [false, true].each do |split_ties|
    utility = strategy.contest_value('classic', known, 1, split_ties: split_ties)
    expected = strategy::OUTCOMES.fetch(5).sum do |dice, weight|
      others = known + [GameRoomDicePokerHands.rank(dice, 'classic')]
      best = (others + [rank]).max
      value = rank == best ? (split_ties ? 1.0 / (1 + others.count(rank)) : 1.0) : 0.0
      weight * value
    end.fdiv(6**5)
    check((utility.call(rank) - expected).abs < 1e-12, 'Pending opponent utility disagrees with complete weighted outcomes')
  end
end
puts 'PASS Dice Poker eligible side pots, all known co-leaders, real settlement advantage and independent pending-outcome oracle'
