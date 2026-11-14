require_relative '../../support/typing_native_form'
require_relative '../../../games/backgammon'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

NativeOptionTest.language = 'en'
game = GameRoomGames::Backgammon.new
repo = Object.new
def repo.players_for(_); %w[Alice Bob]; end
def repo.actor_of(event, _); event.fetch('actor'); end
def repo.event_id(event); event.fetch('id'); end
base = game.replay({}, [{'id'=>1, 'actor'=>'Alice', 'action'=>'opening', 'value'=>'4,3'}], repo)
cell = ->(point) { point >= 13 ? [24 - point, 0] : [point - 1, 1] }
cases = [
  ['empty origin', {8=>1, 0=>14}, {24=>15}, [1, 3], 7, nil,
    'You have no checker on point 7.'],
  ['opposing origin', {8=>1, 0=>14}, {18=>2, 24=>13}, [1, 3], 7, nil,
    'You have no checker on point 7.'],
  ['wrong direction', {8=>1, 0=>14}, {24=>15}, [1, 3], 8, 9,
    'Checkers move toward lower-numbered points.'],
  ['distance before a blocked target', {8=>1, 0=>14}, {19=>2, 24=>13}, [1, 3], 8, 6,
    'A single move must match one of your remaining dice: 1, 3.'],
  ['blocked target', {8=>1, 0=>14}, {20=>2, 24=>13}, [1, 3], 8, 5,
    'Point 5 is blocked by 2 opposing checkers.'],
  ['all origins blocked', {8=>1, 6=>14}, {18=>2, 20=>2, 24=>11}, [1, 3], 8, nil,
    'Point 7 is blocked by 2 opposing checkers. Point 5 is blocked by 2 opposing checkers.'],
  ['wrong bar entry area', {25=>1, 6=>14}, {6=>15}, [2, 5], nil, 6,
    'Choose an entry point from 19 to 24 for your checker on the bar.'],
  ['bar entry needs a different die', {25=>1, 6=>14}, {6=>15}, [2, 5], nil, 22,
    'A single move must match one of your remaining dice: 2, 5.'],
  ['not all checkers home', {4=>1, 8=>1, 0=>13}, {24=>15}, [2, 4], 4, 4,
    'Bring all your checkers into points 1 to 6 before bearing off.'],
  ['no die large enough to bear off', {4=>1, 0=>14}, {24=>15}, [1], 4, 4,
    'None of the remaining dice can bear off this checker.'],
  ['oversized die with a farther checker', {2=>1, 4=>1, 0=>13}, {20=>15}, [3], 2, nil,
    'With a larger die, you must first move a checker farther from the exit.'],
  ['higher-die obligation', {8=>1, 0=>14}, {20=>2, 24=>13}, [1, 2], 8, 7,
    'You must use the higher die, 2.'],
  ['maximum-dice obligation', {4=>1, 0=>14}, {24=>15}, [2, 4], 4, 4,
    'Choose a move that lets you use as many dice as possible.'],
  ['Egyptian point limit', {8=>1, 6=>5, 0=>9}, {24=>15}, [1, 2], 8, 6,
    'Point 6 already has the maximum of 5 checkers.', 5]
]
cases.each do |label, own, other, dice, from, to, expected, limit|
  [0, 1].each do |side|
    view = base.dup
    view.board = side.zero? ? [own, other] : [other, own]
    view.state = base.state.merge(board: view.board, turn: side, dice: dice, point_limit: limit)
    view.current_player = view.players.fetch(side)
    original = Marshal.dump(view)
    spec = game.surface_spec(view, view.current_player)
    assert(spec.is_a?(GameSurfaces::GridSpec), "#{label}: fixture has no editable board")
    surface = GameSurfaces.build(spec)
    messages = []
    surface.define_singleton_method(:speak) { |text| messages << text }
    surface.on_action { raise "#{label}: refusal submitted a move" }
    if from && to
      surface.fields.first.trigger(:select, *cell.call(from))
      assert(surface.cancel_pending_action?, "#{label}: fixture could not select its origin")
    end
    messages.clear
    surface.fields.first.trigger(:select, *cell.call(to || from))
    assert_equal([expected], messages, "#{label}/seat #{side}: wrong or repeated explanation")
    assert(!surface.cancel_pending_action?, "#{label}: refusal retained a selection")
    assert_equal(original, Marshal.dump(view), "#{label}: feedback mutated the game")
  end
end
puts 'PASS Backgammon refusal review: 14 distinct positions in both seats, native origin/destination handlers, exact single feedback and no game mutation'
