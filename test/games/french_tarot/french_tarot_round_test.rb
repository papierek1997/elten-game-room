require_relative "../../../games/french_tarot_support/french_tarot_round"
model = GameRoomGames::FrenchTarotRound
%i[petite garde garde_sans garde_contre].each do |contract|
  round = model.new(model::DECK.shuffle(random: Random.new(41)), dealer: 0)
  raise unless round.bid(1, contract)
  3.times { raise unless round.bid(round.turn, :pass) }
  if round.phase == :discard
    cards = round.hand(1).reject { |suit, rank| %i[trump excuse].include?(suit) || rank == 14 }
    raise unless round.discard(1, cards.first(6))
  end
  72.times { raise unless round.play(round.turn, round.legal_cards(round.turn).first) }
  raise unless round.phase == :finished && round.result[:half_points].sum == 182
  scores = round.contract_scores
  raise unless scores.sum.zero? && scores.values_at(0, 2, 3).uniq.one?
  threshold = GameRoomGames::FrenchTarotScoring::TARGET.fetch(round.result[:oudlers])
  raise unless scores[1].positive? == (round.result[:half_points][0] >= threshold)
end
puts "PASS French Tarot: four contracts and complete rounds"
