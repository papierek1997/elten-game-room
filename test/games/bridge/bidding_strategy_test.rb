require_relative '../../support/bridge'
include GameRoomTest::Assertions

R = GameRoomGames::BridgeRules

def check_bid(hand, calls, expected, explanation, vulnerability: 'none')
  assert_equal(13, hand.uniq.size)
  assert((hand - R::DECK).empty?, 'Invalid fixture hand')
  auction = calls.each_with_index.map { |call, index| [index % 4, call] }
  seat = calls.length % 4
  observation = {'phase'=>'bidding', 'hand'=>hand, 'calls'=>auction, 'seat'=>seat, 'vulnerability'=>vulnerability}
  before = Marshal.dump(observation)
  actions = R.legal_calls(auction, seat).map { |call| {'kind'=>'command', 'action'=>'call', 'call'=>call} }
  choice = GameRoomGames::BridgeStrategy.new.choose(actions: actions, observation: observation, actor: 'Tester', random_source: nil)
  assert_equal(expected, choice.fetch('call'), explanation)
  assert(actions.include?(choice), 'Bot chose an illegal call')
  assert_equal(before, Marshal.dump(observation), 'Bid changed its public observation or hand')
end

opening = %w[AH KH TH 6H 2H AS 7S 4S QD 8D 5D JC 3C]
check_bid(opening, %w[1H P 2H P], 'P', 'A minimum raise should not push this hand to game')
check_bid(opening, %w[1H P 3H P], '4H', 'The same hand should accept a natural invitation')
check_bid(opening, %w[1H 2S 3H P], 'P', 'A forced raise to three is not a jump invitation')

check_bid(%w[AC KC QC JC 8C 2C AH 5H 4H KS 8S 2S 7D], %w[1C P 1H P], '2C',
  'Do not pretend a four-card response fits three hearts')
check_bid(%w[AH KH JH 9H 7H AC 9C 4C 2C 8S 3S 8D 3D], %w[1C 1S], '2H',
  'Show a sound five-card suit with strength when the one level has been taken', vulnerability: 'both')
check_bid(%w[AC KC QC 4C AH 7H 2H 8D 7D 2D 9S 5S 3S], %w[1C 1D], 'P',
  'Do not bid notrump without a stopper in the opponents’ announced suit')

nt_minimum = %w[AS KS JS 2S AH 6H 2H QD 7D 4D JC 6C 3C]
nt_maximum = nt_minimum.map { |card| {'JS'=>'QS', 'JC'=>'QC'}.fetch(card, card) }
check_bid(%w[KH QH 8H 4H QD 7D 2D JC 4C 2C 9S 6S 4S], %w[1N P], '2N',
  'Eight balanced points opposite 1NT are an invitation')
check_bid(nt_minimum, %w[1N P 2N P], 'P', 'Decline an invitation with a minimum 1NT')
check_bid(nt_maximum, %w[1N P 2N P], '3N', 'Accept with a maximum 1NT, not a jump to slam')

check_bid(%w[AS KS 8S 7S 2S AH 7H 2H QD 9D 5D 2D 4C], %w[1S P 1N P], '2D',
  'A minimum opener can describe a lower-ranking second suit at the two level')
two_suits = %w[AD KD 9D 7D 4D AH JH 8H 3H JS 6S 9C 4C]
check_bid(two_suits, %w[1D P 1S P], 'P', 'A minimum should not reverse to a higher-ranking second suit')
check_bid(two_suits.map { |card| card == '9C' ? 'AC' : card }, %w[1D P 1S P], '2H',
  'An opener with extras can show the higher-ranking second suit')

puts 'PASS Bridge bidding: support and invitations, stopper, available competition, natural rebids and unchanged observation'
