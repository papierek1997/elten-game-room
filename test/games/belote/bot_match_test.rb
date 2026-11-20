require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
%w[classic coinchee].each do |variant|
  table = GameRoomTest::DealtCardTable.new('belote', count: 4, seed: 79, options: {'variant'=>variant})
  table.finish_production_match
  assert(table.replay.winner && table.state[:scores].fetch(table.replay.winner) >= 1000, "#{variant}: no winner")
  assert_equal(table.events, table.replay.accepted_events, "#{variant}: a bot action was refused by replay")
end
puts 'PASS production Belote/Coinchée: complete bot auctions, legal card play, melds and match results'
