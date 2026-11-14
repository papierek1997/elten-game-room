require_relative '../support/typing_native_form'

NativeOptionTest.language = 'en'
action = ->(value) { GameSurfaces::Action.new(kind: 'pawn', name: 'move', payload: {'move' => value}) }
moves = [
  GameSurfaces::GridMove.new(origin: [0, 0], destination: [1, 0], action: action.call('first')),
  GameSurfaces::GridMove.new(origin: [0, 0], destination: [2, 1], action: action.call('second')),
  GameSurfaces::GridMove.new(origin: [3, 0], destination: [3, 1], action: action.call('off'))
]
spec = GameSurfaces::GridSpec.new(width: 4, height: 2, cells: [%w[A B C D], %w[E F G H]], move_actions: moves)
surface = GameSurfaces::GridBoard.new(spec)
received = []
surface.on_action { |value| received << value }
driver = NativeTypingFormDriver.new do
  form = GameRoomUI::Form.new(surface.fields, quiet: true)
  form.on(:key_escape) { surface.cancel_pending_action! }
  form.wait
end
begin
  NativeOptionUI.spoken.clear
  driver.press([13])
  raise 'Origin selected a move immediately' unless received.empty? && surface.cancel_pending_action?
  raise 'Origin prompt repeated' unless NativeOptionUI.spoken.count { |text| text == 'Piece selected. Choose its destination.' } == 1
  driver.press([27])
  raise 'Escape retained the origin' if surface.cancel_pending_action?
  driver.press([13])
  driver.press([39])
  driver.press([13])
  raise 'Destination lost the ordinary action' unless received.last&.payload == {'move' => 'first'}
  driver.press([39])
  driver.press([39])
  driver.press([13])
  driver.press([13])
  raise 'Repeated Enter did not choose the sole move' unless received.last&.payload == {'move' => 'off'} && received.length == 2
ensure
  driver.form.resume
  driver.press([]) if driver.instance_variable_get(:@fiber).alive?
end

preview = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(row_actions: [])))
preview.on_action { raise 'Read-only preview submitted a move' }
preview.fields.first.trigger(:select, 0, 0)
raise 'Read-only chat path returned an action' if preview.movement_command(['A1']).action
surface.cancel_pending_action!
first = surface.movement_command(['A1'])
restored = GameSurfaces::GridBoard.new(spec, state: surface.state)
raise 'Quiet refresh forgot the selected origin' unless restored.movement_command(['B1']).action&.payload == {'move' => 'first'}
new_turn = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(selection_epoch: 1)), state: surface.state)
raise 'A new move retained an old origin' if new_turn.cancel_pending_action?
second = surface.movement_command(['B1'])
raise 'Chat coordinates did not share selection semantics' unless first.action.nil? && first.message && second.action&.source == 'chat_command'
surface.action_guard = -> { false }
surface.movement_command(['A1'])
raise 'Blocked input changed selection' if surface.cancel_pending_action?
# A forced origin belongs to the game specification, not fixed coordinates in
# the shared control. This also covers direct entry from a captured-piece cell.
forced = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(width: 4, height: 2,
  cells: spec.cells, move_actions: [moves.last], forced_origin: [3, 0]))
forced.on_action { |value| received << value }
forced.fields.first.trigger(:select, 3, 1)
raise 'Forced origin required a game-specific coordinate' unless received.last.payload == {'move' => 'off'} && received.length == 3
puts 'PASS native grid origin/destination, sole move, Escape, read-only preview, chat commands and write guard'
