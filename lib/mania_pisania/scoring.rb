# encoding: UTF-8
module GameRoomTyping
  # Compare exact values. The round start records the policy used for replay.
  module Scoring
    ACCURACY_ADJUSTED = 1
    WORD_COUNT = 2
    module_function

    def rank(result, variant, version:)
      if version == WORD_COUNT
        words, errors, wpm = result.values_at('words', 'errors', 'wpm')
        # With equal word counts, fewer errors means higher accuracy.
        return [words, -errors, wpm]
      end
      accuracy_adjusted_value(result, variant)
    end

    def accuracy_adjusted_value(result, variant)
      words, errors = result.values_at('words', 'errors')
      return Rational(0) if words.zero?
      accuracy = Rational(words, words + errors)
      basis = variant == 'free' ? result['wpm'].to_r : words
      basis * accuracy ** 2
    end

    def summary(result, variant, version:)
      words, errors = result.values_at('words', 'errors')
      accuracy = words + errors > 0 ? (100.0 * words / (words + errors)).round(1) : 0.0
      score = version == WORD_COUNT ? words : accuracy_adjusted_value(result, variant)
      {score: score.to_f.round(2), accuracy: accuracy}
    end
  end
end
