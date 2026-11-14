require_relative "../../../games/belote_support/belote_deal"
rules = GameRoomGames::BeloteRound
deal = GameRoomGames::BeloteDeal.new(rules::DECK, dealer: 3)
raise unless deal.hand(0).size == 5
raise unless deal.bids(0) == [:pass, deal.upcard.first]
4.times { raise unless deal.bid(deal.turn, :pass) }
raise if deal.bids(0).include?(deal.upcard.first)
raise unless deal.bid(0, deal.bids(0).last)
hands = 4.times.map { |seat| deal.hand(seat) }
raise unless hands.all? { |hand| hand.size == 8 } && hands.flatten(1).uniq.size == 32
raise unless hands[deal.taker].include?(deal.upcard)
32.times { raise unless deal.play(deal.turn, deal.legal_cards(deal.turn).first) }
raise unless deal.phase == :finished
passed = GameRoomGames::BeloteDeal.new(rules::DECK, dealer: 1)
8.times { raise unless passed.bid(passed.turn, :pass) }
raise unless passed.phase == :redeal && passed.turn.nil?
puts "PASS Belote: two bidding rounds, complete deal and redeal"

scorer = GameRoomGames::BeloteDeal
raise unless deal.settlement[:scores].sum == 162
raise unless scorer.settle([81,81], taker: 0, carry: 10) == {scores: [0,81], carry: 91, winner: nil}
raise unless scorer.settle([80,82], taker: 0, carry: 91) == {scores: [0,253], carry: 0, winner: 1}
raise unless scorer.settle([80,82], taker: 0, bonuses: [20,0])[:scores] == [100,82]
raise unless scorer.settle([0,162], taker: 0, bonuses: [20,0])[:scores] == [20,252]
puts "PASS Belote contract settlement"
