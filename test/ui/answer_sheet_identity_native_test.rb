require_relative '../support/background_help_native'
require_relative '../support/assertions'
require EltenTestHost.file('src/ui/controls/grid_box.rb')
GridBox = EltenAPI::Controls::GridBox
Session = EltenAPI::Structs::Session unless defined?(Session)
Session.name = 'Bob'
require_relative '../../lib/game_surfaces'
require_relative '../../lib/game_layout'
require_relative '../../games/categories'

include GameRoomTest::Assertions
$native_tutorial_driver = BackgroundHelpNativeDriver.new

game = GameRoomGames::Categories.new
state = {phase: :answering, round: 1, attempt: 1, options: game.default_options, players: %w[Alice Bob],
  judge: 'Alice', letter: 'A', active_players: ['Bob'], commitments: {},
  round_categories: %w[country city], category_letters: {}}
sheet = game.send(:answering_surface, state, 'Bob')
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: sheet),
  history_items: [], user_items: %w[Alice Bob], users_header: 'People')

def answer_fields(layout)
  layout.surface.fields.grep(EditBox)
end

def update_sheet(layout, sheet, saved)
  layout.update(view_spec: GameRoomLayout::ViewSpec.new(surface: sheet), surface_state: saved,
    history_items: [], user_items: %w[Alice Bob], users_header: 'People')
end

answer_fields(layout)[0].set_text('Austria')
answer_fields(layout)[1].set_text('Athens')
saved = layout.snapshot.surface_state
assert_equal(sheet.id, saved['sheet_id'], 'The local answer draft lost its sheet identity')

update_sheet(layout, game.send(:answering_surface, state, 'Bob'), saved)
assert_equal(%w[Austria Athens], answer_fields(layout).map(&:text),
  'Refreshing the same round discarded unfinished input')
assert_equal({'country' => 'Austria', 'city' => 'Athens'}, layout.surface.submission_action['answers'])

# The client can miss review/summary while disconnected or covered by another
# native scene. Recovery then rebuilds directly from the last displayed sheet.
next_sheet = game.send(:answering_surface, state.merge(round: 2, attempt: 2, letter: 'B'), 'Bob')
assert(sheet.id != next_sheet.id, 'The production model did not select another round')
update_sheet(layout, next_sheet, saved)
assert_equal(['', ''], answer_fields(layout).map(&:text),
  'Previous-round answers leaked into the next sheet')
assert_equal(next_sheet.id, layout.surface.submission_action['sheet_id'])
assert_equal({'country' => '', 'city' => ''}, layout.surface.submission_action['answers'])

answer_fields(layout)[0].set_text('Belgium')
update_sheet(layout, next_sheet, layout.snapshot.surface_state)
assert_equal(['Belgium', ''], answer_fields(layout).map(&:text),
  'A second refresh discarded input belonging to the new round')

retry_sheet = game.send(:answering_surface, state.merge(round: 2, attempt: 3, letter: 'C'), 'Bob')
assert(next_sheet.id != retry_sheet.id, 'The production model reused a sheet for a new attempt')
update_sheet(layout, retry_sheet, layout.snapshot.surface_state)
assert_equal(['', ''], answer_fields(layout).map(&:text),
  'A new attempt reused the abandoned attempt draft')

defaults = GameSurfaces::AnswerSheetSpec.new(id: 'defaults', fields: [
  GameSurfaces::AnswerField.new(id: 'country', label: 'Country', value: 'Canada')])
update_sheet(layout, defaults, saved)
assert_equal(['Canada'], answer_fields(layout).map(&:text), 'A new sheet lost its field default')
answer_fields(layout)[0].set_text('Chile')
update_sheet(layout, defaults, layout.snapshot.surface_state)
assert_equal(['Chile'], answer_fields(layout).map(&:text), 'A same-sheet default overwrote local edits')

legacy = GameSurfaces.build(sheet, state: {'answers' => {'country' => 'Austria'}})
assert_equal({'country' => 'Austria', 'city' => ''}, legacy.state['answers'],
  'A legacy local snapshot lost its unfinished input')
symbol_keys = GameSurfaces.build(sheet,
  state: {sheet_id: 'another_sheet', answers: {country: 'Do not reuse'}})
assert_equal({'country' => '', 'city' => ''}, symbol_keys.state['answers'])

puts 'PASS Native answer sheets preserve same-round drafts and reset different rounds/attempts through the shared layout'
