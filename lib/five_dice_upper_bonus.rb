require_relative 'five_dice_planner'

# Conditional school policy: target remaining faces from highest to lowest.
# A poor result may fill another remaining box instead, consuming one retry.
# Other boxes' points are deliberately not predicted here; their opportunity
# cost remains in the game's ordinary category valuation.
class GameRoomFiveDiceUpperBonus
  WIDTH = 106
  RETRIES = 11
  MAXIMUM = Array.new(64) { |mask|6.times.sum { |face| (mask & (1 << face)).positive? ? (face + 1) * 5 : 0 } }.freeze

  def initialize
    # Finite masks, upper-section points and the actual maximum ten other
    # boxes: no text keys or unbounded match history are retained.
    @values = Array.new(64 * WIDTH * RETRIES)
    @computed = 0
  end

  def probability(faces, needed, flexible)
    raise ArgumentError unless faces.is_a?(Array) && faces.uniq==faces && faces.all? { |face|face.is_a?(Integer) && face.between?(0,5) }
    raise ArgumentError unless needed.is_a?(Integer) && flexible.is_a?(Integer) && flexible.between?(0,10)
    estimate(faces.sum { |face|1 << face }, needed, flexible)
  end

  private

  def estimate(mask, needed, flexible)
    return 1.0 if needed <= 0
    return 0.0 if MAXIMUM.fetch(mask) < needed
    key = (mask * WIDTH + needed) * RETRIES + flexible
    cached = @values[key]
    return cached unless cached.nil?

    @computed += 1
    Thread.pass if (@computed % 256).zero?
    face = mask.bit_length - 1
    other = mask ^ (1 << face)
    retry_value = flexible.positive? ? estimate(mask, needed, flexible - 1) : 0.0
    value = GameRoomFiveDicePlanner::TARGET_COUNTS.each_with_index.sum do |chance, count|
      recorded = estimate(other, needed - count * (face + 1), flexible)
      chance * [recorded, retry_value].max
    end
    @values[key] = value.clamp(0.0,1.0)
  end
end
