require_relative '../../support/duck_challenge_native'
require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'

GameRoomLocalization.boot(settings: {'interface_language'=>'en'}, host_language: 'en')
game = GameRoomGames::Kosciane.new
players = %w[Alice Bob]
repository = CatHeadTailRepository.new(players)
session = {'options'=>JSON.generate(game.default_options)}
events = 3.times.map { |index| cht_event(index + 1, 'Alice', 'roll', '2,2,5,5,5') }
replay = game.replay(session, events, repository)
spec = game.surface_spec(replay, 'Alice')
assert(spec.row_actions.length == replay.state[:match_model].categories.length,
  'A category is listed separately for its score and for crossing out')
assert(spec.cells[4].first == 'Fives: record 15', 'Three fives do not show their normal score')
assert(spec.cells.first.first == 'Ones: record 0', 'An unavailable combination does not show zero')
assert(spec.cells.flatten.none? { |label| label.to_s.include?('Cross out') }, 'Cross-out UI remains')

# A scoring row remains reachable by native navigation and submits its normal
# result, not the former alternative zero for the same category.
scoring_surface = GameSurfaces.build(spec)
driver = DuckChallengeNativeDriver.new
scoring_form = driver.form(scoring_surface)
scoring_actions = []
scoring_surface.on_action { |selection| scoring_actions << selection.to_h }
SpeechOutput.reset
4.times do
  driver.frame(scoring_form, driver.tap(0x28))
  driver.frame(scoring_form)
end
spoken = SpeechOutput.calls.map(&:first)
assert(spoken.last.include?('Fives: record 15'), 'Native navigation does not read the single scoring row')
assert(spoken.none? { |text| text.include?('Score sheet: Alice') }, 'Navigation reread the whole score-sheet prompt')
driver.frame(scoring_form, driver.tap(0x0d))
assert(scoring_actions.one? && scoring_actions.first['category'] == '5', 'The scoring row submitted zero instead of its result')
assert(game.action_for(scoring_actions.first, replay, 'Alice').first == :ok, 'The displayed positive score cannot be recorded')
scored = game.replay(session, events + [cht_event(4, 'Alice', 'score', '5')], repository)
assert(scored.state[:match_model].total('Alice') == 15, 'Three fives were not recorded as fifteen points')

surface = GameSurfaces.build(spec)
driver = DuckChallengeNativeDriver.new
form = driver.form(surface)
actions = []
surface.on_action { |selection| actions << selection.to_h }
SpeechOutput.reset
driver.frame(form, driver.tap(0x0d))
assert(actions.one? && actions.first['category'] == 'cross:1', 'The native zero row does not select its failed result')
assert(game.action_for(actions.first, replay, 'Alice').first == :ok, 'The displayed zero cannot be recorded')
events << cht_event(4, 'Alice', 'score', actions.first['category'])
recorded = game.replay(session, events, repository)
assert(recorded.state[:match_model].total('Alice') == 0 && recorded.current_player == 'Bob',
  'Recording zero did not end the turn without points')
assert(recorded.history.last.text.start_with?('Alice records 0 in Ones, column 1.'), 'History still describes a separate cross')
assert(game.send(:cell_label, :cross) == '0', 'A completed zero is not displayed as a number')
assert(game.score_sheet_choices(recorded.state, 'Alice').first.label.start_with?('Ones: 0,'),
  'The score-sheet readout hides the zero')

# B before the third roll still offers only results the dice can score.
early = game.replay(session, events.first(1), repository)
grid = game.send(:score_grid, early.state, 'Alice', writable: true)
assert(grid.row_actions.none? { |action| action['category'].start_with?('cross:') }, 'Zero was offered before the third roll')
assert(grid.row_actions.count { |action| action['category'] == '5' } == 1, 'Early fives are absent or duplicated')
puts 'PASS General zero entries: one native row per category, normal points or zero, actual Enter/replay, numeric stored view and no premature zero'
