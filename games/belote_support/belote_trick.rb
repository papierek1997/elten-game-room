module GameRoomGames
  module BeloteTrick
    module_function

    NORMAL = [7, 8, 9, 11, 12, 13, 10, 14].freeze
    TRUMP = [7, 8, 12, 13, 10, 14, 9, 11].freeze
    VALUES = {11 => 2, 12 => 3, 13 => 4, 10 => 10, 14 => 11}.freeze

    def winner(cards, trump)
      lead = cards.first.first
      cards.each_index.max_by do |index|
        suit, rank = cards.fetch(index)
        suit == trump ? [2, TRUMP.index(rank)] : [suit == lead ? 1 : 0, NORMAL.index(rank)]
      end
    end

    def points(cards, trump, last: false)
      cards.sum do |suit, rank|
        if suit == trump && rank == 11
          20
        elsif suit == trump && rank == 9
          14
        else
          VALUES.fetch(rank, 0)
        end
      end + (last ? 10 : 0)
    end
  end
end
