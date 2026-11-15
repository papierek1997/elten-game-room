require_relative "../../../games/belote_support/belote_match"
game = GameRoomGames::BeloteMatch.new(target: 300)
deck = GameRoomGames::BeloteRound::DECK
rng = Random.new(142)
raise unless game.deal(deck)
raise if game.deal(deck)
8.times { raise unless game.bid(game.round.turn, :pass) }
raise unless game.dealer == 1 && !game.round && game.scores == [0, 0]
played = 0
until game.winner
  raise if played >= 20
  raise unless game.deal(deck.shuffle(random: rng))
  round = game.round
  raise unless round.turn == (game.dealer + 1) % 4
  raise unless game.bid(round.turn, round.upcard.first)
  32.times do
    player = round.turn
    raise unless game.play(player, round.legal_cards(player).first)
  end
  played += 1
end
raise unless played > 1 && game.scores[game.winner] >= 300
raise if game.deal(deck)
puts "PASS Belote match: #{played} completed deals after a redeal"
