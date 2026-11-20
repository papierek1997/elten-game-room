require_relative '../../support/typing_native_form'
require_relative '../../../games/backgammon'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

NativeOptionTest.language = 'en'
game = GameRoomGames::Backgammon.new
repository = Object.new
def repository.players_for(_session); %w[Alice Bob]; end
def repository.actor_of(event, _session); event.fetch('actor'); end
def repository.event_id(event); event.fetch('id'); end
event = {'id'=>1, 'actor'=>'Alice', 'action'=>'opening', 'value'=>'4,3'}
replay = game.replay({}, [event], repository)

# Exact and oversized dice, both player perspectives, and a checker with
# a normal destination as well as a bearing-off action. First Enter selects.
[
  [{4=>1, 1=>1, 0=>13}, [4, 2], 4, '4,0,4'],
  [{3=>1, 1=>1, 0=>13}, [5, 1], 3, '3,0,5'],
  [{1=>1, 0=>14}, [6], 1, '1,0,6']
].each do |own, dice, point, expected|
  [0, 1].each do |side|
    boards = [{24=>15}, {24=>15}]
    boards[side] = own
    view = replay.dup
    view.state = replay.state.merge(board: boards, dice: dice, turn: side)
    view.board = boards
    view.current_player = view.players.fetch(side)
    actor = view.current_player
    candidate = GameSurfaces.build(game.surface_spec(view, actor))
    emitted = []
    candidate.on_action { |action| emitted << action }
    candidate.fields.first.x, candidate.fields.first.y = point - 1, 1
    trial = NativeTypingFormDriver.new do
      form = GameRoomUI::Form.new(candidate.fields, quiet: true)
      form.on(:key_escape) { candidate.cancel_pending_action! }
      form.wait
    end
    begin
      NativeOptionUI.spoken.clear
      trial.press([13])
      assert(emitted.empty?, 'First Enter bore off a checker')
      assert_equal(1, NativeOptionUI.spoken.size, 'Bearing-off selection repeated its prompt')
      assert_equal(['Selected.'], NativeOptionUI.spoken)
      marked_label = candidate.fields.first.cell_label
      assert(marked_label.end_with?('. Selected.'), 'The selected checker has no native field marker')
      trial.press([27])
      assert(!candidate.cancel_pending_action?, 'Escape retained the checker')
      assert(!candidate.fields.first.cell_label.end_with?('. Selected.'), 'Escape retained the field marker')
      trial.press([13])
      restored = GameSurfaces.build(game.surface_spec(view, actor), state: candidate.state)
      assert(restored.cancel_pending_action?, 'Quiet refresh lost the selected checker')
      assert_equal(marked_label, restored.fields.first.cell_label, 'Quiet refresh lost the marker on the native field')
      changed = view.dup
      changed.accepted_events = view.accepted_events + [{'id'=>2}]
      assert(!GameSurfaces.build(game.surface_spec(changed, actor), state: candidate.state).cancel_pending_action?, 'A new accepted event retained the old checker')
      trial.press([13])
      assert_equal([expected], emitted.map { |action| action.payload.fetch('move') })
      assert(!candidate.cancel_pending_action?, 'Bearing off retained the old selection')
      assert(!candidate.fields.first.cell_label.end_with?('. Selected.'), 'Bearing off retained the field marker')
      selection = {'kind'=>'pawn', 'action'=>'move', 'move'=>expected}
      assert_equal(:ok, game.action_for(selection, view, actor).first, 'UI emitted an illegal move')
      moved = GameRoomGames::BackgammonRules.apply(boards, side, expected.split(',').map(&:to_i))
      assert_equal(own.fetch(0, 0) + 1, moved[side].fetch(0))
    ensure
      trial.form.resume
      trial.press([]) if trial.instance_variable_get(:@fiber).alive?
    end
    readonly = GameSurfaces.build(game.board_grid(view, actor))
    readonly.action_guard = -> { false }
    readonly.on_action { raise 'The board preview performed a move' }
    2.times { readonly.fields.first.trigger(:select, point - 1, 1) }
    assert(!readonly.cancel_pending_action?)
    guarded = GameSurfaces.build(game.surface_spec(view, actor))
    guarded.action_guard = -> { false }
    guarded.on_action { raise 'A guarded board performed a move' }
    2.times { guarded.fields.first.trigger(:select, point - 1, 1) }
    assert(!guarded.cancel_pending_action?)
  end
end

# Even a sole ordinary move requires its destination. A second Enter on
# the origin outside home cancels selection instead of attempting bearing off.
[0, 1].each do |side|
  view = replay.dup
  view.board = [{24=>15}, {24=>15}]
  view.board[side] = {8=>1, 0=>14}
  view.state = replay.state.merge(board: view.board, dice: [6], turn: side)
  view.current_player = view.players.fetch(side)
  original = Marshal.dump(view)
  actor = view.current_player
  sole = GameSurfaces.build(game.surface_spec(view, actor))
  emitted = []
  sole.on_action { |action| emitted << action }
  sole.fields.first.x, sole.fields.first.y = 7, 1
  trial = NativeTypingFormDriver.new { GameRoomUI::Form.new(sole.fields, quiet: true).wait }
  begin
    NativeOptionUI.spoken.clear
    trial.press([13])
    assert_equal(['Selected.'], NativeOptionUI.spoken)
    assert(emitted.empty?)
    trial.press([13])
    assert(emitted.empty?, 'Second Enter automatically performed the sole ordinary move')
    assert_equal(['Selected.', 'Piece selection cancelled.'], NativeOptionUI.spoken)
    assert(!sole.cancel_pending_action?, 'Refused second Enter retained selection')
    assert(!sole.fields.first.cell_label.end_with?('. Selected.'), 'Refused second Enter retained the field marker')
    assert_equal(original, Marshal.dump(view), 'Refused second Enter changed the game')
    trial.press([13])
    6.times { trial.press([37]) }
    trial.press([13])
    assert_equal(['8,2,6'], emitted.map { |action| action.payload.fetch('move') })
    assert_equal(:ok, game.action_for({'kind'=>'pawn', 'action'=>'move', 'move'=>'8,2,6'}, view, actor).first)
  ensure
    trial.form.resume
    trial.press([]) if trial.instance_variable_get(:@fiber).alive?
  end
end

counter_view = replay.dup
counter_view.board = [{25=>2, 0=>3, 6=>10}, {25=>1, 0=>4, 6=>10}]
counters = game.custom_game_shortcuts(counter_view, 'Alice').to_h { |shortcut| [shortcut.key, shortcut.message] }
assert_equal('Bar: Alice, 2. Bob, 1.', counters.fetch('b'))
assert_equal('Borne off: Alice, 3. Bob, 4.', counters.fetch('z'))
puts 'PASS Backgammon native double-Enter only bears off; ordinary moves need destinations, both seats, Escape, quiet refresh, guards and B/Z'
