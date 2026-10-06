if ARGV.first
  require_relative "../support/binary_rules_load"
  GameRoomTestLocalization.use_language("en")
end
require_relative "../support/elten_array_shuffle"
require_relative "../support/native_room_harness"
require_relative "../support/sequence_random"
require_relative "../support/private_archives"
require_relative "../../lib/account_saved_games"
require_relative "../../games/mille_bornes"
require_relative "../../games/four_in_a_row"

class NativeLiveSessionsBroker::Discovery
  def participants
    @core.participants.values.map { |person| { "id" => person.id, "user" => person.user } }
  end

  def hide_participants?
    false
  end
end

class MilleBornesCapacityRoom < NativeRoomHarness
  attr_reader :options, :lobbies

  def initialize(game:, users:, options: nil, broker: NativeLiveSessionsBroker.new, resume_save_id: nil)
    @broker, @game, @users = broker, game, users
    @options = game.normalize_options(options || game.default_options)
    @transports, @repositories, @lobbies = {}, {}, {}
    users.each { |user| add_client(user) }
    arguments = { name: "Native capacity regression", game: game.id, owner: users.first,
      game_options: JSON.generate(@options), resume_save_id: resume_save_id }
    created = as(users.first) { lobbies.fetch(users.first).create_table(**arguments) }
    assert(created.created?, "The lobby did not create a new room")
    @table = created.table
    users.drop(1).each { |user| assert(join(user), "#{user} could not join the native room") }
  end

  def add_client(user)
    program = ProgramDouble.new(broker.endpoint(user, fresh: true))
    @transports[user] = GameRoomTransport.new(program)
    @repositories[user] = GameRepository.new(program, transport: transports.fetch(user), server_tables: {})
    activities = TableActivityRepository.new(server_tables: {}, transport: transports.fetch(user))
    @lobbies[user] = LobbyRepository.new(program, transport: transports.fetch(user), activity_repository: activities)
    transports.fetch(user).start
  end

  def join(user)
    lobby = lobbies.fetch(user)
    discovered = lobby.open_tables.find { |row| row["__id"] == table["__id"] }
    return false unless discovered

    as(user) { lobby.join_table(discovered, user).entered? }
  end

  def assign_teams(seats)
    updated = game.with_team_assignment(options, players: users, seats: seats)
    as(users.first) do
      assert(transports.fetch(users.first).change_game_options(table: table, options: JSON.generate(updated),
        expected_options: table.fetch("game_options"), expected_session_id: 0), "Team selection was not confirmed")
    end
    @table = transports.fetch(users.first).room_snapshot(table).fetch(:table)
    @options = JSON.parse(table.fetch("game_options"))
  end

  def restore(reader, archive)
    data = reader.restored_data(archive, game: game, table_id: table.fetch("__id"), now: archive.fetch("saved_at") + 86_400)
    @session = as(users.first) do
      repositories.fetch(users.first).restore_session(table: table, game: game.id,
        players: data.fetch(:players), options: archive.fetch("options"), restore: data)
    end
  end

  def publish_discovery
    transports.fetch(users.first).instance_variable_get(:@live_store).publish_discovery(table.fetch("__id"))
  end

  def close
    as(users.first) { lobbies.fetch(users.first).close_table(table) }
  end
end

broker = NativeLiveSessionsBroker.new
endpoint = broker.endpoint("Alice")
[0, 1, 9, 10].each do |capacity|
  error = assert_raises(EltenLink::Error) do
    endpoint.create(metadata: {}, participant_metadata: {}, capacity: capacity,
      visibility: :public, discovery_metadata: {}, stack_entries: 32, stack_entry_bytes: 1024)
  end
  assert_equal("capacity must be between 2 and 8", error.message, "Broker did not reproduce the host capacity error")
  assert_equal({}, broker.cores, "Rejected native creation left a session")
  assert_equal([], endpoint.sessions, "Rejected native creation left a membership")
