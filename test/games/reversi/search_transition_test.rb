require_relative '../../../games/reversi'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions
checks = 0
[false,true].product([false,true]).each do |passing, capture|
  game = GameRoomGames::Reversi.new
  env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob],
    options: {'allow_passing'=>passing, 'mandatory_capture'=>capture})
  random = Random.new(761)
  65.times do
    break if env.finished?
    before = Marshal.dump(env.replay)
    actions = env.legal_actions
    actions.each do |action|
      normal, search = env.fork, env.fork_for_search
      assert_equal(normal.step(action), search.step_for_search(action))
      assert_equal(normal.replay.state, search.replay.state, 'Fast search differs from the actual event reducer')
      assert_equal(normal.replay.current_player, search.replay.current_player)
      assert_equal([normal.replay.winner,normal.replay.draw], [search.replay.winner,search.replay.draw])
      checks += 1
    end
    assert_equal(before, Marshal.dump(env.replay), 'Search or normal branch mutated its parent')
    assert_equal(:ok, env.step(actions[random.rand(actions.size)]))
  end
end
puts "PASS Reversi #{checks} normal/fast transition comparisons, four variants, pass, end state and isolated parents"
