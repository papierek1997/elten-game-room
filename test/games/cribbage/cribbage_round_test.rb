require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

table = GameRoomTest::DealtCardTable.new('cribbage', seed: 17)
first = table.replay.current_player
other = (table.replay.players - [first]).first
selection = table.game.legal_actions(table.replay, first).last
assert(table.act(other, selection) != :ok, 'The other player discarded out of turn')
original = table.state[:hands].fetch(first).dup
assert_equal(:ok, table.act(first, selection))
assert_equal(original - [selection['card']], table.state[:hands].fetch(first))
assert(table.act(first, selection) != :ok, 'The same card was discarded twice')
table.finish_production_round
assert(table.state[:played].values.all? { |cards| cards.size == 4 }, 'Pegging omitted a card')
assert_equal(:round_complete, table.state[:phase])
assert(table.state[:scores].values.sum.positive?, 'The table never awarded points')
puts 'PASS production Cribbage: ordered discards, refusal, all eight plays and hand/crib counting'
