require_relative '../../support/bouillabaisse_bot'
include GameRoomTest::Assertions

fixture = GameRoomTest::BouillabaisseBot
deck = BouillabaissePlanning::Round::CARD_IDS.keys - ['2C']
game, replay = fixture.position(hands: {'A'=>deck[0,2], 'B'=>deck[2,2], 'C'=>deck[4,2]},
  round: 6, taken: {'A'=>deck[6,15], 'B'=>deck[21,15], 'C'=>deck[36,15]})
replay.state[:scores].merge!('A'=>190, 'B'=>210, 'C'=>900)
round = BouillabaissePlanning::Round.new(game.bot_observation(replay, 'A'))
assert_equal(615, round.total)

# In the second outcome A collects more points, but B overtakes A.
# Averaging the gap to B and C used to prefer that losing finish.
score = ->(raw) do
  assert_equal(round.total, raw.sum)
  terminal = round.initial.branch
  terminal.raw = raw
  round.utilities(terminal, finish_priority: true).fetch(round.root)
end
win = score.call([90,105,420])   # 100, 105, 480
tie = score.call([90,110,415])   # 100, 100, 485
loss = score.call([160,185,270]) # 30, 25, 630
assert(win > tie && tie > loss, 'Winning the match outranks improving the gap to the last seat')

game, replay = fixture.position(hands: {'A'=>%w[AC KC], 'B'=>%w[3D 4D], 'C'=>%w[5H 6H]}, round: 6)
round = BouillabaissePlanning::Round.new(game.bot_observation(replay, 'A'))
assert_equal(nil, round.forced_world, 'Unknown seats are not exact information')
suits = BouillabaissePlanning::Round::SUIT_IDS
round.initial.voids[1] = 1 << suits.fetch('H')
round.initial.voids[2] = 1 << suits.fetch('D')
assert_equal(%w[3D 4D].map { |card| BouillabaissePlanning::Round::CARD_IDS.fetch(card) },
  round.forced_world.hands[1], 'Public voids and sizes can prove the last distribution')
puts 'PASS Bouillabaisse: final placement and a provably known ending'
