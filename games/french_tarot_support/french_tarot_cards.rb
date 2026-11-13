require_relative "../card_game"
require_relative "french_tarot_round"

module GameRoomGames
  module FrenchTarotCards
    SUITS = %i[clubs diamonds hearts spades].zip(CardGame::CARD_SUITS).to_h.freeze
    RANKS = %w[A 2 3 4 5 6 7 8 9 T J N Q K].freeze
    ENCODED = FrenchTarotRound::DECK.to_h do |card|
      suit, rank = card
      value = case suit
      when :excuse then "EX"
      when :trump then "#{rank}X"
      else RANKS.fetch(rank - 1) + SUITS.fetch(suit)
      end
      [card, value.freeze]
    end.freeze
    DECODED = ENCODED.invert.freeze
    DECK = ENCODED.values.freeze

    def self.encode(card)
      ENCODED.fetch(card)
    end

    def self.decode(value)
      DECODED.fetch(value)
    end
  end
end