end
[2, 8].each do |capacity|
  view = endpoint.create(metadata: {}, participant_metadata: {}, capacity: capacity,
    visibility: :public, discovery_metadata: {}, stack_entries: 32, stack_entry_bytes: 1024)
  assert_equal(capacity, broker.cores.fetch(view.id).capacity, "Broker rejected a supported boundary")
  view.close
end
assert_equal(8, GameRoomLiveSessionStore::MAX_CAPACITY, "Native session capacity must match the host limit")
assert_equal(GameRoomLiveSessionStore::MAX_CAPACITY, LobbyRepository::MAX_ROOM_CAPACITY, "Lobby and native capacity disagree")
assert_equal(8, GameRoomTableControl::MAX_SEATS, "Model seats must match native capacity")
assert_equal(8, GameRepository::MAX_PLAYERS, "Repository seats must match native capacity")
puts "PASS faithful broker capacity rejection, both valid boundaries and consistent model/native limits"

users = %w[Alice Bob Carol Dave Eve Frank Grace Heidi]
game = GameRoomGames::MilleBornes.new
options = { "team_count" => 2, "custom_deck" => true, "include_safeties" => true,
  "counterflow" => true, "include_instant_repairs" => true, "instant_repair_cards" => 9,
  "right_of_way_cards" => 3, "25_cards" => 18 }
room = MilleBornesCapacityRoom.new(game: game, users: users, options: options)
owner_transport = room.transports.fetch("Alice")
owner_repository = room.repositories.fetch("Alice")
assert_equal(8, room.core.capacity, "Native capacity must be eight")
assert_equal(users, room.core.participants.values.map(&:user), "All eight users must have native membership")
users.each do |user|
  snapshot = room.transports.fetch(user).room_snapshot(room.table)
  assert_equal(users, snapshot.fetch(:members), "#{user} lost a native participant")
  assert_equal(8, snapshot.fetch(:table).fetch("max_players"), "#{user} lost the declared capacity")
  lobby = room.lobbies.fetch(user)
  assert_equal(8, lobby.capacity_of(snapshot.fetch(:table)), "#{user}'s lobby changed native capacity")
  assert_equal(users, lobby.snapshot_for(room.table).game_participants, "#{user}'s lobby lost the eighth participant")
end
room.add_client("Judy")
assert(!room.join("Judy"), "A ninth native participant entered a full room")
rejected_endpoint = room.broker.endpoint("Mallory", fresh: true)
error = assert_raises(EltenLink::Error) { rejected_endpoint.add_view(room.core) }
assert_equal("full", error.message, "Native membership rejected the ninth participant for the wrong reason")
assert_equal([], rejected_endpoint.sessions, "Native rejection left a membership")
assert_equal(users, room.core.participants.values.map(&:user), "Rejected membership changed the roster")
assert(room.transports.fetch("Judy").current_room("Judy") == nil, "Rejected membership left a current room")
before_sequence = room.core.last_seq
room.as("Alice") do
  failure = assert_raises(ArgumentError) do
    owner_repository.start_session(table: room.table, game: game.id, players: users + %w[Ivan],
      options: JSON.generate(room.options))
  end
  assert_equal("A game supports at most 8 players", failure.message, "Nine-player start failed for the wrong reason")
end
assert_equal(before_sequence, room.core.last_seq, "Rejected start wrote native records")
puts "PASS lobby creation and eight native members, ninth-member rejection and preserved model roster limit"

