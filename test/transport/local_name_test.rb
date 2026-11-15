require_relative '../support/native_live_sessions'

$game_room_test_user = 'Alice'
names = GameRoomParticipants
revision = names.local_presentation_revision
assert(names.set_local_presentation_name(account: 'Alice', name: '  Local   Person  '), 'Local value was refused')
assert(names.display_name('ALICE') == 'Local Person', 'Local presentation did not change')
assert(names.display_name('Bob_Long_Login') == 'Bob_Long_Login', 'Another account was renamed or shortened')
assert(names.display_name(nil) == '' && names.display_name('') == '' && names.display_name('Unknown') == 'Unknown', 'Missing or unknown participant became the local value')
assert(names.public_display_name('Alice') == 'Alice', 'Local value replaced the public account')
assert(names.local_presentation_revision > revision && names.same?('Alice', 'ALICE') && !names.same?('Alice', 'Local Person'), 'Presentation changed identity or missed invalidation')
assert(!names.set_local_presentation_name(account: 'Bob', name: 'Other Person'), 'A local value changed another account')
revision = names.local_presentation_revision
names.set_local_presentation_name(account: 'Alice', name: 'Local Person')
assert(names.local_presentation_revision == revision, 'Unchanged local value invalidated caches')
begin
  names.set_local_presentation_name(account: 'Alice', name: "Invalid\nValue")
  raise 'Invalid local value was admitted'
rescue ArgumentError
  assert(names.local_presentation_name == 'Local Person', 'Invalid input removed the previous value')
end
assert(names.normalize_local_presentation_name('Ż' * 64) == 'Ż' * 64, 'Unicode input was refused')
assert(names.normalize_local_presentation_name('x' * 65).nil?, 'Oversized input was admitted')
assert(names.normalize_local_presentation_name(' Żaneta Kowalska '.b) == 'Żaneta Kowalska', 'Binary UTF-8 input was refused')
other_runtime = Module.new.extend(GameRoomParticipantNames)
assert(other_runtime.local_presentation_name.empty?, 'Value crossed Runtime namespaces')
bot = names.bot_id(1, 1)
assert(names.display_name(bot) == names.public_display_name(bot), 'Computer name changed')

broker = NativeLiveSessionsBroker.new
transport = GameRoomTransport.new(ProgramDouble.new(broker.endpoint('Alice')))
table = transport.create_room(name: 'Room', game: 'four_in_a_row', owner: 'Alice', game_options: '{}')
core = broker.cores.values.first
assert(core.participants['alice'].metadata == {'table_id'=>table['__id'], 'client'=>'elten_game_room'}, 'Participant metadata changed')
assert(!core.discovery_metadata.key?('owner_display_name') && !core.discovery_metadata.key?('display_names'), 'Discovery gained a profile field')
assert(core.entries.none? { |row| row['packet']['kind'] == 'room_profile' }, 'Room gained a profile record')
assert(table['owner'] == 'Alice', 'Owner identity changed')
count = core.entries.length
names.set_local_presentation_name(account: 'Alice', name: 'Second Person')
assert(core.entries.length == count, 'Local change caused a native write')
transport.invite_user(table_id: table['__id'], user: 'Bob', metadata: {'invitation_id'=>9, 'sender'=>'Alice'})
invitation = broker.endpoint('Bob').next_invitation(timeout: 0)
assert(invitation.inviter.user == 'Alice' && !invitation.invitation_metadata.key?('sender_display_name'), 'Invitation gained a profile or changed identity')
assert(!JSON.generate([core.metadata, core.discovery_metadata, core.entries, invitation.invitation_metadata]).include?('Second Person'), 'Native serialization disclosed a local value')
names.set_local_presentation_name(account: 'Alice', name: '')
assert(names.display_name('Alice') == 'Alice', 'Clearing did not restore the account')
names.set_local_presentation_name(account: 'Alice', name: 'Second Person')
$game_room_test_user = 'Bob'
assert(names.local_presentation_name.empty? && names.display_name('Alice') == 'Alice', 'Local value crossed an account switch')
$game_room_test_user = 'Alice'
assert(names.local_presentation_name.empty?, 'Returning to an account restored a stale value')
puts 'PASS local presentation, unchanged accounts and native metadata/invitation isolation'
