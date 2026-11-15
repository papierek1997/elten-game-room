require_relative "../../../games/cribbage_support/cribbage_match"
deck = (1..13).to_a.product(%i[clubs diamonds hearts spades])
match = GameRoomGames::CribbageMatch.new(target: 61)
dealers = []
20.times do
  break if match.winner
  raise unless match.deal(deck)
  raise if match.deal(deck)
  dealers << match.round.dealer
  2.times do
    seat = match.round.turn
    raise unless match.discard(seat, match.round.hand(seat).first(2))
  end
  while match.round && !match.winner
    seat = match.round.turn
    raise unless match.play(seat, match.round.playable(seat).first)
  end
end
raise unless match.winner && match.scores[match.winner] >= 61
raise unless dealers.size > 1 && dealers.each_cons(2).all? { |a, b| a != b }
raise if match.deal(deck)
puts "PASS Cribbage match"
