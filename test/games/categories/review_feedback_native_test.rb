require_relative '../../support/background_help_native'
require_relative '../../support/assertions'
require EltenTestHost.file('src/ui/controls/grid_box.rb')
GridBox = EltenAPI::Controls::GridBox
require_relative '../../../lib/game_surfaces'
require_relative '../../../games/categories'

include GameRoomTest::Assertions

class CategoriesReviewNativeDriver
  def initialize
    @serial = 0
    EltenAPI::KeyboardState.reset
    $native_tutorial_driver = self
  end

  def tick(_form)
    snapshot([])
  end

  def snapshot(events)
    @serial += 1
    EltenAPI::KeyboardState.update(raw_state: "\0" * 256, events: events, now: @serial * 0.016,
      pressed_implies_held: false, synthesize_repeats: false)
    $input_frame_serial = @serial
    $keyboard_state_frame_serial = @serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
  end

  def press(form, code)
    raw = "\0" * 256
    raw.setbyte(code, 0x80)
    snapshot([[code, true, raw], [code, false]])
    form.update
    snapshot([])
    form.update
  end
end

driver = CategoriesReviewNativeDriver.new
game = GameRoomGames::Categories.new
state = {phase: :review, options: game.default_options, category_letters: {}, round: 1, attempt: 1, roster_revision: 0,
  players: %w[Alice Bob], judge: 'Alice', active_players: ['Bob'], round_player_order: ['Bob'],
  round_categories: ['country'], reveals: {'Bob' => {'country' => 'Austria'}}, decisions: {}, letter: 'A'}
spec = game.send(:review_spec, state)
surface = GameSurfaces.build(spec)
actions = []
surface.on_action { |action| actions << action }
form = GameRoomUI::Form.new(surface.fields + [Button.new('Back')], quiet: true)
form.focus
SpeechOutput.reset
driver.press(form, 0x09)
assert_equal(1, form.index, 'Tab did not enter the first answer')
focus_text = SpeechOutput.calls.map(&:first).join(' ')
assert(focus_text.include?('Austria') && focus_text.include?('Enter confirms the assessment.'),
  'Entering an answer did not give its concise Enter hint')
assert_equal(1, focus_text.scan('Enter confirms the assessment.').length)

SpeechOutput.reset
driver.press(form, 0x28)
assert_equal(1, surface.fields[1].index)
assert(SpeechOutput.calls.any? { |call| call.first.include?('Unique, 2 points') }, 'An arrow did not read the selected assessment')
assert(SpeechOutput.calls.none? { |call| call.first.include?('Enter confirms') }, 'An arrow repeated the focus hint')
assert(actions.empty?, 'Arrow navigation submitted an assessment')
driver.press(form, 0x0D)
assert_equal(1, actions.length)
selection = actions.last
assert_equal({}, surface.state['confirmed'], 'A local Enter pretended its assessment was already accepted')
surface.action_accepted(selection)
assert_equal({spec.items.first.id => 'unique'}, surface.state['confirmed'])
SpeechOutput.reset
driver.press(form, 0x0D)
assert_equal(1, actions.length, 'Repeated Enter duplicated an accepted assessment')
assert(SpeechOutput.calls.none? { |call| call.first.include?('Assessed.') }, 'The field announced success before replay confirmation')

surface.action_guard = -> { false }
driver.press(form, 0x28)
assert_equal(2, surface.fields[1].index, 'A second arrow did not choose the partial assessment')
driver.press(form, 0x0D)
assert_equal(1, actions.length, 'A denied action reached the handler')
assert_equal({spec.items.first.id => 'unique'}, surface.state['confirmed'], 'A denied activation changed the confirmed grade')
surface.action_guard = nil
driver.press(form, 0x0D)
assert_equal(2, actions.length, 'The same choice could not be submitted after denial')
assert_equal('partial', actions.last['decision'])
assert_equal({spec.items.first.id => 'unique'}, surface.state['confirmed'], 'An unaccepted correction overwrote the previous confirmed grade')

SpeechOutput.reset
surface.suppress_next_focus!(1)
surface.fields[1].focus
assert_equal([], SpeechOutput.calls, 'A quiet refresh repeated the answer or hint')
surface.fields[1].focus
assert_equal(1, SpeechOutput.calls.count { |call| call.first.include?('Enter confirms the assessment.') },
  'A later deliberate focus lost the hint')

read_only = GameSurfaces.build(GameSurfaces::ReviewSpec.new(**spec.to_h.merge(read_only: true)))
SpeechOutput.reset
read_only.fields.first.focus
assert(SpeechOutput.calls.none? { |call| call.first.include?('Enter confirms') }, 'A read-only observer was told to confirm an assessment')
assert_equal('Country: Austria', read_only.fields.first.options.first)

puts 'PASS Categories native review: focus-only hint, quiet refresh, explicit acceptance, denied/retried changes and read-only observation'
