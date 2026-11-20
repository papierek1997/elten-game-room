require_relative '../../support/typing_native_form'
require_relative '../../../games/backgammon'
require_relative '../../../games/french_tarot_support/french_tarot_table'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

expected = {
  'en'=>'You have no checker on point 23.',
  'pl'=>'Na polu 23 nie masz swojego pionka.',
  'cs'=>'Na poli 23 nemáte vlastní kámen.',
  'es'=>'No tienes ninguna ficha en el punto 23.',
  'ru'=>'На пункте 23 нет вашей шашки.'
}
selection_prompts = {
  'en'=>'Selected.', 'pl'=>'Zaznaczono.', 'cs'=>'Vybráno.', 'es'=>'Seleccionada.', 'ru'=>'Выбрано.'
}
cancel_prompts = {
  'en'=>'Piece selection cancelled.', 'pl'=>'Anulowano wybór pionka.', 'cs'=>'Výběr figurky byl zrušen.',
  'es'=>'Selección de pieza cancelada.', 'ru'=>'Выбор фигуры отменён.'
}
distance_prompts = {
  'en'=>'A single move must match one of your remaining dice: 4, 3.',
  'pl'=>'Ruch musi odpowiadać jednej z pozostałych kości: 4, 3.',
  'cs'=>'Jeden tah musí odpovídat jedné ze zbývajících kostek: 4, 3.',
  'es'=>'Cada movimiento debe corresponder a uno de tus dados restantes: 4, 3.',
  'ru'=>'Одно перемещение должно соответствовать одной из оставшихся костей: 4, 3.'
}
repository = Object.new
def repository.players_for(_); %w[Alice Bob]; end
def repository.actor_of(event, _); event.fetch('actor'); end
def repository.event_id(event); event.fetch('id'); end
expected.each do |language, message|
  NativeOptionTest.language = language
  game = GameRoomGames::Backgammon.new
  replay = game.replay({}, [{'id'=>1, 'actor'=>'Alice', 'action'=>'opening', 'value'=>'4,3'}], repository)
  surface = GameSurfaces.build(game.surface_spec(replay, 'Alice'))
  surface.on_action { raise 'A translated refusal submitted a move' }
  driver = NativeTypingFormDriver.new { GameRoomUI::Form.new(surface.fields, quiet: true).wait }
  begin
    surface.fields.first.x, surface.fields.first.y = 1, 0
    NativeOptionUI.spoken.clear
    driver.press([13])
    assert_equal([message], NativeOptionUI.spoken, "#{language}: missing, duplicated or binary-mismatched refusal")
  ensure
    driver.form.resume
    driver.press([]) if driver.instance_variable_get(:@fiber).alive?
  end
  [0, 1].each do |side|
    view = replay.dup
    view.state = replay.state.merge(turn: side)
    view.current_player = view.players.fetch(side)
    candidate = GameSurfaces.build(game.surface_spec(view, view.current_player))
    candidate.on_action { raise 'Cancellation or a refused distance submitted a move' }
    # The reported field 13 is the rightmost point of the upper row.
    candidate.fields.first.x, candidate.fields.first.y = 11, 0
    trial = NativeTypingFormDriver.new { GameRoomUI::Form.new(candidate.fields, quiet: true).wait }
    begin
      NativeOptionUI.spoken.clear
      2.times { trial.press([13]) }
      assert_equal([selection_prompts.fetch(language), cancel_prompts.fetch(language)], NativeOptionUI.spoken,
        "#{language}: repeated Enter outside home still explains bearing off")
      assert(!candidate.cancel_pending_action?)
      assert(!candidate.fields.first.cell_label.end_with?(selection_prompts.fetch(language)))
      trial.press([13])
      # Attempt to move from point 13 to point 6 by adding both dice.
      6.times { trial.press([37]) }
      trial.press([40])
      NativeOptionUI.spoken.clear
      trial.press([13])
      assert_equal([distance_prompts.fetch(language)], NativeOptionUI.spoken,
        "#{language}: a refused distance requires an imaginary die or repeats feedback")
      assert(!candidate.cancel_pending_action?)
    ensure
      trial.form.resume
      trial.press([]) if trial.instance_variable_get(:@fiber).alive?
    end
  end
  [[{4=>1, 1=>1, 0=>13}, [4, 2], 4], [{1=>1, 0=>14}, [6], 1]].each do |own, dice, point|
    view = replay.dup
    view.board = [own, {24=>15}]
    view.state = replay.state.merge(board: view.board, dice: dice)
    candidate = GameSurfaces.build(game.surface_spec(view, 'Alice'))
    actions = []
    candidate.on_action { |action| actions << action }
    candidate.fields.first.x, candidate.fields.first.y = point - 1, 1
    trial = NativeTypingFormDriver.new { GameRoomUI::Form.new(candidate.fields, quiet: true).wait }
    begin
      NativeOptionUI.spoken.clear
      trial.press([13])
      assert_equal([selection_prompts.fetch(language)], NativeOptionUI.spoken, "#{language}: bearing-off prompt repeated or untranslated")
      assert(actions.empty?, 'Localized first Enter moved a checker')
      label = candidate.fields.first.cell_label
      assert(label.end_with?(selection_prompts.fetch(language)), "#{language}: the selected native field lacks its marker")
      trial.press([39])
      NativeOptionUI.spoken.clear
      trial.press([37])
      assert_equal([label], NativeOptionUI.spoken, "#{language}: returning to the selected field lost or repeated its marker")
      NativeOptionUI.spoken.clear
      trial.press([13])
      assert_equal(1, actions.size)
      assert_equal([], NativeOptionUI.spoken, "#{language}: second Enter reread the selection prompt")
      assert(!candidate.fields.first.cell_label.end_with?(selection_prompts.fetch(language)), "#{language}: a completed move retained the marker")
    ensure
      trial.form.resume
      trial.press([]) if trial.instance_variable_get(:@fiber).alive?
    end
  end
end
puts 'PASS Backgammon native cancellation, die-distance refusal and bearing-off feedback exactly once in both seats and five languages'
