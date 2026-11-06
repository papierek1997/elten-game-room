require_relative '../../support/duck_challenge_native'
require_relative '../../support/tysiac_redeal_fixture'
require_relative '../../../lib/game_shortcut_bindings'
driver = DuckChallengeNativeDriver.new
f = TysiacRedealFixture.new
seed = TysiacRedealFixture.seed_for { |deck| (%w[9H 9S 9D 9C] - deck.slice(7, 7)).empty? }
f.deal(seed)
replay = f.replay
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: f.game.surface_spec(replay, 'Bob')), user_items: f.players)
layout.form.game_room_background_help_enabled = true
layout.form.focus
selected = []
GameRoomShortcutBindings.bind(layout.form, layout.shortcut_fields, f.game.game_shortcuts(replay, 'Bob'),
  consume: ->(_key) { EltenAPI::KeyboardState.clear_current_frame }) { |shortcut| selected << shortcut }
driver.frame(layout.form, [[0x10,true],[0x44,true,driver.raw([0x10,0x44])]], held: [0x10,0x44])
driver.frame(layout.form, [[0x44,false],[0x10,false]])
assert(selected.size == 1 && selected.first.action_name == 'redeal', 'Native Shift+D did not request a redeal')
shortcut = selected.first
assert(f.move({'kind'=>shortcut.action_kind,'action'=>shortcut.action_name}.merge(shortcut.payload), actor: 'Bob') == :ok,
  'Shift+D bypassed/failed the normal action plan')
assert(f.state[:phase] == :redeal, 'Native request did not cancel the deal')
$activecontrols = []
puts 'PASS native Shift+D, ordinary action validation and four-nines redeal'
