require_relative "../../support/bridge"
include GameRoomTest::Assertions

R = GameRoomGames::BridgeRules
contract = ->(level, strain, doubled = 0, declarer = 0) { R::Contract.new(level: level, strain: strain, doubled: doubled, declarer: declarer) }

# Duplicate scores checked against the standard scoring table.
{
  [1, "N", 0, 7, false] => 90,
  [2, "C", 0, 9, false] => 110,
  [4, "H", 0, 10, false] => 420,
  [3, "N", 0, 10, true] => 630,
  [5, "D", 0, 11, true] => 600,
  [2, "S", 1, 8, false] => 470,
  [2, "S", 1, 9, true] => 870,
  [1, "C", 2, 8, true] => 630,
  [6, "S", 0, 12, true] => 1430,
  [7, "N", 0, 13, false] => 1520,
  [2, "H", 0, 6, true] => -200,
  [3, "D", 1, 6, false] => -500,
  [4, "S", 1, 6, false] => -800,
  [4, "S", 1, 5, false] => -1100,
  [4, "S", 1, 8, true] => -500,
  [4, "S", 1, 7, true] => -800,
  [4, "S", 2, 6, false] => -1600,
  [3, "N", 2, 8, true] => -400
}.each do |(level, strain, doubled, tricks, vulnerable), expected|
  actual = R.duplicate_score(contract.(level, strain, doubled), tricks, vulnerable: vulnerable)
  assert_equal(expected, actual, "#{level}#{strain} x#{doubled} #{tricks} tricks vulnerable=#{vulnerable}")
end

# WBF IMP scale boundaries.
{ 0 => 0, 10 => 0, 20 => 1, 40 => 1, 50 => 2, 210 => 5, 220 => 6, 490 => 10, 500 => 11, 1490 => 16,
  3990 => 23, 4000 => 24, 7600 => 24, -30 => -1, -630 => -12 }.each do |difference, imps|
  assert_equal(imps, R.imps(difference), "IMPs for #{difference}")
end

# Board numbers set the dealer and the 16-board vulnerability cycle.
assert_equal(%i[none ns ew both ns ew both none ew both none ns both none ns ew], (1..16).map { |board| R.board_vulnerability(board) })
assert_equal(R.board_vulnerability(1), R.board_vulnerability(17), "the vulnerability cycle does not repeat")
assert_equal([0, 1, 2, 3, 0], (1..5).map { |board| R.board_dealer(board) }, "wrong board dealers")
assert(R.vulnerable?(:ns, 0) && !R.vulnerable?(:ns, 1) && R.vulnerable?(:both, 1) && !R.vulnerable?(:none, 0), "wrong vulnerability test")

# The datum favours the stronger side and is antisymmetric.
hands = R.deal("0" * 32, 0)
assert_equal(52, hands.flatten.uniq.length, "the deal is not a full deck")
assert_equal(R.deal("0" * 32, 0), hands, "the deal is not deterministic")
swapped = [hands[1], hands[2], hands[3], hands[0]]
assert_equal(-R.datum(hands, :none), R.datum(swapped, :none), "the datum is not symmetric between sides")

# A rubber: partscores add up to a game, the rubber bonus depends on games lost.
rubber = R.new_rubber
no_honors = Array.new(4) { [] }
R.score_rubber_deal(rubber, contract.(2, "H"), 8, hands: no_honors)
assert_equal([60, 0], rubber[:game_line], "a partscore was not kept")
R.score_rubber_deal(rubber, contract.(1, "N"), 8, hands: no_honors)
assert_equal([1, 0], rubber[:games], "two partscores did not make a game")
assert_equal([0, 0], rubber[:game_line], "a new game did not start from zero")
assert_equal([30, 0], rubber[:above], "an overtrick was not scored above the line")
assert(R.rubber_vulnerable?(rubber, 0) && !R.rubber_vulnerable?(rubber, 1), "vulnerability after a game is wrong")
entries = R.score_rubber_deal(rubber, contract.(4, "S", 0, 1), 9, hands: no_honors)
assert_equal([[0, :above, 50, :undertricks]], entries, "a non-vulnerable undertrick went to the wrong side")
R.score_rubber_deal(rubber, contract.(3, "N", 0, 3), 9, hands: no_honors)
assert_equal([1, 1], rubber[:games], "East-West did not win a game")
entries = R.score_rubber_deal(rubber, contract.(4, "H", 0, 2), 10, hands: no_honors)
assert(R.rubber_finished?(rubber) && entries.include?([0, :above, 500, :rubber]), "a 2-1 rubber did not score 500")
quick = R.new_rubber
R.score_rubber_deal(quick, contract.(3, "N"), 9, hands: no_honors)
R.score_rubber_deal(quick, contract.(4, "S"), 10, hands: no_honors)
assert_equal([0, 700], quick[:rubber_bonus], "a 2-0 rubber did not score 700")

# Honours belong to whoever holds them, including a defender.
honor_hands = [%w[2C], %w[AS KS QS JS], %w[3C], %w[4C]]
entries = R.score_rubber_deal(R.new_rubber, contract.(2, "S"), 8, hands: honor_hands)
assert(entries.include?([1, :above, 100, :honors]), "defender's honours were not scored")
entries = R.score_rubber_deal(R.new_rubber, contract.(2, "S"), 8, hands: honor_hands, honors: false)
assert(entries.none? { |entry| entry.last == :honors }, "honours were scored with the option off")
aces = [%w[AS AH AD AC], [], [], []]
assert_equal([0, 150], R.honors(aces, "N"), "four aces at no trump did not score 150")
assert_equal(nil, R.honors(aces, "H"), "four aces counted as trump honours")

puts "PASS bridge scoring: duplicate table, undertricks, IMPs, board cycle, datum, rubber and honours"
