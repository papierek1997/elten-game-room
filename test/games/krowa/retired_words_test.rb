require_relative '../../support/krowa_services'

bank = GameRoomGames::KrowaWordBank.default
retired = GameRoomKrowa::NounData::RETIRED_WORDS.lines.map(&:chomp)
assert(retired.size == 90 && retired.uniq == retired, 'Withdrawn-word provenance is incomplete')
retired.each do |word|
  assert(!bank.include?(word) && bank.historical?(word), "Retired noun is active or unreadable: #{word}")
end
assert(!bank.historical?('nieistniejaceslowo'), 'Historical reads accept arbitrary nouns')
assert(bank.historical?('kot'), 'Active nouns disappeared from historical reads')
tables = KrowaTestTables.new
tables.fetch('krowa_word_scores').insert('word' => 'hizop', 'attempts' => 4)
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: bank, user: 'Alice')
assert(store.ranked_words.map { |row| row['word'] } == ['hizop'], 'Withdrawing a noun hides its published results')
assert(store.word_ranking('hizop').first['attempts'] == 4, 'Exact historical ranking is inaccessible')
assert(store.word_ranking('nieistniejaceslowo').empty?, 'Unknown historical noun was admitted')

run = KrowaTestGame.new(variant: 'daily')
run.instance_variable_set(:@bank, bank)
run.instance_variable_set(:@game, GameRoomGames::Krowa.new(bank: bank))
options = JSON.parse(run.session['options'])
day = options.fetch('__daily_day')
assignment = GameRoomKrowa::DailyAssignment.seal(day, 'hizop')
options['__daily_assignment'] = assignment
run.session['options'] = JSON.generate(options)
assert(bank.assigned_daily(day, assignment).last == 'hizop', 'Canonical daily answer was lost')
assert(run.automatic == :ok && run.replay.state[:length] == 5, 'Retired daily assignment cannot start')
assert(run.guess('Alice', 'corso') == :unknown_noun, 'A daily assignment enables unrelated retired nouns')
assert(run.guess('Alice', 'hizop') == :ok && run.automatic == :ok && run.automatic == :ok,
  'Canonical retired daily answer cannot complete normally')
assert(run.replay.winner == 'Alice', 'Retired daily answer lost the result')
assert(tables.fetch('krowa_word_scores').rows.size == 1, 'Reading historical results changed server rows')
puts 'PASS withdrawn nouns: no new draws, retained rankings, canonical daily start/answer/result, no arbitrary-word admission'
