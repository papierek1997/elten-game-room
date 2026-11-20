require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('belote', count: 4, seed: 142)
assert(table.deal != :ok, 'A deal replaced the active auction')
dealer = table.state[:dealer]
table.finish_production_round
assert_equal(:ok, table.deal)
assert_equal((dealer + 1) % 4, table.state[:dealer], 'Dealer rotation changed')
table.finish_production_match
assert(table.replay.winner && table.state[:scores].fetch(table.replay.winner) >= 1000, 'Production match did not reach its target')
assert(table.deal != :ok, 'A completed match restarted without a new game')
puts 'PASS production Belote match: dealer rotation, target score and terminal refusal'
