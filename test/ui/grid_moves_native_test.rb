require_relative '../support/typing_native_form'

NativeOptionTest.language = 'en'
action = ->(value) { GameSurfaces::Action.new(kind: 'pawn', name: 'move', payload: {'move' => value}) }
moves = [
  GameSurfaces::GridMove.new(origin: [0, 0], destination: [1, 0], action: action.call('first')),
  GameSurfaces::GridMove.new(origin: [0, 0], destination: [2, 1], action: action.call('second')),
  GameSurfaces::GridMove.new(origin: [3, 0], destination: [3, 1], action: action.call('sole'))
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
  raise 'Native selected state is absent from the origin label' unless surface.fields.first.cell_label == 'A. Selected.'
  raise 'Origin prompt repeated' unless NativeOptionUI.spoken.count { |text| text == 'Piece selected. Choose its destination.' } == 1
  driver.press([27])
  raise 'Escape retained the origin' if surface.cancel_pending_action?
  raise 'Escape retained the selected label' unless surface.fields.first.cell_label == 'A'
  driver.press([13])
  driver.press([39])
  driver.press([13])
  raise 'Destination lost the ordinary action' unless received.last&.payload == {'move' => 'first'}
  driver.press([39])
  driver.press([39])
  driver.press([13])
  driver.press([13])
  raise 'Repeated Enter automatically chose a sole ordinary move' unless received.length == 1 && surface.cancel_pending_action?
  raise 'A sole move did not get the ordinary selection prompt' unless NativeOptionUI.spoken.include?('Piece selected. Choose its destination.')
  raise 'Repeated Enter did not follow the ordinary refusal path' unless NativeOptionUI.spoken.last == 'You cannot move the selected piece to this field.'
  driver.press([40])
  driver.press([13])
  raise 'An explicit sole destination did not perform the move' unless received.last&.payload == {'move' => 'sole'} && received.length == 2
ensure
  driver.form.resume
  driver.press([]) if driver.instance_variable_get(:@fiber).alive?
end

preview = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(row_actions: [])))
preview.on_action { raise 'Read-only preview submitted a move' }
preview.fields.first.trigger(:select, 0, 0)
raise 'Read-only chat path returned an action' if preview.movement_command(['A1']).action
raise 'Selection changed the input specification' unless spec.cells == [%w[A B C D], %w[E F G H]]
surface.cancel_pending_action!
first = surface.movement_command(['A1'])
restored = GameSurfaces::GridBoard.new(spec, state: surface.state)
raise 'Quiet refresh lost the native selected label' unless restored.fields.first.cell_label(0, 0) == 'A. Selected.'
raise 'Quiet refresh forgot the selected origin' unless restored.movement_command(['B1']).action&.payload == {'move' => 'first'}
new_turn = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(selection_epoch: 1)), state: surface.state)
raise 'A new move retained an old origin' if new_turn.cancel_pending_action?
raise 'A new move retained an old label' unless new_turn.fields.first.cell_label(0, 0) == 'A'
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
raise 'Forced origin required a game-specific coordinate' unless received.last.payload == {'move' => 'sole'} && received.length == 3
calls = []
explained = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(
  origin_error: ->(cell) { calls << [:origin, cell]; 'No checker here.' },
  destination_error: ->(origin, cell) { calls << [:destination, origin, cell]; 'Blocked point.' })))
NativeOptionUI.spoken.clear
explained.fields.first.trigger(:select, 3, 1)
raise 'Origin refusal lost its explanation' unless NativeOptionUI.spoken == ['No checker here.']
explained.fields.first.trigger(:select, 0, 0)
explained.fields.first.trigger(:select, 2, 0)
raise 'Destination refusal lost selection or explanation' unless explained.cancel_pending_action? && NativeOptionUI.spoken.last == 'Blocked point.'
raise 'Default refusal lost the selected label' unless explained.fields.first.labels[0][0] == 'A. Selected.'
raise 'Grid explanations received incorrect logical cells' unless calls == [[:origin, [3, 1]], [:destination, [0, 0], [2, 0]]]
explained.action_guard = -> { false }
explained.fields.first.trigger(:select, 3, 1)
raise 'A guarded grid ran a refusal callback' unless calls.size == 2
external_move = GameSurfaces::GridMove.new(origin: :external, destination: [1, 1], action: action.call('entry'))
external_spec = GameSurfaces::GridSpec.new(width: 4, height: 2, cells: spec.cells,
  move_actions: [external_move], forced_origin: :external)
