require_relative "hearts_rules"

module GameRoomGames
  class HeartsRound
    DECK = %i[clubs diamonds hearts spades].product((2..14).to_a).map(&:freeze).freeze
    PASS = {left: 1, right: -1, across: 2, hold: 0}.freeze

    attr_reader :turn, :phase

    def initialize(deck, direction:)
      raise ArgumentError, "Invalid deck" unless deck.length == 52 && deck.uniq.size == 52 && (deck - DECK).empty?
      @offset = PASS.fetch(direction)
      @hands = deck.map { |card| card.dup.freeze }.each_slice(13).to_a
      @captured = Array.new(4) { [] }
      @passes = {}
      @trick = []
      @tricks = 0
      @broken = false
      @phase = :pass
      start_play if @offset.zero?
    end

    def hand(seat)
      @hands.fetch(seat).dup
    end

    def trick
      @trick.dup
    end

    def pass(seat, cards)
      return false unless @phase == :pass && (0..3).cover?(seat) && !@passes.key?(seat)
      return false unless cards.size == 3 && cards.uniq.size == 3 && (cards - @hands[seat]).empty?

      @passes[seat] = @hands[seat].select { |card| cards.include?(card) }
      if @passes.size == 4
        @hands = HeartsRules.exchange(@hands, @passes, @offset)
        @passes.clear
        start_play
      end
      true
    end

    def legal_cards(seat)
      return [] unless @phase == :play && seat == @turn
      HeartsRules.legal(@hands.fetch(seat), @trick, first_trick: @tricks.zero?, hearts_broken: @broken)
    end

    def play(seat, card)
      return false unless legal_cards(seat).include?(card)
      @trick << @hands[seat].delete(card)
      @broken ||= card.first == :hearts
      if @trick.size == 4
        winner = (@leader + HeartsRules.trick_winner(@trick)) % 4
        @captured[winner].concat(@trick)
        @trick.clear
        @tricks += 1
        @leader = @turn = winner
        if @tricks == 13
          @phase = :finished
          @turn = nil
        end
      else
        @turn = (@turn + 1) % 4
      end
      true
    end

    def penalties
      HeartsRules.settle(@captured) if @phase == :finished
    end

    private

    def start_play
      @leader = @turn = @hands.index { |hand| hand.include?([:clubs, 2]) }
      @phase = :play
    end
  end
end
