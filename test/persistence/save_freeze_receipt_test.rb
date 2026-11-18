require_relative "../support/saved_games_ui"

broker = NativeLiveSessionsBroker.new
app = SaveAppDriver.new(broker)
$game_room_test_user = 'Alice'
game = GameRoomGames::Uno.new
table = app.lobby.create_table(name: 'Save boundary', game: game.id, owner: 'Alice',
  game_options: '{}', bot_count: 1, bot_names: ['pl20']).table
players = ['Alice'] + GameRoomParticipants.bots_for(table['__id'], 1, names: ['pl20'])
session = app.games.start_session(table: table, game: game.id, players: players,
  options: JSON.generate(game.default_options))
app.prepare_playing_game(table, session, game)
view = broker.endpoint('Alice').sessions.first
view.singleton_class.prepend(Module.new do
  def stack_push(packet, message_id:)
    result = super
    if @fail_after_freeze && packet['kind'] == 'game_boundary' && packet.dig('data', 'frozen') == true
      @fail_after_freeze = false
      self.fail_next_read = EltenAPI::LiveSessions::TimeoutError.new('Read failed after confirmed freeze')
    end
    result
  end
end)
view.instance_variable_set(:@fail_after_freeze, true)
assert(!app.send(:save_current_game, table, session, game), 'Failed read was treated as a saved archive')
assert(!app.games.snapshot_for(session, force_events: true).session['__frozen'], 'Confirmed pause was left behind')
assert(app.send(:saved_games).list.empty?, 'Failed snapshot created an archive')
assert(app.transport.current_room('Alice') && !broker.cores.values.first.closed, 'Failed save closed the table')
boundaries = broker.cores.values.first.entries.select { |entry| entry['packet']['kind'] == 'game_boundary' }
assert(boundaries.map { |entry| entry['packet']['data']['frozen'] } == [true, false], 'Missing or duplicate rollback')
snapshot = app.games.snapshot_for(session)
replay = game.replay(snapshot.session, snapshot.events, app.games)
actor = replay.current_player
selection = game.legal_actions(replay, actor).first
status, plan = game.action_for(selection, replay, actor)
assert(status == :ok, 'Game cannot continue after the failed save')
app.games.append_events(session: session, sequence: app.games.next_sequence(session, snapshot.events),
  events: plan.events, actor: actor, controller: true)
assert(app.games.snapshot_for(session).events.length > snapshot.events.length, 'Next move did not persist')

fresh = app.games.snapshot_for(session).session
app.transport.freeze_game(fresh, round_pause: true)
paused = app.games.snapshot_for(session).session
view.instance_variable_set(:@fail_after_freeze, true)
assert(!app.send(:save_current_game, table, paused, game), 'Failed snapshot was saved during a manual pause')
after_failure = app.games.snapshot_for(session).session
assert(after_failure['__frozen'] && after_failure['__round_pause'], 'A failed save released the earlier manual pause')
assert(app.transport.freeze_game(after_failure, frozen: false, expected_boundary: after_failure['__game_boundary'], round_pause: true),
  'A failed save made the manual pause impossible to resume')

first = app.transport.freeze_game(session)
second = app.transport.freeze_game(session)
assert(!app.transport.freeze_game(session, frozen: false, expected_boundary: first), 'Old rollback released a newer pause')
assert(app.games.snapshot_for(session).session['__frozen'], 'Newer save was unfrozen')
assert(app.transport.freeze_game(session, frozen: false, expected_boundary: second), 'Current receipt cannot release its own pause')
assert(app.transport.abort_game(session), 'Could not end original match')
replacement = app.games.start_session(table: table, game: game.id, players: players,
  options: JSON.generate(game.default_options), expected_previous_session_id: session['__id'])
new_pause = app.transport.freeze_game(replacement)
assert(!app.transport.freeze_game(session, frozen: false, expected_boundary: second), 'Old rollback wrote to an ended game')
assert(app.games.snapshot_for(replacement).session['__frozen'], 'Old rollback released the new game')
assert(app.transport.freeze_game(replacement, frozen: false, expected_boundary: new_pause), 'New game cleanup failed')
puts 'PASS save: confirmed receipt, failed read rollback, next move, newer pause and rematch isolation'
