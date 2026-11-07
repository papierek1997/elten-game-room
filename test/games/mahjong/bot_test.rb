require_relative '../../support/assertions'
require_relative '../../support/mahjong_tiles'
require_relative '../../../games/mahjong_support/bot'
include GameRoomTest::Assertions
include MahjongTestTiles
bot = GameRoomMahjong::Bot
assert_equal(-1, bot.shanten(mahjong_kinds('123m456p789s11122z')))
assert_equal(0, bot.shanten(mahjong_kinds('123m456p789s1112z')))
assert_equal(0, bot.shanten(mahjong_kinds('1122m4455p7788s3z')))
assert_equal(0, bot.shanten(mahjong_kinds('19m19p19s1234567z')))
assert_equal(-1, bot.shanten(mahjong_kinds('147m258p369s12345z'), variant: 'mcr'))
assert_equal(0, bot.shanten(mahjong_kinds('147m258p369s1234z'), variant: 'mcr'))
own = mahjong_kinds('123m456p789s11125z')
discarded = bot.discard_kind(concealed: own)
assert([28, 31].include?(discarded), 'Discarding an isolated tile can preserve all four completed sets')
rest = own.dup
rest.delete_at(rest.index(discarded))
assert_equal(0, bot.shanten(rest), 'The bot should leave the hand ready to win')
assert_equal(27, bot.discard_kind(concealed: own, choices: [27]), 'A forced legal discard cannot be replaced by a stronger illegal choice')
assert_equal(mahjong_kinds('123m456p789s11125z'), own, 'Bot planning must not sort or mutate the authoritative hand')
assert_raises(ArgumentError) { bot.discard_kind(concealed: own, choices: [33]) }
assert_raises(ArgumentError) { bot.discard_kind(concealed: own, public_counts: {27=>2}) }
assert_raises(ArgumentError) { bot.discard_kind(concealed: own, public_counts: {30=>-1}) }
assert_raises(ArgumentError) { bot.shanten([0] * 5) }
assert_raises(ArgumentError) { bot.discard_kind(concealed: own[0...-1]) }
assert(bot.discard_kind(concealed: mahjong_kinds('123m456p789s11z'), melds: [[:pung, 31]], public_counts: {31=>3}),
  'An exposed owned meld is public; it must not be counted twice')

# East leaves a dead wait on the 3 of characters. Discarding a 1 also
# accepts the 2 of characters, of which three copies are not yet visible.
blocked_wait = mahjong_kinds('11112m123p456s111z')
assert_equal(0, bot.discard_kind(concealed: blocked_wait, public_counts: {2=>4}),
  'Prefer a live wait to a formally ready hand with no remaining tile')
puts 'PASS mahjong bot hand distance, live waits, legal discard restrictions, fair observation boundary and nonmutation'
