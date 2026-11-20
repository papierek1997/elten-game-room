# frozen_string_literal: true

require_relative "numeric_challenges"

module GameRoomDuckRacing
  # Only accepts NumericChallenges.public_view and public race facts. This
  # selector has no access to the challenge model, seed, answer or future deck.
  # The ordinary executor supplies the reaction delay and input identity.
  module NumericBot
    REACTION_MS = {
      "rock_paper_scissors" => 650, "dice_duel" => 650,
      "blackjack" => 900, "risky_dice" => 900,
      "guess_number" => 1_300, "copy_number" => 1_400,
      "arithmetic" => 1_800, "race_question" => 1_500,
      "numbered_balls" => 1_100
    }.freeze

    module_function

    # The shared scheduler can combine this with its normal bot delay. There
    # is no timer here, and invoking the selector does not itself make a move.
    def reaction_ms(view)
      REACTION_MS.fetch(view.fetch(:type))
    end

    # Returns a proposal, not an accepted move. The adapter adds a press_id
    # and revalidates the current challenge/seat before its ordinary write.
    def choose(view, seat:, random:, race_snapshot: nil)
      return nil if view[:finished] || !view.fetch(:participants).include?(seat)
      own = view[:own]
      return nil unless own && !own[:done]
      return nil if NumericChallenges::TURN_TYPES.include?(view[:type]) && view[:turn_seat] != seat

      case view[:type]
      when "rock_paper_scissors"
        {kind: :choose, value: NumericChallenges::CHOICES.fetch(random.rand(3))}
      when "dice_duel"
        {kind: :roll}
      when "blackjack"
        {kind: ceiling_decision(view, seat) ? :hit : :stand}
      when "risky_dice"
        {kind: own.fetch(:rolls).empty? || ceiling_decision(view, seat) ? :roll : :save}
      when "guess_number"
        guess_number(own, view.fetch(:answer_digits), random)
      when "copy_number", "arithmetic", "race_question"
        answer_question(view, random, race_snapshot)
      when "numbered_balls"
        count = best_ball_counts(view.fetch(:remaining))
        count.empty? ? nil : {kind: :take, value: count.fetch(random.rand(count.length))}
      end
    end

    # A bounded total-state expectation, not a view of the shuffled deck.
    # Only already public finished attempts can alter the rival model.
    def ceiling_decision(view, seat)
      own = view.fetch(:own)
      cards = view[:type] == "blackjack"
      limit, threshold = cards ? [21, 17] : [25, 19]
      draws = if cards
        counts = (1..13).to_h { |rank| [rank, 4] }
        own.fetch(:cards).each { |card| counts[card / 4 + 1] -= 1 }
        counts.reject { |_rank, count| count.zero? }
      else
        (1..own.fetch(:die).fetch(:die_sides)).to_h { |value| [value, 1] }
      end
      value_of = ->(rank, total) { cards && rank == 1 ? (total + 11 <= limit ? 11 : 1) : (cards ? [rank, 10].min : rank) }
      # Undecided opponents follow a neutral stopping model. Their unknown
      # cards are never read, and the expectation is not claimed to be exact.
      unknown_draws = cards ? (1..13).to_h { |rank| [rank, 4] } : (1..6).to_h { |value| [value, 1] }
      distributions = {}
      distribution = lambda do |total|
        next distributions[total] if distributions.key?(total)
        next distributions[total] = {total => 1.0} if total >= threshold
        result = Hash.new(0.0)
        unknown_draws.each do |rank, weight|
          distribution.call(total + value_of.call(rank, total)).each do |score, probability|
            result[score] += probability * weight.fdiv(unknown_draws.values.sum)
          end
        end
        distributions[total] = result
      end
      completed = view.fetch(:completed_totals, {})
      opponents = (view.fetch(:participants) - [seat]).map do |other|
        completed.key?(other) ? {completed.fetch(other) => 1.0} : distribution.call(0)
      end
      utility = lambda do |total|
        gain = -[total - limit, 0].max.to_f
        if total <= limit
          lower = opponents.map { |dist| dist.sum { |score, probability| score > limit || score < total ? probability : 0.0 } }
          opponents.each_with_index do |dist, index|
            amount = dist.sum { |score, probability| score > limit || score < total ? (total - score).abs * probability : 0.0 }
            gain += amount * lower.each_with_index.reduce(1.0) { |product, (probability, other)| other == index ? product : product * probability }
          end
        end
        opponents.each_with_index do |dist, index|
          dist.each do |score, probability|
            next if score > limit || total <= limit && score <= total
            chance = opponents.each_with_index.reduce(probability) do |product, (other, other_index)|
              next product if other_index == index
              product * other.sum { |value, p| value > limit || value < score ? p : 0.0 }
            end
            gain -= (total - score).abs * chance
          end
        end
        gain
      end
      values = {}
      best = lambda do |total|
        next values[total] if values.key?(total)
        stand = utility.call(total)
        next values[total] = stand if total >= limit
        roll = draws.sum { |rank, weight| weight * best.call(total + value_of.call(rank, total)) }.fdiv(draws.values.sum)
        values[total] = [stand, roll].max
      end
      total = own.fetch(:total)
      roll = draws.sum { |rank, weight| weight * best.call(total + value_of.call(rank, total)) }.fdiv(draws.values.sum)
      roll > utility.call(total) + 1e-9
    end
    private_class_method :ceiling_decision

    def guess_number(own, digits, random)
      raise ArgumentError, 'Invalid public guess width' unless digits.is_a?(Integer) && digits.between?(1, 3)
      # The width is announced to every participant, not a hidden answer.
      # Start in that public interval instead of wasting attempts outside it.
      low, high = 10**(digits - 1), 10**digits - 1
      own.fetch(:attempts).each do |attempt|
        case attempt[:feedback]
        when :higher then low = [low, attempt.fetch(:value) + 1].max
        when :lower then high = [high, attempt.fetch(:value) - 1].min
        when :correct then return nil
        end
      end
      return nil if low > high

      midpoint = (low + high) / 2
      midpoint += random.rand(2) if (low + high).odd?
      {kind: :answer, value: midpoint}
    end
    private_class_method :guess_number

    def answer_question(view, random, snapshot)
      question = view.fetch(:question)
      answer = case question[:kind]
      when :copy_number
        question.fetch(:number)
      when :arithmetic
        left, right = question.values_at(:left, :right)
        case question[:operation]
        when :add then left + right
        when :subtract then left - right
        when :multiply then left * right
        when :divide then left / right
        end
      when :race_question
        return nil unless snapshot
        racer = snapshot.fetch(:racers).fetch(question.fetch(:seat))
        case question[:field]
        when :square then racer.fetch(:progress) % snapshot.fetch(:board_length) + 1
        when :lap then racer.fetch(:progress) / snapshot.fetch(:board_length) + 1
        when :feathers then racer.fetch(:feathers)
        when :card_count then racer.fetch(:card_count)
        end
      end
      return nil unless answer.is_a?(Integer)

      # Mistakes are bounded and belong to the first try; later input uses
      # the visible stimulus again, never a leaked hidden correct answer.
      error_percent = view[:type] == "arithmetic" ? 10 : 4
      if view[:own].fetch(:attempts).empty? && random.rand(100) < error_percent
        answer += (random.rand(3) + 1) * (random.rand(2).zero? ? -1 : 1)
      end
      {kind: :answer, value: answer}
    end
    private_class_method :answer_question

    # At most twelve visible balls. Dynamic programming maximises the final
    # score difference against the opponent without exponential tree growth.
    def best_ball_counts(balls)
      return [] if balls.empty?

      best = Array.new(balls.length + 1, 0)
      choices = []
      (balls.length - 1).downto(0) do |index|
        sum = 0
        candidates = {}
        1.upto([3, balls.length - index].min) do |count|
          sum += balls[index + count - 1]
          candidates[count] = sum - best[index + count]
        end
        best[index] = candidates.values.max
        choices = candidates.select { |_count, value| value == best[index] }.keys if index.zero?
      end
      choices
    end
    private_class_method :best_ball_counts
  end
end
