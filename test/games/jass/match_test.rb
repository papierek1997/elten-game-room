require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
table = GameRoomTest::DealtCardTable.new('jass', count: 4, seed: 19)
actor = table.replay.current_player
other = (table.replay.players - [actor]).first
pass = {'kind'=>'command', 'action'=>'choose_trump', 'choice'=>'pass'}
assert(table.act(other, pass) != :ok, 'Another player selected the rules')
assert(table.act(actor, pass.merge('choice'=>'unknown')) != :ok, 'Unknown trump accepted')
assert_equal(:ok, table.act(actor, pass))
partner = table.replay.current_player
assert_equal((table.state[:seats].index(actor) + 2) % 4, table.state[:seats].index(partner))
choices = table.game.legal_actions(table.replay, partner)
assert(choices.none? { |action| action['choice'] == 'pass' }, 'Partner can pass back indefinitely')
assert_equal(:ok, table.act(partner, choices.find { |action| action['choice'] == 'spades' }))
assert_equal(actor, table.replay.current_player, 'Trump selection changed the opening leader')
dealer = table.state[:dealer]
table.finish_production_round
assert_equal(:ok, table.deal)
assert_equal((dealer + 1) % 4, table.state[:dealer])
table.finish_production_match
assert(table.replay.winner && table.state[:scores].fetch(table.replay.winner) >= 1000, 'Production Jass did not finish')
assert(table.deal != :ok, 'Completed Jass accepted another deal')
puts 'PASS production Jass: partner selection, refusals, opening leader, dealer rotation and complete match'
