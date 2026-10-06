def _(text)
  text
end

require_relative "../../lib/room_presentation"
require_relative "../../lib/game_teams"
require_relative "../../lib/lobby_repository"
require_relative "../../lib/game_repository"
require_relative "../../lib/game_lifecycle"

def players_json(*players)
  JSON.generate(
    "version" => 1,
    "seats" => players.each_with_index.map { |player, index| { "id" => index + 1, "controller" => player } }
  )
end

def assert(condition, message)
  raise message if !condition
end

if !defined?(Session)
  module Session
    def self.name
      "Alice"
    end
  end
end

# The lifecycle contract now runs against the native stack, not deleted
# table insert/select adapters. Older saved player-list parsing stays below.
require_relative "../support/native_room_harness"
h = NativeRoomHarness.new(users: %w[Alice Bob], bots: 1)
$game_room_test_user = 'Alice'
table = h.table
repository = h.repositories['Alice']
first_session = h.start
second_session = h.start
sessions = [first_session, second_session]
assert(repository.session_for_table(table)['__id'] == second_session['__id'], 'latest stack start not selected')
assert(repository.latest_session_id_for_table(table) == second_session['__id'], 'latest native session ID lost')
assert(repository.session_by_id(first_session['__id'], table: table)['__id'] == first_session['__id'], 'old session cannot be restored')
# The transport selects lazily in stack order (covered by the native projection
# tests). The repository supplies its compatibility predicate, not an ID sort.
probe = GameRepository.allocate
probe_transport = Object.new
probe_transport.define_singleton_method(:find_game_session) do |*, **, &predicate|
  rows = [second_session.merge('__id' => 2, '__stack_sequence' => 2), first_session.merge('__id' => 999, '__stack_sequence' => 1)]
  rows.find { |row| !predicate || predicate.call(row) }
end
probe.instance_variable_set(:@transport, probe_transport)
assert(probe.session_for_table(table)['__id'] == 2 && probe.latest_session_id_for_table(table) == 2, 'random ID overrode stack order')

room_snapshot = Struct.new(:participants).new(["Alice", "Bob"])
snapshot_struct = Struct.new(:session)
active_replay = Struct.new(:history) do
  def finished?
    false
  end
end.new([Struct.new(:text).new("Current move")])
finished_replay = Struct.new(:history) do
  def finished?
    true
  end
end.new([Struct.new(:text).new("Last move")])
active_lifecycle = GameRoomLifecycle::State.new(
  room: room_snapshot,
  game_snapshot: snapshot_struct.new(sessions.last),
  game: Object.new,
  replay: active_replay,
  players: ["Alice", "Bob"]
)
assert(active_lifecycle.phase == :active, "an active game has an invalid lifecycle phase")
assert(active_lifecycle.role_for("Bob") == :player, "a current player became an observer")
assert(active_lifecycle.role_for("Carol") == :observer, "a late participant became a player in the running game")
assert(!active_lifecycle.startable_by?("Alice", owner: "Alice"), "an active game allowed another start")

finished_lifecycle = GameRoomLifecycle::State.new(
  room: room_snapshot,
  game_snapshot: snapshot_struct.new(sessions.last),
  game: Object.new,
  replay: finished_replay,
  players: ["Alice", "Bob"]
)
assert(finished_lifecycle.phase == :finished, "a finished game has an invalid lifecycle phase")
assert(finished_lifecycle.history.map(&:text) == ["Last move"], "the finished game lost its history while waiting")
assert(finished_lifecycle.startable_by?("Alice", owner: "Alice"), "the table master cannot start the next game")

next_replay = Struct.new(:history) do
  def finished?
    false
  end
end.new([Struct.new(:text).new("New game started")])
next_lifecycle = GameRoomLifecycle::State.new(
  room: room_snapshot,
  game_snapshot: snapshot_struct.new(sessions.last.merge("__id" => 20)),
  game: Object.new,
  replay: next_replay,
  players: ["Alice", "Bob"]
)
assert(
  next_lifecycle.history.map(&:text) == ["New game started"],
  "history from the previous game leaked into the new game"
)

writes = h.view('Alice').calls[:push]
returned = repository.start_session(table: table, game: table['game'], players: h.session['__players'], expected_previous_session_id: first_session['__id'])
assert(returned['__id'] == second_session['__id'] && h.view('Alice').calls[:push] == writes, 'stale start created a competing game')
simultaneous = 2.times.map do
  Thread.new do
    h.as('Alice') do
      repository.start_session(table: table, game: table['game'], players: h.session['__players'], expected_previous_session_id: second_session['__id'])
    end
  end
