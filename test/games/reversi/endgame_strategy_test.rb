require_relative '../../../games/reversi'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions
game = GameRoomGames::Reversi.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob], options: {'allow_passing'=>false})
prefix = '4,5 3,5 2,6 5,6 2,5 2,3 2,4 2,7 1,2 1,3 0,3 5,2 4,6 0,1 1,7 4,2 1,1 5,5 2,2 4,7 5,1 1,6 5,3 4,1 3,2 0,0 5,0 1,4 5,7 0,7 3,7 2,1 3,0 2,0 1,5 0,4 0,6 6,2 6,5 0,5 3,1 6,0 6,4 5,4 0,2 6,7 6,6 6,3 7,0 3,6 7,4 7,3'
prefix.split.each do |coordinates|
  x, y = coordinates.split(',').map(&:to_i)
  assert_equal(:ok, env.step({'kind'=>'grid','action'=>'select','x'=>x,'y'=>y}))
end
assert_equal(8, env.replay.board.flatten.count(nil))
actor = env.active_actor
before = Marshal.dump(env.replay)
strategy = game.bot_strategy
move = strategy.choose(actions: env.legal_actions, actor: actor, random_source: env.random_source,
  game: game, replay: env.replay, simulation: env)
assert_equal([7,2], move.values_at('x','y'), 'Short endgame missed the forced win beyond the former six plies')
assert_equal(before, Marshal.dump(env.replay))
assert_equal(8, strategy.last_stats[:completed_depth])
assert(strategy.last_stats[:nodes] <= 55_000)

# Independent full minimax of the real remaining moves, not a heuristic score.
memo = {}
solve = lambda do |branch|
  next branch.reward(actor) if branch.finished?
  key = game.bot_search_key(branch.replay, actor)
  next memo[key] if memo.key?(key)
  values = branch.legal_actions.map do |action|
    following = branch.fork_for_search
    assert_equal(:ok, following.step_for_search(action))
    solve.call(following)
  end
  memo[key] = branch.active_actor == actor ? values.max : values.min
end
chosen = env.fork_for_search
assert_equal(:ok, chosen.step_for_search(move))
assert_equal(1.0, solve.call(chosen))
former = env.fork_for_search
assert_equal(:ok, former.step_for_search({'kind'=>'grid','action'=>'select','x'=>7,'y'=>5}))
assert_equal(0.0, solve.call(former), 'Fixture no longer distinguishes the former drawing choice')
puts 'PASS Reversi legal prefix, bounded eight-square solve, win instead of draw, production minimax oracle and nonmutation'
