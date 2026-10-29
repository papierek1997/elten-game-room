require_relative '../../support/krowa_services'
require_relative '../../../games/krowa_support/attempt_archive'

def rejects_history
  yield
  raise 'Invalid history was accepted'
rescue ArgumentError
end

codec = GameRoomGames::KrowaAttemptHistory
words = %w[łąka żółć]
key = codec.identity('word:żółć', words)
payload, nonce = codec.encode('word:żółć', words)
assert(codec.decode('word:żółć', key, payload, nonce) == words, 'Polish history roundtrip')
rejects_history { codec.decode('daily:2026-10-29', key, payload, nonce) }
rejects_history { codec.words(['kot'], count: 2) }
rejects_history { codec.words(%w[las kot], solution: 'las', solved: true) }
rejects_history { codec.words(['kot;las']) }

# Only accepted scores contribute attempts, including across rounds. Pending
# and rejected guesses must never enter a saved or published list.
run = KrowaTestGame.new
run.automatic
assert(run.guess('Alice', 'las') == :ok, 'pending trial setup')
assert(codec.rounds(run.replay)[1].empty?, 'Pending guess was recorded')
run.automatic
assert(codec.rounds(run.replay)[1] == ['las'], 'Scored guess missing')
assert(run.guess('Alice', 'las') == :duplicate, 'Duplicate trial setup')
assert(codec.rounds(run.replay)[1] == ['las'], 'Rejected duplicate was recorded')

tables = KrowaTestTables.new
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: run.bank, user: 'Alice')
assert(store.publish_word('kot', 2, words: %w[las kot]) == :published, 'word history publication')
assert(store.word_attempt_list('kot', user: 'Alice', attempts: 2) == {word: 'kot', words: %w[las kot]}, 'word history read')
assert(store.word_attempt_list('kot', user: 'Bob', attempts: 2) == nil, 'history crossed accounts')
assert(store.publish_word('kot', 1, words: ['kot']) == :published, 'new best publication')
assert(store.word_attempt_list('kot', user: 'Alice', attempts: 1)[:words] == ['kot'], 'history attached to an older score')
assert(store.publish_word('kot', 3, words: %w[las dom kot]) == :unchanged, 'worse result replaced best')
assert(store.publish_word('las', 1) == :published, 'score without consent failed')
assert(store.word_attempt_list('las', user: 'Alice', attempts: 1) == nil, 'missing history invented')

day = '2026-10-29'
tables.fetch('krowa_daily_assignments').insert('day_key' => 20261029,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(day, 'kot'))
store.record_daily_open(day)
assert(store.publish_daily(day, 2, words: %w[las kot]) == :published, 'daily publication')
scores = tables.fetch('krowa_daily_scores').rows
assert(scores.first.keys.sort == %w[__id __insertion_time __insertion_user attempts day_key history_key], 'daily score leaks words')
archive = tables.fetch('krowa_attempt_lists')
before = archive.queries.length
assert(store.daily_attempt_list(day, user: 'Alice', attempts: 2, today: day) == :hidden, 'current daily history exposed')
assert(store.daily_attempt_list(day, user: 'Alice', attempts: 2, today: '2026-10-28') == :hidden, 'future daily history exposed')
assert(archive.queries.length == before, 'hidden history was downloaded')
assert(store.daily_attempt_list(day, user: 'Alice', attempts: 2, today: '2026-10-30') ==
  {word: 'kot', words: %w[las kot]}, 'past daily history unavailable')

# Chunked lists stay optional and recover from partial/lost acknowledgements.
large = (0...1400).map { |i| i.to_s(26).tr('0-9a-p', 'a-z').rjust(3, 'a') } + ['kot']
partial_tables = KrowaTestTables.new
partial = GameRoomGames::KrowaServerStore.new(server_tables: partial_tables, bank: run.bank, user: 'Alice')
parts = partial_tables.fetch('krowa_attempt_lists')
parts.fail_after = 1
assert(partial.publish_word('kot', large.length, words: large) == :unavailable, 'partial history published a score')
assert(parts.rows.length == 1 && partial_tables.fetch('krowa_word_scores').rows.empty?, 'partial upload boundary')
first = parts.rows.first.dup
parts.fail_after = nil
assert(partial.publish_word('kot', large.length, words: large) == :published, 'partial upload did not resume')
assert(parts.rows.first == first && parts.rows.map { |r| r['part'] }.uniq.length == parts.rows.length, 'resume changed nonce or duplicated parts')
assert(partial.word_attempt_list('kot', user: 'Alice', attempts: large.length)[:words] == large, 'large history truncated')

lost_tables = KrowaTestTables.new
lost = GameRoomGames::KrowaServerStore.new(server_tables: lost_tables, bank: run.bank, user: 'Alice')
lost_tables.fetch('krowa_attempt_lists').lost_ack = true
lost_tables.fetch('krowa_word_scores').lost_ack = true
assert(lost.publish_word('kot', 1, words: ['kot']) == :published, 'lost acknowledgements were not read back')
assert(lost.publish_word('kot', 1, words: ['kot']) == :unchanged, 'retry duplicated score')
assert(lost_tables.fetch('krowa_attempt_lists').rows.length == 1, 'retry duplicated history')

