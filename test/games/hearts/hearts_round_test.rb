require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('hearts', count: 4, seed: 17)
GameRoomGames::HeartsRules::DIRECTIONS.each_with_index do |direction, index|
  assert_equal(index + 1, table.state[:round])
  offset = GameRoomGames::HeartsRules::PASS.fetch(direction)
  unless offset.zero?
    selected = table.state[:hands].transform_values { |cards| cards.first(3) }
    12.times do
      actor = table.replay.current_player
      action = table.game.legal_actions(table.replay, actor).find { |choice| selected.fetch(actor).include?(choice['card']) }
      assert_equal(:ok, table.act(actor, action))
    end
    table.state[:seats].each_with_index do |seat, i|
      recipient = table.state[:seats][(i + offset) % 4]
      assert((selected.fetch(seat) - table.state[:hands].fetch(recipient)).empty?, 'Wrong pass recipient')
    end
  end
  assert_equal(['2C'], table.game.legal_actions(table.replay, table.replay.current_player).map { |action| action['card'] })
  table.finish_production_round
  assert_equal(52, table.state[:play_count], 'A production deal omitted cards')
  assert([26, 78].include?(table.state[:round_penalties].values.sum), 'Wrong deal penalties')
  table.deal unless index == 3
end
puts 'PASS production Hearts: four consecutive passing directions, recipients, opening club and 52-card settlements'
