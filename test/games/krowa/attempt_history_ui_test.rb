require_relative '../../support/room_interface'
require_relative '../../support/krowa_services'
require_relative '../../../games/krowa_support/client'

# Deterministic control drivers exercise the actual forms, client and store.
# Native worker/thread scope is covered by leaderboard_task_scope_test.
module EltenAPI::Tasks
  def self.run(**_options); yield; end
end

def alert(_message); end

class TableBox < ListBox
  attr_reader :columns, :rows
  def initialize(columns, rows, **options)
    @columns, @rows = columns, rows
    super(rows, **options)
  end
end

%w[random daily].each do |variant|
  [0, 1, 2, :escape].each do |choice|
    run = KrowaTestGame.new(variant: variant)
    run.automatic
    solution = run.context.hidden_submissions.reveal(session_id: 10, round_id: 'krowa:1', user: 'Alice').payload['word']
    run.guess('Alice', solution); 2.times { run.automatic }
    tables = KrowaTestTables.new
    client = run.game.build_client(run.program, server_tables: tables)
    assert(client.start, 'publication client startup')
    client.define_singleton_method(:definition_dialog) { |_| }
    publisher = client.instance_variable_get(:@leaderboards)
    publisher.define_singleton_method(:show_word_ranking) { |_| }
    publisher.define_singleton_method(:show_daily_ranking) { |_| }
    prompts = 0
    Form.driver = lambda do |form|
      prompts += 1
      list = form.fields.first
      assert(list.options == ['Publish', 'Publish without attempt list', 'Do not publish'], 'publication choices')
      assert(list.index == 0, 'publication must initially select Publish')
      assert(list.instance_variable_get(:@flags) == ListBox::Flags::LeftRight, 'publication must use Left/Right navigation')
      if choice == :escape
        form.cancel_button.trigger(:press)
      else
        list.index = choice
        form.accept_button.trigger(:press)
      end
    end
    2.times { client.after_events(run.replay, 'Alice', context: run.context) }
    assert(prompts == 1, 'publication was offered twice')
    name = variant == 'daily' ? 'krowa_daily_scores' : 'krowa_word_scores'
    scores = tables.fetch(name).rows
    if choice == 0 || choice == 1
      assert(scores.length == 1, 'consented result missing')
      assert(scores.first.key?('history_key') == (choice == 0), 'attempt consent ignored')
    else
      assert(scores.empty?, 'declining or escaping published a result')
    end
    client.close
  end
end

%w[random daily].each do |variant|
  surrendered = KrowaTestGame.new(variant: variant)
  surrendered.automatic; surrendered.surrender('Alice'); surrendered.automatic
  surrender_client = surrendered.game.build_client(surrendered.program, server_tables: KrowaTestTables.new)
  surrender_client.start
  surrender_client.define_singleton_method(:definition_dialog) { |_| }
  Form.driver = ->(_) { raise 'Publication was offered after surrender' }
  surrender_client.after_events(surrendered.replay, 'Alice', context: surrendered.context)
  surrender_client.close
end

retry_run = KrowaTestGame.new
retry_run.automatic
answer = retry_run.context.hidden_submissions.reveal(session_id: 10, round_id: 'krowa:1', user: 'Alice').payload['word']
retry_run.guess('Alice', answer); 2.times { retry_run.automatic }
retry_tables = KrowaTestTables.new
score_table = retry_tables.fetch('krowa_word_scores')
insert = score_table.method(:insert)
score_writes = 0
score_table.define_singleton_method(:insert) do |values|
  score_writes += 1
  score_writes == 1 ? nil : insert.call(values)
end
retry_client = retry_run.game.build_client(retry_run.program, server_tables: retry_tables)
retry_client.start
retry_client.define_singleton_method(:definition_dialog) { |_| }
retry_client.instance_variable_get(:@leaderboards).define_singleton_method(:show_word_ranking) { |_| }
retry_prompts = 0
Form.driver = lambda do |form|
  retry_prompts += 1
  form.fields.first.index = retry_prompts == 1 ? 0 : 1
  form.accept_button.trigger(:press)
end
retry_client.after_events(retry_run.replay, 'Alice', context: retry_run.context)
assert(retry_prompts == 2 && score_table.rows.length == 1, 'failed publication could not be retried explicitly')
assert(!score_table.rows.first.key?('history_key'), 'retry ignored the changed sharing choice')
assert(retry_tables.fetch('krowa_attempt_lists').rows.length == 1, 'explicit retry duplicated history')
retry_client.close

game = KrowaTestGame.new.game
selected, reads = 0, 0
details = GameRoomGames::KrowaAttemptListView.new(game, selection: -> { selected }) do |index|
  reads += 1
  index == 0 ? {word: 'kot', words: %w[las kot]} : nil
