require_relative '../../support/assertions'
require_relative '../../support/mahjong_round'
include GameRoomTest::Assertions
include MahjongRoundFixture

M = GameRoomMahjong

def claim_round(hand, discarded)
  flow = ready_flow(hand, discarded)
  round = M::TableRound.new(flow: flow, variant: 'riichi', dealer: 1)
  round.with(window: M::ClaimOffers.for_discard(flow))
end

# Calling a live yakuhai improves the distance and gives the open hand a
# scoring route. Apply it through the same claim window as a human call.
round = claim_round('123m456p789s1556z', '5z')
choice = round.bot_action(seat: 0)
assert_equal([:pung, 31], choice.fetch(:choice))
accepted = round.action(**choice)
while accepted.window
  seat = accepted.window.pending.first
  pass = accepted.legal_actions(seat: seat).find { |action| action[:choice] == [:pass] }
  accepted = accepted.action(**pass)
end
assert_equal(:discard, accepted.flow.phase)
assert_equal(0, accepted.flow.seat)
assert_equal([:pung], accepted.flow.melds[0].map { |meld| meld.fetch(:type) })
assert_equal([], round.flow.melds[0], 'The former snapshot stays unchanged')

unscored = claim_round('12223m456p789s16z', '2m')
assert(unscored.legal_actions(seat: 0).any? { |action| action[:choice] == [:pung, 1] })
assert_equal([:pass], unscored.bot_action(seat: 0).fetch(:choice),
  'Do not open a hand that cannot score merely to get closer structurally')

flow = ready_flow('147m258p369s1234z', '5z', self_draw: true)
view = flow.observation(viewer: 0)
safe = mahjong_kinds('5z').first
view = view.merge(discard_history: [[2, safe * 4 + 1]])
policy = M::Bot::Policy.new(view, seat: 0, dealer: 0, variant: 'riichi', round_wind: 27, riichi_levels: [0,0,1,0])
actions = flow.hands[0].map { |tile| {type: :discard, tile: tile} }
assert_equal(safe, M::Tiles.kind(policy.choose(actions).fetch(:tile)),
  'A distant hand should discard a tile publicly safe against the declared opponent')

knitted = mahjong_kinds('147m258p369s1z')
melds = [[:pung, 31]]
assert_equal(0, M::Bot.shanten(knitted, melds: melds, variant: 'mcr'))
assert_equal(-1, M::Bot.shanten(knitted + [27], melds: melds, variant: 'mcr'))
puts 'PASS mahjong strategy: score-aware claim, pass without yaku, Riichi defense and open knitted straight'
