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
spec = game.surface_spec(replay, 'Alice')
assert(spec.cells.first.first.start_with?('Point 24:'), 'The first field is an empty bar rather than the board')
assert_equal([12, 2], [spec.width, spec.height])
assert_equal((24.downto(13).to_a + (1..12).to_a), spec.cells.flatten.map { |label| label[/\APoint (\d+):/, 1].to_i })
surface = GameSurfaces.build(spec)
actions = []
surface.on_action { |action| actions << action }
driver = NativeTypingFormDriver.new do
  form = GameRoomUI::Form.new(surface.fields, quiet: true)
  form.on(:key_escape) { surface.cancel_pending_action! }
  form.wait
end
begin
  NativeOptionUI.spoken.clear
  driver.press([13])
  assert_equal(['Selected.'], NativeOptionUI.spoken)
  assert_equal(spec.cells[0][0] + '. Selected.', surface.fields.first.cell_label)
  driver.press([39])
  NativeOptionUI.spoken.clear
  driver.press([37])
  assert_equal([spec.cells[0][0] + '. Selected.'], NativeOptionUI.spoken, 'Returning to the checker lost its selected readout')
  NativeOptionUI.spoken.clear
  driver.press([13])
  assert_equal(['Piece selection cancelled.'], NativeOptionUI.spoken)
  assert(actions.empty?, 'A second Enter outside home performed an ordinary move')
  assert(!surface.cancel_pending_action?, 'A second Enter outside home did not cancel selection')
  assert_equal(spec.cells[0][0], surface.fields.first.cell_label, 'Refusal left a selected cell label')
  driver.press([13])
  driver.press([39])
  NativeOptionUI.spoken.clear
  driver.press([13])
  assert_equal(['A single move must match one of your remaining dice: 4, 3.'], NativeOptionUI.spoken)
  assert(!surface.cancel_pending_action?, 'Refusal retained the selected checker')
  assert(actions.empty?, 'An invalid destination submitted a move')
  driver.press([37])
  driver.press([13])
  driver.press([39])
  3.times { driver.press([39]) }
  driver.press([13])
  assert_equal('24,20,4', actions.last.payload.fetch('move'))
  assert_equal([event], replay.accepted_events, 'Native selection changed accepted history')
  driver.press([27])
  surface.fields.first.x, surface.fields.first.y = 1, 0
  NativeOptionUI.spoken.clear
  driver.press([13])
  assert_equal(['You have no checker on point 23.'], NativeOptionUI.spoken)
  14.times { driver.press([39]) }
  assert_equal(11, surface.fields.first.x, 'The removed bar is still reachable')
  driver.press([40])
  assert_equal(11, surface.fields.first.x, 'The lower row retained an off-board field')
ensure
  driver.form.resume
  driver.press([]) if driver.instance_variable_get(:@fiber).alive?
end

def refused_destination(game, replay, from, to)
  spec = game.surface_spec(replay, replay.current_player)
  surface = GameSurfaces.build(spec)
  actions = []
  surface.on_action { |action| actions << action }
  surface.fields.first.trigger(:select, *from) unless spec.forced_origin
  NativeOptionUI.spoken.clear
  surface.fields.first.trigger(:select, *to)
  raise 'Refused destination emitted a move' unless actions.empty?
  NativeOptionUI.spoken.last
end

view = replay.dup
view.state = replay.state.merge(board: [{8=>1, 6=>14}, {20=>2, 24=>13}], dice: [1, 3])
view.board = view.state[:board]
assert_equal('Point 5 is blocked by 2 opposing checkers.', refused_destination(game, view, [7, 1], [4, 1]))
assert_equal('Checkers move toward lower-numbered points.', refused_destination(game, view, [7, 1], [8, 1]))
view.state = replay.state.merge(board: [{25=>1, 6=>14}, {6=>15}], dice: [2, 5])
view.board = view.state[:board]
assert_equal('Choose an entry point from 19 to 24 for your checker on the bar.', refused_destination(game, view, nil, [5, 1]))
assert_equal(:external, game.surface_spec(view, 'Alice').forced_origin)
entry_surface = GameSurfaces.build(game.surface_spec(view, 'Alice'))
entry_surface.on_action { |action| actions << action }
entry_surface.fields.first.trigger(:select, 1, 0)
assert_equal('25,23,2', actions.last.payload.fetch('move'))
assert(!entry_surface.cancel_pending_action?, 'Mandatory entry left a phantom selected board point')
view.state = replay.state.merge(board: [{8=>1, 6=>14}, {18=>2, 20=>2, 24=>11}], dice: [1, 3])
view.board = view.state[:board]
blocked = GameSurfaces.build(game.surface_spec(view, 'Alice'))
NativeOptionUI.spoken.clear
blocked.fields.first.trigger(:select, 7, 1)
assert_equal('Point 7 is blocked by 2 opposing checkers. Point 5 is blocked by 2 opposing checkers.', NativeOptionUI.spoken.last)

selection = game.legal_actions(replay, 'Alice').find { |choice| choice['move'] == '24,20,4' }
status, plan = game.action_for(selection, replay, 'Alice')
assert_equal(:ok, status)
command = plan.events.first
move = {'id'=>2, 'actor'=>'Alice', 'action'=>command.action, 'value'=>command.value}
after = game.replay({}, [event, move], repository)
history = after.history.select { |entry| entry.event_id == 2 }
assert_equal('play2', game.event_sound_cues(event: move, before_replay: replay,
  after_replay: after, history: history, viewer: 'Alice', random_variant: 0))
assert_equal(['Alice moves a checker from point 24 to point 20.'], history.map(&:text))
assert_equal(1, after.state[:dice].size)
assert(after.history.none? { |entry| entry.key.start_with?('blocked:') }, 'A playable turn announced a forced pass')
puts 'PASS Backgammon native 24-point board, Enter explanations, bar entry and checker sound'
