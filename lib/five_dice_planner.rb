# Exact bounded look-ahead over sorted multisets, shared by five-dice games.
# The caller supplies only its own score sheet and public rules, never RNG.
class GameRoomFiveDicePlanner
  def initialize(&score)
    @score = score
    @rolls, @decisions = {}, {}
  end

  def roll_value(kept, remaining_rolls)
    key = [remaining_rolls, kept]
    return @rolls[key] if @rolls.key?(key)
    value = if kept.length == 5
      best_value(kept, remaining_rolls - 1)
    else
      (1..6).sum { |face| roll_value((kept + [face]).sort, remaining_rolls) } / 6.0
    end
    @rolls[key] = value
  end

  private

  def best_value(dice, remaining_rolls)
    key = [remaining_rolls, dice]
    return @decisions[key] if @decisions.key?(key)
    best = @score.call(dice, 3 - remaining_rolls) || -Float::INFINITY
    if remaining_rolls > 0
      subsets = [[]]
      dice.tally.each do |face, count|
        subsets = subsets.flat_map { |subset| (0..count).map { |number| subset + Array.new(number, face) } }
      end
      subsets.each do |kept|
        next if kept.length == 5
        best = [best, roll_value(kept, remaining_rolls)].max
      end
    end
    @decisions[key] = best
  end
end
