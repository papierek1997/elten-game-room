# encoding: UTF-8
module GameRoomTyping
  # Compare exact values. The round start records the policy used for replay.
  module Scoring
    ACCURACY_ADJUSTED = 1
    WORD_COUNT = 2
    WEIGHTED_WORD_COUNT = 3
    MULTIPLAYER_FREE_VERSIONS = [WORD_COUNT, WEIGHTED_WORD_COUNT].freeze
    module_function

    def rank(result, variant, version:)
      case version
      when WEIGHTED_WORD_COUNT
        [points(result, variant, version: version), accuracy(result), result['wpm']]
      when WORD_COUNT
        words, errors, wpm = result.values_at('words', 'errors', 'wpm')
        # With equal word counts, fewer errors means higher accuracy.
        [words, -errors, wpm]
      else
        points(result, variant, version: version)
      end
    end

    def accuracy(result)
      words, errors = result.values_at('words', 'errors')
      return Rational(0) if words.zero?
      Rational(words, words + errors)
    end

    def points(result, variant, version:)
      words = result['words']
      return words if version == WORD_COUNT
      basis = version == ACCURACY_ADJUSTED && variant == 'free' ? result['wpm'].to_r : words
      basis * accuracy(result) ** 2
    end

    def summary(result, variant, version:)
      score = points(result, variant, version: version)
      {score: score.to_f.round(2), accuracy: (100 * accuracy(result)).to_f.round(1)}
    end
  end
end
