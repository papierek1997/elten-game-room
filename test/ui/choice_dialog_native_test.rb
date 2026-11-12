require_relative '../support/duck_challenge_native'
require_relative '../../games/taboo'
require_relative '../../lib/game_screen'

class NativeChoiceDriver < DuckChallengeNativeDriver
  attr_reader :modal, :prompts

  def initialize(key:, index: nil, before_input: nil)
    super()
    @key, @selection, @before_input = key, index, before_input
    @frames, @prompts = 0, []
  end

  def tick(form)
    @frames += 1
    raise 'Choice dialog ignored Enter/Escape' if @frames > 8
    if form.instance_variable_get(:@wait)
      raise 'Choice opened another form or required another key' if @modal
      @modal = form
      list = form.fields.first
      assert(list.instance_of?(ListBox), 'Choice replaced the native list control')
      cancel_index = form.fields.index(form.cancel_button)
      assert(cancel_index && form.instance_variable_get(:@hidden)[cancel_index], 'Choice lacks hidden native cancellation')
      assert(SpeechOutput.calls.one?, "Choice prompt did not occur once: #{SpeechOutput.calls.inspect}")
      @prompts << SpeechOutput.calls.first.first
      @before_input&.call(list)
      list.index = @selection unless @selection.nil?
      snapshot(tap(@key), [])
    else
      snapshot([], [])
    end
  end
end

def native_choice(key:, index: nil, before_input: nil)
  SpeechOutput.reset
  driver = NativeChoiceDriver.new(key: key, index: index, before_input: before_input)
  result = yield
  assert(driver.modal, 'Expected a real native choice form')
  assert(driver.modal.instance_variable_get(:@wait) == false, 'Choice form remained open')
  assert(!EltenAPI::KeyboardState.current.pressed[key], 'Choice leaked its closing key')
  [result, driver]
end

# Native shared helper, including index zero, cancelled/default selection and
# stale Enter cleanup. Constructors must be quiet; Form owns the one prompt.
value, driver = native_choice(key: 0x0D, before_input: ->(list) { assert(list.index == 1, 'Requested default was lost') }) do
  GameRoomUI.choose_index('Choose a result', %w[First Second], index: 1)
end
assert(value == 1 && driver.prompts.first.include?('Choose a result'), 'Shared choice changed its selected index/header')
value, = native_choice(key: 0x1B) { GameRoomUI.choose_index('Choose a result', %w[First Second]) }
assert(value.nil?, 'Escape returned a result')
assert(GameRoomUI.choose_index('No choices', []).nil?, 'Empty choices invented a selection')

# Execute the exact maintained documentation snippet, not a separate copy of
# its call. Only this known local example is selected; never evaluate imports.
document = File.read(File.expand_path('../../docs/UI.md', __dir__), encoding: 'UTF-8')
section = document.split('### Single-choice modal dialogs', 2).last
example = section && section.match(/^```ruby\r?\n(.*?)^```/m)
assert(example, 'The documented local-choice example is missing')
program = Object.new
[[0x0D, nil, :second], [0x0D, 0, :first], [0x1B, nil, nil]].each do |key, index, expected|
  value, = native_choice(key: key, index: index, before_input: ->(list) { assert(list.index == 1, 'Documented default changed') }) do
    eval(example[1], binding, 'docs/UI.md local-choice example')
  end
  assert(value == expected, 'Documented choice did not retain its values/cancellation')
end

spec = GameSurfaces::TabooSpec.new(token: 'turn-1', phase: :review,
  lines: [], status: '', action: nil, master: true,
  review: [{word: 'Dog', forbidden: %w[animal bark], label: 'Unassessed'}],
  results: [['correct', 'Correct'], ['neutral', 'Neutral'], ['incorrect', 'Incorrect']], opponent: false)

%i[correction restart].each do |mode|
  surface = GameSurfaces::TabooSurface.new(spec)
  emitted = []
  surface.on_action { |action| emitted << action.to_h }
  native_choice(key: 0x1B) do
    mode == :correction ? surface.fields.first.trigger(:select) : surface.fields.last.press
  end
  assert(emitted.empty? && surface.state['index'] == 0, "Taboo #{mode}: cancellation changed the result/cursor")
  native_choice(key: 0x0D, index: mode == :correction ? 2 : 1) do
    mode == :correction ? surface.fields.first.trigger(:select) : surface.fields.last.press
  end
  expected = mode == :correction ? {'index' => 0, 'result' => 'incorrect'} : {}
  assert(emitted.one? && emitted.first['token'] == 'turn-1' &&
    expected.all? { |key, value| emitted.first[key] == value }, "Taboo #{mode}: Enter lost the shown result/token")
end

surface = GameSurfaces::TabooSurface.new(spec)
emitted = []
surface.on_action { |action| emitted << action }
native_choice(key: 0x0D, index: 2, before_input: ->(_list) { surface.update_spec(spec.dup.tap { |new_spec| new_spec.token = 'turn-2' }) }) do
  surface.fields.first.trigger(:select)