end
assert(reads == 0, 'constructing a list performed I/O')
selected = 1; selected = 0
assert(reads == 0, 'moving between results performed I/O')
details.field.trigger(:before_focus)
assert(details.field.options == ['las. 0', 'kot. 3'], 'word/match presentation')
details.field.index = 1
details.field.trigger(:before_focus)
assert(reads == 1 && details.field.index == 1, 'returning to the same history reloaded it or moved its cursor')
selected = 1
details.field.trigger(:before_focus)
assert(details.field.options.empty? && details.field.empty_label == 'No recorded attempts', 'legacy entry retained another result history')

run = KrowaTestGame.new
tables = KrowaTestTables.new
store = GameRoomGames::KrowaServerStore.new(server_tables: tables, bank: run.bank, user: 'Alice')
store.publish_word('kot', 2, words: %w[las kot])
store.publish_word('las', 1)
ranking = GameRoomGames::KrowaLeaderboardClient.new(run.program, run.game, store: store)
Form.driver = lambda do |form|
  assert(form.fields[1].header == 'Attempt list', 'Tab from ranking does not reach history')
  form.fields[1].trigger(:before_focus)
  assert(form.fields[1].options == ['las. 0', 'kot. 3'], 'ranking history for selected user')
  form.cancel_button.trigger(:press)
end
ranking.show_word_ranking('kot')

client = run.game.build_client(run.program, server_tables: tables)
client.start
profile = client.instance_variable_get(:@profile)
profile.data['gallery'].merge!('kot' => {'attempts' => 2, 'at' => 1, 'words' => %w[las kot]},
  'las' => {'attempts' => 1, 'at' => 2})
Form.driver = lambda do |form|
  list, attempts = form.fields.first(2)
  assert(list.options == ['las: 1 attempts', 'kot: 2 attempts'], 'gallery must show words and attempts only, newest first')
  attempts.trigger(:before_focus)
  assert(attempts.options.empty?, 'legacy gallery entry invented attempts')
  list.index = 1
  attempts.trigger(:before_focus)
  assert(attempts.options == ['las. 0', 'kot. 3'], 'gallery history is not under Tab')
  form.cancel_button.trigger(:press)
end
client.open_gallery

day = '2026-10-29'
tables.fetch('krowa_daily_assignments').insert('day_key' => 20261029,
  'assignment' => GameRoomKrowa::DailyAssignment.seal(day, 'kot'))
store.record_daily_open(day)
store.publish_daily(day, 1, words: ['kot'])
GameRoomClock.define_singleton_method(:synchronize) { true }
GameRoomClock.define_singleton_method(:synchronized?) { true }
server_day = Time.utc(2026, 10, 29, 12)
GameRoomClock.define_singleton_method(:now) { server_day.to_f }
Form.driver = lambda do |form|
  attempts = form.fields[1]
  before = tables.fetch('krowa_attempt_lists').queries.length
  attempts.trigger(:before_focus)
  assert(attempts.options.empty? && attempts.empty_label.start_with?("Today's Daily Krowa"), 'current daily attempts displayed')
  assert(tables.fetch('krowa_attempt_lists').queries.length == before, 'today attempts downloaded')
  server_day = Time.utc(2026, 10, 30, 12)
  attempts.trigger(:before_focus)
  assert(attempts.options == ['kot. 3'], 'midnight did not unlock history on refocus')
  form.cancel_button.trigger(:press)
end
ranking.send(:show_daily_ranking, day)

# Completed tower rounds retain separate checked lists without changing the
# existing publication identity or adding any tower words to the gallery.
tower = KrowaTestGame.new(variant: 'tower', players: %w[Alice Bob])
tower.automatic
secret = tower.context.hidden_submissions.reveal(session_id: 10, round_id: 'krowa:1', user: 'Alice').payload['word']
tower.guess('Alice', secret); 2.times { tower.automatic }
tower.automatic
tower.surrender('Alice'); tower.automatic
completed = tower.replay
tower_client = tower.game.build_client(tower.program, server_tables: tables)
tower_client.start
histories = GameRoomGames::KrowaAttemptHistory.rounds(completed)
rounds = tower_client.send(:tower_publication_rounds, completed.state, histories: histories)
assert(rounds.first[:words] == [secret] && rounds.last[:words].empty?, 'tower rounds mixed their lists')
without_lists = rounds.map { |round| round.reject { |key, _| key == :words } }
assert(tower_client.send(:tower_run_code, completed, rounds) == tower_client.send(:tower_run_code, completed, without_lists), 'history changed existing tower run identity')
tower_client.instance_variable_get(:@profile).observe(completed)
assert(tower_client.instance_variable_get(:@profile).data['gallery'].empty?, 'tower words entered solo gallery')
Form.driver = nil
client.close; tower_client.close
puts 'PASS Krowa attempt UI: publication choices/escape, lazy Tab lists, exact selections, legacy entries, server midnight and tower identity'
