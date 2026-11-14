require_relative "french_tarot_scoring"
require_relative "french_tarot_trick"

module GameRoomGames
  module FrenchTarotBot
    module_function

    def bid(hand, choices)
      return :pass if choices == [:pass]
      trumps = hand.count { |suit, _| suit == :trump }
      oudlers = hand.count { |card| FrenchTarotScoring.oudler?(card) }
      kings = hand.count { |suit, rank| suit != :trump && rank == 14 }
      high_trumps = hand.count { |suit, rank| suit == :trump && rank >= 16 }
      strength = trumps * 2 + oudlers * 6 + kings * 2 + high_trumps
      desired = if oudlers >= 2 && trumps >= 12 && strength >= 47 then :garde_contre
                elsif oudlers >= 2 && trumps >= 8 && strength >= 34 then :garde_sans
                elsif oudlers >= 1 && trumps >= 5 && strength >= 26 then :garde
                elsif trumps >= 4 && strength >= 20 then :petite
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
        unless losers.empty?
          # A defender's current high card is not a secured allied trick while
          # declarer still has to play. Do not donate a king to a likely trump.
          taker_played = (taker - leader) % 4 < trick.length
          return losers.min_by { |card| cost(card) } unless taker_played
          return losers.max_by { |card| FrenchTarotScoring.half_points(card) - (FrenchTarotScoring.oudler?(card) ? 20 : 0) }
        end
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
