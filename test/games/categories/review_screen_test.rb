require_relative "../../support/background_help_game_screen"
require_relative "../../support/sequence_random"
require_relative "../../../games/categories"

# Arrange an ordinary committed/revealed answer sheet, then exercise the actual
# ReviewSurface -> GameScreen#run -> SessionRunner -> native stack boundary.
game = GameRoomGames::Categories.new
configured_options = game.normalize_options(game.default_options.merge(
  'category_set' => 'custom', 'custom_categories' => %w[country city female_first_name],
  'round_category_count' => 3, 'round_time' => 0))
game.define_singleton_method(:default_options) { configured_options }
$game_room_test_user = 'Alice'
h, screen = screen_fixture(game)
screen.instance_variable_set(:@game_services, {transport: h.transports['Alice']})
vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
context = GameRoomGames::ActionContext.new(session_id: h.session['__id'], table_id: h.table['__id'],
  hidden_submissions: vault, random_source: GameRoomRandom::SequenceSource.new([1]), now: 1000)
h.submit('Alice', context: context)
h.submit('Bob', {'kind' => 'answer_sheet', 'action' => 'submit',
  'answers' => {'country' => 'Austria', 'city' => 'Athens', 'female_first_name' => 'Alice'}}, context: context)
h.submit('Alice', context: context)
h.submit('Bob', context: context)
h.submit('Alice', context: context)
before = h.replay('Alice')
assert(before.state[:phase] == :review && before.state[:decisions].empty?, 'review setup failed')
prefix_count = before.accepted_events.length

# Confirm three groups, clear the second, confirm its corrected grade, finish.
choices = [[0, 1], [1, 2], [2, 3], [1, 0], [1, 1]]
step, finished = 0, false
review_surface, review_form, runner = nil, nil, nil
submissions = []
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
Form.driver = lambda do |form|
  raise "Review stopped at step #{step}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  if runner.nil?
    runner = screen.instance_variable_get(:@session_runner)
    assert(runner.is_a?(GameRoomSessionRunner), 'screen did not create the real session runner')
    real_submit = runner.method(:submit)
    runner.define_singleton_method(:submit) do |**arguments|
      result = real_submit.call(**arguments)
      submissions << {revision: arguments.fetch(:replay).accepted_events.length,
        action: arguments.fetch(:selection)['action'], result: result.first}
      result
    end
  end
  events = h.events('Alice')
  if step <= choices.length
    layout = screen.instance_variable_get(:@layout)
    surface = layout.surface.reuse_candidates.find { |candidate| candidate.is_a?(GameSurfaces::ReviewSurface) }
    assert(surface, 'judge did not receive the production review surface')
    review_surface ||= surface
    review_form ||= form
    assert(surface.equal?(review_surface) && form.equal?(review_form), 'inline review unexpectedly rebuilt its form')
    assert(events.length == prefix_count + step, 'earlier inline grade was not committed exactly once')
    if step < choices.length
      index, choice = choices[step]
      control = surface.fields[1 + index]
      control.index = choice
      step += 1
      control.trigger(:select)
    else
      step += 1
      surface.fields.last.trigger(:press)
    end
  elsif events.any? { |event| event['action'] == 'review_commit' }
    assert(events.count { |event| event['action'] == 'review_commit' } == 1, 'final review duplicated')
    finished = true
    screen.instance_variable_get(:@layout).back_button.trigger(:press)
  end
end
h.as('Alice') { assert(screen.run == :back, 'review changed the ordinary exit behavior') }
assert(finished && submissions.length == 6, 'not all inline/final actions traversed the real runner')
assert(submissions.all? { |entry| entry[:result] == :ok }, 'runner rejected an inline or final grade')
assert(submissions.map { |entry| entry[:revision] } == (prefix_count..prefix_count + 5).to_a,
  'later grade/final submission reused an older accepted-event revision')
replay = h.replay('Alice')
assert(replay.accepted_events.length == h.events('Alice').length, 'committed review events were rejected by replay')
assert(replay.history.count { |entry| entry.kind == :review_end } == 1, 'review finish history missing or duplicated')
changes = h.events('Alice').drop(prefix_count).map { |event| event['action'] }
assert(changes.first(6) == %w[review_unique review_partial review_incorrect review_clear review_unique review_commit],
  'multi-step review changed event ordering or omitted the correction')
h.assert_converged('inline grades and final review')
puts 'PASS Categories GameScreen: five inline assessments/corrections and final review use six successive real-runner revisions, one form, no duplicate events'
