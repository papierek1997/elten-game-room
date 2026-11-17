require_relative '../../../games/go'
require_relative '../../support/dice_games'
include DiceGamesSupport

game = GameRoomGames::Go.new
repository = Repository.new(%w[Alice Bob])
replay = game.replay(dice_session(game, komi: '0'), [], repository)
state = replay.state
state[:stones][2 * 9 + 2] = 1
[[1, 2], [2, 1], [2, 3]].each { |x, y| state[:stones][y * 9 + x] = 0 }
state[:moves] = 162
before = Marshal.dump(state)
choice = game.bot_strategy.choose(actions: game.legal_actions(replay, 'Alice'), actor: 'Alice',
  random_source: GameRoomRandom::SeededSource.new(1), game: game, replay: replay)
check(choice['x'] == 3 && choice['y'] == 2, 'Long game passed instead of taking the legal capture')
check(before == Marshal.dump(state), 'Planning mutated the Go position')
puts 'PASS Go late-game legal capture remains preferable to pass'
