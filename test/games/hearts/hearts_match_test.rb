require_relative "../../../games/hearts_support/hearts_match"
model = GameRoomGames::HeartsMatch.new
rng = Random.new(137)
rounds = 0
until model.winner
  raise "Match exceeded round bound" if rounds >= 100
  raise unless model.deal(GameRoomGames::HeartsRound::DECK.shuffle(random: rng))
  round = model.round
  raise unless round.phase == (rounds % 4 == 3 ? :play : :pass)
  if round.phase == :pass
    4.times { |seat| raise unless model.pass(seat, round.hand(seat).last(3)) }
  end
  52.times { seat = round.turn; raise unless model.play(seat, round.legal_cards(seat).first) }
  rounds += 1
end
raise unless model.scores.max >= 100 && model.scores[model.winner] == model.scores.min
raise if model.deal(GameRoomGames::HeartsRound::DECK)
puts "PASS Hearts match: #{rounds} rounds"
