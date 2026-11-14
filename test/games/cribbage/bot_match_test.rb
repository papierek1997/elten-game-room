require_relative "../../../games/cribbage_support/cribbage_bot"
require_relative "../../../games/cribbage_support/cribbage_match"
bot = GameRoomGames::CribbageBot
raise unless bot.play([[6, :clubs], [13, :hearts]], [5, 4]) == [6, :clubs]
match = GameRoomGames::CribbageMatch.new(target: 121)
rng = Random.new(2026)
20.times do
  break if match.winner
  raise unless match.deal(bot::DECK.shuffle(random: rng))
  2.times do
    round = match.round
    seat = round.turn
    hand = round.hand(seat)
    cards = bot.discard(hand, dealer: round.dealer == seat)
    raise unless match.discard_slots(seat, cards.map { |card| hand.index(card) })
  end
  while match.round && !match.winner
    round = match.round
    seat = round.turn
    raise unless match.play(seat, bot.play(round.playable(seat), round.sequence))
  end
end
raise unless match.winner && match.scores[match.winner] >= 121
puts "PASS Cribbage: bots complete a 121-point match"
