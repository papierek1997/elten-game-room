module GameRoomTwentyOneStrategy
  CARDS = (1..10).to_h { |value| [value, value == 10 ? 4 : 1] }.freeze
  ONE_DIE = (1..6).to_h { |value| [value, 1] }.freeze
  TWO_DICE = ONE_DIE.keys.product(ONE_DIE.keys).map(&:sum).tally.freeze
  BUST = 22

  module_function

  def total(hard, ace)
    hard + (ace && hard <= 11 ? 10 : 0)
  end

  def average(weights)
    weights.sum { |value, weight| weight * yield(value) }.fdiv(weights.values.sum)
  end

  def card_dealer(upcard)
    holes = CARDS.reject { |value, _| (upcard == 1 && value == 10) || (upcard == 10 && value == 1) }
    @card_dealers ||= {}
    @card_dealers[upcard] ||= distribution(holes) do |value|
      terminal_distribution(upcard + value, upcard == 1 || value == 1, {}) { CARDS }
    end
  end

  def card_opponent
    @card_opponent ||= terminal_distribution(0, false, {}) { CARDS }
  end

  def dice_opponent(two_dice)
    @dice_opponents ||= {}
    @dice_opponents[two_dice] ||= terminal_distribution(0, false, {}, cards: false) do |sum|
      dice_weights(two_dice, sum)
    end
  end

  def dice_weights(two_dice, sum)
    two_dice && sum < 16 ? TWO_DICE : ONE_DIE
  end

  def terminal_distribution(hard, ace, memo, cards: true, &draws)
    memo[[hard, ace]] ||= begin
      sum = total(hard, ace)
      if sum >= 17
        { [sum, BUST].min => 1.0 }
      else
        distribution(draws.call(sum)) do |value|
          terminal_distribution(hard + value, ace || (cards && value == 1), memo, cards: cards, &draws)
        end
      end
    end
  end

  def distribution(weights)
    result = Hash.new(0.0)
    denominator = weights.values.sum.to_f
    weights.each do |value, weight|
      yield(value).each { |score, chance| result[score] += chance * weight / denominator }
    end
    result
  end

  # Probability of beating still-unresolved opponents, using a generic stand-at-17
  # opponent. Completed turns are public; no future card or roll is inspected.
  def contest_value(known, remaining, opponent, split_ties:, bonus: 0.0)
    best = known.reject { |value| value > 21 }.max || 0
    ties = best.zero? ? 0 : known.count(best)
    lambda do |sum|
      next 0.0 if sum < best || sum > 21
      below = opponent.sum { |value, probability| (value == BUST || value < sum) ? probability : 0.0 }
      equal = opponent.fetch(sum, 0.0)
      if split_ties
        prior_ties = sum == best ? ties : 0
        # Average the share of the pool, not the number of opponents tied.
        coefficient = 1
        (0..remaining).sum do |tied|
          term = coefficient * equal**tied * below**(remaining - tied) / (1 + prior_ties + tied)
          coefficient = coefficient * (remaining - tied) / (tied + 1)
          term
        end
      else
        sum > best ? below**remaining * (sum == 21 ? 1 + bonus : 1) : 0.0
      end
    end
  end

  class Plan
    def initialize(stand_value, bust_value: 0, cards: true, &draws)
      @stand_value, @bust_value, @cards, @draws = stand_value, bust_value, cards, draws
      @optimal = {}
    end

    def stand(hard, ace)
      sum = GameRoomTwentyOneStrategy.total(hard, ace)
      sum > 21 ? @bust_value : @stand_value.call(sum)
    end

    def draw(hard, ace, stop: false)
      GameRoomTwentyOneStrategy.average(@draws.call(GameRoomTwentyOneStrategy.total(hard, ace))) do |value|
        next_ace = ace || (@cards && value == 1)
        stop ? stand(hard + value, next_ace) : optimal(hard + value, next_ace)
      end
    end

    def optimal(hard, ace)
      @optimal[[hard, ace]] ||= begin
        hold = stand(hard, ace)
        GameRoomTwentyOneStrategy.total(hard, ace) >= 21 ? hold : [hold, draw(hard, ace)].max
      end
    end
  end
end
