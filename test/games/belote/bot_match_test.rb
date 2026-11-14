require_relative "../../../games/belote_support/belote_match"
require_relative "../../../games/belote_support/belote_bot"
bot = GameRoomGames::BeloteBot
match = GameRoomGames::BeloteMatch.new
rng = Random.new(79)
80.times do
  break if match.winner
  raise unless match.deal(GameRoomGames::BeloteRound::DECK.shuffle(random: rng))
  while (round = match.round)
    seat = round.turn
    action = if round.phase == :bidding
      match.bid(seat, bot.bid(round.bids(seat), round.hand(seat), round.upcard))
    else
      match.play(seat, bot.play(round.legal_cards(seat), round.trump))
    end
    raise "Bot submitted an illegal action" unless action
  end
end
raise unless match.winner && match.scores[match.winner] >= 1000
puts "PASS Belote bot match to 1000"
