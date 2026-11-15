require_relative "cribbage_round"

module GameRoomGames
  class CribbageMatch
    attr_reader :round, :winner

    def initialize(target: 121)
      raise ArgumentError unless [61, 91, 121, 241].include?(target)
      @target = target
      @dealer = 0
      @scores = [0, 0]
      @awarded = [0, 0]
    end

    def scores
      @scores.dup
    end

    def deal(deck)
      return false if @winner || @round
      @round = CribbageRound.new(deck, dealer: @dealer)
      @awarded = [0, 0]
      true
    end

    def discard(player, cards)
      return false if @winner || !@round || !@round.discard(player, cards)
      settle_play
      true
    end

    def discard_slots(player, slots)
      return false if @winner || !@round || !@round.discard_slots(player, slots)
      settle_play
      true
    end

    def play(player, card)
      return false if @winner || !@round
      return false unless @round.play(player, card) do |seat, points|
        award(seat, points)
        !@winner.nil?
      end
      if !@winner && @round.phase == :count
        @round.count_entries.each do |seat, points|
          award(seat, points)
          break if @winner
        end
        unless @winner
          @round = nil
          @dealer = 1 - @dealer
        end
      end
      true
    end

    private

    def settle_play
      @round.points.each_with_index do |points, seat|
        award(seat, points - @awarded[seat])
        @awarded[seat] = points
      end
    end

    def award(seat, points)
      return if @winner
      @scores[seat] += points
      @winner = seat if @scores[seat] >= @target
    end
  end
end
