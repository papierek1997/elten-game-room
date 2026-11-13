require_relative "../../../games/french_tarot_support/french_tarot_match"
deck = GameRoomGames::FrenchTarotRound::DECK
match = GameRoomGames::FrenchTarotMatch.new(deals: 2)
raise unless match.deal(deck)
4.times { raise unless match.bid(match.round.turn, :pass) }
raise unless match.dealer == 1 && match.round.nil? && match.completed_deals.zero?
expected = [0, 0, 0, 0]
2.times do |index|
  raise unless match.deal(deck.shuffle(random: Random.new(index + 40)))
  round = match.round
  raise unless round.turn == index + 2
  raise unless match.bid(round.turn, :garde_sans)
  3.times { raise unless match.bid(round.turn, :pass) }
  72.times { raise unless match.play(round.turn, round.legal_cards(round.turn).first) }
  expected = expected.zip(round.contract_scores).map(&:sum)
  raise unless match.scores == expected && match.scores.sum.zero?
end
raise unless match.finished? && match.winners.all? { |seat| expected[seat] == expected.max }
raise if match.deal(deck)
puts "PASS French Tarot match: redeal, rotation and settlement"
