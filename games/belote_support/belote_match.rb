require_relative "belote_deal"

module GameRoomGames
  class BeloteMatch
    attr_reader :round, :winner, :dealer, :carry

    def initialize(target: 1000)
      raise ArgumentError unless target.is_a?(Integer) && target.positive?
      @target = target
      @dealer = @carry = 0
      @scores = [0, 0]
    end

    def scores
      @scores.dup
    end

    def deal(deck)
      return false if @round || @winner
      @round = BeloteDeal.new(deck, dealer: @dealer)
      true
    end

    def bid(seat, choice)
      return false unless @round&.bid(seat, choice)
      next_dealer if @round.phase == :redeal
      true
    end

    def play(seat, card, announce: false)
      return false unless @round&.play(seat, card, announce: announce)
      if @round.phase == :finished
        settlement = @round.settlement(carry: @carry)
        @carry = settlement.fetch(:carry)
        @scores = @scores.zip(settlement.fetch(:scores)).map(&:sum)
        @winner = @scores.each_index.max_by { |team| @scores[team] } if @scores.max >= @target && @scores.uniq.size == 2
        next_dealer
      end
      true
    end

    private

    def next_dealer
      @round = nil
      @dealer = (@dealer + 1) % 4 unless @winner
    end
  end
end
