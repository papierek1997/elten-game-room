require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('cribbage', seed: 19)
dealer = table.state[:dealer]
assert(table.deal != :ok, 'A second deal replaced the active hand')
table.finish_production_round
assert_equal(:ok, table.deal)
assert_equal((dealer + 1) % 2, table.state[:dealer], 'Dealer did not alternate')
table.finish_production_match
assert(table.replay.finished? && table.state[:scores].fetch(table.replay.winner) >= 121,
  'The actual registered game did not finish at 121')
assert(table.deal != :ok, 'A completed game accepted a new deal')
puts 'PASS production Cribbage match: dealer rotation, immediate finish at 121 and terminal refusal'
