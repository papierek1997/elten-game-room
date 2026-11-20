require_relative 'five_dice_planner'

# Exact final one/two entries. Games own legality, recording, bonuses and
# utility; this class owns only the finite three-roll expectation and reuse.
class GameRoomFiveDiceScoreTail
  attr_reader :future_evaluations

  def initialize(position:, choices:, record:, slots:, value:, identity:)
    @position, @choices, @record = position, choices, record
    @slots, @value, @identity = slots, value, identity
    @futures, @future_evaluations = {}, 0
    @turn = GameRoomFiveDicePlanner.new do |dice, rolls|
      @choices.call(@position, dice, rolls).filter_map { |choice| score_value(choice, dice, rolls) }.max
    end
  end

  def score_value(choice, dice, rolls)
    after = @record.call(@position, choice, dice, rolls)
    return nil unless after
    return @value.call(after) if @slots.call(after).zero?

    key = @identity.call(after)
    return @futures[key] if @futures.key?(key)
    # Retain scalars, not whole planners or replay/model branches.
    @futures.shift if @futures.size >= 256
    future = GameRoomFiveDicePlanner.new do |rolled, number|
      @choices.call(after, rolled, number).filter_map do |last|
        final = @record.call(after, last, rolled, number)
        @value.call(final) if final
      end.max
    end
    @future_evaluations += 1
    @futures[key] = future.roll_value([], 3)
  end

  def roll_value(kept, remaining)
    @turn.roll_value(kept, remaining)
  end
end
