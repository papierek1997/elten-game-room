require_relative "../../../games/french_tarot_support/french_tarot_trick"
r = GameRoomGames::FrenchTarotTrick
excuse = [:excuse, 0]
hand = [excuse, [:trump, 2], [:trump, 20], [:clubs, 3]]
raise unless r.legal(hand, [excuse, [:clubs, 4]]) == [[:clubs, 3], excuse]
raise unless r.legal(hand, [[:hearts, 4], [:trump, 10]]) == [[:trump, 20], excuse]
raise unless r.legal(hand, [[:trump, 21]]) == [[:trump, 2], [:trump, 20], excuse]
raise unless r.winner([excuse, [:clubs, 4], [:clubs, 3], [:diamonds, 14]]) == 1
raise unless r.winner([[:hearts, 14], [:trump, 1], excuse, [:trump, 21]]) == 3
puts "PASS French Tarot trick legality"
