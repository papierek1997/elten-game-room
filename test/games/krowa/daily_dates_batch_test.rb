require_relative '../../support/ui'
require_relative '../../support/krowa_services'
require_relative '../../../games/krowa_support/leaderboards'

today = '2026-10-22'
dates = (1..365).map { |offset| (Date.iso8601(today) - offset).iso8601 }
bank = GameRoomGames::KrowaWordBank.default
tables = KrowaTestTables.new
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: bank, user: 'Alice')
table = tables.fetch('krowa_daily_assignments')
dates.drop(1).each do |date|
  table.insert('day_key' => date.delete('-').to_i,
    'assignment' => GameRoomKrowa::DailyAssignment.seal(date, 'kot'))
end
# The first native row, not a later conflicting dictionary, is authoritative.
table.insert('day_key' => dates.last.delete('-').to_i,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(dates.last, 'las'))
[today, '2026-10-23'].each do |date|
  table.insert('day_key' => date.delete('-').to_i, 'assignment' => 'Must not decrypt current/future words')
end
before = Marshal.dump(table.rows)
client = GameRoomGames::KrowaLeaderboardClient.new(nil, nil, store: store)
shown = client.send(:daily_date_rows, [today] + dates, today)
assert(shown == [[today, ''], [dates.first, '']] + dates.drop(1).map { |date| [date, 'kot'] },
  'Date order, blank missing/current solution or earliest assignment changed')
puts "Assignment reads for 365 past dates: #{table.queries.size}"
# Four 100-key batches plus an empty-page confirmation for the missing date.
# A short nonempty page alone cannot prove that this batch is exhausted.
assert(table.queries.size <= 5, 'Daily date browser still issues one assignment read per day')
assert(Marshal.dump(table.rows) == before, 'Date browsing wrote or mutated assignment rows')
table.queries.each do |query|
  assert(query.fetch(:where).fetch('day_key').fetch('in').all? { |key| key < 20261022 },
    'Batch read requested a current/future answer')
end

# More than one page of duplicate rows cannot hide an earliest assignment for
# another requested day. A later duplicate is never a replacement answer.
paged = KrowaTestTables.new
assignments = paged.fetch('krowa_daily_assignments')
600.times { assignments.insert('day_key' => 20261020,
  'assignment' => GameRoomKrowa::DailyAssignment.seal('2026-10-20', 'kot')) }
assignments.insert('day_key' => 20261019,
  'assignment' => GameRoomKrowa::DailyAssignment.seal('2026-10-19', 'las'))
paged_store = GameRoomGames::KrowaServerStore.new(server_tables: paged, bank: bank, user: 'Alice')
assert(paged_store.daily_words(%w[2026-10-20 2026-10-19 2026-10-20 invalid], today: today) ==
  {'2026-10-20' => 'kot', '2026-10-19' => 'las'}, 'Paged duplicates or repeated input broke canonical lookup')
assert(assignments.queries.size == 2, 'Incomplete first page lost requested dates or made redundant reads')
assignments.queries.clear
assert(paged_store.daily_words([today, '2026-10-23', 'invalid'], today: today).empty? && assignments.queries.empty?,
  'Empty valid scope requested private/current assignments')
assert(paged_store.daily_words(dates, today: nil).empty? && assignments.queries.empty?, 'Unconfirmed date read assignments')
paged.enabled = false
assert(paged_store.daily_words(dates, today: today).empty? && assignments.queries.empty?, 'Unavailable tables were queried')

# A malformed canonical row remains an explicit failure, not permission to
# choose a later duplicate or return a partial, apparently successful list.
broken = KrowaTestTables.new
broken.fetch('krowa_daily_assignments').insert('day_key' => 20261020, 'assignment' => 'broken')
broken.fetch('krowa_daily_assignments').insert('day_key' => 20261020,
  'assignment' => GameRoomKrowa::DailyAssignment.seal('2026-10-20', 'kot'))
broken_store = GameRoomGames::KrowaServerStore.new(server_tables: broken, bank: bank, user: 'Alice')
begin
  broken_store.daily_words(['2026-10-20'], today: today)
  raise 'Corrupt first assignment silently replaced or skipped'
rescue ArgumentError
end
puts 'PASS daily date batches: 365 dates in at most 5 reads including missing-date EOF, canonical first rows, paging, current privacy and unavailable/corrupt data'
