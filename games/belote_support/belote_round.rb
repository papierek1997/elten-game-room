require_relative "belote_trick"

module GameRoomGames
  class BeloteRound
    SUITS = %i[clubs diamonds hearts spades].freeze
    DECK = SUITS.product((7..14).to_a).map(&:freeze).freeze
    attr_reader :turn

    def initialize(deck, trump:, leader:)
      raise ArgumentError unless deck.size == 32 && deck.uniq.size == 32 && (deck - DECK).empty?
      raise ArgumentError unless SUITS.include?(trump) && [0, 1, 2, 3].include?(leader)
      @hands = deck.map { |card| card.dup.freeze }.each_slice(8).to_a
      @trump, @leader, @turn = trump, leader, leader
      @trick, @scores = [], [0, 0]
      @completed = 0
    end

    def hand(seat); @hands.fetch(seat).dup; end

    def scores
      @scores.dup
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

    def legal_cards(seat)
      return [] unless @turn && seat == @turn
      partner_winning = !@trick.empty? && (@leader + BeloteTrick.winner(@trick, @trump)) % 4 == (seat + 2) % 4
      self.class.legal(@hands[seat], @trick, trump: @trump, partner_winning: partner_winning)
    end

    def play(seat, card)
      return false unless legal_cards(seat).include?(card)
      @trick << @hands[seat].delete(card)
      if @trick.size == 4
        @leader = (@leader + BeloteTrick.winner(@trick, @trump)) % 4
        @completed += 1
        @scores[@leader % 2] += BeloteTrick.points(@trick, @trump, last: @completed == 8)
        @trick.clear
        @turn = @completed == 8 ? nil : @leader
      else
        @turn = (seat + 1) % 4
      end
      true
    end
  end
end
