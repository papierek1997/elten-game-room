require_relative "../card_game"
require_relative "belote_round"

module GameRoomGames
  module BeloteCards
    SUITS = BeloteRound::SUITS.zip(CardGame::CARD_SUITS).to_h.freeze
    RANKS = (2..14).zip(CardGame::CARD_RANKS).to_h.freeze
    ENCODED = BeloteRound::DECK.to_h do |card|
      suit, rank = card
      [card, (RANKS.fetch(rank) + SUITS.fetch(suit)).freeze]
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
