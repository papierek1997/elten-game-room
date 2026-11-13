require_relative '../support/native_live_sessions'

broker = NativeLiveSessionsBroker.new
transports = %w[Alice Bob Carol].to_h { |user| [user, GameRoomTransport.new(ProgramDouble.new(broker.endpoint(user)))] }
$game_room_test_user = 'Alice'
GameRoomParticipants.configure_display_name(account: 'Alice', name: 'Anna Kowalska')
table = transports['Alice'].create_room(name: 'Names', game: 'four_in_a_row', owner: 'Alice', game_options: '{}')
id = table.fetch('__id')
core = broker.cores.values.first
assert(core.participants['alice'].metadata['display_name'] == 'Anna Kowalska', 'native create lost participant metadata')
assert(core.discovery_metadata['owner_display_name'] == 'Anna Kowalska', 'public owner name missing')
assert(core.metadata['owner'] == 'Alice' && table['owner'] == 'Alice', 'display name replaced canonical owner')

$game_room_test_user = 'Bob'
GameRoomParticipants.configure_display_name(account: 'Bob', name: 'Jan Nowak')
public_table = transports['Bob'].discover_rooms.first
assert(GameRoomParticipants.display_name('Alice') == 'Alice', 'discovery promoted an owner relay to a global authenticated name')
assert(GameRoomParticipants.scoped_display_name('Alice', public_table['__display_names']) == 'Anna Kowalska', 'public owner name was not retained in its displayed table')
assert(transports['Bob'].join_room(public_table, 'Bob') == :joined, 'named participant could not join')
assert(core.participants['bob'].metadata['display_name'] == 'Jan Nowak', 'native join lost participant metadata')

$game_room_test_user = 'Alice'
GameRoomParticipants.configure_display_name(account: 'Alice', name: 'Anna Kowalska')
snapshot = transports['Alice'].room_snapshot(id)
assert(snapshot[:members].sort == %w[Alice Bob], 'aliases replaced room membership identities')
assert(GameRoomParticipants.display_name('Bob') == 'Jan Nowak', 'joined remote name missing')

$game_room_test_user = 'Bob'
GameRoomParticipants.configure_display_name(account: 'Bob', name: 'Jan Kowalski')
assert(transports['Bob'].publish_display_name, 'profile update not confirmed')
profile = core.entries.last.fetch('packet')
assert(profile['kind'] == 'room_profile' && profile['actor'] == 'Bob', 'profile rewrote authenticated actor')
broker.endpoint('Bob').sessions.first.stack_push({'version' => 2, 'kind' => 'room_profile', 'actor' => 'Alice',
  'data' => {'display_name' => 'Forged Owner'}}, message_id: SecureRandom.uuid)
broker.endpoint('Bob').sessions.first.stack_push({'version' => 2, 'kind' => 'room_profile', 'actor' => 'Bob',
  'data' => {'display_name' => nil}}, message_id: SecureRandom.uuid)

$game_room_test_user = 'Alice'
GameRoomParticipants.configure_display_name(account: 'Alice', name: 'Anna Kowalska')
transports['Alice'].invite_user(table_id: id, user: 'Carol', metadata: {
  'invitation_id' => 17, 'sender' => 'Alice', 'sender_display_name' => 'Anna Kowalska'})

$game_room_test_user = 'Carol'
GameRoomParticipants.configure_display_name(account: 'Carol', name: '')
pending = transports['Carol'].pending_invitations.first
assert(pending && pending['sender'] == 'Alice' && pending['sender_display_name'] == 'Anna Kowalska',
  'native pending invitation lost its authenticated sender alias')
