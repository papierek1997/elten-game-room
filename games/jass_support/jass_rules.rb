module GameRoomGames
  # Stateless rules used by the production table and its bot.
  module JassRules
    SUITS = %i[clubs diamonds hearts spades].freeze
    DECK = SUITS.product((6..14).to_a).map(&:freeze).freeze
    TRUMP_ORDER = [6, 7, 8, 10, 12, 13, 14, 9, 11].freeze
    VALUES = {10 => 10, 11 => 2, 12 => 3, 13 => 4, 14 => 11}.freeze

    def self.legal(cards, trick, trump)
      return cards.dup if trick.empty?
      lead = trick.first.first
      follow = cards.select { |suit, _| suit == lead }
      return follow.empty? ? cards.dup : follow if lead == trump
      candidates = follow.empty? ? cards : cards.select { |suit, _| suit == lead || suit == trump }
      highest = trick.filter_map { |suit, rank| TRUMP_ORDER.index(rank) if suit == trump }.max
      return candidates.dup unless highest
      allowed = candidates.reject { |suit, rank| suit == trump && TRUMP_ORDER.index(rank) < highest }
      allowed.empty? ? candidates.dup : allowed
    end

    def self.settle_trick(trick, trump, last: false)
      lead = trick.first.first
      winner = trick.each_index.max_by do |index|
        suit, rank = trick.fetch(index)
        suit == trump ? [2, TRUMP_ORDER.index(rank)] : [suit == lead ? 1 : 0, trump == :low ? -rank : rank]
      end
      points = trick.sum do |suit, rank|
        if suit == trump && rank == 11
          20
        elsif suit == trump && rank == 9
          14
        elsif trump == :low && rank == 6
          11
        elsif trump == :low && rank == 14
          0
        elsif %i[high low].include?(trump) && rank == 8
          8
        else
          VALUES.fetch(rank, 0)
        end
      end
      [winner, points + (last ? 5 : 0)]
    end
  end
end