room.assign_teams([0, 1, 0, 1, 0, 1, 0, 1])
assert_equal(before_sequence + 1, room.core.last_seq, "Team choice must write one atomic record")
room.broker.deliver(duplicate: true)
teams = [%w[Alice Carol Eve Grace], %w[Bob Dave Frank Heidi]]
team_text = "Team 1: Alice, Carol, Eve, Grace. Team 2: Bob, Dave, Frank, Heidi."
users.each do |user|
  transport = room.transports.fetch(user)
  snapshot = transport.room_snapshot(room.table)
  saved = JSON.parse(snapshot.fetch(:table).fetch("game_options"))
  assignment = game.prepared_team_assignment(saved, players: users)
  assert(assignment && assignment.valid?, "#{user} lost the eight-player team assignment")
  assert_equal(teams, 2.times.map { |index| assignment.members_for(index) }, "#{user} changed teams")
  assert(game.table_options_announcement(saved).include?("Teams: Two teams"), "#{user} cannot announce the two-team setting")
  activities = TableActivityRepository.new(server_tables: {}, transport: transport)
  entries = activities.entries_for(room.table).select { |entry| entry.kind == "options_changed" }
  assert_equal(1, entries.length, "#{user} duplicated the confirmed team announcement")
  assert_equal(teams, entries.first.teams, "#{user} truncated the team activity roster")
  assert_equal(team_text, activities.text_for(entries.first, game_name: ->(identifier) { identifier }), "#{user} omitted team members in history")
end
room.publish_discovery
reader = room.transports.fetch("Judy")
discovered = reader.discover_rooms.find { |row| row["__id"] == room.table["__id"] }
assert_equal(8, discovered.fetch("max_players"), "Discovery changed capacity")
assert_equal(8, discovered.fetch("player_count"), "Discovery changed player count")
assert_equal(8, discovered.fetch("__native_participant_count"), "Discovery lost native members")
roster = reader.discovered_roster(discovered)
if room.core.discovery_metadata.key?("roster")
  assert_equal(:ready, roster.fetch(:status), "Published roster could not be read")
  assert_equal(users.sort, roster.fetch(:players).sort, "Read-only discovery lost the eighth player")
  assert_equal([], roster.fetch(:observers), "Discovery invented observers")
else
  roles = room.core.participants.values.map { |person| [person.id, 0] }.sort_by(&:first)
  expanded = room.core.discovery_metadata.merge("roster" => [1, roles, []])
  assert(JSON.generate(expanded).bytesize > GameRoomLiveSessionStore::DISCOVERY_BYTES, "Discovery omitted a roster that fits its budget")
  assert_equal({ status: :unavailable }, roster, "Omitted optional roster must not report an empty room")
end
discovered_options = reader.discovered_options(discovered)
assert_equal(:ready, discovered_options.fetch(:status), "Discovery options were unavailable")
assert_equal(room.options, JSON.parse(discovered_options.fetch(:options)), "Discovery lost custom counts or teams")
assert(reader.current_room("Judy") == nil, "Read-only discovery joined the full room")
puts "PASS two teams of four through confirmed options, all-client history and public discovery"

room.start
session_without_embedded_players = room.session.reject { |key, _value| key == "__players" }
assert_equal(users, owner_repository.players_for(session_without_embedded_players), "Persisted eight-seat JSON cannot be read")
[users + %w[Ivan Judy], users.first(7) + ["alice"]].each do |invalid|
  encoded = JSON.generate("version" => 1, "seats" => invalid.each_with_index.map { |user, index| { "id" => index + 1, "controller" => user } })
  assert_equal([], owner_repository.players_for(session_without_embedded_players.merge("players_json" => encoded)), "Invalid persisted roster was accepted")
end
context = GameRoomGames::ActionContext.new(session_id: room.session.fetch("__id"), table_id: room.table.fetch("__id"),
  random_source: GameRoomRandom::SequenceSource.new(Array.new(16, 17)))
