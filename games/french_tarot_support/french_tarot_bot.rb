require_relative "french_tarot_scoring"
require_relative "french_tarot_trick"

module GameRoomGames
  module FrenchTarotBot
    module_function

    def bid(hand, choices)
      return :pass if choices == [:pass]
      trumps = hand.count { |suit, _| suit == :trump }
      strength = trumps * 2 + hand.count { |card| FrenchTarotScoring.oudler?(card) } * 6
      desired = if strength >= 30 then :garde_sans
                elsif strength >= 24 then :garde
                elsif strength >= 17 then :petite
                else :pass
                end
      choices.include?(desired) ? desired : :pass
    end

    def discard(hand)
      ordinary = hand.reject { |suit, rank| %i[trump excuse].include?(suit) || rank == 14 }
      trumps = hand.select { |card| card.first == :trump && !FrenchTarotScoring.oudler?(card) }
      (ordinary.sort_by(&:last) + trumps.sort_by(&:last)).first(6)
    end

    def play(legal, trick, taker:, seat:, leader:)
      return legal.min_by { |card| cost(card) } if trick.empty?
      current = FrenchTarotTrick.winner(trick)
      own_side = (seat == taker)
      allied = current && (((leader + current) % 4 == taker) == own_side)
      winners = legal.select { |card| FrenchTarotTrick.winner(trick + [card]) == trick.size }
      if allied
        losers = legal - winners
        return losers.max_by { |card| FrenchTarotScoring.half_points(card) - (FrenchTarotScoring.oudler?(card) ? 20 : 0) } unless losers.empty?
      end
      (winners.empty? ? legal : winners).min_by { |card| cost(card) }
    end

    def cost(card)
      suit, rank = card
      return 100 if FrenchTarotScoring.oudler?(card)
      suit == :trump ? 20 + rank : rank
    end
  end
end
