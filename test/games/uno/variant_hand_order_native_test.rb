require_relative '../../support/duck_challenge_native'
require_relative '../../../games/uno'
require_relative '../../../lib/game_screen'

GameRoomLocalization.boot(settings: {'interface_language'=>'en'}, host_language:'en')
Session.name = 'Alice'
game = GameRoomGames::Uno.new
raw = %w[R5a G2a B5a Y1a R5b R2a NF0]
by_colour = %w[Y1a R2a R5a R5b B5a G2a NF0]
by_number = %w[Y1a R2a G2a R5a R5b B5a NF0]
[
  [{}, by_colour, 'C'],
  [{'interceptions'=>true}, by_colour, 'C'],
  [{'straights'=>true}, by_number, 'H'],
  [{'interceptions'=>true, 'super_interceptions'=>true}, by_number, 'H'],
  [{'interceptions'=>true, 'super_interceptions'=>true, 'straights'=>true}, by_number, 'H']
].each do |variant, expected, key|
  state = game.send(:initial_state, %w[Alice Bob], game.default_options.merge(variant))
  state.update(phase: :playing, current_player:'Alice', colour:'Y', discard:['Y4a'],
    hands:{'Alice'=>raw.dup, 'Bob'=>[]})
  replay = GameRoomGames::Replay.new(players:state[:players], state:state, current_player:'Alice', history:[], accepted_events:[])
  surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
  control = surface.fields.first
  ids = -> { surface.displayed_hand_cards('hand').map(&:id) }
  assert(control.is_a?(ListBox) && ids.call == expected, "#{variant}: wrong native initial order")
  control.index = ids.call.index('R5b')
  driver = DuckChallengeNativeDriver.new
  form = driver.form(surface)
  form.extend(GameRoomLayout::ShortcutFormBehavior)
  writes = []
  surface.on_action { |action| writes << action }
  shortcuts = game.game_shortcuts(replay, 'Alice').select { |item| item.action_name == 'sort_cards' }
  assert(shortcuts.map { |item| item.payload['mode'] }.sort == %w[colour number], 'UNO exposes an artificial third sorting method')
  screen = GameScreen.allocate
  screen.instance_variable_set(:@game, game)
  GameRoomShortcutBindings.bind(form, surface.fields, shortcuts, consume: ->(*) {}) do |shortcut|
    screen.send(:activate_game_shortcut, shortcut, surface, replay:replay)
  end
  driver.frame(form)
  SpeechOutput.reset
  driver.frame(form, driver.tap(key.ord, modifiers:[0x10]))
  assert(ids.call == expected.reverse, "#{variant}: first sorting key did not reverse the active default")
  assert(ids.call[control.index] == 'R5b', 'Sorting changed the physical cursor')
  assert(SpeechOutput.calls.length == 1 && SpeechOutput.calls.first.first.include?('descending'),
    "#{variant}: sorting was not announced once: #{SpeechOutput.calls.inspect}")
  driver.frame(form)
  SpeechOutput.reset
  driver.frame(form, driver.tap(key.ord, modifiers:[0x10]))
  assert(ids.call == expected && SpeechOutput.calls.length == 1 && SpeechOutput.calls.first.first.include?('ascending'),
    'Second key did not restore ascending order with one announcement')
  # Rank order interleaves colours; horizontal navigation still follows Y/R/B/G
  # while vertical navigation crosses every card in the displayed list.
  surface.handle_command('sort_cards', 'mode'=>'number')
  control.index = ids.call.index('R2a')
  driver.frame(form)
  driver.frame(form, driver.tap(0x27))
  assert(ids.call[control.index] == 'B5a', 'Variant changed the colour cycle or target card')
  index = control.index
  driver.frame(form)
  driver.frame(form, driver.tap(0x28))
  assert(control.index == index + 1, 'Vertical navigation was restricted to one colour')
  snapshot = Marshal.dump(replay)
  manual = ids.call
  assert(!surface.handle_command('sort_cards', 'mode'=>'none'), 'A retained acquisition-order callback bypassed the declaration')
  surface.update_spec(game.surface_spec(replay, 'Alice'))
  assert(surface.fields.first.equal?(control) && ids.call == manual, 'Refresh replaced the hand or manual order')
  state[:hands]['Alice'] << 'Y3a'
  surface.update_spec(game.surface_spec(replay, 'Alice'))
  assert(ids.call == %w[Y1a R2a G2a Y3a R5a R5b B5a NF0] && ids.call[control.index] == 'Y3a',
    'A received card was appended outside the chosen order or lost the cursor')
  state[:hands]['Alice'].pop
  assert(Marshal.dump(replay) == snapshot && writes.empty?, 'Sorting/arrows wrote a move or changed the reducer')
end
puts 'PASS UNO native variant ordering: first-key default reversal, single direction announcement, physical cursor, interleaved arrows, manual override and received cards; no live accounts or physical keyboard'
