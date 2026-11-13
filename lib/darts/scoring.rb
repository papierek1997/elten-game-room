# encoding: UTF-8

module GameRoomDarts
  module Scoring
    BOARD_LIMIT = 1_000
    ZONES = [
      [180, 100],
      [380, 75],
      [650, 50],
      [1_000, 25]
    ].freeze
    SECTORS = %w[east north_east north north_west west south_west south south_east].freeze
    module_function

    def points(x, y)
      radius = Math.sqrt(x.to_i * x.to_i + y.to_i * y.to_i)
      ZONES.each do |limit, score|
        return score if radius <= limit
      end
      0
    end

    def zone(x, y)
      score = points(x, y)
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
