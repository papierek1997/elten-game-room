require_relative '../../support/duck_challenge_native'
require_relative '../../support/tysiac_two_player'
require_relative '../../../lib/game_shortcut_bindings'

driver = DuckChallengeNativeDriver.new
fixture = TwoPlayerTysiacFixture.new
fixture.auction
fixture.choose
game, replay = fixture.game, fixture.replay
layout = GameRoomLayout::Screen.new(view_spec:GameRoomLayout::ViewSpec.new(surface:game.surface_spec(replay,'Bob')),
  user_items:%w[Alice Bob])
form = layout.form
form.game_room_background_help_enabled = true
form.focus
seen = []
GameRoomShortcutBindings.bind(form,layout.shortcut_fields,game.game_shortcuts(replay,'Bob'),
  consume:->(_key) { EltenAPI::KeyboardState.clear_current_frame }) { |shortcut| seen << shortcut }
press = lambda do |modifiers|
  held = modifiers + [0x52]
  driver.frame(form, modifiers.map { |key| [key,true] } + [[0x52,true,driver.raw(held)]], held:held)
  driver.frame(form, [[0x52,false]] + modifiers.reverse.map { |key| [key,false] })
end
press.call([])
assert(seen.length == 1 && seen.last.kind == :announcement && seen.last.message == 'Bob: 100', 'Native R does not read the brief contract')
press.call([0x11])
assert(seen.length == 1, 'R steals Ctrl+R from table settings')
press.call([0x10])
assert(seen.length == 2 && seen.last.kind == :action && seen.last.action_name == 'surrender', 'Native Shift+R does not activate surrender')
command = seen.last
status, plan = game.action_for({'kind'=>command.action_kind,'action'=>command.action_name}.merge(command.payload),replay,'Bob')
assert(status == :ok && plan.events.map(&:action) == ['surrender'], 'Native surrender bypasses the normal action path')
tips = GameRoomContextHelp.game_field_tips(layout.surface.fields)
assert(tips.any? { |text| text.start_with?('R,') } && tips.any? { |text| text.start_with?('Shift+R,') }, 'F1 omits new keys')
$activecontrols = []
puts 'PASS native Thousand R/Shift+R dispatch, shared action path, F1 and Ctrl+R isolation'
