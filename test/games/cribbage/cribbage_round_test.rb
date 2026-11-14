require_relative "../../../games/cribbage_support/cribbage_round"
deck = (1..13).to_a.product(%i[clubs diamonds hearts spades])
round = GameRoomGames::CribbageRound.new(deck, dealer: 0)
raise if round.discard(0, round.hand(0).first(2))
2.times do
  player = round.turn
  raise unless round.discard(player, round.hand(player).first(2))
end
raise unless round.turn == 1
8.times do
  player = round.turn
  raise unless round.play(player, round.playable(player).first)
end
raise unless round.phase == :count && round.count_entries.map(&:first) == [1, 0, 0]
puts "PASS Cribbage round"

# A match-ending award during pegging must stop before further play/counting.
round = GameRoomGames::CribbageRound.new(deck, dealer: 0)
2.times do
  player = round.turn
  raise unless round.discard(player, round.hand(player).first(2))
end
awards = []
while round.phase == :play
  player = round.turn
  raise unless round.play(player, round.playable(player).first) { |seat, points| awards << [seat, points]; true }
end
raise unless awards.size == 1 && round.phase == :finished && round.turn.nil?
raise unless round.count_entries.empty? && round.playable(0).empty?
puts "PASS Cribbage immediate finish"

slots_round = GameRoomGames::CribbageRound.new(deck, dealer: 0)
original = slots_round.hand(1)
raise if slots_round.discard_slots(0, [0, 1])
raise if slots_round.discard_slots(1, [0, 0])
raise if slots_round.discard_slots(1, [-1, 1])
raise unless slots_round.hand(1) == original
raise unless slots_round.discard_slots(1, [5, 0])
raise unless slots_round.hand(1) == original[1, 4]
raise unless slots_round.discard_slots(0, [1, 3])
raise unless slots_round.phase == :play
puts "PASS Cribbage ordered discard slots"
