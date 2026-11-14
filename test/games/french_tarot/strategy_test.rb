require_relative '../../../games/french_tarot_support/french_tarot_bot'
bot = GameRoomGames::FrenchTarotBot
choices = [:pass, *GameRoomGames::FrenchTarotScoring::CONTRACTS.keys]
weak = %i[clubs diamonds hearts].product((1..6).to_a)
raise 'Weak hand overbid' unless bot.bid(weak, choices) == :pass
strong = [:trump].product((1..16).to_a) + [[:excuse, 0], [:clubs, 14]]
raise 'Strong hand never used its available contract' unless bot.bid(strong, choices) == :garde_contre
legal = [[:diamonds, 2], [:diamonds, 14]]
trick = [[:clubs, 14]]
raise 'Bot donated king before declarer played' unless bot.play(legal, trick, taker: 2, seat: 1, leader: 0) == legal.first
trick = [[:clubs, 2], [:clubs, 14]]
raise 'Bot failed to feed an already secured allied trick' unless bot.play(legal, trick, taker: 0, seat: 2, leader: 0) == legal.last
puts 'PASS own-hand bids and publicly known trick safety, before and after declarer acts'
