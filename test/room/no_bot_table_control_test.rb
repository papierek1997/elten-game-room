require_relative "../support/no_bot_table_control"

no_bots = EltenGameRoom::GAME_REGISTRY.ids.select { |id| !EltenGameRoom::GAME_REGISTRY.build(id).supports_bots? }
assert(no_bots.sort == %w[categories krowa mania_pisania scrabble taboo], "Uncovered no-bot game: #{no_bots.inspect}")

%w[scrabble taboo].each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  names = %w[Alice Bob Carol Dave].first(game.minimum_players)
  h = NativeRoomHarness.new(game: game, users: names)
  h.start
  h.add_client('Watcher'); h.join('Watcher')
  owner = h.transports['Alice']
  h.as('Alice') { owner.set_observer(h.table, true, actor: 'Alice', subject: 'Watcher') }
  runners = names.to_h { |name| [name, runner_for(h, name)] }
  names.each { |name| step(h, runners[name], name, count: 2) }
  assert(h.replay('Alice').accepted_events.any?, "#{id}: initial deal did not happen")
  old_events = h.events('Alice')
  old_state = h.replay('Alice')
  h.as('Alice') { owner.replace_game_player(h.table, session_id: h.session['__id'], player: 'Bob', replacement: 'Watcher') }
  names.each { |name| step(h, runners[name], name, count: 2) }
  assert(h.replay('Alice').players == names.map { |n| n == 'Bob' ? 'Watcher' : n }, "#{id}: actual model lost place")
  assert(h.replay('Alice').history.first(old_state.history.size).map(&:text) == old_state.history.map(&:text), "#{id}: rewrote history")
  assert(h.events('Alice') == old_events, "#{id}: replacement wrote a game move")
  if id == 'scrabble'
    assert(h.replay('Alice').state[:racks]['Watcher'] == old_state.state[:racks]['Bob'], 'Scrabble lost inherited tiles')
  else
    assert(h.replay('Alice').state[:teams].flatten.include?('Watcher'), 'Taboo kept old team member')
  end
  # Move ownership to a spectator, then leave a playing human's place empty.
  h.as('Alice') { owner.transfer_room_owner(h.table, 'Bob') }
  h.as('Watcher') { h.transports['Watcher'].deactivate_table(table_id: h.table['__id']) }
  names.each { |name| step(h, runners[name], name, count: 4) }
  snapshot = h.transports['Bob'].room_snapshot(h.table)
  assert(snapshot[:bots].empty? && h.replay('Bob').players.include?('Watcher'), "#{id}: unsupported automatic bot or lost seat")
  assert(h.events('Bob') == old_events, "#{id}: played on behalf of missing human")
  room = LobbyRepository::TableSnapshot.new(**snapshot)
  rows = RoomPresentation.game_users(room: room, game: game, replay: h.replay('Bob'), players: h.replay('Bob').players,
    owner: 'Bob', options: game.default_options)
  assert(rows.find { |row| row.participant == 'Watcher' }&.label&.include?('disconnected'), "#{id}: no manageable absent-player row")
  assert(GameRoomParticipantMenu.replacement_candidates(room: room, players: h.replay('Bob').players, participant: 'Watcher', game: game) == ['Bob'], "#{id}: absent seat has wrong candidates")
  h.join('Watcher')
  step(h, runners['Bob'], 'Bob', count: 2)
  assert(h.replay('Bob').players.include?('Watcher') && h.transports['Bob'].room_snapshot(h.table)[:bots].empty?, "#{id}: unfilled seat cannot return")
  h.as('Bob') { h.transports['Bob'].replace_game_player(h.table, session_id: h.session['__id'], player: 'Watcher', replacement: 'Bob') }
  names.each { |name| step(h, runners[name], name, count: 2) }
  assert(h.replay('Bob').players == names, "#{id}: restored original human list differs")
  h.assert_converged("#{id}: owner/observer, exit/return, replacements", expected_count: old_events.size)
  # Test the next real actions, not only a projected participant list.
  if id == 'scrabble'
    actor = h.replay('Bob').current_player
    no_bot_command(h, actor, actor, {'kind' => 'command', 'action' => 'pass'})
    assert(h.replay('Bob').state[:idle_turns] == 1, 'Scrabble cannot continue after replacement')
  else
    replay = h.replay('Bob')
    giver = replay.current_player
    no_bot_command(h, giver, giver, {'action' => 'start', 'token' => game.token(replay.state)})
    replay = h.replay('Bob')
    no_bot_command(h, 'Bob', names.first, {'action' => 'begin', 'token' => game.token(replay.state)},
      now: replay.state[:deadline], moderator: true)
    replay = h.replay('Bob')
    no_bot_command(h, giver, giver, {'action' => 'correct', 'token' => game.token(replay.state)}, now: replay.state[:time])
    replay = h.replay('Bob')
    no_bot_command(h, 'Bob', names.first, {'action' => 'timeout', 'token' => game.token(replay.state)},
      now: replay.state[:deadline], moderator: true)
    replay = h.replay('Bob')
    no_bot_command(h, 'Bob', names.first, {'action' => 'approve', 'token' => game.token(replay.state)},
      now: replay.state[:time], moderator: true)
    assert(h.replay('Bob').state[:completed] == 1 && h.replay('Bob').state[:scores].sum == 1,
      'Taboo new moderator cannot finish and score a real turn')
  end
  h.assert_converged("#{id}: continued play after replacements and ownership change")
  # Normal room closure and last-person closure still work without bot support.
  h.as('Bob') do
    lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint('Bob')), transport: h.transports['Bob'], server_tables: Object.new)
    lobby.leave_table(h.table, 'Bob')
  end
  names.reject { |n| n == 'Bob' }.each { |n| step(h, runners[n], n) }
  assert(!h.core.closed, "#{id}: departing master destroyed shared table")
  runners.each_value(&:close)
  puts "#{id}: native no-bot lifecycle and real replay/runner OK"
