require_relative '../../support/duck_challenge_native'
require_relative '../../support/cat_head_tail'
require_relative '../../support/localization'
require_relative '../../../games/kosciane'
require_relative '../../../games/balut'
require_relative '../../../lib/game_screen'

Session.define_singleton_method(:name) { 'Alice' }

# Let the native Form#wait announce its own entry, then stop at its first
# ordinary input frame. Native forms do not emit a synthetic :update event.
class ScoringEntryDriver < DuckChallengeNativeDriver
  attr_accessor :stop_form
  def tick(form)
    super
    @score_ticks = @score_ticks.to_i + 1
    raise 'Scoring form did not reach its input boundary' if @score_ticks > 1000
    return unless form.equal?(stop_form) && form.instance_variable_get(:@wait)

    self.stop_form = nil
    form.resume_for_refresh
  end
end

class ScoreSelectionRepository < CatHeadTailRepository
  def session_id(_session); 7; end
end

def score_selection_screen(game, repository, session)
  screen = GameScreen.allocate
  {program: Object.new, repository: repository, game: game, session: session,
    table: {'__id'=>4}, table_owner: 'Alice', game_services: {}, activity_repository: nil,
    game_name: ->(id) { id.to_s }, presentation_ui_thread: Thread.current}.each do |key, value|
    screen.instance_variable_set("@#{key}", value)
  end
  screen.send(:initialize_view_state)
  screen.instance_variable_set(:@hidden_submissions, nil)
  screen.instance_variable_set(:@random_source, nil)
  screen
end

games = [GameRoomGames::Yahtzee.new, GameRoomGames::Kosciane.new, GameRoomGames::Balut.new]
%w[en pl cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  games.each do |game|
    native = ScoringEntryDriver.new
    repository = ScoreSelectionRepository.new(%w[Alice Bob])
    session = {'__id'=>7, '__players'=>%w[Alice Bob], 'options'=>JSON.generate(game.default_options)}
    events = 3.times.map { |index| cht_event(index+1, 'Alice', 'roll', '2,2,5,5,5') }
    second = game.replay(session, events.first(2), repository)
    third = game.replay(session, events, repository)
    assert(game.game_view_spec(second, 'Alice').decision_focus_key.nil?, 'An unfinished roll enters scoring')
    screen = score_selection_screen(game, repository, session)
    before = screen.send(:prepare_action_view, second)
    screen.send(:remember_layout_position, before.layout)
    screen.instance_variable_set(:@suppress_surface_focus, true)
    view = screen.send(:prepare_action_view, third)
    assert(view.announce_finished_focus && !view.silent_entry,
      "#{language}/#{game.id}: third roll still opens scoring silently")
    layout = view.layout
    form = layout.form
    native.stop_form = form
    SpeechOutput.reset
    form.wait
    spoken = SpeechOutput.calls.map(&:first)
    if game.id == 'yahtzee'
      prompt = GameRoomLocalization.translate('Choose a scoring category')
      first = game.surface_spec(third, 'Alice').categories.first.label
    else
      prompt = game.send(:score_sheet_title, third.state, 'Alice')
      first = game.send(:score_grid, third.state, 'Alice', writable: true).cells.first.first
    end
    assert(spoken.size == 1 && spoken.first.include?(prompt) && spoken.first.include?(first),
      "#{language}/#{game.id}: native scoring entry omits or repeats its prompt/first result: #{spoken.inspect}")
    screen.send(:remember_layout_position, layout)
    screen.instance_variable_set(:@suppress_surface_focus, true)
    repeated = screen.send(:prepare_action_view, third)
    assert(!repeated.announce_finished_focus && repeated.silent_entry, 'Unchanged scoring view repeats its announcement')
    assert(game.game_view_spec(third, 'Bob').decision_focus_key.nil?, 'Another player receives the scoring decision')
    assert(game.game_view_spec(third, 'Watcher').decision_focus_key.nil?, 'An observer receives the scoring decision')

    [:chat, :history, :users].each do |section|
      quiet = score_selection_screen(game, repository, session)
      previous = quiet.send(:prepare_action_view, second).layout
      previous.chat.set_text('Unsent draft')
      previous.form.index = previous.form.fields.index(previous.public_send(section))
      quiet.send(:remember_layout_position, previous)
      quiet.instance_variable_set(:@suppress_surface_focus, true)
      next_view = quiet.send(:prepare_action_view, third)
      assert(next_view.layout.focus_location.first == section && !next_view.announce_finished_focus,
        "Scoring interrupts #{section}")
      assert(next_view.layout.chat.text == 'Unsent draft', 'Scoring clears the chat draft')
    end
  end
end
puts 'PASS third-roll scoring: real GameScreen view preparation and native form entry, one prompt/first result, quiet refresh and room-focus safety in all three games/five languages'
