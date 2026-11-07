# Assign hypothetical cards without inspecting a real opponent's hand.
# Callers own their public constraints, retry budget and probability model.
module GameRoomHiddenCardDeals
  module_function

  def assign(cards, players, counts, random, &allowed)
    remaining = counts.dup
    result = players.to_h { |player| [player, []] }
    ordered = cards.sort_by do |card|
      [players.count { |player| allowed.call(player, card) }, random.rand]
    end
    ordered.each do |card|
      eligible = players.select { |player| remaining.fetch(player, 0) > 0 && allowed.call(player, card) }
      return nil if eligible.empty?

      draw = random.rand(eligible.sum { |player| remaining.fetch(player) })
      selected = eligible.find { |player| (draw -= remaining.fetch(player)) < 0 }
      result[selected] << card
      remaining[selected] -= 1
    end
    remaining.values.any? { |count| count != 0 } ? nil : result
  end
end
