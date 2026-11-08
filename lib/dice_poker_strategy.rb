require_relative "dice_poker_hands"

module GameRoomDicePokerStrategy
  OUTCOMES = (0..5).map do |count|
    (1..6).to_a.repeated_combination(count).map do |dice|
      weight = (1..count).reduce(1, :*) / dice.tally.values.map { |n| (1..n).reduce(1, :*) }.reduce(1, :*)
      [dice.freeze, weight].freeze
    end.freeze
  end.freeze

  class Plan
    def initialize(variant, best, pending)
      @variant, @best, @pending = variant, best, pending
      @holds, @rolls, @turns = {}, {}, {}
    end

    def stand(dice)
      @holds[dice] ||= begin
        rank = GameRoomDicePokerHands.rank(dice, @variant)
        comparison = @best ? (rank <=> @best) : 1
        if comparison < 0
          0.0
        else
          share = comparison.zero? ? 0.5 : 1.0
          share * (@pending.zero? ? 1 : strength(rank)**@pending)
        end
      end
    end

    def roll(keep, throws)
      @rolls[[keep, throws]] ||= begin
        count = 5 - keep.size
        OUTCOMES.fetch(count).sum do |rolled, weight|
          dice = (keep + rolled).sort
          weight * (throws == 1 ? stand(dice) : final_decision(dice))
        end.fdiv(6**count)
      end
    end

    private

    # When later players haven't rolled, use a fixed model of an unknown
    # five-die hand. The strongest already completed hand is known exactly.
    def strength(rank)
      distribution = GameRoomDicePokerStrategy.random_strengths(@variant)
      distribution.fetch(rank)
    end

    def final_decision(dice)
      @turns[dice] ||= begin
        keeps = (0...5).flat_map { |count| dice.combination(count).to_a.uniq }
        [stand(dice), keeps.map { |keep| roll(keep, 1) }.max].max
      end
    end
  end

  def self.random_strengths(variant)
    @random_strengths ||= {}
    @random_strengths[variant] ||= begin
      weights = Hash.new(0)
      OUTCOMES.fetch(5).each { |dice, weight| weights[GameRoomDicePokerHands.rank(dice, variant)] += weight }
      lower = 0
      weights.sort.to_h do |rank, weight|
        chance = (lower + weight / 2.0) / (6**5)
        lower += weight
        [rank, chance]
      end.freeze
    end
  end
end
