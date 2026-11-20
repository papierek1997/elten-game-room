require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
round = GameRoomGames::BeloteRules
hand = [[:hearts, 9], [:hearts, 11], [:diamonds, 14]]
raise unless round.legal(hand, [[:clubs, 7], [:hearts, 9]], trump: :hearts, partner_winning: false) == [[:hearts, 11]]
raise unless round.legal(hand, [[:clubs, 7]], trump: :hearts, partner_winning: true) == hand
raise unless round.legal(hand, [[:hearts, 9]], trump: :hearts, partner_winning: true) == [[:hearts, 11]]
table = GameRoomTest::DealtCardTable.new('belote', count: 4, seed: 17)
actor = table.replay.current_player
bid = table.game.legal_actions(table.replay, actor).find { |action| action['choice'] != 'pass' }
assert_equal(:ok, table.act(actor, bid))
table.finish_production_round
assert_equal(32, table.state[:play_count])
assert_equal(162, table.state[:trick_points].values.sum)
assert_equal(:round_complete, table.state[:phase])
puts 'PASS production Belote: legal trumps, a real auction and all eight tricks'
