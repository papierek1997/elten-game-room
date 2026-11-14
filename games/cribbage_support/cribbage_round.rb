require_relative "cribbage_scoring"

module GameRoomGames
  class CribbageRound
    attr_reader :dealer, :turn, :phase, :starter

    def initialize(deck, dealer:)
      expected = (1..13).to_a.product(%i[clubs diamonds hearts spades])
      raise ArgumentError unless deck.size == 52 && (deck - expected).empty? && deck.uniq.size == 52
      raise ArgumentError unless [0, 1].include?(dealer)
      @dealer = dealer
      @turn = 1 - dealer
      @phase = :discard
      @hands = [[], []]
      12.times { |index| @hands[(index + @turn) % 2] << deck[index].dup.freeze }
      @starter = deck[12].dup.freeze
      @crib, @sequence = [], []
      @points = [0, 0]
      @last = nil
    end

    def points
      @points.dup
    end

    def hand(player)
      @hands.fetch(player).dup
    end

    # A discard can travel as two receipt positions without exposing ranks.
    # The caller must preserve native receipt order when constructing the hand.
    def discard_slots(player, slots)
      return false unless @phase == :discard && player == @turn
      return false unless self.class.valid_discard_slots?(slots, @hands[player].size)

      discard(player, @hands[player].values_at(*slots))
    end

    def self.valid_discard_slots?(slots, hand_size)
      slots.is_a?(Array) && slots.size == 2 && slots.uniq.size == 2 &&
        slots.all? { |index| index.is_a?(Integer) && index.between?(0, hand_size - 1) }
    end

    def discard(player, cards)
      return false unless @phase == :discard && player == @turn
      return false unless cards.size == 2 && cards.uniq.size == 2 && (cards - @hands[player]).empty?
      @crib.concat(@hands[player].select { |card| cards.include?(card) })
      @hands[player] -= cards
      @turn = 1 - player
      if @crib.size == 4
        @points[@dealer] += 2 if @starter.first == 11
        @remaining = @hands.map(&:dup)
        @phase = :play
      end
      true
    end

    def sequence; @sequence.dup; end

    def playable(player)
      return [] unless @phase == :play
      @remaining.fetch(player).select { |card| CribbageScoring.pegging(@sequence + [card.first]) }
    end

    def play(player, card, &on_award)
      return false unless player == @turn && playable(player).include?(card)
      @remaining[player].delete(card)
      @sequence << card.first
      return true if award(player, CribbageScoring.pegging(@sequence), &on_award)
      @last = player
      other = 1 - player
      exact = @sequence.sum { |rank| [rank, 10].min } == 31
      if !exact && !playable(other).empty?
        @turn = other
      elsif !exact && !playable(player).empty?
        @turn = player
      else
        return true if !exact && award(@last, 1, &on_award)
        @sequence.clear
        @turn = @remaining[other].empty? ? player : other
        @phase = :count if @remaining.all?(&:empty?)
      end
      true
    end

    def award(player, points)
      @points[player] += points
      return false unless block_given? && points.positive?
      return false unless yield(player, points)
      @phase = :finished
      @turn = nil
      true
    end
    private :award

    def count_entries
      return [] unless @phase == :count
      other = 1 - @dealer
      [[other, CribbageScoring.hand(@hands[other], @starter)],
       [@dealer, CribbageScoring.hand(@hands[@dealer], @starter)],
       [@dealer, CribbageScoring.hand(@crib, @starter, crib: true)]]
    end
  end
end