end.map(&:value)
assert(simultaneous.map { |row| row['__id'] }.uniq.length == 1, 'concurrent starts diverged')
# A native start persists one room checkpoint and one complete game record.
assert(h.view('Alice').calls[:push] == writes + 2, 'concurrent starts wrote more than one checkpoint/start pair')
h.instance_variable_set(:@session, simultaneous.first)
assert(repository.players_for(simultaneous.first) == repository.players_for(second_session), 'atomic start lost frozen seats')

many_players = {
  "__players" => ["Alice", "Bob", "Carol", "Dave"],
  "player_one" => "Alice",
  "player_two" => "Bob"
}
assert(
  repository.players_for(many_players) == ["Alice", "Bob", "Carol", "Dave"],
  "a generic game session was reduced to two players"
)

event_session = {
  "__id" => 23,
  "__insertion_user" => "Alice",
  "table_id" => 7,
  "player_one" => "Alice",
  "player_two" => "Bob",
  "status" => "active",
  "players_json" => players_json("Alice", "Bob", "Carol", "Dave")
}
assert(
  repository.players_for(event_session) == ["Alice", "Bob", "Carol", "Dave"],
  "the atomic persisted player list was not restored"
)
assert(repository.players_for(event_session.merge("players_json" => "")).empty?, "a session without the new player list was accepted")
assert(repository.players_for(event_session.merge("players_json" => "not-json")).empty?, "an invalid player list was accepted")
assert(
  repository.players_for(event_session.merge("players_json" => players_json("Alice", "alice"))).empty?,
  "duplicate players were accepted"
)
invalid_seats = JSON.generate(
  "version" => 1,
  "seats" => [{ "id" => 2, "controller" => "Alice" }, { "id" => 1, "controller" => "Bob" }]
)
assert(repository.players_for(event_session.merge("players_json" => invalid_seats)).empty?, "unordered seats were accepted")

bot = GameRoomParticipants.bot_id(7, 1)
bot_session = {
  "__id" => 24,
  "__insertion_user" => "Alice",
  "table_id" => 7,
  "player_one" => "Alice",
  "__players" => ["Alice", bot]
}
valid_bot_event = { "__insertion_user" => "Alice", "actor" => bot }
forged_bot_event = { "__insertion_user" => "Bob", "actor" => bot }
forged_human_event = { "__insertion_user" => "Alice", "actor" => "Bob" }
assert(repository.actor_of(valid_bot_event, bot_session) == bot, "the table owner's computer move was rejected")
assert(repository.actor_of(forged_bot_event, bot_session).empty?, "another user was allowed to move a computer")
assert(repository.actor_of(forged_human_event, bot_session) == "Alice", "a claimed human actor replaced the server author")
assert(
  repository.next_sequence(
    event_session.merge("__players" => ["Alice", "Bob", "Carol", "Dave"]),
    [{ "sequence" => 1 }, { "sequence" => 2 }]
  ) == 3,
  "game events did not continue after the greatest accepted sequence"
)
assert(
  repository.next_sequence(
    event_session.merge("__players" => ["Alice", "Bob"]),
    [{ "sequence" => 7 }]
  ) == 8,
  "a session did not continue after its greatest accepted sequence"
)

fast_session = h.session
pushes = h.view('Alice').calls[:push]
inserted = repository.append_events(session: fast_session, sequence: 4,
  events: [{ 'action' => 'answer', 'value' => 'Poland' }, { action: 'answer', value: 'Poznan' }])
assert(h.view('Alice').calls[:push] == pushes + 1, 'multi-event move was not one native atomic write')
assert(inserted.length == 2 && inserted.map { |row| row['__id'] }.uniq.length == 2, 'multi-event move lost distinct event IDs')
assert(inserted.map { |row| row['sequence'] } == [4, 5], 'multi-event sequence changed')
assert(inserted.all? { |row| row['session_id'] == fast_session['__id'] }, 'write used wrong game')
native_bot = repository.players_for(fast_session).find { |user| GameRoomParticipants.bot?(user) }
bot_move = repository.append_events(session: fast_session, sequence: 6, events: [{action: 'place', value: '2,2'}], actor: native_bot)
assert(repository.actor_of(bot_move.first, fast_session) == native_bot, 'bot move became coordinator move')
h.broker.deliver
current = repository.snapshot_for(fast_session).events
reads = h.view('Alice').calls[:read]
assert(repository.snapshot_for(fast_session).events == current && h.view('Alice').calls[:read] == reads, 'unchanged native cache reread or lost events')
h.write('Bob', [{action: 'answer', value: 'remote'}], sequence: 7)
h.broker.deliver
h.transports['Alice'].dispatch_pending_events
updated = repository.snapshot_for(fast_session).events
assert(updated.first(current.length) == current && updated.length == current.length + 1, 'remote action lost prefix/order')
revision = repository.events_revision(updated)
assert(repository.event_revision(fast_session, known_revision: revision) == revision, 'unchanged revision changed')
h.assert_converged('lifecycle event cache', expected_count: 4)

