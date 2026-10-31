require_relative '../../support/krowa_services'
require_relative '../../../games/krowa_support/server_schema'

tables = KrowaTestTables.new
bank = KrowaTestGame.new.bank
old_schema = Marshal.load(Marshal.dump(GameRoomGames::KrowaServerSchema::TABLES))
old_schema.delete('krowa_attempt_lists')
%w[krowa_word_scores krowa_daily_scores krowa_tower_rounds].each do |name|
  old_schema[name]['columns'].delete('history_key')
end
old_schema['krowa_tower_scores']['columns'].delete('histories_shared')
reads = 0
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: bank, user: 'Alice',
  schema_reader: -> { reads += 1; {'data' => {'tables' => old_schema}} })
assert(store.publish_word('kot', 1, words: ['kot']) == :history_unavailable, 'old server accepted a missing history table')
assert(store.publish_word('kot', 1) == :published, 'old server rejected an ordinary score')
store.record_daily_open('2026-10-29')
assert(store.publish_daily('2026-10-29', 1, words: ['kot']) == :history_unavailable, 'old daily history accepted')
assert(store.publish_daily('2026-10-29', 1) == :published, 'old daily score rejected')
rounds = [{word: 'kot', attempts: 1, solved: true, words: ['kot']}]
code = 'f' * 64
assert(store.publish_tower(run_code: code, participants: %w[Alice Bob], rounds: rounds) == :history_unavailable, 'old tower history accepted')
no_lists = rounds.map { |round| round.reject { |key, _| key == :words } }
assert(store.publish_tower(run_code: code, participants: %w[Alice Bob], rounds: no_lists) == :published, 'old tower score rejected')
assert(!tables.fetch('krowa_tower_scores').rows.first.key?('histories_shared'), 'unknown column sent to old server')
assert(!tables.instance_variable_get(:@tables).key?('krowa_attempt_lists'), 'missing history table queried')
assert(reads == 1, 'schema repeatedly queried')

ready = GameRoomGames::KrowaServerStore.new(server_tables: KrowaTestTables.new, bank: bank, user: 'Alice',
  schema_reader: -> { {'data' => JSON.generate('tables' => GameRoomGames::KrowaServerSchema::TABLES)} })
assert(ready.publish_word('kot', 1, words: ['kot']) == :published, 'updated schema did not enable histories')
puts 'PASS Krowa schema compatibility: explicit missing-history feedback, all old score paths retained, one metadata read, updated schema enables sharing'
