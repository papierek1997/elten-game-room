require_relative '../support/duck_challenge_native'
require_relative '../../games/base'
require_relative '../../lib/game_shortcut_bindings'
require_relative '../../lib/game_history_navigation'

# A modifier can be released, or first pressed, after the action key but before
# the same UI frame is dispatched. Feed the actual native ordered key events.
def press_frame(driver, key, timing, modifier = 0x10, characters: '')
  events, held = case timing
  when :held
    [[[modifier, true], [key, true, driver.raw([modifier, key])], [key, false]], [modifier]]
  when :released
    [driver.tap(key, modifiers: [modifier]), []]
  when :added_after
    [[[key, true, driver.raw([key])], [key, false], [modifier, true]], [modifier]]
  else
    [driver.tap(key), []]
  end
  [events, held, characters]
end

def drive_press(driver, form, key, timing, modifier = 0x10, characters: '')
  events, held, text = press_frame(driver, key, timing, modifier, characters: characters)
  driver.frame(form, events, held: held, characters: text)
end

def simple_layout
  spec = GameSurfaces::PawnTrackSpec.new(id: 'hand', header: 'Cards', items: [
    GameSurfaces::PawnTrackItem.new(id: 'K', label: 'King')])
  GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: spec))
end

%i[held released added_after plain].each do |timing|
  packet = GameSurfaces::PacketCardSpec.new(id: 'hand', header: 'Cards',
    cards: [GameSurfaces::Card.new(id: 'K', label: 'King', value: 'K')],
    allow_packet: true, hand_order: ['K'], hand_epoch: 'deal-1')
  marriage = GameSurfaces::CardTableSpec.new(zones: [
    GameSurfaces::CardZoneSpec.new(id: 'hand', header: 'Cards', hand_order: ['K'], hand_epoch: 'deal-1',
      cards: [GameSurfaces::Card.new(id: 'K', label: 'King', value: 'K', shift_choice: 'marriage')])])
  { packet: packet, marriage: marriage }.each do |kind, spec|
    driver = DuckChallengeNativeDriver.new
    surface = GameSurfaces.build(spec)
    emitted = []
    surface.on_action { |action| emitted << action.to_h }
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    form.focus
    drive_press(driver, form, 0x0d, timing)
    shifted = %i[held released].include?(timing)
    if kind == :packet
      assert(shifted ? emitted.empty? && surface.state['selected_ids'] == ['K'] :
        emitted.size == 1 && surface.state['selected_ids'].empty?, "#{timing}: packet uses final Shift state")
    else
      assert(emitted.size == 1 && (emitted.first['choice_id'] == 'marriage') == shifted,
        "#{timing}: marriage uses final Shift state")
    end
  end

  driver = DuckChallengeNativeDriver.new
  layout = simple_layout
  selected = []
  keys = [GameRoomGames::GameShortcut.new(key: 'r', label: 'Contract', kind: :announcement, message: 'Contract'),
    GameRoomGames::GameShortcut.new(key: 'r', modifiers: [:shift], label: 'Surrender', kind: :action,
      action_kind: 'command', action_name: 'surrender')]
  GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, keys,
    consume: ->(_key) { EltenAPI::KeyboardState.clear_current_frame }) { |key| selected << key }
  layout.form.focus
  drive_press(driver, layout.form, 0x52, timing)
  expected = %i[held released].include?(timing) ? :action : :announcement
  assert(selected.size == 1 && selected.first.kind == expected, "#{timing}: wrong R/Shift+R action")
end

# Press-time matching and editable gating must agree, including punctuation
# not listed in KeyboardScheme.KEY_CODES and both Ctrl and Alt shortcuts.
{ control: 0x11, alt: 0x12 }.each do |modifier, code|
  %i[released added_after].each do |timing|
    driver = DuckChallengeNativeDriver.new
    layout = simple_layout
    selected = []
    key = GameRoomGames::GameShortcut.new(key: 'r', modifiers: [modifier], label: 'Report',
      kind: :announcement, message: 'Report')
    GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, [key], consume: ->(_key) {}) { selected << true }
    layout.form.index = layout.form.fields.index(layout.chat)
    layout.form.focus
    drive_press(driver, layout.form, 0x52, timing, code, characters: timing == :added_after ? 'r' : '')
    assert(selected.size == (timing == :released ? 1 : 0), "#{modifier}/#{timing}: chat shortcut gating disagrees")
    assert(layout.chat.text.include?('r'), 'A plain R was consumed by a modifier pressed later') if timing == :added_after
  end
end

{ 'semicolon' => 0xba, 'backspace' => 0x08, 'delete' => 0x2e }.each do |key, code|
  %i[released added_after].each do |timing|
    driver = DuckChallengeNativeDriver.new
    layout = simple_layout
    shortcut = GameRoomGames::GameShortcut.new(key: key, modifiers: [:control], label: 'Action',
      kind: :announcement, message: 'Action')
    selected = []
    GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, [shortcut], consume: ->(_key) {}) { selected << true }
    layout.form.focus
    drive_press(driver, layout.form, code, timing, 0x11)
    assert(selected.size == (timing == :released ? 1 : 0), "#{key}/#{timing}: punctuation key mapping")
  end
