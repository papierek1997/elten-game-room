require_relative "cribbage_scoring"

module GameRoomGames
  module CribbageBot
    DECK = (1..13).to_a.product(%i[clubs diamonds hearts spades]).map(&:freeze).freeze
    module_function

    def discard(hand, dealer:)
      unseen = DECK - hand
      hand.combination(2).max_by do |cards|
        kept = hand - cards
        expected_hand = unseen.sum { |starter| CribbageScoring.hand(kept, starter) }
        ranks = cards.map(&:first)
        crib_hint = (ranks.uniq.one? ? 2 : 0) + (ranks.sum { |rank| [rank, 10].min } == 15 ? 2 : 0)
        expected_hand + (dealer ? 1 : -1) * crib_hint * unseen.size
      end
    end

    def play(legal, sequence)
      legal.max_by do |card|
        ranks = sequence + [card.first]
        total = ranks.sum { |rank| [rank, 10].min }
        [CribbageScoring.pegging(ranks), total == 5 || total == 21 ? -1 : 0, -card.first]
      end
    end
  end
end
