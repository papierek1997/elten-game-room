require_relative '../support/session_runner'
require_relative '../../games/cheat'
require_relative '../../games/kosciane'
require_relative '../../lib/local_game_presentation'
include GameRoomTest::Assertions

runtime = Object.new
runtime.define_singleton_method(:read_json) { |_path, default: nil| default }
runtime.define_singleton_method(:write_json) { |_path, _value| true }
names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
names.save('Anna Żółć')

[GameRoomGames::TicTacToe.new, GameRoomGames::Cheat.new, GameRoomGames::Kosciane.new].each do |game|
  room = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
  room.start
  runner = runner_for(room, 'Alice')
  begin
    step(room, runner, count: 2)
    if game.id != 'cheat'
      room.as('Alice') do
        replay = room.replay('Alice')
        status, = runner.submit(session: room.session, replay: replay,
          selection: game.legal_actions(replay, 'Alice').first, actor: 'Alice')
        assert_equal(:ok, status)
      end
      step(room, runner)
    end
    published = runner.ready_presentation_snapshot
    assert(published && !published.replay.accepted_events.empty?, 'The normal runner did not publish a played game')
    room.as('Alice') do
      renderer = GameRoomLocalGamePresentation.new(game, names)
      [false, true].each do |immutable_log|
        boundary = GameRoomSnapshot.copy(published.replay)
        boundary.players = boundary.players.map(&:dup)
        if game.id == 'kosciane'
          model = boundary.state[:match_model]
          model.instance_variable_set(:@players, model.instance_variable_get(:@players).map(&:dup).freeze)
        end
        boundary.accepted_events = GameRoomSnapshot::Log.from_owned(boundary.accepted_events) if immutable_log
        local = renderer.replay(published.session, published.snapshot.events, room.repositories.fetch('Alice'), boundary: boundary)
        assert_equal(boundary.accepted_events, local.accepted_events)
        assert_equal(boundary.current_player, local.current_player)
        assert(local.history.any? { |entry| entry.text.include?('Anna Żółć') }, 'Published roster did not get the full local name')
        altered = GameRoomSnapshot.copy(boundary)
        altered.current_player = 'Forged boundary'
        assert_raises(ArgumentError) { renderer.replay(published.session, published.snapshot.events, room.repositories.fetch('Alice'), boundary: altered) }
        if game.id == 'kosciane'
          altered = GameRoomSnapshot.copy(boundary)
          altered.state[:match_model].instance_variable_set(:@rolls, 0)
          assert_raises(ArgumentError) { renderer.replay(published.session, published.snapshot.events, room.repositories.fetch('Alice'), boundary: altered) }
        end
      end
    end
  ensure
    runner.close
  end
end
puts 'PASS local presentation of ordinary runner publications: native immutable accepted logs retain the exact semantic boundary'