concurrent_tables = KrowaTestTables.new
concurrent_store = GameRoomGames::KrowaServerStore.new(server_tables: concurrent_tables, bank: run.bank, user: 'Alice')
concurrent_parts = concurrent_tables.fetch('krowa_attempt_lists')
scope = 'word:kot'
concurrent_key = codec.identity(scope, large)
envelope_a, nonce_a = codec.encode(scope, large)
envelope_b, nonce_b = codec.encode(scope, large)
count = (envelope_a.bytesize + 2047) / 2048
concurrent_parts.insert('list_key' => concurrent_key, 'part' => 0, 'parts' => count,
  'nonce' => nonce_a, 'payload' => envelope_a[0, 2048])
envelope_b.scan(/.{1,2048}/).each_with_index do |payload, index|
  concurrent_parts.insert('list_key' => concurrent_key, 'part' => index, 'parts' => count,
    'nonce' => nonce_b, 'payload' => payload)
end
assert(concurrent_store.publish_word('kot', large.length, words: large) == :published, 'concurrent envelopes prevented recovery')
assert(concurrent_store.word_attempt_list('kot', user: 'Alice', attempts: large.length)[:words] == large, 'competing envelope parts were mixed')

# A shorter native page is not EOF. Preserve every part and the exact author.
native_select = parts.method(:select)
parts.define_singleton_method(:select) { |**opts| native_select.call(**opts.merge(limit: [opts.fetch(:limit), 1].min)) }
assert(partial.word_attempt_list('kot', user: 'Alice', attempts: large.length)[:words] == large, 'short page truncated history')
parts.rows.last['payload'] = 'not a valid envelope'
rejects_history { partial.word_attempt_list('kot', user: 'Alice', attempts: large.length) }

code = 'd' * 64
tower_rounds = [{word: 'kot', attempts: 2, solved: true, words: %w[las kot]},
  {word: 'dom', attempts: 1, solved: false, words: ['las']}]
assert(store.publish_tower(run_code: code, participants: %w[Alice Bob], rounds: tower_rounds) == :published, 'tower histories publication')
rounds = store.tower_rounds(code, user: 'Alice')
assert(store.tower_attempt_list(rounds.first)[:words] == %w[las kot], 'completed tower round list')
assert(store.tower_attempt_list(rounds.last)[:words] == ['las'], 'failed tower round list')
assert(store.tower_ranking.first['rounds'] == 1, 'histories changed tower scoring')
assert(store.published_tower_rounds(store.tower_ranking.first).first['history_key'], 'shared tower history hidden')

retry_code = 'e' * 64
summary = tables.fetch('krowa_tower_scores')
original_insert = summary.method(:insert)
summary.define_singleton_method(:insert) { |_| nil }
assert(store.publish_tower(run_code: retry_code, participants: %w[Alice Bob], rounds: tower_rounds) == :unavailable, 'summary failure setup')
summary.define_singleton_method(:insert, &original_insert)
no_lists = tower_rounds.map { |round| round.reject { |key, _| key == :words } }
assert(store.publish_tower(run_code: retry_code, participants: %w[Alice Bob], rounds: no_lists) == :published, 'changed tower consent retry')
published = store.tower_ranking.find { |row| row['run_code'] == retry_code }
assert(store.published_tower_rounds(published).none? { |row| row.key?('history_key') }, 'final tower opt-out exposed partially uploaded lists')

# The local gallery keeps the attempts belonging to the best actual result.
profile_run = KrowaTestGame.new
profile_run.automatic
solution = profile_run.context.hidden_submissions.reveal(session_id: 10, round_id: 'krowa:1', user: 'Alice').payload['word']
other = %w[kot las dom].find { |word| word != solution }
profile_run.guess('Alice', other); profile_run.automatic
profile_run.guess('Alice', solution); 2.times { profile_run.automatic }
profile = GameRoomGames::KrowaProfile.new(profile_run.program, user: 'Alice')
profile.observe(profile_run.replay)
assert(profile.data['gallery'].fetch(solution)['words'] == [other, solution], 'gallery lost ordered attempts')
profile.data['gallery'].fetch(solution).delete('words')
profile.observe(profile_run.replay)
assert(profile.data['gallery'].fetch(solution)['words'] == [other, solution], 'equal best result could not fill a legacy gallery entry')
writes = profile_run.program.writes
profile.observe(profile_run.replay)
assert(profile_run.program.writes == writes, 'replay rewrote local history')
assert(GameRoomGames::KrowaProfile.new(profile_run.program, user: 'Bob').data['gallery'].empty?, 'gallery crossed accounts')
puts 'PASS Krowa attempt histories: accepted scores, UTF-8, exact results, consent, delayed daily disclosure, tower rounds, chunks/recovery and gallery'
