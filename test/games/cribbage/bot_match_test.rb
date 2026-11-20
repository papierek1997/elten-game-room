require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
assert_equal([6, :clubs], GameRoomGames::CribbageBot.play([[6, :clubs], [13, :hearts]], [5, 4]))
table = GameRoomTest::DealtCardTable.new('cribbage', seed: 2026)
table.finish_production_match
assert(table.replay.winner && table.state[:scores].fetch(table.replay.winner) >= 121,
  'Production bot decisions did not complete the game')
assert(table.events == table.replay.accepted_events, 'A selected bot move was not accepted in replay')
puts 'PASS Cribbage bots: informative pegging choice and complete production-table match'
