require_relative '../support/ui'
require_relative '../../lib/game_screen'
require_relative '../../lib/local_game_presentation'
require_relative '../support/cheat'
require_relative '../../games/tic_tac_toe'
require_relative '../support/assertions'
include GameRoomTest::Assertions

screen = GameScreen.allocate
session = {'__id' => 1, '__game_revision' => 1, 'options' => '{}'}
snapshot = Struct.new(:session, :events)
packet = Struct.new(:snapshot)
old = snapshot.new(session, [{'id' => 1}])
fresh = snapshot.new(session.merge('__game_revision' => 2), [{'id' => 1}, {'id' => 2}])
runner = Object.new
runner.define_singleton_method(:ready_presentation_snapshot) { packet.new(fresh) }
screen.instance_variable_set(:@last_game_payload, [old])
screen.instance_variable_set(:@session_runner, runner)
assert_equal(fresh, screen.send(:receiver_presentation_snapshot, session), 'Inline acknowledged write used an old input solely because the CAS changed')
fresh.session = fresh.session.merge('__id' => 2)
assert_equal(old, screen.send(:receiver_presentation_snapshot, session), 'A new game supplied raw input for the former game')
old.session = old.session.merge('options' => '{"changed":true}')
assert_equal(nil, screen.send(:receiver_presentation_snapshot, session, required: false))
assert_raises(ArgumentError) { screen.send(:receiver_presentation_snapshot, session) }
puts 'PASS local presentation snapshot: fresh acknowledged write across transport CAS, exact semantic session identity, no foreign game/options fallback'

game = GameRoomGames::TicTacToe.new
repository = GameRoomTest::CheatFixture::Repository.new(%w[Alice Bob])
session = {'__id' => 4, '__game_revision' => 1, 'options' => '{}'}
first = {'id' => 1, 'actor' => 'Alice', 'action' => 'place', 'value' => '1,1', 'created_at' => 10}
old = snapshot.new(session, [first])
fresh = snapshot.new(session.merge('__game_revision' => 2),
  [first.merge('created_at' => 20), {'id' => 2, 'actor' => 'Bob', 'action' => 'place', 'value' => '2,1', 'created_at' => 21}])
screen.instance_variable_set(:@last_game_payload, [old])
screen.instance_variable_set(:@game, game)
screen.instance_variable_set(:@repository, repository)
screen.instance_variable_set(:@session, session)
memory = Object.new
memory.define_singleton_method(:read_json) { |_path, default: nil| default }
memory.define_singleton_method(:write_json) { |_path, _value| true }
names = GameRoomLocalNamePresentation.new(runtime: memory, account: 'Alice')
names.save('Anna Żółć')
screen.define_singleton_method(:receiver_names) { names }
canonical = game.replay(session, old.events, repository)
screen.send(:presentation_replay).bind_source(session, canonical, old.events)
screen.send(:process_new_events, canonical)
local = screen.send(:display_replay, canonical)
assert_equal(canonical.accepted_events, local.accepted_events,
  'The ready worker snapshot replaced the exact foreground source')
