require_relative '../../support/bouillabaisse_bot'
include GameRoomTest::Assertions

fixture = GameRoomTest::BouillabaisseBot
game, replay = fixture.position(hands: {'A'=>%w[KH AH], 'B'=>%w[2D]}, round: 1, trick: [['B','QH']],
  taken: {'A'=>%w[2C 3C], 'B'=>%w[2S 3S]}, all_or_nothing: true)
assert_equal('AH', fixture.choose(game, replay), 'An unavoidable equally costly trick should shed the highest winner')

game, replay = fixture.position(hands: {'A'=>%w[2C AC 3H], 'B'=>%w[AH 2D]}, round: 2, trick: [['B','KC']])
assert_equal('AC', fixture.choose(game, replay), 'Missed a clean chance to release a high card')

game, replay = fixture.position(hands: {'A'=>%w[4D 3H], 'B'=>%w[5D 4H], 'C'=>%w[QH AH 2D]}, round: 5,
  actor: 'C', trick: [['A','KC'], ['B','3C']])
assert_equal('QH', fixture.choose(game, replay), 'Dump the 260-point card instead of the higher ace when both lose')

game, replay = fixture.position(hands: {'A'=>%w[AH 2H], 'B'=>%w[2D]}, round: 1, trick: [['B','KH']],
  taken: {'B'=>%w[3C 4C 3S 4S]}, all_or_nothing: true)
assert_equal('AH', fixture.choose(game, replay), 'Take a small penalty to stop the opponent collecting everything')
replay.state[:options]['all_or_nothing'] = false
assert_equal('2H', fixture.choose(game, replay), 'Do not take unnecessary penalty tricks when there is no sweep bonus')

game, replay = fixture.position(hands: {'A'=>%w[QH 2D], 'B'=>%w[2H]}, round: 3, trick: [['B','KC']],
  taken: {'B'=>%w[QC QD QS 3C]}, all_or_nothing: true)
assert_equal('2D', fixture.choose(game, replay), 'Do not dump the last scoring card into the opponent’s sweep')
replay.state[:options]['all_or_nothing'] = false
assert_equal('QH', fixture.choose(game, replay), 'Dumping that card is good when a sweep cannot reverse the penalty')

game, replay = fixture.position(hands: {'A'=>%w[AH 2H], 'B'=>%w[2D]}, round: 6, trick: [['B','KH']],
  taken: {'A'=>%w[3C 4C 3S 4S]}, all_or_nothing: true)
assert_equal('2H', fixture.choose(game, replay), 'Avoid collecting everything in the reward round when it reverses the score')
replay.state[:options]['all_or_nothing'] = false
assert_equal('AH', fixture.choose(game, replay), 'Take the valuable trick normally in the reward round')

game, replay = fixture.position(hands: {'A'=>%w[AC 2D 3D], 'B'=>%w[QH 4D 5D], 'C'=>%w[AH 6D 7D]}, round: 2,
  taken: {'A'=>%w[KC KH QD]}, plays: [['A','KC'], ['B','KH'], ['C','QD']])
assert(fixture.choose(game, replay) != 'AC', 'Do not lead a sure winner into opponents known to be void with penalties outstanding')

game, replay = fixture.position(hands: {'A'=>%w[5C KC AD], 'B'=>%w[2C AC 3D]}, round: 1)
round = BouillabaissePlanning::Round.new(game.bot_observation(replay, 'A'))
policy = BouillabaissePlanning::Policy.new(round, round.initial)
chance = policy.win_chance(BouillabaissePlanning::Round::CARD_IDS.fetch('5C'))
assert(chance.between?(0.5, 0.99), 'A higher unseen card is not a forced overtake if its holder can duck')

puts 'PASS Bouillabaisse tactics: high releases, clean tricks, costly discards, void leads, and both sweep directions'
