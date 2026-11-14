require_relative "jass_round"

module GameRoomGames
  class JassMatch
    attr_reader :dealer, :round, :winner

    def initialize(target: 1000)
      raise ArgumentError unless [1000, 1500, 2000].include?(target)
      @target = target
      @dealer = 0
      @totals = [0, 0]
    end

    def scores
      @round ? @totals.zip(@round.scores).map(&:sum) : @totals.dup
    end

    def deal(deck)
      return false if @round || @winner
      @round = JassRound.new(deck, dealer: @dealer)
      true
    end

    def bid(seat, choice)
      !@winner && !!@round&.bid(seat, choice)
    end

    def play(seat, card)
      return false if @winner || !@round&.play(seat, card)
      current = scores
      @winner = current.index { |points| points >= @target }
      unless @round.turn || @winner
        @totals = current
        @round = nil
        @dealer = (@dealer + 1) % 4
      end
      true
    end
  end
end
