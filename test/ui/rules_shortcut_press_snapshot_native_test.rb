require_relative '../support/duck_challenge_native'
require_relative '../../lib/game_rules'

[:held, :released, :added_after, :plain, :shift, :option].each do |timing|
  driver = DuckChallengeNativeDriver.new
  spec = GameSurfaces::PawnTrackSpec.new(id: 'rows', header: 'Cards', items: [
    GameSurfaces::PawnTrackItem.new(id: 'A', label: 'A')])
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: spec))
  calls = 0
  field = layout.surface.fields.first
  GameRoomRules.bind_ctrl_f1(layout.form, [field]) { calls += 1 }
  assert(field.get_tips.count { |tip| tip == 'Ctrl+F1, Game rules.' } == 1,
    'The native field must advertise the actual rules shortcut once')
  layout.form.focus
  key, main = 0x70, EltenAPI::KeyboardScheme.key_code(EltenAPI::KeyboardScheme.main_modifier)
  events, held = case timing
  when :held
    [[[main, true], [key, true, driver.raw([main, key])], [key, false]], [main]]
  when :released
    [driver.tap(key, modifiers: [main]), []]
  when :added_after
    [[[key, true, driver.raw([key])], [key, false], [main, true]], [main]]
  when :shift
    [driver.tap(key, modifiers: [main, 0x10]), []]
  when :option
    [driver.tap(key, modifiers: [main, EltenAPI::KeyboardScheme.key_code(:option)]), []]
  else
    [driver.tap(key), []]
  end
  driver.frame(layout.form, events, held: held)
  expected = [:held, :released].include?(timing) ? 1 : 0
  assert(calls == expected, "Rules shortcut ignored the actual F1 press modifiers: #{timing}")
end

$activecontrols = []
puts 'PASS native rules binding: one help tip, held/released/late Ctrl, plain F1, Shift and Alt exclusion'
