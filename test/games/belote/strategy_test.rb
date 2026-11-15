require_relative '../../support/assertions'
require_relative '../../../games/belote_support/belote_bot'
include GameRoomTest::Assertions
bot = GameRoomGames::BeloteBot
trick = [[:clubs, 10], [:clubs, 7], [:clubs, 14]]
cards = [[:diamonds, 14], [:diamonds, 7], [:hearts, 11]]
assert_equal([:diamonds, 14], bot.play(cards, :hearts, trick: trick, partner_winning: true),
  'Bot overtook a winning partner instead of contributing a valuable discard')
assert_equal([:clubs, 14], bot.play([[:clubs, 14], [:clubs, 7]], :hearts,
  trick: [[:clubs, 10], [:clubs, 8], [:clubs, 9]]), 'Bot gave away a trick it could win')
assert_equal([:clubs, 13], bot.play([[:clubs, 12], [:clubs, 13]], :hearts,
  trick: [[:clubs, 7], [:clubs, 8], [:clubs, 9]]), 'Bot retained a higher card when every legal card won')
puts 'PASS Belote strategy: feed partner, win an available trick, shed high cards in a forced win'
