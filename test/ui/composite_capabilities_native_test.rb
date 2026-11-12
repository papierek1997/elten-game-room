require_relative '../support/duck_challenge_native'
require_relative '../../games/domino'

def wrap_surface(spec)
  GameSurfaces::CompositeSpec.new(parts: [
    GameSurfaces::SurfacePart.new(id: 'nested', surface: GameSurfaces::CompositeSpec.new(parts: [
      GameSurfaces::SurfacePart.new(id: 'content', surface: spec)])),
    GameSurfaces::SurfacePart.new(id: 'commands', surface: GameSurfaces::CommandPanelSpec.new(commands: [
      GameSurfaces::Command.new(id: 'skip', label: 'Skip')]))])
end

question = GameSurfaces::QuestionSpec.new(id: 'question', prompt: 'Read before answering.',
  mode: :single_choice, prompt_as_text: true, submit_on_select: true,
  options: [GameSurfaces::QuestionOption.new(id: 'a', label: 'Answer A'),
    GameSurfaces::QuestionOption.new(id: 'b', label: 'Answer B')])
[question, wrap_surface(question)].each do |spec|
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: spec))
  form = layout.form
  form.focus
  driver.frame(form, driver.tap(0x28))
  assert(form.fields[form.index].is_a?(GameSurfaces::QuestionSurface::AnswerList), 'Nested question did not receive the native form')
  driver.frame(form, driver.tap(0x26))
  assert(form.fields[form.index].is_a?(GameSurfaces::QuestionSurface::PromptText), 'Nested answer cannot return to its question')
end

board = GameSurfaces::PieceBoardSpec.new(id: 'board', width: 1, height: 1,
  header: 'Board', pieces: [[nil]], row_origin: :top, selectable: [], targets: {},
  coordinate_label_sets: { 'cells' => [['A1']] }, default_coordinate_label_set: 'cells',
  silent_positions_by_coordinate_label_set: { 'cells' => [[0, 0]] }, silent_sound: 'test-cue')
driver = DuckChallengeNativeDriver.new
surface = GameSurfaces.build(wrap_surface(board))
cues = []
surface.sound_player = ->(name) { cues << name }
form = GameRoomUI::Form.new(surface.fields, quiet: true)
form.focus
cues.clear
driver.frame(form, driver.tap(0x0d))
assert(cues == ['test-cue'], 'Nested piece board lost or duplicated its sound capability')
surface.sound_player = nil
driver.frame(form, driver.tap(0x0d))
assert(cues == ['test-cue'], 'Cleared composite sound callback remains retained')

game = GameRoomGames::Domino.new
state = game.initial_state(%w[A B], game.default_options)
state.merge!(phase: :playing, round: 1, turn: 1, current_player: 'A',
  hands: { 'A' => %w[110 120 240], 'B' => ['330'] }, chain: [{ tile: '240', left: 2, right: 4 }])
replay = GameRoomGames::Replay.new(players: state[:players], state: state, current_player: 'A', history: [])
sheet = GameSurfaces::AnswerSheetSpec.new(id: 'round-1', fields: [
  GameSurfaces::AnswerField.new(id: 'country', label: 'Country', value: 'Austria')])
piece = GameSurfaces::Piece.new(id: 'piece', label: 'Piece', owner: 'A')
moving_board = GameSurfaces::PieceBoardSpec.new(id: 'moves', width: 2, height: 1, header: 'Board',
  pieces: [[piece, nil]], row_origin: :top, selectable: [[0, 0]], targets: { [0, 0] => [[1, 0]] })
{ answers: sheet, tiles: game.surface_spec(replay, 'A'), pieces: moving_board }.each do |kind, spec|
  driver = DuckChallengeNativeDriver.new
  surface = GameSurfaces.build(spec)
  emitted = []
  allowed = false
  surface.action_guard = -> { allowed }
  surface.on_action { |action| emitted << action.to_h }
  form = GameRoomUI::Form.new(surface.fields, quiet: true)
  form.index = form.fields.size - 1 if kind == :answers
  surface.fields.first.index = 1 if kind == :tiles
  form.focus
  if kind == :pieces
    driver.frame(form, driver.tap(0x0d))
    driver.frame(form, driver.tap(0x27))
  end
  driver.frame(form, driver.tap(0x0d))
  assert(emitted.empty?, "#{kind}: local action guard was bypassed")
  allowed = true
  driver.frame(form)
  driver.frame(form, driver.tap(0x0d))
  assert(emitted.size == 1, "#{kind}: legal action was lost or duplicated")
  assert(emitted.first['kind'] == { answers: 'answer_sheet', tiles: 'tile', pieces: 'piece_board' }.fetch(kind),
    "#{kind}: guarded conversion changed the action's meaning")
end
$activecontrols = []
puts 'PASS native composite form/audio forwarding and shared guards for answer sheets, actual Domino tiles and piece moves'
