require_relative "../../../games/hearts_support/hearts_rules"
r = GameRoomGames::HeartsRules
h = [[:clubs, 2], [:hearts, 14], [:spades, 12]]
raise unless r.legal(h, [], first_trick: true, hearts_broken: false) == [[:clubs, 2]]
raise unless r.legal(h, [[:clubs, 5]], first_trick: false, hearts_broken: true) == [[:clubs, 2]]
raise unless r.legal(h, [[:diamonds, 5]], first_trick: true, hearts_broken: false) == [[:clubs, 2]]
raise unless r.trick_winner([[:clubs, 5], [:hearts, 14], [:clubs, 6], [:spades, 12]]) == 2
raise unless r.settle([[], (2..14).map { |rank| [:hearts,rank] } + [[:spades,12]], [], []]) == [26,0,26,26]
puts "PASS Hearts: opening, following suit and shooting the moon"
