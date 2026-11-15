require_relative "../../../games/jass_support/jass_match"
require_relative "../../../games/jass_support/jass_bid"
game = GameRoomGames::JassMatch.new
rng = Random.new(19)
dealers = []
until game.winner
  raise "No winner after 20 deals" if dealers.size >= 20
  dealers << game.dealer
  raise unless game.deal(GameRoomGames::JassRound::DECK.shuffle(random: rng))
  raise if game.deal(GameRoomGames::JassRound::DECK)
  seat = game.round.turn
  bids = GameRoomGames::JassBid
  raise if bids.apply(game, (seat + 1) % 4, "spades") || bids.apply(game, seat, "unknown")
  raise unless bids.apply(game, seat, "pass")
  partner = game.round.turn
  raise if bids.actions(game.round, partner).any? { |move| move["choice"] == "pass" }
  choice = bids.actions(game.round, partner).find { |move| move["choice"] == "spades" }
  raise unless bids.apply(game, partner, choice.fetch("choice")) && game.round.turn == seat
  while game.round && !game.winner
    seat = game.round.turn
    raise unless game.play(seat, game.round.legal_cards(seat).first)
  end
end
raise unless game.scores[game.winner] >= 1000
raise unless dealers.each_cons(2).all? { |a, b| b == (a + 1) % 4 }
raise if game.deal(GameRoomGames::JassRound::DECK)
puts "PASS Jass match: #{dealers.size} deals"
