# encoding: UTF-8
module GameRoomTyping
  # Compare exact values, not rounded spoken scores. Existing start records
  # without this policy retain their original result when replayed/restored.
  module Scoring
    module_function

    def value(result, variant)
      words, errors = result.values_at('words', 'errors')
      return Rational(0) if words.zero?
      accuracy = Rational(words, words + errors)
      basis = variant == 'free' ? result['wpm'].to_r : words
      basis * accuracy ** 2
    end

    def summary(result, variant)
      words, errors = result.values_at('words', 'errors')
      accuracy = words + errors > 0 ? (100.0 * words / (words + errors)).round(1) : 0.0
      {score: value(result, variant).to_f.round(2), accuracy: accuracy}
    end
  end
end
