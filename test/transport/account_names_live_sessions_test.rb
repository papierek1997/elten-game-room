require_relative '../support/native_room_harness'
require_relative '../../games/four_in_a_row'

harness = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
core = harness.core
harness.as('Alice') { harness.transports.fetch('Alice').instance_variable_get(:@live_store).publish_discovery(harness.table.fetch('__id')) }
core.participants.each_value do |participant|
  assert(participant.metadata.keys.sort == %w[client table_id], 'A new participant still publishes a display name')
end
assert(!core.discovery_metadata.key?('owner_display_name') && !core.discovery_metadata.key?('display_names'),
  'A new table still publishes aliases')
assert(core.entries.none? { |entry| entry.fetch('packet')['kind'] == 'room_profile' }, 'Table creation still writes profiles')

# A cold reader of an old table must ignore every old source of human aliases.
core.participants['alice'].metadata['display_name'] = 'Old Alice'
core.participants['bob'].metadata['display_name'] = 'Old Bob'
core.discovery_metadata = core.discovery_metadata.merge('owner_display_name'=>'Old Alice',
  'display_names'=>{'Alice'=>'Old Alice', 'Bob'=>'Old Bob'})
harness.as('Bob') do
  harness.view('Bob').stack_push({'version'=>2, 'kind'=>'room_profile', 'actor'=>'Bob',
    'data'=>{'display_name'=>'New Bob'}}, message_id: SecureRandom.uuid)
  harness.view('Bob').stack_push({'version'=>2, 'kind'=>'room_profile', 'actor'=>'Alice',
    'data'=>{'display_name'=>'Forged Alice'}}, message_id: SecureRandom.uuid)
end
harness.add_client('Carol')
transport = harness.transports.fetch('Carol')
table = transport.discover_rooms.first
assert(table && !table.key?('__display_names'), 'Discovery retained an obsolete alias directory')
roster = transport.discovered_roster(table)
assert(roster[:status] == :ready && roster[:players].sort == %w[Alice Bob], 'Old names changed the native roster')
assert(!roster.key?(:display_names), 'The public roster still exposes aliases')
assert(harness.join('Carol'), 'Old profile records blocked a cold join')

harness.as('Alice') do
  harness.transports.fetch('Alice').invite_user(table_id: harness.table.fetch('__id'), user: 'Dave', metadata: {
    'invitation_id'=>17, 'sender'=>'Alice', 'sender_display_name'=>'Old Alice'})
end
harness.add_client('Dave')
pending = harness.as('Dave') { harness.transports.fetch('Dave').pending_invitations.first }
assert(pending && pending['sender'] == 'Alice' && !pending.key?('sender_display_name'),
  'An old invitation replaced its authenticated sender or retained its alias')

# Ignoring obsolete profile records must not skip later genuine gameplay.
harness.start
harness.submit('Alice', {'kind'=>'grid', 'action'=>'select', 'x'=>0, 'y'=>0})
%w[Alice Bob Carol].each do |user|
  snapshot = harness.transports.fetch(user).room_snapshot(harness.table)
  assert(snapshot[:members].sort == %w[Alice Bob Carol], 'Aliases replaced canonical membership')
  assert(GameRoomParticipants.display_name('Alice') == 'Alice' && GameRoomParticipants.display_name('Bob') == 'Bob',
    'An old self-authored or forged profile was used for presentation')
  replay = harness.replay(user)
  assert(replay.board.flatten.compact == [0] && replay.current_player == 'Bob' && replay.accepted_events.size == 1,
    'A profile record blocked subsequent accepted game actions')
end
puts 'PASS old participant/discovery/profile/invitation aliases ignored; new memberships publish only account identity and later gameplay survives'
