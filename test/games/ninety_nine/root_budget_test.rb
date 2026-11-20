require_relative '../../../games/ninety_nine'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions
game = GameRoomGames::NinetyNine.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob Carol Dave], seed: 773)
actor = env.active_actor
actions = env.legal_actions(actor)
before = Marshal.dump(env.replay.state)
[1, 17, 150].each do |budget|
  selected = [actions, actions.reverse].map do |order|
    strategy = NinetyNinePlanning::Strategy.new(depth: 4, fair_worlds: 4, node_limit: budget)
    move = strategy.choose(actions: order, actor: actor, random_source: GameRoomRandom::SeededSource.new(1), game: game, replay: env.replay)
    assert(actions.include?(move))
    assert(strategy.last_stats[:completed_depth] >= 1 && strategy.last_stats[:nodes] <= budget)
    move
  end
  assert_equal(selected.first, selected.last, 'An unfinished later depth biased root-action order')
end
assert_equal(before, Marshal.dump(env.replay.state))
puts 'PASS 99 completed root iterations, very small budgets, order-independent choice and untouched match'
