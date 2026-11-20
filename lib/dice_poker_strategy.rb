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
      @work = 0
    end

    def stand(dice)
      @holds[dice] ||= @utility.call(GameRoomDicePokerHands.rank(dice, @variant))
    end

    def roll(keep, throws)
      @rolls[[keep, throws]] ||= begin
        count = 5 - keep.size
        OUTCOMES.fetch(count).sum do |rolled, weight|
          dice = (keep + rolled).sort
          weight * (throws == 1 ? stand(dice) : decision(dice, throws - 1).last)
        end.fdiv(6**count)
      end
    end

    def decision(dice, remaining)
      @turns[[dice, remaining]] ||= begin
        @work += 1
        Thread.pass if (@work % 64).zero?
        keeps = (0...5).flat_map { |count| dice.combination(count).to_a.uniq }
        candidates = [[dice, stand(dice)]]
        candidates.concat(keeps.map { |keep| [keep, roll(keep, remaining)] }) if remaining.positive?
        candidates.max_by { |keep, value| [value, keep.length] }
      end
    end
  end

  # Public, bounded opponent model: optimise the percentile of the final
  # combination while retaining dice, rather than rerolling all five blindly.
  # This is a neutral policy estimate, not the opponents' actual hidden dice.
  def self.modeled_outcomes(variant, attempts)
    raise ArgumentError, 'Invalid public throw limit' unless attempts.is_a?(Integer) && attempts.between?(1, 3)
    return random_outcomes(variant) if attempts == 1

    @modeled_outcomes ||= {}
    @modeled_outcomes[[variant, attempts]] ||= begin
      base = random_outcomes(variant)
      plan = Plan.new(variant, ->(rank) { lower, equal = base.fetch(rank); lower + equal / 2 })
      hands = OUTCOMES.fetch(5).to_h { |dice, weight| [dice, weight.fdiv(6**5)] }
      (attempts - 1).downto(1) do |remaining|
        following = Hash.new(0.0)
        hands.each do |dice, probability|
          keep = plan.decision(dice, remaining).first
          count = 5 - keep.length
          OUTCOMES.fetch(count).each do |rolled, weight|
            following[(keep + rolled).sort] += probability * weight.fdiv(6**count)
          end
        end
        hands = following
        Thread.pass
      end
      weights = base.to_h { |rank, _| [rank, 0.0] }
      hands.each { |dice, probability| weights[GameRoomDicePokerHands.rank(dice, variant)] += probability }
      lower = 0.0
      weights.sort.to_h do |rank, probability|
        chance = [lower, probability].freeze
        lower += probability
        [rank.freeze, chance]
      end.freeze
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

  def self.contest_value(variant, known, pending, split_ties:, attempts: 1)
    best = known.max
    ties = known.count(best)
    distribution = modeled_outcomes(variant, attempts)
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

  def self.pot_value(variant, pots, actor, completed, attempts: 1)
    layers = pots.filter_map do |pot|
      next unless pot[:eligible].include?(actor)
      others = pot[:eligible] - [actor]
      known = others.filter_map { |player| completed[player] if completed.key?(player) }
      pending = others.count { |player| !completed.key?(player) }
      utility = contest_value(variant, known, pending, split_ties: true, attempts: attempts)
      [pot[:amount], utility]
    end
    ->(rank) { layers.sum { |amount, utility| amount * utility.call(rank) } }
  end
end
