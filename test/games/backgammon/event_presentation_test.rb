require_relative '../../support/background_help_game_screen'
require_relative '../../../games/backgammon'
require_relative '../../../games/chess'
require_relative '../../../games/checkers'

original_play = GameRoomSounds.method(:play)
begin
  game = GameRoomGames::Backgammon.new
  harness, screen = screen_fixture(game)
  screen.send(:process_new_events, harness.replay('Alice'))
  harness.view('Alice').next_random_values = [4, 3]
  context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(87))
  harness.submit('Alice', {'kind'=>'dice', 'action'=>'opening'}, context: context)
  screen.send(:process_new_events, harness.replay('Alice'))
  calls = []
  GameRoomSounds.define_singleton_method(:play) { |_program, cue, **options| calls << [cue, options]; nil }
  before = harness.replay('Alice')
  harness.write('Alice', [GameRoomGames::EventCommand.new(action: 'move', value: '24,20,4')])
  after = harness.replay('Alice')
  screen.send(:process_new_events, after)
  assert(calls.count { |cue, _| cue == 'play2' } == 1, 'The actual screen presenter did not request the shared checker sound exactly once')
  screen.send(:process_new_events, after)
  assert(calls.count { |cue, _| cue == 'play2' } == 1, 'Quiet refresh replayed the checker sound')
  event = after.accepted_events.last
  [GameRoomGames::Chess.new, GameRoomGames::Checkers.new].each do |other|
    cue = other.event_sound_cues(event: event, before_replay: before, after_replay: after,
      history: [], viewer: 'Alice', random_variant: 0)
    assert(cue == 'play2', 'Backgammon no longer shares the chess/checkers move effect')
  end
ensure
  screen&.send(:stop_session_runner)
  GameRoomSounds.define_singleton_method(:play, original_play)
end
puts 'PASS Backgammon real screen presentation emits the chess/checkers move cue once, no repeat on refresh'
