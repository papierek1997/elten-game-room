require_relative "../../../lib/dice_poker_hands"
require_relative "../../../lib/liars_dice_rules"

def check(value, message); raise message unless value; end
hands = [[6,6,6,6,6], [6,6,6,6,1], [6,6,6,2,2], [2,3,4,5,6], [5,5,5,2,1], [4,4,3,3,6], [4,4,2,3,6], [1,2,3,4,6]]
ranks = hands.map { |dice| GameRoomDicePokerHands.rank(dice, "classic") }
check(ranks.each_cons(2).all? { |higher, lower| (higher <=> lower) == 1 }, "Wrong poker hand ordering")
check(GameRoomDicePokerHands.rank([1,2,3,4,5], "classic") == [4,5], "Low straight missing")
check(GameRoomDicePokerHands.rank([1,2,3,4,5], "no_straights").first == 0, "No-straights variant counts a straight")
check((GameRoomDicePokerHands.rank([1,1,1,1,1], "aces_high") <=> GameRoomDicePokerHands.rank([6,6,6,6,6], "aces_high")) == 1, "Ones are not high")
check((GameRoomDicePokerHands.rank([2,2,5,5,6], "classic") <=> GameRoomDicePokerHands.rank([2,2,4,4,6], "classic")) == 1, "Two-pair tie break")
histogram = Hash.new(0)
(1..6).to_a.repeated_permutation(5) { |dice| histogram[GameRoomDicePokerHands.rank(dice, "classic").first] += 1 }
check(histogram == {7=>6, 6=>150, 5=>300, 4=>240, 3=>1200, 2=>1800, 1=>3600, 0=>480}, "Poker dice combinatorics changed")

rules = GameRoomLiarsDiceRules
bid = {quantity: 7, face: 4}
check(rules.raise_allowed?(4, 1, bid, variant: "perudo", total: 20), "Switch to half rounded up")
check(!rules.raise_allowed?(3, 1, bid, variant: "perudo", total: 20), "Too few wilds")
check(!rules.raise_allowed?(1, 1, nil, variant: "perudo", total: 20), "Perudo opens on wilds")
check(rules.raise_allowed?(9, 2, {quantity: 4, face: 1}, variant: "perudo", total: 20), "Switch from wilds")
check(!rules.raise_allowed?(8, 6, {quantity: 4, face: 1}, variant: "perudo", total: 20), "Low switch from wilds")
check(!rules.raise_allowed?(8, 5, bid, variant: "perudo", total: 20, palifico: true), "Palifico face was changed")
check(rules.raise_allowed?(8, 5, bid, variant: "perudo", total: 20, palifico: true, may_change: true), "Former Palifico player cannot change face")
check(rules.count([1,1,4,4,5], 4, variant: "perudo") == 4, "Wild count")
check(rules.count([1,1,4,4,5], 4, variant: "perudo", palifico: true) == 2, "Palifico wild count")
check(rules.count([1,1,4,4,5], 1, variant: "perudo") == 2, "Wilds counted twice")
check(rules.count([1,1,4,4,5], 4, variant: "rdr") == 2, "RDR has wild ones")
check(!rules.raise_allowed?(21, 6, nil, variant: "classic", total: 20), "Bid exceeds total dice")
200.times do |seed|
  dice = rules.dice(seed.to_s(16), "0123456789abcdef" * 2, 5)
  check(dice == rules.dice(seed.to_s(16), "0123456789abcdef" * 2, 5) && dice.all? { |value| value.between?(1,6) }, "Private dice derivation")
end
check(rules.dice('a'*32, 'b'*32, 5) != rules.dice('c'*32, 'b'*32, 5), "Server seed has no effect")
puts "Dice game rules: all 7776 poker hands, tie breaks, variants, Perudo raises, Palifico and private derivation passed"
