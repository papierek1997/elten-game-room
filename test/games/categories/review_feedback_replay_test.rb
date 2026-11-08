require_relative '../../support/background_help_game_screen'
require_relative '../../support/sequence_random'
require_relative '../../../games/categories'

game = GameRoomGames::Categories.new
options = game.normalize_options(game.default_options.merge('category_set' => 'custom',
  'custom_categories' => %w[country city female_first_name], 'round_category_count' => 3, 'round_time' => 0))
game.define_singleton_method(:default_options) { options }
h, screen = screen_fixture(game)
context = GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
  hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new),
  random_source: GameRoomRandom::SequenceSource.new([1]), now: 1000)
h.submit('Alice', context: context)
h.submit('Bob', {'kind' => 'answer_sheet', 'action' => 'submit',
  'answers' => {'country' => 'Austria', 'city' => 'Athens', 'female_first_name' => 'Alice'}}, context: context)
h.submit('Alice', context: context)
h.submit('Bob', context: context)
h.submit('Alice', context: context)
initial = h.replay('Alice')
assert(initial.state[:phase] == :review, 'Review setup failed')

make_presenter = lambda do |viewer|
  speech = []
  presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { h.repositories['Alice'] },
    program: -> { Object.new }, viewer: -> { viewer }, client: -> { nil },
    surface_state: -> { {} }, clock: -> { 0 }, covered: -> { false },
    speech: ->(text) { speech << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
  presenter.process_new_events(initial, session: h.session)
  speech.clear
  [presenter, speech]
end
judge, judge_speech = make_presenter.call('Alice')
player, player_speech = make_presenter.call('Bob')
observer, observer_speech = make_presenter.call('Watcher')

layout = screen.send(:prepare_action_view, initial).layout
review = layout.surface.reuse_candidates.find { |surface| surface.is_a?(GameSurfaces::ReviewSurface) }
selected = nil
layout.surface.on_action { |selection| selected = selection }
review.fields[1].index = 1
review.fields[1].trigger(:select)
wait = GameScreen::WaitState.new(replay: initial, revision: h.repositories['Alice'].events_revision(initial.accepted_events))
alerts = []
screen.define_singleton_method(:alert) { |text| alerts << text }
screen.instance_variable_set(:@synchronizer, nil)
repository = h.repositories['Alice']
real_append = repository.method(:append_events)
fault = nil
repository.define_singleton_method(:append_events) do |**arguments|
  raise fault if fault
  real_append.call(**arguments)
end

# Exercise the actual inline task's stale/uncertain rejection path, not just
# ReviewSurface#emit_action. Neither may reach the acceptance callback.
[GameRoomSessionRunner::StaleView.new, GameRoomNetworkErrors::UncertainWrite.new('injected missing acknowledgement')].each do |error|
  fault = error
  screen.instance_variable_set(:@selected_surface_action, selected)
  h.as('Alice') { screen.send(:handle_inline_wait, wait, layout) }
  assert(review.state['confirmed'].empty?, "#{error.class} falsely confirmed the grade")
  assert(wait.replay.equal?(initial), 'A failed assessment replaced the accepted replay')
  assert(h.events('Alice').length == initial.accepted_events.length, 'Failure fixture wrote a grade')
  [judge, player, observer].each { |presenter| presenter.process_new_events(h.replay('Alice'), session: h.session) }
  assert(judge_speech.empty?, 'A failed assessment announced success')
  screen.instance_variable_set(:@automatic_recovery_pending, false)
end
fault = nil
review.fields[1].trigger(:select)
screen.instance_variable_set(:@selected_surface_action, selected)
h.as('Alice') { screen.send(:handle_inline_wait, wait, layout) }
item_id = selected['item_id']
assert(review.state['confirmed'] == {item_id => 'unique'}, 'An accepted write was not confirmed in the open form')
assert(wait.replay.state[:decisions] == {item_id => 'unique'}, 'The confirmed UI differs from the accepted replay')
assert(wait.revision == repository.events_revision(wait.replay.accepted_events), 'Inline acknowledgement lost its new revision')
accepted = h.replay('Alice')
3.times { [judge, player, observer].each { |presenter| presenter.process_new_events(accepted, session: h.session) } }
assert(judge_speech == ['Assessed.'], 'Accepted local assessment was silent or repeated')
assert(player_speech.none? { |line| line == 'Assessed.' } && observer_speech.none? { |line| line == 'Assessed.' },
  'Local acknowledgement leaked to another participant or observer')
assert(player_speech.any? { |line| line.include?('Austria') } && observer_speech == player_speech,
  'Other viewers lost the canonical assessment announcement')
assert(accepted.history.any? { |entry| entry.kind == :review && entry.text.include?('Austria') }, 'Assessment history was removed')
assert(accepted.history.none? { |entry| entry.text == 'Assessed.' }, 'Local acknowledgement entered canonical history')

# A rejected duplicate may be present in transport, but cannot generate a
# second local success. A newly opened view must not announce historical success.
event = h.events('Alice').last
h.write('Alice', game.send(:event_plan, event['action'], event['value']).events)
duplicate = h.replay('Alice')
assert(duplicate.accepted_events.length == accepted.accepted_events.length, 'The duplicate fixture was unexpectedly accepted')
judge.process_new_events(duplicate, session: h.session)
assert(judge_speech == ['Assessed.'], 'Rejected duplicate announced local success')
assert(game.describe_event(h.events('Alice').last, repository, duplicate, 'Alice').empty?, 'A directly described rejected grade announced success')
cold, cold_speech = make_presenter.call('Alice')
cold.last_seen_event_id = nil
cold.process_new_events(duplicate, session: h.session)
assert(cold_speech.empty?, 'Reopening the game replayed an old local success')

puts 'PASS Categories feedback: real inline stale/uncertain failures, same-choice retry, accepted model/UI, local success once, canonical history, other viewers, rejected duplicate and cold reconstruction'
