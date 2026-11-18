require_relative '../../support/cheat'
include GameRoomTest::CheatFixture
cheat_start
until @replay.finished?
  action = @replay.state[:phase] == :reaction ? cheat_command('accept') :
    cheat_play(@replay.state[:hands].fetch(@replay.current_player).take(4))
  cheat_move(action)
end
result = @game.tournament_result(@replay, options: @replay.state[:options])
assert_equal([@replay.winner], result[:winners])
assert_equal(nil, result[:scores])
assert_equal(@players, result[:units].keys)
assert_equal(false, result[:draw])
assert_equal([:draw, :scores, :units, :winners], result.keys.sort)
puts 'PASS Cheat result from complete accepted history: one winner, no fabricated scores or placements'