end

# Secret answer protocols cannot silently transfer unrevealed data. The
# common UI must reject the operation before any write, including no-bot games.
%w[categories krowa].each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  phases = id == 'categories' ? %i[answering revealing] : %i[setup active revealing]
  phases.each do |phase|
    replay = Struct.new(:state) { def finished?; false; end }.new({phase: phase})
    assert(game.controller_change_error(replay), "#{id}/#{phase}: private phase accepts takeover")
    assert(game.controller_change_error(replay, replacement: true), "#{id}: invented a bot")
  end
  assert(game.controller_change_error(nil) == nil, "#{id}: waiting table cannot change master")
  puts "#{id}: no bot and explicit private-phase restriction OK"
end

# Check the actual application guard, not only the game policy method. No
# transfer, replacement or voluntary host exit may discard private answers.
%w[categories krowa].each do |id|
  variants = id == 'krowa' ? %w[daily random race tower] : [nil]
  variants.each do |variant|
    game = EltenGameRoom::GAME_REGISTRY.build(id)
    if variant == 'daily'
      assert(game.table_join_error({'variant' => variant}, viewer: 'Bob', owner: 'Alice'), 'Daily Krowa allowed another participant')
      assert(!game.table_invitations_allowed?({'variant' => variant}), 'Daily Krowa allowed invitations')
      next # There cannot be a second live participant to inherit this table.
    end
    broker = NativeLiveSessionsBroker.new
    $game_room_test_user = 'Alice'
    app = LifecycleApp.new(broker)
    table = app.lobby.create_table(name: 'Private phase', game: id, owner: 'Alice', game_options: '{}').table
    other = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Bob')))
    other.join_room(table, 'Bob')
    room = app.lobby.snapshot_for(table)
    phases = id == 'categories' ? %i[answering revealing] : %i[setup active revealing]
    phases.each do |phase|
      replay = Struct.new(:state) { def finished?; false; end }.new({phase: phase, options: {'variant' => variant}})
      state = Struct.new(:game, :replay, :room, :session) { def active?; true; end }.new(game, replay, room, {'__id' => 'private-fixture'})
      app.define_singleton_method(:load_room_state) { |*_args, **_kwargs| state }
      before = broker.cores.values.first.last_seq
      [:transfer_master, :replace_player].each do |action|
        assert(!app.send(:change_table_control, table, action, 'Bob', replacement: :new_bot), "#{id}/#{variant}: private UI transfer")
      end
      assert(!app.send(:leave_table_from_screen, table), "#{id}/#{variant}: host abandoned private data without notice")
      assert(app.notices.last == 'The current game contains private data that cannot be transferred at this stage.', 'Missing private-phase explanation')
      assert(broker.cores.values.first.last_seq == before && !broker.cores.values.first.closed,
        "#{id}/#{variant}: rejected private operation changed the server")
    end
  end
end
puts 'All four games without bots covered; occupied-place exchange cannot bypass no-bot/private-phase policy: OK'