room.submit("Alice", { "kind" => "command", "action" => "deal" }, context: context)
dealt = room.replay("Alice")
assert(dealt.state.fetch(:teams), "Deal disabled team play")
assert_equal([0, 1, 0, 1, 0, 1, 0, 1], dealt.state.fetch(:seats), "Deal changed the teams")
assert_equal(Array.new(8, 6), users.map { |user| dealt.state.fetch(:hands).fetch(user).length }, "Eight players were not fully dealt")
cards = dealt.state.fetch(:hands).values.flatten + dealt.state.fetch(:draw_pile)
assert(!cards.include?(nil) && cards.uniq.length == cards.length, "Dealing introduced missing or duplicate physical cards")
assert_equal(game.deck_counts_for(room.options), cards.map { |card| card.split(":").first }.tally, "Dealing changed custom card counts")
users.first(7).each do |user|
  room.submit(user, { "kind" => "command", "action" => "draw" })
  card = room.replay(user).state.fetch(:hands).fetch(user).first
  room.submit(user, { "kind" => "card", "action" => "discard", "card" => card })
end
room.assert_converged("eight-client custom deal and seven turns", expected_count: 15)
before = room.replay("Alice")
assert_equal("Heidi", before.current_player, "Fixture did not reach the eighth player's turn")
assert_equal(users.first(7), before.accepted_events.drop(1).map { |event| event.fetch("actor") }.uniq,
  "Native replay lost authenticated turn authors")
puts "PASS eight-seat repository serialization, physical custom deal and authenticated turn replay"

resources = PrivateArchiveDouble.new
no_disk = Object.new
def no_disk.read_json(*)
  raise "Unexpected local save read"
end
def no_disk.update_json(*)
  raise "Unexpected local save write"
end
saves = AccountSavedGames.new(no_disk, owner: "Alice", resources: resources)
archive = room.as("Alice") do
  boundary = owner_transport.freeze_game(room.session)
  snapshot = owner_repository.snapshot_for(room.session, force_events: true)
  saves.put(game: game, table: room.table, snapshot: snapshot, repository: owner_repository, now: boundary.created_at)
end
original_event_ids = before.accepted_events.map { |event| owner_repository.event_id(event) }
room.close
assert(room.core.closed, "Original native room must be closed before restoration")
other_installation = AccountSavedGames.new(no_disk, owner: "Alice", resources: resources)
manifest = other_installation.list
assert_equal([archive.fetch("id")], manifest.map { |row| row.fetch("id") }, "Eight-player archive disappeared from the account list")
assert_equal(users, manifest.first.fetch("players"), "Archive manifest truncated the roster")
fetched = other_installation.fetch(manifest.first.fetch("id"))
assert_equal(archive, fetched, "Archive fetch changed the persisted payload")
restored = MilleBornesCapacityRoom.new(game: game, users: users, options: JSON.parse(fetched.fetch("options")),
  broker: room.broker, resume_save_id: fetched.fetch("id"))
restored.restore(other_installation, fetched)
assert(restored.table.fetch("__live_session_id") != room.table.fetch("__live_session_id"), "Restoration reused the old native session")
assert(restored.session.fetch("__id") != room.session.fetch("__id"), "Restoration reused the old game session")
assert_equal(8, restored.core.participants.length, "Restoration did not use eight fresh native memberships")
users.each do |user|
  repository = restored.repositories.fetch(user)
  lobby = restored.lobbies.fetch(user)
  assert_equal(8, lobby.capacity_of(restored.table), "#{user}'s restored lobby changed capacity")
  assert_equal(users, lobby.snapshot_for(restored.table).game_participants, "#{user}'s restored lobby lost a participant")
  session = repository.session_for_table(restored.table)
  assert(session, "#{user} could not resolve the restored eight-player session")
  assert_equal(users, repository.players_for(session), "#{user} lost the restored roster")
  snapshot = repository.snapshot_for(session, force_events: true)
  replay = game.replay(snapshot.session, snapshot.events, repository)
  assert_equal(before.state, replay.state, "#{user} changed restored custom state")
  assert_equal(original_event_ids, replay.accepted_events.map { |event| repository.event_id(event) }, "#{user} changed archived event identities")
  assert_equal(room.options, JSON.parse(session.fetch("options")), "#{user} changed restored options")
