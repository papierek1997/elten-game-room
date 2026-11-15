require_relative "hearts_rules"

module GameRoomGames
  module HeartsBot
    module_function

    def pass(hand)
      hand.max_by(3) do |suit, rank|
        danger = suit == :spades && rank >= 12 ? 20 : 0
        [rank + danger, HeartsRules.penalty([suit, rank])]
      end
    end

    def play(legal, trick)
      return legal.min_by(&:last) if trick.empty?

      lead = trick.first.first
      return legal.max_by { |card| [HeartsRules.penalty(card), card.last] } if legal.none? { |card| card.first == lead }

      high = trick.select { |card| card.first == lead }.map(&:last).max
      below = legal.select { |card| card.last < high }
      return below.max_by(&:last) unless below.empty?
      return legal.max_by(&:last) if trick.size == 3 && trick.none? { |card| HeartsRules.penalty(card).positive? }

      legal.min_by(&:last)
    end
  end
end
