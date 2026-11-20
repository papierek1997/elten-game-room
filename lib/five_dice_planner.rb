# Exact bounded look-ahead over sorted multisets, shared by five-dice games.
# The caller supplies only its own score sheet and public rules, never RNG.
class GameRoomFiveDicePlanner
  # Five independent dice, retaining the target face through three throws.
  # This is a conditional policy distribution, never the live game's RNG.
  TARGET_COUNTS = [1, 5, 10, 10, 5, 1].each_with_index.map do |combinations, count|
    probability = 1.0 - (5.0 / 6)**3
    combinations * probability**count * (1 - probability)**(5 - count)
  end.freeze

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
    Thread.pass if (@decisions.length % 128).zero?
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
