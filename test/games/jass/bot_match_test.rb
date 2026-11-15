require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
%w[playroom schieber].each do |variant|
  table = GameRoomTest::DealtCardTable.new('jass', count: 4, seed: 91, options: {'variant'=>variant})
  table.finish_production_match
  assert(table.replay.winner && table.state[:scores].fetch(table.replay.winner) >= 1000, "#{variant}: no winner")
  assert_equal(table.events, table.replay.accepted_events, "#{variant}: a selected bot decision was refused")
end
puts 'PASS production Jass/Schieber: legal bot choices and complete games through the registered reducer'
