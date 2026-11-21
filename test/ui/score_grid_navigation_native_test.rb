require_relative '../support/duck_challenge_native'
require_relative '../../games/base'
require_relative '../../lib/game_shortcut_bindings'

rows = Array.new(20) { |index| ["Category #{index + 1}", "Score #{index + 1}"] }
rows[4][0] = 'Żetony'
rows[11][0] = 'Żywioły'
rows[16][0] = 'Sum'
rows[18][0] = 'Żubry'
rows.last[1] = ''

[false, true].each do |writable|
  actions = writable ? rows.each_index.map do |row|
    GameSurfaces::Action.new(kind: 'dice', name: 'score', payload: {'category' => row})
  end : []
  spec = GameSurfaces::GridSpec.new(width: 2, height: rows.length, header: 'Score sheet', cells: rows,
    row_origin: :top, hide_coordinates: true, row_actions: actions)
  surface = GameSurfaces.build(spec, state: {'x' => 1, 'y' => 3})
  selections = []
  surface.on_action { |action| selections << action }
  driver = DuckChallengeNativeDriver.new
  form = driver.form(surface)
  move = lambda do |key, x, y, characters: '', modifiers: [], held: []|
    SpeechOutput.reset
    events = driver.tap(key, modifiers: modifiers).reject { |code, down| !down && held.include?(code) }
    driver.frame(form, events, held: held, characters: characters)
    assert(surface.state.values_at('x', 'y') == [x, y], "Key #{key} did not land on #{[x, y]}")
    assert(SpeechOutput.calls.map(&:first) == [rows[y][x]], "Key #{key} did not read just its destination")
    assert(selections.empty?, 'Navigation submitted a score')
    driver.frame(form)
  end
  move.call(0x24, 0, 0) # Home
  move.call(0x27, 1, 0) # Right
  move.call(0x22, 1, 15) # Page Down: the same 15-row step as a host list.
  move.call(0x21, 1, 0)
  move.call(0x23, 0, 19) # End
  move.call(0x21, 0, 4)
  move.call(0x22, 0, 19)
  move.call(0x5a, 0, 4, characters: 'ż', modifiers: [0x11, 0x12])
  move.call(0x5a, 0, 11, characters: 'Ż')
  move.call(0x5a, 0, 18, characters: 'ż')
  move.call(0x5a, 0, 11, characters: 'Ż', modifiers: [0x10], held: [0x10])

  SpeechOutput.reset
  driver.frame(form, driver.tap(0x51), characters: 'q')
  assert(surface.state.values_at('x', 'y') == [0, 11] && SpeechOutput.calls.empty?, 'An unmatched letter moved the cursor')
  driver.frame(form)

  # The host caches typed characters for the rest of a frame, even when the
  # current game shortcut clears the physical press before the grid updates.
  form.extend(GameRoomLayout::ShortcutFormBehavior)
  shortcut = GameRoomGames::GameShortcut.new(key: 's', kind: :announcement, label: 'Read scores', message: 'Score totals')
  GameRoomShortcutBindings.bind(form, surface.fields, [shortcut], consume: ->(_) {
    form.send(:getkeychar)
    EltenAPI::KeyboardState.clear_current_frame
  }) { |command| speak(command.message) }
  SpeechOutput.reset
  driver.frame(form, driver.tap(0x53), characters: 's')
  assert(SpeechOutput.calls.map(&:first) == ['Score totals'], 'A declared shortcut also searched the grid')
  assert(surface.state.values_at('x', 'y') == [0, 11], 'A shortcut moved the cursor')
  driver.frame(form)

  driver.frame(form, driver.tap(0x0d))
  assert(selections.map { |action| action.payload['category'] } == (writable ? [11] : []),
    'Enter no longer respects the selected row or read-only table')
end

board = GameSurfaces.build(GameSurfaces::GridSpec.new(width: 2, height: rows.length, cells: rows),
  state: {'x' => 1, 'y' => 3})
driver = DuckChallengeNativeDriver.new
form = driver.form(board)
SpeechOutput.reset
[0x24, 0x23, 0x21, 0x22].each { |key| driver.frame(form, driver.tap(key)) }
driver.frame(form, driver.tap(0x5a), characters: 'ż')
assert(board.state.values_at('x', 'y') == [1, 3] && SpeechOutput.calls.empty?,
  'A playfield acquired table-only navigation')
puts 'PASS native score table: Home, End, page steps, Unicode names, shortcut priority, selection, and board isolation'
