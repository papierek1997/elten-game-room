require_relative '../../support/assertions'
require_relative '../../support/krowa_services'
include GameRoomTest::Assertions

def cap_krowa_pages(table, count)
  select = table.method(:select)
  table.define_singleton_method(:select) { |**query| select.call(**query).first(count) }
end

bank = GameRoomGames::KrowaWordBank.default
tables = KrowaTestTables.new
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: bank, user: 'Alice')
words = bank.instance_variable_get(:@repository).words.uniq.first(2001)
assert_equal(2001, words.length)
word_scores = tables.fetch('krowa_word_scores')
words.first(1001).each_with_index do |word, index|
  word_scores.insert('word' => word, 'attempts' => 1)['__insertion_time'] = 1_700_000_000 + index
end
expected = store.ranked_words
target = expected.last.fetch('word')
assert(store.search_ranked_words(target, today: '2026-11-11').any? { |row| row['word'] == target },
  'Full-response control did not find a published word')
cap_krowa_pages(word_scores, 1000)
word_scores.queries.clear
assert(store.search_ranked_words(target, today: '2026-11-11').any? { |row| row['word'] == target },
  'A short server page hid a published word within the existing 2000-result bound')
assert_equal([0, 1000, 1001], word_scores.queries.map { |query| query.fetch(:offset) })
assert_equal(expected, store.ranked_words, 'Paging changed grouped word order or aggregates')

# A shorter response is not EOF, but the existing total raw-row bound is.
words.drop(1001).each_with_index do |word, index|
  word_scores.insert('word' => word, 'attempts' => 1)['__insertion_time'] = 1_700_001_001 + index
end
word_scores.queries.clear
bounded = store.ranked_words(limit: 50_000)
assert_equal(2000, bounded.length)
assert_equal(words.reverse.first(2000), bounded.map { |row| row.fetch('word') })
assert_equal([0, 1000], word_scores.queries.map { |query| query.fetch(:offset) })
assert(word_scores.queries.all? { |query| query.fetch(:limit) <= 1000 }, 'Word pages exceed the server cap')
assert_equal([words.last], store.ranked_words(limit: 0).map { |row| row.fetch('word') })

small = KrowaTestTables.new
small_store = GameRoomGames::KrowaServerStore.new(server_tables: small, bank: bank, user: 'Alice')
scores = small.fetch('krowa_daily_scores')
dates = (1..7).map { |day| "2026-11-0#{day}" }
dates.each_with_index do |date, index|
  scores.user = "Player#{index}"
  scores.insert('day_key' => 20261101, 'attempts' => index + 1)
  scores.insert('day_key' => date.delete('-').to_i, 'attempts' => index + 1)
end
full_ranking = small_store.daily_ranking(dates.first)
full_days = small_store.daily_days
cap_krowa_pages(scores, 2)
assert_equal(full_ranking, small_store.daily_ranking(dates.first), 'Short daily ranking page ended the scan')
assert_equal(full_ranking.first(3), small_store.daily_ranking(dates.first, limit: 3))
assert_equal(full_days, small_store.daily_days, 'Short daily date page ended the scan')
assert_equal(full_days.first(3), small_store.daily_days(limit: 3))

assignments = small.fetch('krowa_daily_assignments')
3.times { assignments.insert('day_key' => 20261101,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(dates.first, 'kot')) }
assignments.insert('day_key' => 20261101,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(dates.first, 'las'))
assignments.insert('day_key' => 20261102,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(dates[1], 'kot'))
assignments.insert('day_key' => 20261103,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(dates[2], 'kot'))
assignments.insert('day_key' => 20261111, 'assignment' => 'Current answer must not be opened')
cap_krowa_pages(assignments, 2)
assert_equal(dates.first(3).to_h { |date| [date, 'kot'] },
  small_store.daily_words(dates + ['2026-11-11'], today: '2026-11-11'),
  'Short assignment pages lost dates, used a duplicate or disclosed the current answer')
found = small_store.search_ranked_words('kot', today: '2026-11-11')
assert_equal(dates.first(3).sort, found.map { |row| row.fetch('daily_date') }.sort,
  'Daily public search stopped at a short assignment or score page')
assert(small_store.search_ranked_words('las', today: '2026-11-11').empty?, 'Noncanonical assignment was used')

completions = small.fetch('krowa_daily_completions')
dates.each { |date| completions.insert('day_key' => date.delete('-').to_i, 'status' => 1) }
cap_krowa_pages(completions, 2)
before = Marshal.dump(completions.rows)
assert(small_store.synchronize_daily(dates), 'Short completion pages prevented synchronization')
assert_equal(before, Marshal.dump(completions.rows), 'Short pages duplicated existing daily completions')

rounds = small.fetch('krowa_tower_rounds')
code = 'a' * 64
5.times { |index| rounds.insert('run_code' => code, 'round' => index + 1, 'word' => 'kot', 'attempts' => 1, 'solved' => 1) }
rounds.insert('run_code' => code, 'round' => 1, 'word' => 'las', 'attempts' => 2, 'solved' => 1)
rounds.user = 'Bob'
rounds.insert('run_code' => code, 'round' => 6, 'word' => 'las', 'attempts' => 1, 'solved' => 1)
cap_krowa_pages(rounds, 2)
details = small_store.tower_rounds(code, user: 'Alice')
assert_equal((1..5).to_a, details.map { |row| row.fetch('round') })
assert(details.all? { |row| row.fetch('word') == 'kot' }, 'Paging changed canonical round/account selection')

# A failure after a short page is a failure of the whole read, not partial success.
select = word_scores.method(:select)
word_scores.define_singleton_method(:select) do |**query|
  raise IOError, 'Later page failed' if query.fetch(:offset, 0).positive?
  select.call(**query)
end
assert_raises(IOError) { store.search_ranked_words(target, today: '2026-11-11') }
puts 'PASS Krowa short pages: public word/day search, exact offsets, existing bounds/order, canonical/private dates, migration, tower details and later-page failure'
