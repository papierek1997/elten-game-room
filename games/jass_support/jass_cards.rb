require_relative "jass_round"

module GameRoomGames
  module JassCards
    SUITS = {clubs: "C", diamonds: "D", hearts: "H", spades: "S"}.freeze
    RANKS = (6..14).zip(%w[6 7 8 9 T J Q K A]).to_h.freeze
    ENCODED = JassRound::DECK.to_h { |suit, rank| [[suit, rank].freeze, (RANKS.fetch(rank) + SUITS.fetch(suit)).freeze] }.freeze
    DECODED = ENCODED.invert.freeze
    DECK = ENCODED.values.freeze

    def self.encode(card); ENCODED.fetch(card); end
    def self.decode(value); DECODED.fetch(value); end
  end
end
