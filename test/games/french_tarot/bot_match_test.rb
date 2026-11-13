require_relative "../../../games/french_tarot_support/french_tarot_match"
require_relative "../../../games/french_tarot_support/french_tarot_bot"
bot = GameRoomGames::FrenchTarotBot
match = GameRoomGames::FrenchTarotMatch.new
deck = GameRoomGames::FrenchTarotRound::DECK
rng = Random.new(81)
24.times do
  break if match.finished?
  raise unless match.deal(deck.shuffle(random: rng))
  while (round = match.round)
    seat = round.turn
    ok = case round.phase
         when :bid then match.bid(seat, bot.bid(round.hand(seat), round.bids(seat)))
         when :discard then match.discard(seat, bot.discard(round.hand(seat)))
         when :play then match.play(seat, bot.play(round.legal_cards(seat), round.trick, taker: round.taker, seat: seat, leader: round.lead_seat))
         end
    raise "Invalid bot action: #{round.phase}" unless ok
  end
end
raise unless match.finished? && match.completed_deals == 4 && match.scores.sum.zero?
puts "PASS French Tarot bot match"
