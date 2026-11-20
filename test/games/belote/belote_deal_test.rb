require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('belote', count: 4, seed: 31)
assert(table.state[:hands].values.all? { |hand| hand.size == 5 }, 'First deal did not give five cards')
offered = GameRoomGames::BeloteCards.decode(table.state[:upcard]).first.to_s
4.times do
  actor = table.replay.current_player
  action = table.game.legal_actions(table.replay, actor).find { |choice| choice['choice'] == 'pass' }
  assert_equal(:ok, table.act(actor, action))
end
actor = table.replay.current_player
choices = table.game.legal_actions(table.replay, actor)
assert(choices.none? { |choice| choice['choice'] == offered }, 'Second auction offers the rejected suit')
assert_equal(:ok, table.act(actor, choices.find { |choice| choice['choice'] != 'pass' }))
assert(table.state[:hands].values.all? { |hand| hand.size == 8 }, 'The second deal did not complete all hands')
assert_equal(32, table.state[:hands].values.flatten.uniq.size)
assert(table.state[:hands].fetch(table.state[:taker]).include?(table.state[:upcard]), 'The taker did not receive the upcard')
table.finish_production_round
passed = GameRoomTest::DealtCardTable.new('belote', count: 4, seed: 51)
8.times do
  actor = passed.replay.current_player
  assert_equal(:ok, passed.act(actor, passed.game.legal_actions(passed.replay, actor).find { |choice| choice['choice'] == 'pass' }))
end
assert_equal(:round_complete, passed.state[:phase])
assert(passed.state[:scores].values.all?(&:zero?), 'A passed-out deal awarded a score')
puts 'PASS production Belote: both auctions, complete hands, upcard and passed-out deal'

scorer = GameRoomGames::BeloteSettlement
raise unless scorer.settle([81,81], taker: 0, carry: 10) == {scores: [0,81], carry: 91, winner: nil}
raise unless scorer.settle([80,82], taker: 0, carry: 91) == {scores: [0,253], carry: 0, winner: 1}
raise unless scorer.settle([80,82], taker: 0, bonuses: [20,0])[:scores] == [100,82]
raise unless scorer.settle([0,162], taker: 0, bonuses: [20,0], sweep: 1)[:scores] == [20,252]
raise unless scorer.settle([0,162], taker: 0, bonuses: [20,0])[:scores] == [20,162]
puts 'PASS Belote contract settlement: tie carry, set contract, belote and sweep'
