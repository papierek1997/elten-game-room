require_relative "hearts_round"

module GameRoomGames
  class HeartsMatch
    DIRECTIONS = %i[left right across hold].freeze
    attr_reader :round, :winner

    def initialize(target: 100)
      raise ArgumentError unless target.is_a?(Integer) && target.positive?
      @target = target
      @scores = Array.new(4, 0)
      @index = 0
    end

    def scores; @scores.dup; end

    def deal(deck)
      return false if @round || @winner
      @round = HeartsRound.new(deck, direction: DIRECTIONS[@index % 4])
      true
    end

    def pass(seat, cards)
      return false unless @round && !@winner
      @round.pass(seat, cards)
    end

    def play(seat, card)
      return false unless @round && !@winner && @round.play(seat, card)
      return true unless @round.phase == :finished
      @scores = @scores.zip(@round.penalties).map(&:sum)
      @round = nil
      @index += 1
      if @scores.max >= @target
        leaders = @scores.each_index.select { |seat| @scores[seat] == @scores.min }
        @winner = leaders.first if leaders.one?
      end
      true
    end
  end
end
