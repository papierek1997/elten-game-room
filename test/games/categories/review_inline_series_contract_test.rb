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
assert(h.replay('Alice').state[:phase] == :review, 'Fixture did not reach review')

# Use the production GameScreen#run, runner and event presenter. Only the
# existing test host's control driver and speech sink are used here. In
# particular this test must not call process_new_events itself: doing so hid
# the missing production presentation after a successful inline assessment.
stage, frames, item_index = :settle, 0, 1
per_grade, surface_ids = [], []
chosen_field = nil
$spoken_messages.clear
Form.driver = lambda do |form|
  layout = screen.instance_variable_get(:@layout)
  review = layout.surface.reuse_candidates.find { |surface| surface.is_a?(GameSurfaces::ReviewSurface) }
  raise 'Review unexpectedly disappeared' unless review
  frames += 1
  case stage
  when :settle
    next if frames < 150
    assert(screen.instance_variable_get(:@session_runner), 'Full GameScreen did not start its real runner')
    layout.chat.set_text('Unsent draft during assessment')
    layout.chat.restore_selection(index: 4, check: 9)
    layout.history.restore_selection(index: 0, check: 5)
    stage, frames = :submit, 0
  when :submit
    field = review.fields.fetch(item_index)
    chosen_field = field
    form.index = form.fields.index(field)
    field.index = 1
    surface_ids << review.object_id
    field.trigger(:select)
    stage, frames = :wait_for_acceptance, 0
  when :wait_for_acceptance
    assert(review.state['confirmed'].length == item_index, 'Inline action did not update the accepted UI grade')
    assert(form.fields[form.index.to_i].equal?(chosen_field), 'Inline acknowledgement moved focus away from the assessed answer')
    assert(layout.chat.text == 'Unsent draft during assessment' && [layout.chat.index, layout.chat.check] == [4, 9],
      'Inline acknowledgement changed an unrelated chat draft or selection')
    assert([layout.history.index, layout.history.check] == [0, 5], 'Inline acknowledgement moved the existing history selection')
    next if frames < 150
    per_grade << {accepted: review.state['confirmed'].length,
      acknowledgements: $spoken_messages.count { |message| message == 'Assessed.' },
      presenter_event: screen.send(:event_presenter).last_seen_event_id}
    item_index += 1
    if item_index <= 3
      stage, frames = :submit, 0
    else
      actual = h.replay('Alice')
      details = {per_grade: per_grade, accepted_decisions: actual.state[:decisions],
        review_history: actual.history.count { |entry| entry.kind == :review },
        history_control: layout.history.items.dup,
        last_accepted_event: actual.accepted_events.last['__id'],
        speech: $spoken_messages.dup, surface_ids: surface_ids}
      puts JSON.pretty_generate(details)
      assert(actual.state[:decisions].length == 3 && details[:review_history] == 3, 'Native broker did not accept all three distinct grades')
      assert(per_grade.map { |row| row[:acknowledgements] } == [1, 2, 3],
        'Each accepted inline grade must reach the ordinary presenter once, before another action is needed')
      assert(screen.send(:event_presenter).last_seen_event_id == actual.accepted_events.last['__id'], 'Inline presentation cursor did not follow the accepted replay')
      reviews = actual.history.select { |entry| entry.kind == :review }.map(&:text)
      assert(reviews.all? { |text| layout.history.items.include?(text) }, 'Accepted inline grades are missing from the existing history control')
      # A later normal metadata/feed refresh must not replay the local success
      # or recreate any assessment. Do not manually invoke a presentation hook.
      h.transports.fetch('Alice').update_room(h.table, {'name' => 'Quiet refresh after three assessments'}, actor: 'Alice')
      stage, frames = :late_refresh, 0
    end
  when :late_refresh
    next if frames < 200
    assert($spoken_messages.count { |message| message == 'Assessed.' } == 3, 'A later feed duplicated an inline acknowledgement')
    assert(h.replay('Alice').history.count { |entry| entry.kind == :review } == 3, 'A later feed duplicated assessment history')
    assert(review.state['confirmed'].length == 3, 'A quiet refresh forgot accepted grades')
    assert(form.fields[form.index.to_i].equal?(chosen_field) && layout.chat.text == 'Unsent draft during assessment',
      'Late feed refresh moved focus or cleared the draft')
    assert([layout.history.index, layout.history.check] == [0, 5], 'Late feed refresh moved the history selection')
    stage = :done
    layout.back_button.trigger(:press)
  end
end

begin
  h.as('Alice') { assert(screen.run == :back, 'Normal review exit failed') }
  assert(stage == :done, 'Inline series did not complete')
ensure
  Form.driver = nil
end
puts 'PASS Categories real inline series: three native accepted grades, one ordinary presentation each, later feed deduplication and canonical history'
