require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('hearts', count: 4, seed: 317)
table.finish_production_match
assert_equal(table.events, table.replay.accepted_events, 'A bot selected a move refused by production replay')
assert(table.replay.winner && table.state[:scores].fetch(table.replay.winner) == table.state[:scores].values.min,
  'Bots did not complete the actual Hearts table')
puts 'PASS Hearts bots: complete production exchanges, legal tricks and score settlement'
