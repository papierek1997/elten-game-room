require_relative '../../support/typing_native_form'
require_relative '../../../games/backgammon'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

repo = Object.new
def repo.players_for(_session); %w[Alice Bob]; end
def repo.actor_of(event, _session); event.fetch('actor'); end
def repo.event_id(event); event.fetch('id'); end

texts = {
  'en'=>['Alice moves a checker from point 8 to point 2.', 'Alice enters a checker from the bar on point 23.', 'Alice bears off a checker from point 4.'],
  'pl'=>['Alice przesuwa pionek z pola 8 na pole 2.', 'Alice wprowadza pionek z bandy na pole 23.', 'Alice zdejmuje pionek z pola 4.'],
  'cs'=>['Alice přesouvá kámen z bodu 8 na bod 2.', 'Alice vrací kámen z baru na bod 23.', 'Alice vyvádí kámen z bodu 4.'],
  'es'=>['Alice mueve una ficha del punto 8 al punto 2.', 'Alice vuelve a introducir una ficha de la barra en el punto 23.', 'Alice retira una ficha del punto 4.'],
  'ru'=>['Alice передвигает шашку с пункта 8 на пункт 2.', 'Alice вводит шашку с бара на пункт 23.', 'Alice снимает шашку с пункта 4.']
}

positions = [
  [[{8=>1, 0=>14}, {24=>15}], [6], '8,2,6'],
  [[{25=>1, 0=>14}, {24=>15}], [2], '25,23,2'],
  [[{4=>1, 0=>14}, {24=>15}], [4], '4,0,4']
]
texts.each do |language, expected|
  NativeOptionTest.language = language
  positions.each_with_index do |(boards, dice, value), index|
    game = GameRoomGames::Backgammon.new
    # Seed a legal late-game position, then use the real production reducer,
    # ordinary action validator and event cue hook; there is no alternate model.
    initial = game.send(:initial_game_state, game.normalize_options({})).merge(
      board: boards, phase: :move, dice: dice)
    game.define_singleton_method(:initial_game_state) { |_| Marshal.load(Marshal.dump(initial)) }
    before = game.replay({}, [], repo)
    selection = {'kind'=>'pawn', 'action'=>'move', 'move'=>value}
    status, plan = game.action_for(selection, before, 'Alice')
    assert_equal(:ok, status)
    command = plan.events.fetch(0)
    event = {'id'=>1, 'actor'=>'Alice', 'action'=>command.action, 'value'=>command.value}
    after = game.replay({}, [event], repo)
    cold = game.class.new
    cold.define_singleton_method(:initial_game_state) { |_| Marshal.load(Marshal.dump(initial)) }
    assert_equal(after.to_h, cold.replay({}, [event], repo).to_h, 'Cold replay changed the move feedback')
    assert_equal([event], after.accepted_events)
    history = after.history.select { |entry| entry.event_id == 1 && entry.kind == :move }
    assert_equal([expected.fetch(index)], history.map(&:text), "#{language}: technical or repeated move announcement")
    assert_equal('play2', game.event_sound_cues(event: event, before_replay: before,
      after_replay: after, history: history, viewer: 'Alice', random_variant: 0))
  end
end
puts 'PASS Backgammon natural ordinary/entry/bearing-off history and shared board-piece cue, real reducer in five languages'