# Manage computers on actual native rooms, preserving cache identity, history
# and maximum occupancy. No table-counter repair writes remain in this API.
managed = NativeRoomHarness.new(users: ['Alice'])
activity = TableActivityRepository.new(transport: managed.transports['Alice'], server_tables: {})
lobby = LobbyRepository.new(ProgramDouble.new(managed.broker.endpoint('Alice')), transport: managed.transports['Alice'], activity_repository: activity)
row = managed.table
snapshot = lobby.snapshot_for(row)
writes = managed.view('Alice').calls[:push]
20.times { assert(lobby.snapshot_for(row).members == ['Alice'], 'native snapshot lost members') }
assert(managed.view('Alice').calls[:push] == writes, 'unchanged snapshot wrote counters')
7.times do
  result = lobby.add_bot(row, snapshot: snapshot)
  assert(result.updated? && result.snapshot.equal?(snapshot) && result.activity, 'cached bot update/history lost')
end
assert(snapshot.participants.length == 8 && snapshot.bots.uniq.length == 7, 'bot occupancy incorrect')
assert(activity.entries_for(row, viewer: 'Alice').count { |entry| entry.kind == 'bot_added' } == 7, 'bot history missing/duplicated')
writes = managed.view('Alice').calls[:push]
assert(lobby.add_bot(row, snapshot: snapshot).status == :full && managed.view('Alice').calls[:push] == writes, 'full room accepted a bot')
removed_bot = snapshot.bots.last
assert(lobby.remove_bot(row, snapshot: snapshot).updated?, 'owner could not remove bot')
managed.add_client('Bob')
assert(managed.join('Bob'), 'freed place could not be joined')
managed.broker.deliver
writes = managed.view('Alice').calls[:push]
before = snapshot.bots.dup
assert(lobby.remove_bot(row, snapshot: snapshot, participant: removed_bot).status == :stale, 'a stale selection removed a different bot')
assert(snapshot.bots == before && managed.view('Alice').calls[:push] == writes, 'stale bot update wrote or changed local state')
fresh = lobby.snapshot_for(row)
assert(fresh.members == ['Alice', 'Bob'] && fresh.bots == before, 'human join or stale selection corrupted native occupancy')
lobby.set_game_active(row, true, snapshot: fresh)
assert(fresh.table['status'] == 'playing', 'start did not update room status')
lobby.set_game_active(row, false, snapshot: fresh)
assert(fresh.table['status'] == 'waiting', 'end did not restore waiting status')
6.times { assert(lobby.remove_bot(row, snapshot: fresh).updated?, 'bot removal failed') }
assert(lobby.remove_bot(row, snapshot: fresh).status == :none, 'absent bot removal changed room')
assert(lobby.capacity_of({'max_players' => 2}) == 8 && lobby.capacity_of({'max_players' => 12}) == 8, 'lobby capacity exceeded the eight-seat service limit')

active_labels = RoomPresentation.user_labels(
  ["Alice", "Bob", "Carol"],
  bots: ["bot:7:1"],
  owner: "alice",
  players: ["Alice", "Bob", "bot:7:1"],
  active: true,
  team_assignment: GameRoomTeams::Assignment.new(
    players: ["Alice", "Bob", "bot:7:1", "Dave"],
    team_size: 2,
    seats: [0, 1, 0, 1]
  )
)
assert(active_labels[0].include?("table master") && active_labels[0].include?("player") && active_labels[0].include?("team 1"), "the table master role is incomplete")
assert(active_labels[1].include?("player"), "the second player role is missing")
assert(active_labels[2].include?("observer"), "an observer was presented as a player")
assert(active_labels[3].include?("Computer 1") && active_labels[3].include?("computer") && active_labels[3].include?("player") && active_labels[3].include?("team 1"), "a computer has invalid room roles")

waiting_labels = RoomPresentation.user_labels(
  ["Alice", "Carol"],
  owner: "Alice",
  players: ["Alice", "Bob"],
  active: false
)
assert(waiting_labels.all? { |label| label.include?("waiting for a game") }, "finished-game users are not waiting")

puts "Room lifecycle tests passed"