end
assert(emitted.empty?, 'Taboo accepted a result after its shown token changed')

shortcut = GameRoomGames::GameShortcut.new(key: 'c', kind: :choice, label: 'Choose card', prompt: 'Cards',
  action_kind: 'card', action_name: 'select', value_key: 'card',
  choices: [GameRoomGames::ShortcutChoice.new(value: 'AS', label: 'Ace'), GameRoomGames::ShortcutChoice.new(value: 'KS', label: 'King')])
screen = GameScreen.allocate
action, = native_choice(key: 0x0D, index: 0) { screen.send(:choice_shortcut_action, shortcut) }
assert(action['card'] == 'AS' && action.source == 'shortcut:c', 'Choice shortcut lost index zero, payload or provenance')
action, = native_choice(key: 0x1B) { screen.send(:choice_shortcut_action, shortcut) }
assert(action.nil?, 'Choice shortcut submitted after Escape')

card = Object.new.extend(GameSurfaces::CardActions)
guard = true
card.define_singleton_method(:action_allowed?) { guard }
accepted, = native_choice(key: 0x0D, index: 1) { card.send(:confirm_card_action, 'Play this card?') }
assert(accepted, 'Card Yes was not accepted')
accepted, = native_choice(key: 0x1B) { card.send(:confirm_card_action, 'Play this card?') }
assert(!accepted, 'Card confirmation accepted Escape')
accepted, = native_choice(key: 0x0D, index: 1, before_input: ->(_list) { guard = false }) { card.send(:confirm_card_action, 'Play this card?') }
assert(!accepted, 'Card confirmation bypassed its changed action guard')

# Exercise native arrow input rather than assigning every selected index.
# In confirmations, AnyDir must retain Right/Left behavior and Program
# ownership even with binary-loaded translated text.
class NativeChoiceSequenceDriver < DuckChallengeNativeDriver
  attr_accessor :owner, :outer
  attr_reader :modal

  def initialize(keys, owner: nil)
    super()
    @keys, @owner = keys, owner
    @frames = 0
  end

  def tick(form)
    @frames += 1
    raise 'Choice did not finish its finite native key sequence' if @frames > 12
    if !form.equal?(@outer) && form.instance_variable_get(:@wait)
      @modal ||= form
      assert(@modal.equal?(form) && form.game_room_program.equal?(@owner), 'Choice changed its owning form/Program')
      key = @keys.shift
      raise 'Choice requested an extra closing key' unless key
      snapshot(tap(key), [])
    else
      snapshot([], [])
    end
  end
end

%w[en pl cs es ru].each do |language|
  GameRoomLocalization.boot(settings: {'interface_language' => language, 'known_languages' => [language]}, host_language: language)
  program = Object.new
  driver = NativeChoiceSequenceDriver.new([0x27, 0x0D], owner: program)
  SpeechOutput.reset
  selected = GameRoomUI.choose_index('Wybierz żółty wynik'.b, ['Pierwszy'.b, 'Żółty'.b],
    program: program, flags: ListBox::Flags::AnyDir)
  assert(selected == 1 && driver.modal.game_room_program.equal?(program), 'Native Right/Enter or Program ownership was lost')
  assert(SpeechOutput.calls.size == 2 && SpeechOutput.calls.all? { |call| call.first.encoding == Encoding::UTF_8 && call.first.valid_encoding? },
    'Binary choice captions or native initial/navigation speech changed')
end

%i[correction restart].each do |mode|
  program = Object.new
  driver = NativeChoiceSequenceDriver.new([0x1B], owner: program)
  surface = GameSurfaces::TabooSurface.new(spec)
  surface.program = program
  actions, departures = [], []
  surface.on_action { |action| actions << action }
  outer = GameRoomUI::Form.new(surface.fields, program: program, quiet: true)
  driver.outer = outer
  leave = Button.new('Leave')
  leave.on(:press) { departures << true }
  outer.cancel_button = leave
  outer.index = mode == :correction ? 0 : outer.fields.length - 1
  focused = outer.fields[outer.index]
  outer.focus
  SpeechOutput.reset
  driver.frame(outer, driver.tap(0x0D))
  assert(driver.modal && actions.empty? && departures.empty?, 'Native outer Enter/Escape changed the game or left the table')
  assert(outer.fields[outer.index].equal?(focused) && SpeechOutput.calls.one?, 'Modal return lost focus or reread its parent')
  assert(!EltenAPI::KeyboardState.current.pressed[0x1B], 'Modal Escape leaked into its native parent')
end
$activecontrols = []
puts 'PASS native shared choices: one prompt, selected default, Enter, Escape, empty list, Taboo correction/restart/stale token, shortcut identity and post-dialog card guard'
