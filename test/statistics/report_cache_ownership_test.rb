require_relative '../support/statistics_tables'
require_relative '../../lib/game_statistics_periods'
require_relative '../support/assertions'
include GameRoomTest::Assertions

api = StatisticsMemoryApi.new
table = api.table(nil, nil, GameRoomStatistics::Schema::EVENTS)
# A native HTTP JSON response owns its strings. Do not let the table double's
# shallow Hash copy turn this into a mutation of the fake backend itself.
def table.masked(row)
  JSON.parse(JSON.generate(super))
end
store = GameRoomStatistics::Store.new(app_uuid: 'isolated-report-test', user: 'Alice',
  current_user: -> { 'Alice' }, client: Object.new, api: api, monotonic: -> { 1.0 })
store.write_batch(%w[quiz uno].each_with_index.flat_map do |game, index|
  %w[started completed].map do |kind|
    {'kind' => kind, 'game' => game, 'mode' => 'humans', 'day_key' => 20261111,
      'match' => format('00000000-0000-4000-8000-%012d', index)}
  end
end)
day = Date.new(2026, 11, 11)
period = GameRoomStatistics::Period.new(key: 'today', label: 'Today', from_date: day, to_date: day)
first = store.report(period)
expected = Marshal.load(Marshal.dump(first))
assert_equal(%w[quiz uno], first.fetch('games').map { |game| game.fetch('id') }.sort)
canonical_reads = table.queries.count { |query| query[:group_by] }
quiz = first.fetch('games').find { |game| game.fetch('id') == 'quiz' }
quiz.fetch('id').replace('uno')
quiz['completed'] = 999
quiz.fetch('modes').fetch('humans')['completed'] = 999
first['completed'] = 999
first.fetch('games').delete_if { |game| game.equal?(quiz) }
reused = store.report(period, reuse_snapshot: true)
assert_equal(expected, reused, 'Editing an earlier public report poisoned the private canonical read snapshot')
assert_equal(canonical_reads, table.queries.count { |query| query[:group_by] }, 'Isolation fix disabled canonical snapshot reuse')
assert_equal(%w[quiz uno], table.rows.map { |row| row.fetch('game') }.uniq.sort, 'The probe mutated the fake server')
assert_equal(reused, store.report(period, reuse_snapshot: false), 'Cached and freshly read reports diverged')
reused.fetch('games').clear
assert_equal(expected, store.report(period, reuse_snapshot: true), 'A caller still owns part of a later report')

puts 'PASS statistics report ownership: mutable caller results, unchanged backend, canonical-cache reuse and identical fresh/cached reports'
