module GameRoomDicePokerHands
  module_function

  def rank(dice, variant)
    values = dice.map { |value| variant == "aces_high" && value == 1 ? 7 : value }
    groups = values.tally.sort_by { |value, count| [-count, -value] }
    counts = groups.map(&:last)
    category = case counts
    when [5] then 7
    when [4, 1] then 6
    when [3, 2] then 5
    when [3, 1, 1] then 3
    when [2, 2, 1] then 2
    when [2, 1, 1, 1] then 1
    else 0
    end
    if variant == "classic" && dice.uniq.size == 5 && dice.max - dice.min == 4
      return [4, dice.max]
    end
    [category] + groups.map(&:first)
  end
end
