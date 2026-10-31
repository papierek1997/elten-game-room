require_relative "../../support/room_interface"
require_relative "../../support/krowa_services"
require_relative "../../../games/krowa_support/client"

# This test follows the result-publication path synchronously; it does not
# claim to exercise the native host's worker scheduler.
module EltenAPI
  module Tasks
    def self.run(**_options); yield; end
  end
end

run = KrowaTestGame.new(variant: 'daily')
assert(run.automatic == :ok, 'daily round did not open')
word = run.bank.daily(Time.utc(2026, 9, 18, 12)).last
assert(run.guess('Alice', word) == :ok, 'daily answer was rejected')
2.times { assert(run.automatic == :ok, 'daily answer was not verified and revealed') }
assert(run.replay.finished?, 'daily round did not finish')

tables = KrowaTestTables.new
client = run.game.build_client(run.program, server_tables: tables)
assert(client.start, 'daily client did not start')
store = client.instance_variable_get(:@server_store)
publisher = Object.new
publications = []
publisher.define_singleton_method(:publish_daily) do |date, attempts, words: nil|
  publications << [date, attempts, store.publish_daily(date, attempts, words: words)]
end
publisher.define_singleton_method(:publish_word) { |*| raise 'Daily solution leaked to per-word leaderboard' }
client.instance_variable_set(:@leaderboards, publisher)
prompts = []
client.define_singleton_method(:publication_choice) { |text| prompts << text; :with_attempts }
client.define_singleton_method(:definition_dialog) { |_word| }

2.times { client.after_events(run.replay, 'Alice', context: run.context) }
assert(publications == [['2026-09-18', 1, :published]], 'finished daily result was not published exactly once')
assert(prompts.length == 1 && !prompts.first.include?(word), 'daily publication prompt exposed the solution or repeated')
assert(tables.fetch('krowa_word_scores').rows.empty?, 'daily result also appeared in ordinary word scores')
assert(tables.fetch('krowa_daily_scores').rows.first.keys.sort == %w[__id __insertion_time __insertion_user attempts day_key history_key],
  'daily publication persisted a solution')

declined = run.game.build_client(run.program, server_tables: KrowaTestTables.new)
assert(declined.start, 'second client did not start')
declined.instance_variable_set(:@leaderboards, publisher)
declined.define_singleton_method(:publication_choice) { |_text| nil }
declined.define_singleton_method(:definition_dialog) { |_word| }
declined.after_events(run.replay, 'Alice', context: run.context)
assert(publications.length == 1, 'declining publication still sent a score')

tables.enabled = false
assert(store.publish_daily('2026-09-18', 1) == :unavailable, 'table access failure claimed publication success')
assert(store.daily_ranking('2026-09-18').empty? && store.daily_days.empty?, 'unavailable rankings queried tables')
client.close
declined.close
puts 'PASS Daily Krowa: completed round, confirmation, dedicated ranking, no solution leak, replay deduplication and denied tables'
