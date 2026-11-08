require_relative '../../support/categories'
require_relative '../../support/sequence_random'

game = GameRoomGames::Categories.new
assert(game.default_options['target_score'] == 50, 'New tables do not default to 50 points')
assert(game.normalize_options(game.default_options.merge('target_score' => 100))['target_score'] == 100,
  'The new default overwrote an explicit target')
repository = CategoriesRepository.new(%w[Alice Bob])
options = game.normalize_options(game.default_options.merge(
  'category_set' => 'custom', 'custom_categories' => ['country'],
  'round_category_count' => 1, 'round_time' => 10))
session = {'options' => JSON.generate(options)}
context = GameRoomGames::ActionContext.new(now: 100,
  hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source: GameRoomRandom::SequenceSource.new([1, 1]))
events = []
commit = lambda do |actor, selection = nil|
  replay = game.replay(session, events, repository)
  selection ||= game.automatic_action(replay, actor, context: context)
  assert(selection, "No action in #{replay.state[:phase]}")
  status, plan = game.action_for(selection, replay, actor, context: context)
  assert(status == :ok, "Action rejected in #{replay.state[:phase]}: #{status}")
  append_plan(events, plan, actor, now: context.now)
  game.replay(session, events, repository)
end

first_round = commit.call('Alice')
context.now = first_round.state[:deadline] + 3
commit.call('Alice') # No answers: the server closes the completed time window.
review = commit.call('Alice')
assert(review.state[:phase] == :review, 'The empty-answer fixture missed review')
commit.call('Alice', surface_action('review', 'finish', 'decisions' => {}))
completed = commit.call('Alice')
assert(completed.state[:phase] == :round_complete, 'Scoring did not finish the round')
finished_at = events.find { |entry| entry['action'] == 'round_finished' }.fetch('created_at')
assert(completed.state[:resume_at] == finished_at + 2, 'Pause is not based on the committed round-finish timestamp')
revision = events.map { |event| event.fetch('id') }

[finished_at, finished_at + 1].each do |now|
  context.now = now
  assert(game.automatic_action(completed, 'Alice', context: context).nil?, 'The next round started before the fixed pause')
  assert(!game.automatic_action_due?(completed, 'Alice', context: context), 'The executor wakes before the pause expires')
  status, plan = game.action_for({'kind' => 'automatic', 'action' => 'start_round'}, completed, 'Alice', context: context)
  assert(status != :ok && plan.nil?, 'A previously selected start bypassed the remaining pause')
end

context.now = finished_at + 2
assert(game.automatic_action_due?(completed, 'Alice', context: context),
  'An unchanged event revision never wakes the executor when the pause ends')
action = game.automatic_action(completed, 'Alice', context: context)
assert(action && action['action'] == 'start_round', 'No round start at the exact pause boundary')
assert(events.map { |event| event.fetch('id') } == revision, 'The pause needs an extra event instead of a local due check')
next_round = commit.call('Alice', action)
assert(next_round.state[:round] == 2 && next_round.state[:deadline] == context.now + 10,
  'The next answering clock included the score/pause interval')
assert(next_round.accepted_events.length == events.length, 'The normal history lost accepted events')

# A restored match can use another server epoch and a paused clock offset.
# Native timestamps must be translated exactly once into the game's epoch.
shifted_session = session.merge('__server_started_at' => 1_000, 'created_at' => 900, '__clock_offset' => 17)
shifted_events = events.take(revision.length).map { |entry| entry.merge('created_at' => entry['created_at'] + 117) }
shifted = game.replay(shifted_session, shifted_events, repository)
assert(shifted.state[:resume_at] == completed.state[:resume_at], 'Server/restore clock offset changed the two-second pause')
assert(game.automatic_action_due?(shifted, 'Alice', context: context), 'A restored game did not wake at the same game-time boundary')

# Completed history must include everyone, including a shared winner. This
# fixture uses the already-established two-point test threshold, not defaults.
final_session = {'options' => JSON.generate(options.merge('target_score' => 2, 'tie_mode' => 'shared'))}
final_context = GameRoomGames::ActionContext.new(session_id: 903, table_id: 904, now: 200,
  hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source: GameRoomRandom::SequenceSource.new([1, 1]))
final_events = []
play_unique_round(game, final_session, repository, final_events, final_context,
  owner: 'Alice', judge: 'Alice', answerer: 'Bob')
finished = play_unique_round(game, final_session, repository, final_events, final_context,
  owner: 'Alice', judge: 'Bob', answerer: 'Alice')
assert(finished.finished? && finished.draw, 'The final-history fixture did not finish normally')
totals = finished.history.select { |entry| entry.kind == :final_scores }
assert(totals.length == 1 && totals.first.text.include?('Alice: 2') && totals.first.text.include?('Bob: 2'),
  'Final history omitted or duplicated cumulative player scores')
assert(game.replay(final_session, final_events, repository).history.count { |entry| entry.kind == :final_scores } == 1,
  'Replaying finished history duplicated the final totals')

puts 'PASS Categories: default-only 50, committed timestamp, fixed pause, due wakeup, full next-round time, restored-clock offset and final cumulative history'
