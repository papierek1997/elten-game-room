# frozen_string_literal: true

module GameRoomDuckRacing
  module Settlement
    Transfer = Data.define(:from, :to, :amount)
    Result = Data.define(:winner, :balances, :transfers, :burned, :grants, :outcome)

    module_function

    # A ceiling adds blackjack/risky-dice bust rules. The best valid total
    # wins; busted totals pay the absolute difference, then burn their excess.
    def difference(balances:, scores:, ceiling: nil, eligible: balances.keys, max_transfer: nil)
      validate_scores!(balances, scores) { |score| score.is_a?(Integer) }
      validate_eligible!(balances, eligible)
      raise ArgumentError, "Invalid score ceiling" unless ceiling.nil? || (ceiling.is_a?(Integer) && ceiling.positive?)
      unless max_transfer.nil? || (max_transfer.is_a?(Integer) && max_transfer >= 0)
        raise ArgumentError, "Invalid feather transfer limit"
      end

      valid = scores.select { |seat, score| eligible.include?(seat) && (ceiling.nil? || score <= ceiling) }
      winner = unique_best(valid, higher: true)
      penalties = ceiling ? scores.transform_values { |score| [score - ceiling, 0].max } : {}
      settle(balances, winner, penalties: penalties, draw: winner.nil? && valid.length > 1) do |loser|
        amount = (scores.fetch(winner) - scores.fetch(loser)).abs
        max_transfer.nil? ? amount : [amount, max_transfer].min
      end
    end

    # Compare exact fractions. Display rounding must not break a tie or turn
    # a small positive advantage into zero feathers.
    def accuracy(balances:, percentages:, eligible: balances.keys)
      validate_scores!(balances, percentages) do |score|
        (score.is_a?(Integer) || score.is_a?(Rational)) && score.between?(0, 100)
      end
      validate_eligible!(balances, eligible)
      valid = percentages.select { |seat, _| eligible.include?(seat) }
      winner = unique_best(valid, higher: true)
      settle(balances, winner, draw: winner.nil? && valid.length > 1) { |loser| ((percentages.fetch(winner) - percentages.fetch(loser)).to_r / 10).ceil }
    end

    def fixed(balances:, winner:, amount:, draw: false)
      validate_balances!(balances)
      raise ArgumentError, "Invalid winner" unless winner.nil? || balances.key?(winner)
      raise ArgumentError, "Invalid feather stake" unless amount.is_a?(Integer) && amount >= 0
      raise ArgumentError, "Invalid draw" unless [true, false].include?(draw) && (!draw || winner.nil?)

      settle(balances, winner, draw: draw) { |_loser| amount }
    end

    # Only the best distances matter, including when nobody guessed exactly.
    # The target's digit count selects the scale; equal distances are a draw.
    def guess_number(balances:, target:, distances:, eligible: balances.keys)
      unless target.is_a?(Integer) && target.between?(1, 999)
        raise ArgumentError, 'Invalid guessing target'
      end
      validate_scores!(balances, distances) { |distance| distance.nil? || distance.is_a?(Integer) && distance.between?(0, 998) }
      validate_eligible!(balances, eligible)
      valid = distances.select { |seat, distance| eligible.include?(seat) && !distance.nil? }
      winner = unique_best(valid, higher: false)
      settle(balances, winner, draw: winner.nil? && valid.length > 1) do |loser|
        distance = eligible.include?(loser) ? distances.fetch(loser) : nil
        next 5 if distance.nil?

        advantage = distance - distances.fetch(winner)
        amount = if target < 10
          (advantage * 5 + 7) / 8
        else
          step = target < 100 ? 10 : 100
          (advantage + step - 1) / step
        end
        [amount, 5].min
      end
    end

    def quiz(balances:, answers:)
      validate_scores!(balances, answers) { |correct| correct == true || correct == false }
      grants = answers.select { |_seat, correct| correct }.transform_values { 4 }
      updated = balances.to_h { |seat, balance| [seat, balance + grants.fetch(seat, 0)] }
      Result.new(nil, updated.freeze, [].freeze, {}.freeze, grants.freeze, :quiz)
    end

    def sound_order(balances:, winner:, misplaced:)
      validate_scores!(balances, misplaced) { |count| count.is_a?(Integer) && count.between?(0, 8) }
      raise ArgumentError, 'Invalid sound-order winner' unless winner.nil? || balances.key?(winner) && misplaced[winner].zero?
      settle(balances, winner) { |loser| [misplaced.fetch(loser), 5].min }
    end

    def validate_balances!(balances)
      unless balances.is_a?(Hash) && balances.all? { |_seat, balance| balance.is_a?(Integer) && balance >= 0 }
        raise ArgumentError, "Invalid feather balances"
      end
    end
    private_class_method :validate_balances!

    def validate_eligible!(balances, eligible)
      unless eligible.is_a?(Array) && eligible.uniq == eligible && (eligible - balances.keys).empty?
        raise ArgumentError, "Invalid eligible challenge participants"
      end
    end
    private_class_method :validate_eligible!

    def validate_scores!(balances, scores)
      validate_balances!(balances)
      unless scores.is_a?(Hash) && scores.size == balances.size && scores.keys.all? { |seat| balances.key?(seat) } &&
          scores.values.all? { |score| yield score }
        raise ArgumentError, "Invalid challenge results"
      end
    end
    private_class_method :validate_scores!

    def unique_best(scores, higher:)
      return nil if scores.empty?

      best = higher ? scores.values.max : scores.values.min
      winners = scores.select { |_seat, score| score == best }.keys
      winners.length == 1 ? winners.first : nil
    end
    private_class_method :unique_best

    def settle(balances, winner, penalties: {}, draw: false)
      updated = balances.dup
      transfers = []
      if winner
        balances.each_key do |loser|
          next if loser == winner

          amount = [yield(loser), updated.fetch(loser)].min
          next if amount.zero?

          updated[loser] -= amount
          updated[winner] += amount
          transfers << Transfer.new(loser, winner, amount)
        end
      end
      burned = {}
      penalties.each do |seat, penalty|
        amount = [penalty, updated.fetch(seat)].min
        next if amount.zero?

        updated[seat] -= amount
        burned[seat] = amount
      end
      Result.new(winner, updated.freeze, transfers.freeze, burned.freeze, {}.freeze,
        winner ? :won : (draw ? :draw : :no_winner))
    end
    private_class_method :settle
  end
end
