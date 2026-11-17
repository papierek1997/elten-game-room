# encoding: UTF-8
require_relative '../../../lib/darts/difficulty'
require_relative '../../../lib/darts/scoring'

def assert(value, message)
  raise message unless value
end

difficulty = GameRoomDarts::Difficulty
assert(difficulty::IDS == %w[easy normal hard expert master legendary],
  'Darts difficulty order changed')
assert(difficulty::PROFILES.values.map { |profile| profile[:hold] } == [0.45, 0.25, 0.10, 0.07, 0.05, 0.03],
  'advanced levels no longer shorten the correction hold to 0.07, 0.05 and 0.03 seconds')
%i[step jitter drift centre_multiplier score_curve].each do |field|
  values = difficulty::PROFILES.values.map { |profile| profile[field] }
  assert(values.each_cons(2).all? { |left, right| right >= left },
    "Darts #{field} is not monotonic across difficulty levels")
end

high_value_radii = difficulty::IDS.map do |level|
  (0..GameRoomDarts::Scoring::BOARD_LIMIT).count do |radius|
    GameRoomDarts::Scoring.points(radius, 0, difficulty:level) >= 90
  end
end
assert(high_value_radii.first(3).uniq.length == 1 &&
  high_value_radii.drop(2).each_cons(2).all? { |wider, narrower| narrower < wider },
  "advanced high-value zones did not narrow monotonically: #{high_value_radii.inspect}")

[
  ['hard', 849, 'hard'], ['hard', 850, 'expert'],
  ['expert', 799, 'expert'], ['expert', 800, 'master'],
  ['master', 749, 'master'], ['master', 750, 'legendary']
].each do |from, score, expected|
  result = {'difficulty'=>from, 'rounds'=>3, 'total_score'=>score}
  assert(difficulty.unlock_after(from, result) == expected,
    "unlock threshold for #{from} accepted or rejected the wrong score")
end
assert(difficulty.unlock_after('hard', {'difficulty'=>'hard', 'rounds'=>5, 'total_score'=>900}) == 'hard',
  'a match with a different length unlocked Expert')
assert(difficulty.unlock_after('hard', {'difficulty'=>'expert', 'rounds'=>3, 'total_score'=>900}) == 'hard',
  'Darts progression skipped the required previous difficulty')

puts 'PASS Darts difficulty: short holds, narrower scoring and sequential three-round unlocks'
