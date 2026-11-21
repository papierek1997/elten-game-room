require_relative '../support/duck_challenge_native'
require_relative '../support/assertions'
require_relative '../../lib/game_layout'
require_relative '../../lib/game_shortcut_bindings'
require_relative '../../games/base'
include GameRoomTest::Assertions

driver = DuckChallengeNativeDriver.new
layouts = []
begin
  [true, false].each do |digits_only|
    spec = GameSurfaces::QuestionSpec.new(id: 'native-digits', mode: :text,
      prompt: 'Amount', show_submit_button: false, digits_only: digits_only)
    layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: spec), user_items: %w[Alice Bob])
    layouts << layout
    field = layout.surface.fields.first
    shortcuts = %w[s a 1].map do |key|
      GameRoomGames::GameShortcut.new(key: key, kind: :announcement, label: key, message: key)
    end
    shortcuts << GameRoomGames::GameShortcut.new(key: 't', modifiers: [:control],
      kind: :announcement, label: 'Duration', message: 'Duration')
    observed = []
    GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, shortcuts,
      consume: ->(_key) { EltenAPI::KeyboardState.clear_current_frame }) { |shortcut| observed << shortcut.key }
    assert(field.instance_variable_get(:@blocked_context_shortcuts).include?('t'),
      'Amount shortcut registration bypassed the shared native edit-menu conflict filter')
    layout.form.index = layout.form.fields.index(field)
    driver.frame(layout.form, driver.tap(0x31), characters: '1')
    assert_equal('1', field.text, 'A number shortcut stole numeric input')
    assert_equal([], observed)
    before = [field.text.dup, field.index, field.check, field.game_room_edit_generation]
    driver.frame(layout.form, driver.tap(0x53), characters: 's')
    driver.frame(layout.form)
    if digits_only
      assert_equal(['s'], observed, 'A declared information key did not leave the numeric field')
      assert_equal(before, [field.text, field.index, field.check, field.game_room_edit_generation])
      refused = []
      field.define_singleton_method(:play_sound) { |sound, **_options| refused << sound }
      driver.frame(layout.form, driver.tap(0x41), characters: 'A')
      assert_equal(%w[s a], observed, 'The immediate action key was captured as amount text')
      assert_equal('1', field.text)
      assert(!refused.include?('border'), 'Caps Lock produced a refusal sound after a valid letter command')
    else
      assert_equal([], observed, 'The numeric opt-in changed ordinary text ownership')
      assert_equal('1s', field.text)
    end
    layout.begin_bindings
  end
  puts 'PASS shared native digit-only question input: digits retain editing, current letter bindings activate once, ordinary text remains editable'
ensure
  layouts.each(&:begin_bindings)
  EltenAPI::KeyboardState.clear_current_frame
  $activecontrols = []
end
