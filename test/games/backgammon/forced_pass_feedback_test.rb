require_relative '../../support/private_simulation'
require_relative '../../support/assertions'
require_relative '../../../games/backgammon'
include GameRoomTest::Assertions

found = false
[137, 138].each do |seed|
  game = GameRoomGames::Backgammon.new
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[Alice Bob], seed: seed)
  600.times do
    break if env.finished? || found
    before = env.replay
    actor = env.active_actor
    action = env.legal_actions.max_by { |candidate| game.bot_action_score(before, actor, candidate) }
    assert_equal(:ok, env.step(action))
    after = env.replay
    added = after.history.drop(before.history.size).select { |entry| entry.key.start_with?('blocked:') }
    next if added.empty?
    assert_equal(1, added.size, 'A blocked turn was announced more than once')
    assert_equal("#{actor} cannot move. The turn ends.", added.first.text)
    assert_equal(:roll, after.state[:phase])
    assert(after.current_player != actor, 'Forced-pass speech did not match the actual turn change')
    found = true
  end
  break if found
end
assert(found, 'The bounded production-game fixture did not encounter a blocked turn')
puts 'PASS Backgammon forced-pass feedback follows an actual accepted roll/move and matches the next player'
