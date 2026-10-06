require_relative "../support/axel_pong_doubles_lobby"

app = PongDoublesLobbyApp.new
row = PongDoublesLobbyTest.create_pong(app)
bob_repository = PongDoublesLobbyTest.join(app, row, 'Bob')
2.times { app.lobby.add_bot(row) }
room = app.lobby.snapshot_for(row, force: true)
players = room.game_participants
session = PongDoublesLobbyTest.with_forms(PongDoublesLobbyTest.start_teams(players, [0, 1, 0, 1])) { app.send(:start_new_game, row) }
assert(session.nil? && app.games.session_for_table(row, force: true).nil?, 'Accept started the game instead of saving teams')
session = PongDoublesLobbyTest.with_forms { app.send(:start_new_game, row) }
assert(session, 'Explicit Start did not create the match after accepting teams')
state = app.send(:load_room_state, row, title: 'test')
old_replay = state.replay
old_options = state.session['options'].dup
old_players = state.players.dup
# The interrupted match remains available as history, not as current roster.
assert(app.transport.abort_game(state.session), 'could not interrupt the native test game')
removed = room.bots.first
result = app.lobby.remove_bot(row, snapshot: room, participant: removed)
assert(result.updated? && result.snapshot.bots.length == 1, 'native removal did not update the actual roster')
state = app.send(:load_room_state, row, title: 'after removal', force: true)
assert(state.waiting?, 'aborted game is not waiting')
rows = app.send(:room_user_rows, state)
assert(rows.map(&:participant) == result.snapshot.participants, 'removed bot was resurrected from previous match')
assert(rows.none? { |item| item.label.include?('team ') }, 'waiting roster retained old teams')
assert(state.players == old_players && state.session['options'] == old_options, 'removal rewrote historical players or teams')
PongDoublesLobbyTest.as_user('Bob') do
  program = ProgramDouble.new(app.broker.endpoint('Bob'))
  transport = bob_repository.instance_variable_get(:@transport)
  lobby = LobbyRepository.new(program, transport: transport, server_tables: {})
  remote_room = lobby.snapshot_for(row, force: true)
  remote_session = bob_repository.session_for_table(row, force: true)
  remote_snapshot = bob_repository.snapshot_for(remote_session, force_events: true)
  remote = GameRoomLifecycle::State.new(room: remote_room, game_snapshot: remote_snapshot, game: state.game,
    replay: state.game.replay(remote_session, remote_snapshot.events, bob_repository), players: bob_repository.players_for(remote_session))
  assert(remote.waiting? && app.send(:room_user_rows, remote).map(&:participant) == remote_room.participants,
    'second reader retained the removed bot or missed interruption')
end
app.lobby.add_bot(row)
fresh = app.lobby.snapshot_for(row, force: true)
game = app.send(:game_definition, 'axel_pong')
assignment = game.team_assignment(game.options_from_json(row['game_options']), players: fresh.game_participants)
assert(assignment.valid? && assignment.players == fresh.game_participants, 'new team assignment reused the removed bot')

# Exercise the shared selector (humans and bots), preserving game seat order.
list = GameRoomScreens::TeamList.new(assignment, index: 1)
list.define_singleton_method(:keyboard_binding_pressed?) { |binding| binding == [:key_down, :shift] }
list.update
assert(list.index == 2 && assignment.players[2] == fresh.game_participants[1], 'cursor does not follow swapped person')
assert(assignment.seats_for(fresh.game_participants) == [0, 0, 1, 1], 'swap changed the game turn order instead of team assignment')
# Accept through the actual selector, then start from the waiting room.
accepted = PongDoublesLobbyTest.with_forms(lambda do |form|
  control = form.fields.first
  control.index = 1
  control.define_singleton_method(:keyboard_binding_pressed?) { |binding| binding == [:key_down, :shift] }
  control.update
  PongDoublesLobbyTest.button(form, 'Accept teams').trigger(:press)
end) { app.send(:change_table_teams, row) }
assert(accepted, 'Team editor did not persist the selected line-up')
assert(app.games.session_for_table(row, force: true)['__id'] == session['__id'], 'Team editor unexpectedly started a match')
next_session = PongDoublesLobbyTest.with_forms { app.send(:start_new_game, row) }
assert(app.games.players_for(next_session) == fresh.game_participants, 'rematch changed participant order')
assert(JSON.parse(next_session['options'])['team_seats'] == [0, 0, 1, 1], 'Start did not persist Shift team selection')
puts 'PASS aborted roster, named bot removal/replacement, historical integrity and shared team movement'