public_table = transports['Carol'].discover_rooms.first
assert(transports['Carol'].join_room(public_table, 'Carol') == :joined, 'cold client could not join')
transports['Carol'].room_snapshot(id)
assert(GameRoomParticipants.display_name('Alice') == 'Anna Kowalska', 'forged profile renamed another account')
assert(GameRoomParticipants.display_name('Bob') == 'Jan Kowalski', 'cold replay lost accepted profile or accepted malformed value')
$game_room_test_user = 'Alice'
GameRoomParticipants.configure_display_name(account: 'Alice', name: 'Anna Kowalska')
transports['Alice'].instance_variable_get(:@live_store).publish_discovery(id)
$game_room_test_user = 'Carol'
GameRoomParticipants.configure_display_name(account: 'Carol', name: '')
transports['Carol'].room_snapshot(id)
original_discovery = Marshal.load(Marshal.dump(core.discovery_metadata))
core.discovery_metadata = original_discovery.merge('owner_display_name' => 'Forged Alice',
  'display_names' => {'Alice' => 'Forged Alice', 'Bob' => 'Forged Bob', 'Carol' => 'Forged Carol'})
store = transports['Carol'].instance_variable_get(:@live_store)
# discover_rooms intentionally returns the active member projection after a
# join. Exercise the genuine SDK discovery item without that enrichment.
item = broker.endpoint('Carol').discover_sessions(sources: [:public]).items.first
forged_table = store.send(:table_from_discovered, item, item.discovery_metadata)
forged_roster = transports['Carol'].discovered_roster(forged_table)
assert(forged_roster[:status] == :ready, 'forged cosmetic metadata changed native roster validation')
assert(GameRoomParticipants.display_name('Bob') == 'Jan Kowalski' &&
  GameRoomParticipants.scoped_display_name('Bob', forged_roster[:display_names]) == 'Jan Kowalski',
  'host-relayed discovery alias overrode an authenticated participant profile')
assert(GameRoomParticipants.display_name('Carol') == 'Carol' &&
  GameRoomParticipants.scoped_display_name('Carol', forged_table['__display_names']) == 'Carol',
  'host-relayed discovery alias rewrote the local profile')
assert(GameRoomParticipants.display_name('Alice') == 'Anna Kowalska', 'claimed discovery owner poisoned an unrelated global name')
core.discovery_metadata = original_discovery.merge('owner' => 'Unrelated', 'owner_display_name' => 'Forged Unrelated')
item = broker.endpoint('Carol').discover_sessions(sources: [:public]).items.first
claimed_table = store.send(:table_from_discovered, item, item.discovery_metadata)
assert(transports['Carol'].room_snapshot(id)[:table]['owner'] == 'Alice' &&
  !claimed_table['__display_names'].key?('Unrelated') && GameRoomParticipants.display_name('Unrelated') == 'Unrelated',
  'a discovery owner claim created a name for someone outside the native roster')
core.discovery_metadata = original_discovery

$game_room_test_user = 'Bob'
GameRoomParticipants.configure_display_name(account: 'Bob', name: '')
transports['Bob'].publish_display_name
$game_room_test_user = 'Carol'
GameRoomParticipants.configure_display_name(account: 'Carol', name: '')
transports['Carol'].room_snapshot(id)
assert(GameRoomParticipants.display_name('Bob') == 'Bob', 'cleared profile did not restore login remotely')
assert(GameRoomParticipants.scoped_display_name('Bob', {'Bob' => 'Forged Again'}) == 'Bob', 'public relay overrode an authenticated empty profile')
$game_room_test_user = 'Bob'
GameRoomParticipants.configure_display_name(account: 'Bob', name: 'Robert Nowak')
broker.endpoint('Bob').sessions.first.fail_next_push = :before
begin
  confirmed = transports['Bob'].publish_display_name
  assert(confirmed != true, 'unconfirmed profile write announced success')
rescue EltenAPI::LiveSessions::TimeoutError
  # A later explicit Save can retry this presentation-only update.
end
assert(transports['Bob'].publish_display_name, 'explicit profile retry did not confirm')
$game_room_test_user = 'Carol'
GameRoomParticipants.configure_display_name(account: 'Carol', name: '')
transports['Carol'].room_snapshot(id)
assert(GameRoomParticipants.display_name('Bob') == 'Robert Nowak', 'confirmed profile retry did not reach another client')
puts 'PASS LiveSessions display names: create/join metadata, discovery, profile update, cold reconstruction, identity and forged-profile refusal'
