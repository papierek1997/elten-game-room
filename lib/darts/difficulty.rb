# encoding: UTF-8

module GameRoomDarts
  module Difficulty
    BASE_HIGHEST = 'hard'.freeze
    IDS = %w[easy normal hard expert master legendary].freeze
    PROFILES = {
      'easy' => {step: 78.0, jitter: 5.0, hold: 0.45, drift: 31.0,
        centre_multiplier: 1.9, score_curve: 0.7},
      'normal' => {step: 82.0, jitter: 12.0, hold: 0.25, drift: 47.0,
        centre_multiplier: 1.9, score_curve: 0.7},
      'hard' => {step: 86.0, jitter: 22.0, hold: 0.10, drift: 67.0,
        centre_multiplier: 1.9, score_curve: 0.7},
      'expert' => {step: 90.0, jitter: 27.0, hold: 0.07, drift: 83.0,
        centre_multiplier: 2.05, score_curve: 0.9},
      'master' => {step: 94.0, jitter: 32.0, hold: 0.05, drift: 102.0,
        centre_multiplier: 2.25, score_curve: 1.15},
      'legendary' => {step: 98.0, jitter: 36.0, hold: 0.03, drift: 123.0,
        centre_multiplier: 2.5, score_curve: 1.45}
    }.transform_values { |profile| profile.freeze }.freeze
    UNLOCKS = {
      'expert' => {from: 'hard', rounds: 3, minimum_score: 850}.freeze,
      'master' => {from: 'expert', rounds: 3, minimum_score: 800}.freeze,
      'legendary' => {from: 'master', rounds: 3, minimum_score: 750}.freeze
    }.freeze

    module_function

    def normalize(value)
      value = value.to_s
      IDS.include?(value) ? value : 'normal'
    end

    def profile(value)
      PROFILES.fetch(normalize(value))
    end

    def level(value)
      IDS.index(value.to_s)
    end

    def unlocked_ids(highest = BASE_HIGHEST)
      index = level(highest)
      index = level(BASE_HIGHEST) if index == nil || index < level(BASE_HIGHEST)
      IDS.first(index + 1)
    end

    def highest(left, right)
      [left, right].map { |value| normalize_highest(value) }.max_by { |value| level(value) }
    end

    def unlock_after(highest, result)
      current = normalize_highest(highest)
      target = IDS[level(current).to_i + 1]
      rule = target && UNLOCKS[target]
      return current unless rule && result.is_a?(Hash)
      return current unless result['difficulty'] == rule[:from] && result['rounds'] == rule[:rounds]
      return current unless result['total_score'].is_a?(Integer) && result['total_score'] >= rule[:minimum_score]

      target
    end

    def normalize_highest(value)
      value = value.to_s
      IDS.include?(value) && level(value) >= level(BASE_HIGHEST) ? value : BASE_HIGHEST
    end
  end
end
