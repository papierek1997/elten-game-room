require_relative "../../../games/hearts_support/hearts_round"
r = GameRoomGames::HeartsRound
r::PASS.each do |direction, offset|
  round = r.new(r::DECK, direction: direction)
  unless direction == :hold
    choices = 4.times.map { |seat| round.hand(seat).first(3) }
    4.times { |seat| raise unless round.pass(seat, choices[seat]) }
    4.times { |seat| raise unless choices[seat].all? { |card| round.hand((seat + offset) % 4).include?(card) } }
  end
  raise unless round.legal_cards(round.turn) == [[:clubs, 2]]
  52.times do
    player = round.turn
    raise unless round.play(player, round.legal_cards(player).first)
  end
  raise unless round.phase == :finished && round.turn.nil?
  raise unless [26, 78].include?(round.penalties.sum)
end
puts "PASS Hearts: 52 plays and all four passing directions"
