require_relative '../../support/typing_native_form'
require_relative '../../../games/backgammon'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

repository = Object.new
def repository.players_for(session); session.fetch('__players', %w[Alice Bob]); end
def repository.actor_of(event, _session); event.fetch('actor'); end
def repository.event_id(event); event.fetch('id'); end
rows = [
  ['Alice', 'opening', '3,6'], ['Bob', 'move', '13,10,3'], ['Bob', 'move', '8,2,6'],
  ['Alice', 'roll', '2,6'], ['Alice', 'move', '24,22,2'], ['Alice', 'move', '22,16,6'],
  ['Bob', 'roll', '2,1'], ['Bob', 'move', '10,9,1']
]
events = rows.each_with_index.map { |(actor, action, value), index| {'id'=>index + 1, 'actor'=>actor, 'action'=>action, 'value'=>value} }
templates = {
  'en'=>['%{player} moves a checker from point %{from} to point %{to}.', "The opponent's checker goes to the bar."],
  'pl'=>['%{player} przesuwa pionek z pola %{from} na pole %{to}.', 'Pionek przeciwnika trafia na bandę.'],
  'cs'=>['%{player} přesouvá kámen z bodu %{from} na bod %{to}.', 'Soupeřův kámen jde na bar.'],
  'es'=>['%{player} mueve una ficha del punto %{from} al punto %{to}.', 'La ficha rival va a la barra.'],
  'ru'=>['%{player} передвигает шашку с пункта %{from} на пункт %{to}.', 'Шашка соперника отправляется на бар.']
}
templates.each do |language, (template, capture)|
  NativeOptionTest.language = language
  game = GameRoomGames::Backgammon.new
  before = game.replay({}, events[0...-1], repository)
  replay = game.replay({}, events, repository)
  assert_equal(8, replay.accepted_events.size)
  assert_equal(1, before.board[0].fetch(16))
  assert_equal(1, replay.board[0].fetch(25), 'The actual capture changed')
  assert_equal(1, replay.board[1].fetch(9))
  assert(!replay.board[0].key?(16))
  original = Marshal.dump(replay)
  {'Alice'=>[15, 16], 'aLiCe'=>[15, 16], 'Bob'=>[10, 9], 'Watcher'=>[15, 16]}.each do |viewer, (from, to)|
    expected = (template % {player: 'Bob', from: from, to: to}) + ' ' + capture
    displayed = game.history_entries_for_display(replay, viewer)
    history = displayed.find { |entry| entry.event_id == 8 && entry.kind == :move }
    assert_equal(expected, history.text, "#{language}/#{viewer}: history uses the other board's numbering")
    assert_equal([expected], game.describe_event_for_display(events.last, repository, replay, viewer), "#{language}/#{viewer}: speech and history disagree")
    board = game.board_grid(replay, viewer)
    cell = to >= 13 ? [24 - to, 0] : [to - 1, 1]
    assert(board.cells[cell[1]][cell[0]].include?('Bob, 1'), 'Displayed destination and occupied board cell disagree')
  end
  assert_equal(original, Marshal.dump(replay), 'View projections mutated the canonical replay')
  assert_equal(GameRoomGames::Backgammon.new.replay({}, events, repository).to_h, replay.to_h, 'Cold reconstruction changed the captured move')

  # A historical name may no longer be in the current roster. Its event-time
  # seat, not a lookup of that name in today's roster, owns the coordinates.
  session = {'__players'=>%w[Alice Carol], '__initial_players'=>%w[Alice Bob],
    '__seat_changes'=>[{'id'=>9, 'players'=>%w[Alice Carol]}]}
  replaced = game.replay(session, events, repository)
  expected = (template % {player: 'Bob', from: 10, to: 9}) + ' ' + capture
  assert_equal(expected, game.history_entries_for_display(replaced, 'Carol').find { |entry| entry.event_id == 8 }.text,
    'Replacement renamed the historical player or lost the historical seat')
end

NativeOptionTest.language = 'en'
[[25, 23, 2, {25=>1, 0=>14}, 'enters a checker from the bar on point 2.'],
 [4, 0, 4, {4=>2, 0=>13}, 'bears off a checker from point 21.']].each do |from, to, die, own, ending|
  game = GameRoomGames::Backgammon.new
  initial = game.send(:initial_game_state, game.normalize_options({})).merge(board: [own, {24=>15}], phase: :move, dice: [die])
  game.define_singleton_method(:initial_game_state) { |_| Marshal.load(Marshal.dump(initial)) }
  event = {'id'=>1, 'actor'=>'Alice', 'action'=>'move', 'value'=>[from, to, die].join(',')}
  replay = game.replay({}, [event], repository)
  assert_equal([event], replay.accepted_events)
  expected = "Alice #{ending}"
  assert_equal([expected], game.describe_event_for_display(event, repository, replay, 'Bob'))
  assert_equal(expected, game.history_entries_for_display(replay, 'Bob').find { |entry| entry.kind == :move }.text)
end
puts 'PASS reported Backgammon capture: board, live speech and exported history agree for both seats, observers, five languages, replacements, entry and bearing off'
