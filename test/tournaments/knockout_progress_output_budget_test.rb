require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/assertions'
require_relative '../../lib/tournaments/server_phase_plan'
include GameRoomTest::Assertions
T = GameRoomTournaments

[9, 32].each do |length|
  seeds = Array.new(128) { |index| format('player%03d', index + 1).ljust(length, 'x') }
  seeds.each { |name| T::Publication::Data.account(name) }
  base = T::KnockoutRound.build(seeds: seeds, players_per_match: 2, round_number: 1)
  history = base.fetch('matches').map do |match|
    people = match.fetch('participants')
    {'id' => "played-#{match.fetch('id')}", 'participants' => people,
      'winners' => [people.first], 'scores' => {people.first => 11, people.last => 3}}
  end
  assert_equal(64, T::Standings.validated_results(units: seeds, results: history, max_results: 4096).size)
  before = Marshal.dump([base, history])
  view = T::KnockoutWinSeries.progress(base: base, history: history, target: 1)
  assert_equal('ready_next_round', view.dig('sports', 'state'))
  assert_equal(seeds.each_slice(2).map(&:first), view.dig('sports', 'next_seeds'))
  assert_equal(64, view.fetch('summaries').size)
  assert(view.frozen? && view.fetch('series').all?(&:frozen?), 'Progress must remain immutable')
  view.fetch('series').each_with_index do |series, index|
    people = base.fetch('matches').fetch(index).fetch('participants')
    assert_equal('completed', series.fetch('state'))
    assert_equal({people.first => 1, people.last => 0}, series.fetch('wins'))
    assert_equal({people.first => 11, people.last => 3}, series.dig('summary', 'scores'))
  end
  assert_equal(before, Marshal.dump([base, history]), 'Projection mutated the accepted source')
  assert_equal(:invalid_standings, assert_raises(T::Publication::Invalid) do
    T::KnockoutWinSeries.progress(base: base, history: history + [history.first], target: 1)
  end.code)
  if length == 32
    assert(JSON.generate(view).bytesize > T::Publication::MAX_JSON_BYTES,
      'Regression no longer exceeds the default Data.copy output budget')
  end
end

# Only the combined series output uses the existing larger series-plan budget.
# A generic publication copy keeps its original bound.
assert_equal(:json_budget, assert_raises(T::Publication::Invalid) do
  T::Publication::Data.copy({'value' => 'x' * T::Publication::MAX_JSON_BYTES})
end.code)
puts 'PASS knockout progress output:128 legal accounts/64 scored pairings, frozen summaries, unchanged input/validation and ordinary data budget'
