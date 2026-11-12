require_relative '../../support/ui'
require_relative '../../../lib/game_surfaces'
require_relative '../../support/duck_challenge_ui'
include DuckChallengeTest
# The lightweight editing fixture has no numeric flag by default. Native
# editing/validation is exercised in challenge_native and numeric_shortcuts.
EditBox::Flags::Numbers = 4

def connect_surface(model, seat: 0)
  surface = challenge_surface(model, seat: seat)
  field = surface.fields.first
  field.model_keyboard_input!
  @pressed, @held = [], []
  field.define_singleton_method(:key_pressed?) { |key, **| @test_pressed.include?(key) }
  field.define_singleton_method(:key_held?) { |key| @test_held.include?(key) }
  field.instance_variable_set(:@test_pressed, @pressed)
  field.instance_variable_set(:@test_held, @held)
  form = Form.new([field, EditBox.new('Chat', text: 'Keep draft')])
  $activecontrols = [form, field]
  [surface, form, field]
end

def press_surface(surface, form, code, shift: false)
  @pressed.replace([code]); @held.replace([code] + (shift ? [0x10] : []))
  surface.fields.first.update
  result = surface.take_input(form)
  @pressed.clear; @held.clear
  surface.fields.first.update
  result
end

expected = {
  'rock_paper_scissors' => [0x0D, :choose, 'rock'], 'dice_duel' => [0x0D, :roll, nil],
  'blackjack' => [0x20, :hit, nil], 'risky_dice' => [0x0D, :roll, nil],
  'guess_number' => [0x0D, :answer, '42'], 'copy_number' => [0x0D, :answer, '42'],
  'arithmetic' => [0x0D, :answer, '42'], 'race_question' => [0x0D, :answer, '42'],
  'numbered_balls' => [0x32, :take, 2], 'count_ducks' => [0x0D, :answer, 7],
  'rhythm' => [0x0D, :begin, nil], 'sound_order' => [0x32, :preview, 2],
  'simon' => [0x31, :tone, 1], 'sound_memory' => [0x30, :reveal, 0],
  'hit_duck' => [0x35, :target, 5], 'quiz' => [0x34, :answer, 3]
}
expected.each do |kind, (key, action_kind, value)|
  model = challenge_state(kind)
  seat = ENGINE.current_turn(model) || 0
  acknowledge_challenge(model, seat: seat) if %w[count_ducks rhythm simon hit_duck].include?(kind)
  surface, form, field = connect_surface(model, seat: seat)
  if surface.presentation[:mode] == :text
    field.set_text(kind == 'count_ducks' ? '7' : '42')
  end
  action = press_surface(surface, form, key)
  want = {kind: action_kind, press_id: 1}
  want[:value] = value unless value.nil?
  assert_equal([want], action, "Wrong #{kind} mapping")
  assert_equal([], surface.take_input(form), 'Input drained twice')
  @pressed.replace([key]); @held.replace([key]); field.update
  first = surface.take_input(form)
  field.update
  assert_equal([], surface.take_input(form), "#{kind} autorepeat became another input")
  @pressed.clear; @held.clear; field.update
  form.index = 1
  press_surface(surface, form, key)
  form.index = 0
  assert_equal([], surface.take_input(form), "#{kind} input from chat was delayed")
  assert_equal('Keep draft', form.fields.last.text)
end

model = challenge_state('risky_dice')
surface, form, field = connect_surface(model, seat: ENGINE.current_turn(model))
field.index = 1 # Stub lists do not implement host navigation; covered natively.
assert_equal(:save, press_surface(surface, form, 0x0D).first[:kind])
field.index = 0
assert_equal(:roll, press_surface(surface, form, 0x0D).first[:kind])

model = challenge_state('sound_order')
surface, form, field = connect_surface(model)
assert_equal([], press_surface(surface, form, 0x32, shift: true))
assert_equal([{kind: :swap, value: 2, other: 8, press_id: 1}], press_surface(surface, form, 0x38, shift: true))
assert_equal([], press_surface(surface, form, 0x0D))
assert_equal(:button, surface.presentation[:mode])
assert_equal([], surface.presentation[:options])
assert_equal([], press_surface(surface, form, 0x0D))

model = challenge_state('count_ducks')
surface, form, field = connect_surface(model)
assert_equal([], press_surface(surface, form, 0x74), 'Replay worked before listening finished')
acknowledge_challenge(model)
surface.present(ENGINE.view(model, seat: 0))
assert_equal(:replay, press_surface(surface, form, 0x74).first[:kind])

model = challenge_state('copy_number')
surface, form, field = connect_surface(model)
field.set_text('kept draft'); field.restore_selection(index: 3, check: 5)
original = field.object_id
surface.present(ENGINE.view(model, seat: 0))
assert_equal([original, 'kept draft', 3, 5], [surface.fields.first.object_id, field.text, field.index, field.check])
surface.action_guard = -> { false }
assert_equal([], press_surface(surface, form, 0x0D), 'Screen action guard was bypassed')
surface.action_guard = nil
@held.replace([0x0D]); field.focus
@pressed.replace([0x0D]); field.update
assert_equal([], surface.take_input(form), 'Held Enter submitted after focus')
@pressed.clear; @held.clear; field.update
assert_equal(:answer, press_surface(surface, form, 0x0D).first[:kind])
assert(!surface.reusable_for?(GameSurfaces::DuckChallengeSpec.new(**surface.spec.to_h.merge(challenge_id: 'next'))))

$activecontrols = nil
puts 'PASS Duck surface: 16 key maps, scoped input, no repeat, lists, previews/swaps, replay gating, draft/focus and command guard'
