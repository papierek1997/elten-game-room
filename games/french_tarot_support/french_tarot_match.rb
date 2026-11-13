require_relative "french_tarot_round"

module GameRoomGames
  class FrenchTarotMatch
    attr_reader :dealer, :round, :completed_deals

    def initialize(deals: 4)
      raise ArgumentError unless deals.is_a?(Integer) && deals.positive?
      @limit = deals
      @dealer = @completed_deals = 0
      @scores = Array.new(4, 0)
    end

    def scores
      @scores.dup
    end

    def finished?
      @completed_deals >= @limit
    end

    def winners
      return unless finished?
      best = @scores.max
      @scores.each_index.select { |seat| @scores[seat] == best }
    end

    def deal(deck)
      return false if @round || finished?
      @round = FrenchTarotRound.new(deck, dealer: @dealer)
      true
    end

    def bid(seat, contract)
      return false unless @round&.bid(seat, contract)
      rotate_dealer if @round.phase == :redeal
      true
    end

    def discard(seat, cards)
      !!@round&.discard(seat, cards)
    end

    def play(seat, card)
      return false unless @round&.play(seat, card)
      if @round.phase == :finished
        @scores = @scores.zip(@round.contract_scores).map(&:sum)
        @completed_deals += 1
        rotate_dealer
      end
      true
    end

    private

    def rotate_dealer
      @round = nil
      @dealer = (@dealer + 1) % 4 unless finished?
    end
  end
end