end

{ 0xbc => [:move, -1], 0xbe => [:move, 1], 0x24 => [:jump, :first], 0x23 => [:jump, :last] }.each do |code, operation|
  %i[released added_after].each do |timing|
    driver = DuckChallengeNativeDriver.new
    layout = simple_layout
    observed = []
    GameRoomHistory.bind(layout.form) { |*arguments| observed << arguments }
    layout.form.focus
    drive_press(driver, layout.form, code, timing, 0x11)
    assert(observed == (timing == :released ? [operation] : []), "History #{code}/#{timing}: wrong operation")
  end
end

# Ctrl+Shift changes the history category, not the entry; release both within
# one frame. These aliases must resolve to the same physical punctuation key.
driver = DuckChallengeNativeDriver.new
layout = simple_layout
observed = []
GameRoomHistory.bind(layout.form) { |*arguments| observed << arguments }
layout.form.focus
driver.frame(layout.form, driver.tap(0xbc, modifiers: [0x11, 0x10]))
assert(observed == [[:category, -1]], 'Quick Ctrl+Shift+Comma lost the history category')

question = GameSurfaces::QuestionSpec.new(id: 'question', prompt: 'Read before choosing.',
  mode: :single_choice, prompt_as_text: true, submit_on_select: true,
  options: [GameSurfaces::QuestionOption.new(id: 'a', label: 'Answer A')])
[0x10, 0x11, 0x12, 0x2d].each do |modifier|
  %i[released added_after].each do |timing|
    [:down, :up].each do |direction|
      driver = DuckChallengeNativeDriver.new
      layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: question))
      source = direction == :down ? 0 : 1
      layout.form.index = source
      layout.form.focus
      drive_press(driver, layout.form, direction == :down ? 0x28 : 0x26, timing, modifier)
      assert(layout.form.index == (timing == :released ? source : 1 - source),
        "#{direction}/#{modifier}/#{timing}: modified question navigation crossed controls")
    end
  end
end

{ 0xbc => %i[comma , <], 0xbe => %i[period . >], 0xba => %i[semicolon ; :] }.each do |code, aliases|
  driver = DuckChallengeNativeDriver.new
  layout = simple_layout
  driver.snapshot(driver.tap(code, modifiers: [0x11, 0x10]), [])
  snapshot = EltenAPI::KeyboardState.current
  (aliases + [code]).each do |key|
    assert(GameRoomUI.modifiers_when_pressed(layout.form, key) == [:control, :shift], "Alias #{key} lost press modifiers")
  end
  assert(EltenAPI::KeyboardState.current.equal?(snapshot) && snapshot.pressed[code], 'Modifier inspection consumed native input')
end
[0xa2, 0xa3].each do |modifier|
  driver = DuckChallengeNativeDriver.new
  layout = simple_layout
  driver.snapshot(driver.tap(0x52, modifiers: [modifier]), [])
  assert(GameRoomUI.modifiers_when_pressed(layout.form, :key_r) == [:control], 'Left/right Ctrl or named letter was not resolved')
end

# Preserve the host's repeat cadence; clearing a frame is not a held-key
# suppression policy. Compare like-for-like handlers, not a one-shot guess.
def repeat_count(shared:)
  driver = DuckChallengeNativeDriver.new
  selected = []
  if shared
    layout = simple_layout
    form = layout.form
    shortcut = GameRoomGames::GameShortcut.new(key: 'r', label: 'Read', kind: :announcement, message: 'Read')
    GameRoomShortcutBindings.bind(form, layout.shortcut_fields, [shortcut],
      consume: ->(_key) { EltenAPI::KeyboardState.clear_current_frame }) { selected << true }
  else
    form = GameRoomUI::Form.new([Button.new('Native reference')], quiet: true)
    form.on(:key_r) { selected << true; EltenAPI::KeyboardState.clear_current_frame }
  end
  form.focus
  driver.frame(form, [[0x52, true, driver.raw([0x52])]], held: [0x52])
  4.times { driver.frame(form, [[0x52, :repeat, driver.raw([0x52])]], held: [0x52]) }
  count = selected.size
  driver.frame(form, [[0x52, false]])
  driver.frame(form)
  driver.frame(form, driver.tap(0x52))
  assert(selected.size == count + 1, 'Fresh press after release was lost or duplicated')
  count
end
native_repeats = repeat_count(shared: false)
assert(native_repeats.positive? && repeat_count(shared: true) == native_repeats, 'Shared binding changed the native repeat policy')

$activecontrols = []
puts 'PASS native press-time modifiers: cards, shortcuts, editable fields, history, punctuation and question boundaries'
