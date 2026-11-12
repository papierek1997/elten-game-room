require_relative "dice_poker_hands"

module GameRoomDicePokerStrategy
  OUTCOMES = (0..5).map do |count|
    (1..6).to_a.repeated_combination(count).map do |dice|
      weight = (1..count).reduce(1, :*) / dice.tally.values.map { |n| (1..n).reduce(1, :*) }.reduce(1, :*)
      [dice.freeze, weight].freeze
    end.freeze
  end.freeze

  class Plan
    def initialize(variant, utility)
      @variant, @utility = variant, utility
      @holds, @rolls, @turns = {}, {}, {}
    end

    def stand(dice)
      @holds[dice] ||= @utility.call(GameRoomDicePokerHands.rank(dice, @variant))
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

    def final_decision(dice)
      @turns[dice] ||= begin
        keeps = (0...5).flat_map { |count| dice.combination(count).to_a.uniq }
        [stand(dice), keeps.map { |keep| roll(keep, 1) }.max].max
      end
    end
  end

  # Later players use the existing generic five-die model, never future rolls.
  # Keep strict-lower and equal probabilities separate: a point tie is a whole
  # point, whereas a chip tie divides the pot among every tied eligible player.
  def self.random_outcomes(variant)
    @random_outcomes ||= {}
    @random_outcomes[variant] ||= begin
      weights = Hash.new(0)
      OUTCOMES.fetch(5).each { |dice, weight| weights[GameRoomDicePokerHands.rank(dice, variant)] += weight }
      lower = 0
      weights.sort.to_h do |rank, weight|
        chance = [lower.fdiv(6**5), weight.fdiv(6**5)].freeze
        lower += weight
        [rank.freeze, chance]
      end.freeze
    end
  end

  def self.contest_value(variant, known, pending, split_ties:)
    best = known.max
    ties = known.count(best)
    distribution = random_outcomes(variant)
    lambda do |rank|
      next 0.0 if best && (rank <=> best) < 0
      below, equal = distribution.fetch(rank)
      next (below + equal)**pending unless split_ties

      prior_ties = rank == best ? ties : 0
      coefficient = 1
      (0..pending).sum do |tied|
        share = coefficient * equal**tied * below**(pending - tied) / (1 + prior_ties + tied)
        coefficient = coefficient * (pending - tied) / (tied + 1)
        share
      end
    end
  end

  def self.pot_value(variant, pots, actor, completed)
    layers = pots.filter_map do |pot|
      next unless pot[:eligible].include?(actor)
      others = pot[:eligible] - [actor]
      known = others.filter_map { |player| completed[player] if completed.key?(player) }
      pending = others.count { |player| !completed.key?(player) }
      utility = contest_value(variant, known, pending, split_ties: true)
      [pot[:amount], utility]
    end
    ->(rank) { layers.sum { |amount, utility| amount * utility.call(rank) } }
  end
end
