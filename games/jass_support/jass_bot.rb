require_relative "jass_round"

module GameRoomGames
  module JassBot
    module_function

    def bid(view)
      choices = view.fetch(:bids)
      suits = choices - [:pass]
      return if suits.empty?
      hand = view.fetch(:hand)
      values = suits.to_h do |suit|
        cards = hand.select { |card| card.first == suit }
        [suit, cards.sum { |_, rank| 2 + JassRound::TRUMP_ORDER.index(rank) }]
      end
      values[:high] = hand.sum { |_, rank| [rank - 11, 0].max * 3 } if suits.include?(:high)
      values[:low] = hand.sum { |_, rank| [9 - rank, 0].max * 3 } if suits.include?(:low)
      best = suits.max_by { |suit| values.fetch(suit) }
      choices.include?(:pass) && values.fetch(best) < 20 ? :pass : best
    end

    def play(view)
      cards = view.fetch(:legal_cards)
      trick = view.fetch(:trick)
      trump = view.fetch(:trump)
      return cards.max_by { |suit, rank| strength(suit, rank, trump) } if trick.empty?
      lead = trick.first.first
      best = trick.map { |suit, rank| strength(suit, rank, trump, lead) }.max
      winning = cards.select { |suit, rank| strength(suit, rank, trump, lead) > best }
      (winning.empty? ? cards : winning).min_by { |suit, rank| strength(suit, rank, trump, lead) }
    end

    def strength(suit, rank, trump, lead = suit)
      suit == trump ? 30 + JassRound::TRUMP_ORDER.index(rank) : suit == lead ? (trump == :low ? 15 - rank : rank) : 0
    end
  end
end
