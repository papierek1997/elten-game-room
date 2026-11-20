require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions
bot = GameRoomGames::FrenchTarotBot
hand = (2..10).map { |rank| [:trump, rank] } +
  [[:trump,1],[:excuse,0],[:hearts,14],[:hearts,13],[:hearts,3],[:clubs,13],[:clubs,12],[:clubs,2],
    [:diamonds,13],[:diamonds,11],[:diamonds,2],[:spades,13],[:spades,12],[:spades,5],[:spades,6]]
before = Marshal.dump(hand)
discard = bot.discard(hand)
assert_equal(6, discard.uniq.size)
assert((discard & [[:trump,1],[:excuse,0],[:hearts,14]]).empty?, 'Discarded a protected king/oudler')
assert(discard.count { |_, rank| rank >= 11 } >= 4, 'Unprotected court points were kept to lose instead of banked in the discard')
assert_equal(4, bot.discard(hand - discard.first(2), count: 4).size, 'Replanning after two discards tried to discard six again')
assert_equal(before, Marshal.dump(hand))
puts 'PASS Tarot joint discard, banked court points, protected cards, remaining count and immutable hand'
