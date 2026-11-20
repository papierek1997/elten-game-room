require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('hearts', count: 4, seed: 137)
assert(table.deal != :ok, 'An active hand can be replaced')
table.finish_production_match
assert(table.state[:scores].values.max >= 100, 'The game ended before the score limit')
assert_equal(table.state[:scores].values.min, table.state[:scores].fetch(table.replay.winner), 'The lowest score did not win')
assert(table.deal != :ok, 'A completed game can be redealt')
puts 'PASS production Hearts match: repeated deals, score limit, lowest-score winner and terminal refusal'
