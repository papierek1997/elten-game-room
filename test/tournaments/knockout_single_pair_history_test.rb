require_relative '../support/assertions'
require_relative '../../lib/tournaments/server_phase_plan'
include GameRoomTest::Assertions

T = GameRoomTournaments
seeds = %w[alice bob]
base = T::KnockoutRound.build(seeds: seeds, players_per_match: 2, round_number: 1)
history = Array.new(256) do |index|
  {'id' => "prior-game-#{index}", 'participants' => seeds,
    'winners' => index < 60 ? [] : [seeds[(index - 60) % 2]], 'scores' => nil}
end
history = T::Publication::Data.copy(history, max_bytes: 262_144, max_nodes: 16_384, max_depth: 12)
assert_equal(256, T::Standings.validated_results(units: seeds, results: history, max_results: 4096).size)
plan = T::KnockoutWinSeries.build(base: base, history: history, target: 99, attempt: 257)
metadata = plan.slice('round', 'seeds', 'players_per_match', 'generation', 'series').merge(
  'phase_digest' => 'c' * 64, 'parent_plan_digest' => 'd' * 64)
generation = 'a' * 64
schedule, matches = T::KnockoutSchedule.matches(metadata: metadata, generation: generation)
candidate = {'schedule_id' => schedule, 'publication_digest' => 'b' * 64,
  'roster_generation' => generation, 'publication_ref' => {'author' => 'alice', 'publication_key' => 'single-pair'},
  'format' => 'knockout', 'roster' => seeds, 'matches' => matches, 'knockout' => metadata,
  'knockout_wins_to' => 99, 'final_wins_to' => 99, 'knockout_rematch' => false, 'final_rematch' => false}
receipts_for = lambda do |value, winners|
  value.fetch('matches').map do |match|
    {'match_id' => match['match_id'], 'leg' => match['leg'], 'summary' => {
      'participants' => match['players'].sort, 'winners' => winners, 'scores' => nil,
      'draw' => winners.empty?, 'event_count' => 5}}
  end
end
rows_for = lambda do |receipts|
  receipts.map do |receipt|
    receipt.fetch('summary').slice('participants', 'winners', 'scores').merge(
      'id' => JSON.generate([receipt['match_id'], receipt['leg']]))
  end
end

# The257th game is a draw. Both players still have98 wins, so a99-win
# series must remain open. Only the current phase, not the whole series,
# has the ordinary256-result limit.
receipts = receipts_for.call(candidate, [])
rows = rows_for.call(receipts)
before = Marshal.dump(candidate)
view = T::KnockoutStandings.calculate(candidate: candidate, units: seeds, results: rows, unit_key: 'players')
assert_equal('awaiting_series', view.fetch('knockout_state'))
assert_equal({'alice' => 98, 'bob' => 98}, view.fetch('series_progress').first.fetch('wins'))
assert_equal(257, view.fetch('series_history').size)
next_candidate = T::ServerPhasePlan.build(candidate: candidate, results: receipts).fetch('candidate')
assert_equal(257, next_candidate.dig('knockout', 'series', 'history').size)
assert_equal(before, Marshal.dump(candidate), 'Advancing changed the accepted previous phase')

finishing = receipts_for.call(next_candidate, ['alice'])
completed = T::KnockoutStandings.calculate(candidate: next_candidate, units: seeds,
  results: rows_for.call(finishing), unit_key: 'players')
assert_equal('completed', completed.fetch('knockout_state'))
assert_equal('alice', completed.fetch('champion'))
assert_equal(99, completed.fetch('series_progress').first.fetch('wins').fetch('alice'))

full = history + rows
ordinary_error = assert_raises(T::Publication::Invalid) { T::Standings.calculate(units: seeds, results: full) }
assert_equal(:invalid_standings, ordinary_error.code, 'The fix expanded ordinary phase capacity')
[
  full.first(256) + [full.first.dup],
  full.first(256) + [full.last.merge('participants' => %w[alice outsider])],
  full.first(256) + [full.last.merge('scores' => {'alice' => 1})]
].each do |invalid|
  error = assert_raises(T::Publication::Invalid) do
    T::KnockoutSeries.wins_projection(units: seeds, results: invalid, id: 'series', target: 99)
  end
  assert_equal(:invalid_standings, error.code, 'Long-series validation skipped identity/participant/score checks')
end
puts 'PASS knockout single-pair history:257th draw, next phase,99th win, input ownership and unchanged ordinary/invalid-result limits'
