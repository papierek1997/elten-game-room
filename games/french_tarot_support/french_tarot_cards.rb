require_relative "../card_game"

module GameRoomGames
  module FrenchTarotCards
    SUITS = %i[clubs diamonds hearts spades].zip(CardGame::CARD_SUITS).to_h.freeze
    RANKS = %w[A 2 3 4 5 6 7 8 9 T J N Q K].freeze
    CARDS = (%i[clubs diamonds hearts spades].product((1..14).to_a) +
      [:trump].product((1..21).to_a) + [[:excuse, 0]]).map(&:freeze).freeze
    ENCODED = CARDS.to_h do |card|
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
