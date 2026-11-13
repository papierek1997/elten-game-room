module GameRoomGames
  module FrenchTarotScoring
    module_function

    # Use half-points so no binary floating point enters settlement.
    TARGET = [112, 102, 82, 72].freeze
    CONTRACTS = {petite: 1, garde: 2, garde_sans: 4, garde_contre: 6}.freeze

    def oudler?(card)
      suit, rank = card
      suit == :excuse || (suit == :trump && [1, 21].include?(rank))
    end

    def half_points(card)
      suit, rank = card
      return 9 if oudler?(card)
      return 1 if suit == :trump
      {14=>9, 13=>7, 12=>5, 11=>3}.fetch(rank, 1)
    end

    def contract_value(cards, contract)
      margin = cards.sum { |card| half_points(card) } - TARGET.fetch(cards.count { |card| oudler?(card) })
      sign = margin.negative? ? -1 : 1
      sign * (50 + margin.abs) * CONTRACTS.fetch(contract)
    end
  end
end
