require_relative '../../support/background_help_game_screen'
require_relative '../../support/session_runner'
require_relative '../../support/sequence_random'

module CategoriesReviewAckContract
  module_function

  def fixture
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
    replay = h.replay('Alice')
    assert(replay.state[:phase] == :review, 'Fixture did not reach review')
    runner = runner_for(h, 'Alice', covered: -> { false })
    screen.instance_variable_set(:@session_runner, runner)
    # The real writer/runner handles the receipt. Scheduling the next UI retry
    # is not part of this boundary test, so keep the sync policy outside it.
    screen.instance_variable_set(:@synchronizer, nil)
    alerts = []
    screen.define_singleton_method(:alert) { |message| alerts << message }
    layout = screen.send(:prepare_action_view, replay).layout
    review = layout.surface.reuse_candidates.find { |surface| surface.is_a?(GameSurfaces::ReviewSurface) }
    wait = GameScreen::WaitState.new(replay: replay, revision: h.repositories['Alice'].events_revision(replay.accepted_events))
    [h, screen, runner, layout, review, wait, alerts]
  end

  def select(layout, review, decision_index)
    selected = nil
    layout.surface.on_action { |action| selected = action }
    review.fields[1].index = decision_index
    review.fields[1].trigger(:select)
    assert(selected, 'Choice failed to emit an action')
    selected
  end

  def submit(h, screen, wait, layout, selected)
    screen.instance_variable_set(:@selected_surface_action, selected)
    h.as('Alice') { screen.send(:handle_inline_wait, wait, layout) }
  end
end

evidence = []
[:before, :after].each do |fault|
  h, screen, runner, layout, review, wait, alerts = CategoriesReviewAckContract.fixture
  begin
    selected = CategoriesReviewAckContract.select(layout, review, 1)
    id = selected['item_id']
    before_entries = h.core.entries.length
    before_events = wait.replay.accepted_events.length
    h.broker.automatic_delivery = false
    native = h.view('Alice')
    native.fail_next_push = fault
    CategoriesReviewAckContract.submit(h, screen, wait, layout, selected)
    assert(review.state['confirmed'].empty?, "#{fault}: a missing native receipt optimistically confirmed a grade")
    assert(wait.replay.accepted_events.length == before_events, "#{fault}: the failed inline action replaced the local accepted replay")
    expected_written = fault == :after ? 1 : 0
    assert(h.core.entries.length == before_entries + expected_written, "#{fault}: fault did not happen at its intended native boundary")
    attempted_id = native.instance_variable_get(:@push_attempts).last.first
    # New cursor selection remains local; recovery must never use it to
    # replace the original grade whose receipt is currently unknown.
    review.fields[1].index = 2
    h.as('Alice') { assert(h.transports['Alice'].reconcile(h.table['__id']), 'Native receipt recovery failed') }
    recovered = h.replay('Alice')
    assert(recovered.state[:decisions] == {id => 'unique'}, "#{fault}: recovery used a newer unsent choice")
    assert(h.core.entries.length == before_entries + 1, "#{fault}: receipt recovery duplicated the grade")
    assert(native.instance_variable_get(:@push_attempts).last.first == attempted_id, "#{fault}: recovery changed the operation identity")
    restored = GameSurfaces.build(h.game.surface_spec(recovered, 'Alice'), state: layout.surface.state)
    restored_review = restored.reuse_candidates.find { |surface| surface.is_a?(GameSurfaces::ReviewSurface) }
    assert(restored_review.state['confirmed'] == {id => 'unique'}, "#{fault}: authoritative recovery failed to confirm the accepted grade")
    assert(restored_review.state['decisions'][id] == 'partial', "#{fault}: rebuilding discarded an unsubmitted cursor choice")
    emitted = []
    restored.on_action { |action| emitted << action }
    restored_review.fields[1].index = 1
    restored_review.fields[1].trigger(:select)
    assert(emitted.empty?, "#{fault}: the recovered grade was sent again on Enter")
    evidence << {native_fault: fault, accepted_grade: recovered.state[:decisions], additional_records: h.core.entries.length - before_entries}
  ensure
    runner.close
  end
end

# A callback received before an HTTP timeout is already a valid receipt. The
# live form may confirm that action once, then clear it through another real
# accepted action; neither path relies on merely invoking the local handler.
h, screen, runner, layout, review, wait, alerts = CategoriesReviewAckContract.fixture
begin
  selected = CategoriesReviewAckContract.select(layout, review, 1)
  id = selected['item_id']
  before_entries = h.core.entries.length
  h.view('Alice').fail_next_push = :after
  CategoriesReviewAckContract.submit(h, screen, wait, layout, selected)
  assert(review.state['confirmed'] == {id => 'unique'}, 'A native callback receipt was lost when the HTTP reply timed out')
  assert(wait.replay.state[:decisions] == {id => 'unique'}, 'The open form confirmed something other than the accepted model grade')
  assert(h.core.entries.length == before_entries + 1, 'A confirmed callback duplicated the action')
  clearing = CategoriesReviewAckContract.select(layout, review, 0)
  assert(review.state['confirmed'] == {id => 'unique'}, 'Choosing Not assessed cleared the confirmed grade before acceptance')
  CategoriesReviewAckContract.submit(h, screen, wait, layout, clearing)
  assert(review.state['confirmed'].empty? && wait.replay.state[:decisions].empty?, 'Accepted clearing failed to remove the confirmed grade')
  retried = CategoriesReviewAckContract.select(layout, review, 1)
  CategoriesReviewAckContract.submit(h, screen, wait, layout, retried)
  assert(review.state['confirmed'] == {id => 'unique'} && h.core.entries.length == before_entries + 3, 'Cleared grade was not retryable exactly once')
  evidence << {native_fault: 'after with callback', accepted_grade: review.state['confirmed'], additional_records: h.core.entries.length - before_entries}
ensure
  runner.close
end

puts JSON.pretty_generate(evidence)
puts 'PASS independent Categories receipt boundaries: native before/after timeout, no optimistic confirmation, stable recovery identity, newer local choice, callback-before-timeout, accepted clearing and retry'