end
restored.broker.deliver(duplicate: true)
restored.assert_converged("restored eight-client archive", expected_count: 15)
restored.submit("Heidi", { "kind" => "command", "action" => "draw" })
restored.assert_converged("eighth player's post-restore move", expected_count: 16)
after = restored.replay("Alice")
assert_equal(7, after.state.fetch(:hands).fetch("Heidi").length, "Eighth player's next move did not draw a card")
assert_equal(before.state.fetch(:draw_pile).length - 1, after.state.fetch(:draw_pile).length, "Post-restore draw changed deck size incorrectly")
assert_equal("Heidi", after.accepted_events.last.fetch("actor"), "Eighth player's move lost authentication")
assert_equal([archive.fetch("id")], other_installation.list.map { |row| row.fetch("id") }, "Restoration removed the only archive")
restored.close
puts "PASS eight-player account save/list/fetch, new lobby room, repository restoration and eighth-player next move"

default_room = MilleBornesCapacityRoom.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
assert_equal(8, default_room.core.capacity, "A new table no longer has eight places")
assert_equal(8, default_room.table.fetch("max_players"), "Default room projection changed capacity")
assert_equal(8, default_room.lobbies.fetch("Alice").capacity_of(default_room.table), "Default lobby capacity changed")
assert_equal(8, default_room.lobbies.fetch("Alice").capacity_of({}), "Legacy lobby capacity changed")
store = default_room.transports.fetch("Alice").instance_variable_get(:@live_store)
metadata = default_room.core.metadata.reject { |key, _value| key == "max_players" }
legacy = store.send(:table_from_metadata, metadata, default_room.table.fetch("__id"))
assert_equal(8, legacy.fetch("max_players"), "Missing legacy max_players metadata no longer means eight")
default_room.start
default_room.submit("Alice", { "kind" => "grid", "action" => "select", "x" => 3, "y" => 0 })
default_room.assert_converged("existing two-player Four in a Row", expected_count: 1)
default_room.close
puts "PASS unchanged eight-place capacity/legacy metadata and Four in a Row"

computers = MilleBornesCapacityRoom.new(game: game, users: ["Alice"])
lobby = computers.lobbies.fetch("Alice")
assert_equal(8, lobby.capacity_of(computers.table), "Bot room has the wrong lobby capacity")
known_bots = []
computers.as("Alice") do
  1.upto(7) do |count|
    result = lobby.add_bot(computers.table, snapshot: lobby.snapshot_for(computers.table))
    assert(result.updated?, "Lobby rejected computer #{count}: #{result.status}")
    assert_equal(count, result.snapshot.bots.length, "Lobby lost an added computer")
    assert_equal(known_bots, result.snapshot.bots.first(known_bots.length), "Adding a computer changed existing identities")
    assert_equal(count + 1, result.snapshot.participant_count, "Lobby participant count omitted a computer")
    known_bots = result.snapshot.bots.dup
  end
  before_full = computers.core.last_seq
  rejected = lobby.add_bot(computers.table, snapshot: lobby.snapshot_for(computers.table))
  assert_equal(:full, rejected.status, "Lobby added a computer beyond eight places")
  assert_equal(before_full, computers.core.last_seq, "Rejected computer addition wrote records")
  assert_equal(known_bots, rejected.snapshot.bots, "Rejected addition changed computer identities")
  removed = lobby.remove_bot(computers.table, snapshot: lobby.snapshot_for(computers.table))
  assert(removed.updated?, "Lobby could not remove the last computer")
  assert_equal(known_bots.first(6), removed.snapshot.bots, "Removal changed other computers")
  replaced = lobby.add_bot(computers.table, snapshot: lobby.snapshot_for(computers.table))
  assert(replaced.updated?, "Lobby could not fill the freed final place")
  assert_equal(8, replaced.snapshot.participant_count, "Refilling the room did not reach capacity")
end
computers.start
assert_equal(8, computers.repositories.fetch("Alice").players_for(computers.session).length, "Repository omitted a computer at the lobby limit")
computers.close
puts "PASS lobby bot addition/removal/refill through eight and ninth-place rejection"
