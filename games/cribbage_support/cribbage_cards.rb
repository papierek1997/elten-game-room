require_relative "../card_game"
require_relative "cribbage_bot"

module GameRoomGames
  module CribbageCards
    SUITS = %i[clubs diamonds hearts spades].zip(CardGame::CARD_SUITS).to_h.freeze
    RANKS = ["A", *CardGame::CARD_RANKS.take(12)].freeze
    ENCODED = CribbageBot::DECK.to_h do |card|
      rank, suit = card
      [card, (RANKS.fetch(rank - 1) + SUITS.fetch(suit)).freeze]
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
