require_relative "../../../games/jass_support/jass_match"
require_relative "../../../games/jass_support/jass_bot"
game = GameRoomGames::JassMatch.new
bot = GameRoomGames::JassBot
rng = Random.new(91)
20.times do
  break if game.winner
  raise unless game.deal(GameRoomGames::JassRound::DECK.shuffle(random: rng))
  round = game.round
  until round.trump
    seat = round.turn
    raise unless game.bid(seat, bot.bid(round.observation(seat)))
  end
  while game.round && !game.winner
    seat = round.turn
    raise unless game.play(seat, bot.play(round.observation(seat)))
  end
end
raise unless game.winner && game.scores[game.winner] >= 1000
puts "PASS Jass bot match"
