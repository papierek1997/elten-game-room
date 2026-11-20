# encoding: UTF-8
require_relative 'difficulty'

module GameRoomDarts
  module Scoring
    BOARD_LIMIT = 1_000
    SCORE_CURVE = Difficulty.profile('normal')[:score_curve]
    SECTORS = %w[east north_east north north_west west south_west south south_east].freeze
    module_function

    def on_board?(x, y)
      Math.sqrt(x.to_f * x.to_f + y.to_f * y.to_f) <= BOARD_LIMIT
    end

    def points(x, y, difficulty: 'normal')
      radius = Math.sqrt(x.to_i * x.to_i + y.to_i * y.to_i)
      return 0 if radius > BOARD_LIMIT
      return 100 if radius.zero?

      remaining = (BOARD_LIMIT - radius) / BOARD_LIMIT.to_f
      curve = Difficulty.profile(difficulty)[:score_curve]
      (100.0 * remaining**curve).round.clamp(1, 100)
    end

    def zone(x, y, difficulty: 'normal')
      score = points(x, y, difficulty: difficulty)
      score.zero? ? :outside : score
    end

    def sector(x, y)
      return :center if x.to_i.zero? && y.to_i.zero?

      angle = Math.atan2(y.to_f, x.to_f)
      index = ((angle + Math::PI / 8) / (Math::PI / 4)).floor % 8
      SECTORS[index].to_sym
    end

    def bounded_coordinate?(value)
      value.is_a?(Integer) && value.between?(-BOARD_LIMIT, BOARD_LIMIT)
    end
  end
end