external = GameSurfaces::GridBoard.new(external_spec)
external.on_action { |value| received << value }
external.fields.first.trigger(:select, 1, 1)
raise 'External origin needed a selectable source cell' unless received.last.payload == {'move' => 'entry'} && received.size == 4
[
  external_spec.to_h.merge(forced_origin: nil),
  external_spec.to_h.merge(move_actions: [GameSurfaces::GridMove.new(origin: :external, destination: :external, action: action.call('bad'))]),
  spec.to_h.merge(clear_selection_on_error: 'false'),
  spec.to_h.merge(selection_message: 'not callable')
].each do |invalid|
  begin
    GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**invalid))
  rescue ArgumentError
    next
  end
  raise 'A malformed move specification was accepted'
end
prompt_calls = []
self_destination = GameSurfaces::GridMove.new(origin: [3, 0], destination: [3, 0], action: action.call('off'))
explicit_spec = GameSurfaces::GridSpec.new(**spec.to_h.merge(move_actions: [moves.last, self_destination],
  clear_selection_on_error: true, selection_message: ->(cell) { prompt_calls << cell; 'Selected checker.' }))
explicit = GameSurfaces::GridBoard.new(explicit_spec)
explicit.on_action { |value| received << value }
NativeOptionUI.spoken.clear
explicit.fields.first.trigger(:select, 3, 0)
explicit.fields.first.trigger(:select, 0, 1)
raise 'The explicit prompt repeated' unless prompt_calls == [[3, 0]] && NativeOptionUI.spoken.first == 'Selected checker.'
raise 'A refused destination retained the checker' if explicit.cancel_pending_action?
raise 'A refused destination retained its label' unless explicit.fields.first.labels[0][3] == 'D'
explicit.fields.first.trigger(:select, 3, 0)
explicit.action_guard = -> { false }
explicit.fields.first.trigger(:select, 0, 1)
raise 'Guarded input changed selection or ran a prompt' unless explicit.cancel_pending_action? && prompt_calls.size == 2
explicit.action_guard = -> { true }
explicit.fields.first.trigger(:select, 3, 0)
raise 'Second Enter lost the explicitly declared self-destination move' unless received.last.payload == {'move' => 'off'} && !explicit.cancel_pending_action?
raise 'An emitted move retained its label' unless explicit.fields.first.labels[0][3] == 'D'
explicit.movement_command(['D1'])
explicit.movement_command(['A2'])
raise 'Chat-command refusal retained the checker' if explicit.cancel_pending_action?
external_preview = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**external_spec.to_h.merge(row_actions: [])))
external_preview.on_action { raise 'An external-origin preview submitted a move' }
external_preview.fields.first.trigger(:select, 1, 1)
raise 'An external-origin preview returned a chat action' if external_preview.movement_command(['B2']).action
selected_state = {'move_origin'=>[0, 0], 'selection_epoch'=>nil}
restored_preview = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(row_actions: [])), state: selected_state)
raise 'A read-only preview revealed a selected origin' unless restored_preview.fields.first.labels == spec.cells
bottom = GameSurfaces::GridBoard.new(GameSurfaces::GridSpec.new(**spec.to_h.merge(row_origin: :bottom)))
bottom.fields.first.trigger(:select, 0, 1)
raise 'Bottom-oriented selection marked the wrong native row' unless bottom.fields.first.labels[1][0] == 'A. Selected.' && bottom.fields.first.labels[0][0] == 'E'
bottom.cancel_pending_action!
raise 'Bottom-oriented cancellation retained the selected label' unless bottom.fields.first.labels[1][0] == 'A'
puts 'PASS native grid selection, explicit self-destination, no implicit sole move, external entry, refusal cleanup, Escape, quiet refresh, previews and guards'
