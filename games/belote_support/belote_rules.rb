require_relative 'belote_trick'

module GameRoomGames
  # Pure shared card rules; BeloteTable is the only state/round reducer.
  module BeloteRules
    SUITS = %i[clubs diamonds hearts spades].freeze
    DECK = SUITS.product((7..14).to_a).map(&:freeze).freeze

    def self.bid_choices(offered, passes)
      [:pass] + (passes < 4 ? [offered] : SUITS - [offered])
    end

    def self.legal(hand, trick, trump:, partner_winning:)
      return hand.dup if trick.empty?
      lead = trick.first.first
      follow = hand.select { |card| card.first == lead }
      trumps = hand.select { |card| card.first == trump }
      return follow unless follow.empty? || lead == trump
      return hand.dup if trumps.empty? || (lead != trump && partner_winning)
      highest = trick.select { |card| card.first == trump }.map { |card| BeloteTrick::TRUMP.index(card.last) }.max
      higher = highest ? trumps.select { |card| BeloteTrick::TRUMP.index(card.last) > highest } : trumps
      higher.empty? ? trumps : higher
    end
  end
end
