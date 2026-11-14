require_relative "../../../games/belote_support/belote_round"
round = GameRoomGames::BeloteRound
hand = [[:hearts, 9], [:hearts, 11], [:diamonds, 14]]
raise unless round.legal(hand, [[:clubs, 7], [:hearts, 9]], trump: :hearts, partner_winning: false) == [[:hearts, 11]]
raise unless round.legal(hand, [[:clubs, 7]], trump: :hearts, partner_winning: true) == hand
raise unless round.legal(hand, [[:hearts, 9]], trump: :hearts, partner_winning: true) == [[:hearts, 11]]
deal = round.new(round::DECK.shuffle(random: Random.new(17)), trump: :hearts, leader: 0)
32.times do
  seat = deal.turn
  raise unless deal.play(seat, deal.legal_cards(seat).first)
end
raise unless deal.turn.nil? && deal.scores.sum == 162
puts "PASS Belote: legal plays and all eight tricks"
