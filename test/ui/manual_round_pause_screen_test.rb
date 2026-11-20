require_relative '../support/ui'
require_relative '../support/clock_event_contract'
require_relative '../support/session_runner'
require_relative '../../games/poker'
require_relative '../../lib/game_room_pending_operation'
require_relative '../../lib/game_screen'

# Run the native Tasks worker without opening a desktop window.
def loop_update(*); Thread.pass; end

ClockEventContract.with_server_time do |time|
  fixture = ClockEventContract::Fixture.new(GameRoomGames::Poker.new, users: %w[Alice Bob])
  h = fixture.h
  h.add_client('Watcher')
  assert(h.join('Watcher'), 'Observer could not join')
  h.as('Watcher') { h.transports['Watcher'].set_observer(h.table, true, actor: 'Watcher') }
  fixture.submit('Alice')
  time.call(1002)
  fixture.submit(fixture.replay.current_player, {'kind' => 'command', 'action' => 'fold'})
  viewers = %w[Alice Bob Watcher]
  screens, waits, spoken = {}, {}, {}
  viewers.each do |user|
    h.as(user) do
      repository = h.repositories.fetch(user)
      transport = h.transports.fetch(user)
      room = -> { LobbyRepository::TableSnapshot.new(**transport.room_snapshot(h.table)) }
      snapshot = repository.snapshot_for(h.session)
      activity = TableActivityRepository.new(server_tables: Object.new, transport: transport)
      sync = GameRoomSync::Controller.new(transport: transport, table_id: h.table['__id'], session_id: h.session['__id'])
      screen = GameScreen.new(program: ProgramDouble.new(h.broker.endpoint(user)), repository: repository,
        game: h.game, session: snapshot.session, table: h.table, table_owner: 'Alice', synchronizer: sync,
        room_snapshot_provider: room, activity_repository: activity)
      spoken[user] = []
      screen.define_singleton_method(:speak_table_automatically) { |text| spoken[user] << text }
      screen.instance_variable_set(:@room_snapshot, room.call)
      screen.instance_variable_set(:@activity_entries, activity.entries_for(h.table, viewer: user))
      replay = h.game.replay(snapshot.session, snapshot.events, repository)
      screen.send(:process_new_table_activity, replay)
      screen.send(:process_new_events, replay)
      spoken[user].clear
      screens[user] = screen
      waits[user] = GameScreen::WaitState.new(replay: replay, revision: repository.events_revision(snapshot.events))
    end
  end
  refresh = lambda do |user|
    h.as(user) do
      screen, wait = screens.fetch(user), waits.fetch(user)
      assert(screen.send(:handle_signal_wait, wait, nil), 'A native pause boundary did not request a screen refresh')
      snapshot, _room, entries = screen.send(:fetch_game_payload)
      screen.instance_variable_set(:@session, snapshot.session)
      screen.instance_variable_set(:@activity_entries, entries)
      wait.replay = h.game.replay(snapshot.session, snapshot.events, h.repositories.fetch(user))
      3.times { screen.send(:process_new_table_activity, wait.replay) }
    end
  end
  paused = fixture.snapshot.session
  h.as('Alice') { h.transports['Alice'].freeze_game(paused, round_pause: true) }
  viewers.each do |user|
    refresh.call(user)
    assert(spoken[user] == ['Game paused.'], "#{user}: pause was not announced before resume/deal: #{spoken[user].inspect}")
    assert(fixture.snapshot(user).session['__frozen'], 'The feedback check unexpectedly resumed the game')
  end
  paused = fixture.snapshot.session
  h.as('Alice') do
    h.transports['Alice'].freeze_game(paused, frozen: false, round_pause: true, expected_boundary: paused['__game_boundary'])
  end
  fixture.submit('Alice')
  viewers.each do |user|
    h.as(user) do
      screen = screens.fetch(user)
      # Run the actual foreground payload/event ordering. Native window lifetime
      # and the independent runner were checked separately; this read is local.
      %i[start_sound_output start_session_runner stop_pending_speech close_game_runtime].each do |method|
        screen.define_singleton_method(method) {}
      end
      screen.define_singleton_method(:start_game_client) { true }
      screen.define_singleton_method(:wait_for_action) { |*| :back }
      screen.define_singleton_method(:synchronize_table_status) { |*| }
      assert(screen.run == :back, 'Foreground screen did not return normally')
      assert(spoken[user].first(2) == ['Game paused.', 'Game resumed.'],
        "#{user}: resume was delayed behind the next deal: #{spoken[user].inspect}")
      assert(spoken[user].count('Game resumed.') == 1, 'The resume boundary was repeated')
      assert(fixture.replay(user).state[:hand_number] == 2, 'No immediate next deal in the coalesced payload')
    end
  end
end
puts 'PASS native screen pause feedback: cached foreground activity invalidates before resume/deal for host, guest and observer'
