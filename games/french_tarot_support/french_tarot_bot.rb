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

    def discard(hand, count: 6)
      ordinary = hand.reject { |suit, rank| %i[trump excuse].include?(suit) || rank == 14 }
      trumps = hand.select { |card| card.first == :trump && !FrenchTarotScoring.oudler?(card) }
      return ordinary + trumps.sort_by(&:last).first(count - ordinary.size) if ordinary.size <= count

      plans = {0 => [0.0, []]}
      ordinary.group_by(&:first).each do |suit, cards|
        # Discards go into declarer's scoring pile. Banking an unprotected
        # court card is useful; treating its points as a discard penalty
        # instead leaves it in hand to be lost to a defender's trump.
        discard_cost = ->(card) { -FrenchTarotScoring.half_points(card) + card.last * 0.15 }
        ordered = cards.sort_by(&discard_cost)
        following = {}
        plans.each do |used, (value, chosen)|
          0.upto([count - used, cards.size].min) do |number|
            outgoing = ordered.first(number)
            retained = hand.count { |card| card.first == suit } - number
            cost = outgoing.sum(&discard_cost)
            cost -= 6 if retained.zero? && trumps.size >= 7
            candidate = [value + cost, chosen + outgoing]
            index = used + number
            following[index] = candidate if !following.key?(index) || candidate.first < following[index].first
          end
        end
        plans = following
      end
      plans.fetch(count).last
    end

    def play(legal, trick, taker:, seat:, leader:, hand: legal)
      return legal.min_by { |card| cost(card) } if trick.empty?
      current = FrenchTarotTrick.winner(trick)
      own_side = (seat == taker)
      allied = current && (((leader + current) % 4 == taker) == own_side)
      winners = legal.select { |card| FrenchTarotTrick.winner(trick + [card]) == trick.size }
      excuse = legal.find { |card| card.first == :excuse }
      cheapest = legal.reject { |card| card.first == :excuse }.map { |card| cost(card) }.min.to_i
      return excuse if excuse && hand.size > 1 && !allied && winners.empty? && (hand.size <= 3 || cheapest >= 12)
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
