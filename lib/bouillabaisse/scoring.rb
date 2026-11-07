module BouillabaissePlanning
  module Scoring
    module_function

    def trick_points(round)
      [1, 5, 6].include?(round) ? 5 : 0
    end

    # Used by both the real game and hypothetical completed rounds. In round
    # six, taking everything reverses the normally beneficial subtraction too.
    def additions(raw, round:, all_or_nothing:)
      total = raw.values.sum
      raw.to_h do |player, value|
        value = -value if all_or_nothing && round != 4 && value == total && total.positive?
        [player, round == 6 ? -value : value]
      end
    end
  end
end
