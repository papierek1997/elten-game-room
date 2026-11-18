require_relative '../support/session_runner'
require_relative '../../lib/local_game_presentation'
require_relative '../../lib/room_presentation'
include GameRoomTest::Assertions

runtime = Object.new
runtime.define_singleton_method(:read_json) { |_path, default: nil| default }
runtime.define_singleton_method(:write_json) { |_path, _value| true }
names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
names.save('Grzegorz Turek')
other = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Bob')
game = GameRoomGames::TicTacToe.new
room = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
room.start
room.add_client('Watcher')
assert(room.join('Watcher'), 'Observer could not join')
runners = room.users.to_h { |user| [user, runner_for(room, user)] }
begin
  [[0, 0], [1, 0], [0, 1], [1, 1], [0, 2]].each do |x, y|
    actor = room.replay('Alice').current_player
    room.as(actor) do
      status, = runners.fetch(actor).submit(session: room.session, replay: room.replay(actor),
        selection: {'kind' => 'grid', 'action' => 'select', 'x' => x, 'y' => y}, actor: actor)
      assert_equal(:ok, status)
    end
    room.assert_converged('local name receiver fixture')
    %w[Alice Bob Watcher].each do |viewer|
      room.as(viewer) do
        repo = room.repositories.fetch(viewer)
        snapshot = repo.snapshot_for(room.session)
        service = viewer == 'Alice' ? names : other
        view = GameRoomLocalGamePresentation.new(game, service).replay(snapshot.session, snapshot.events, repo)
        text = view.history.map(&:text).join('\n')
        if viewer == 'Alice'
          assert(text.include?('Grzegorz Turek'), 'Own full roster name is missing')
          assert(text.include?('Grzegorz A1'), 'Own move did not use the first name')
        else
          assert(!text.include?('Grzegorz'), 'Local name leaked to another client or observer')
          assert(text.include?('Alice A1'), 'Remote canonical move author changed')
        end
        assert(!Marshal.dump([snapshot.session, snapshot.events]).include?('Grzegorz'), 'Receiver text entered the native session')
        assert_equal(%w[Alice Bob], view.players)
      end
    end
  end
  assert_equal('Alice', room.replay('Bob').winner)
ensure
  runners.each_value(&:close)
end
puts 'PASS local broker three receiver views through normal executor/repositories: full own roster/result, first-name moves, unchanged opponent/observer views and native event bytes; no live-server claim'
