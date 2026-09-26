require_relative 'support/native_room_harness'

$room_presence_identity_cases = 0

def presence_case(name)
  yield
  $room_presence_identity_cases += 1
  puts "PASS room presence identity: #{name}"
end

presence_case('identity API creates unrelated UUIDs and strictly validates strings') do
  assert(defined?(GameRoomPresence::Identity), 'The room presence identity API is missing')
  identity = GameRoomPresence::Identity
  ids = Array.new(20) { identity.create }
  assert(ids.uniq == ids, 'New room identities were reused')
  assert(ids.all? { |id| /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.match?(id) }, 'Creation did not use random version-4 UUIDs')
  assert(ids.all? { |id| identity.valid?(id) == true }, 'Created identities failed validation')
  canonical = '12345678-abcd-4abc-8abc-123456789abc'
  assert(identity.valid?(canonical) == true, 'A canonical UUID was rejected')
  invalid = [nil, false, true, 123, [], {}, canonical.to_sym, canonical.upcase,
    " #{canonical}", "#{canonical}\n", "#{canonical}\x00", canonical.delete('-'),
    canonical.tr('a', 'g'), "native:#{canonical}", "\xff".b, "\xff".force_encoding('UTF-8'),
    canonical.encode('UTF-16LE'), {'id' => canonical}]
  invalid.each { |value| assert(identity.valid?(value) == false, "Invalid room identity accepted: #{value.inspect}") }
end

presence_case('public and private rooms keep distinct tokens only in authoritative metadata') do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  owner = h.transports.fetch('Alice')
  private_room = h.as('Alice') do
    owner.create_room(name: h.table['name'], game: 'test', owner: 'Alice', game_options: '{}', private_table: true)
  end
  cores = [h.core, h.broker.cores.fetch(private_room['__live_session_id'])]
  ids = cores.map { |core| core.metadata['statistics_room_id'] }
  assert(ids.all? { |id| GameRoomPresence::Identity.valid?(id) }, 'A public or private room has no authoritative anonymous token')
  assert(ids.uniq == ids, 'Distinct rooms reused a room identity')
  cores.each do |core|
    id = core.metadata.fetch('statistics_room_id')
    native_ids = [core.id, core.metadata['table_id'].to_s, core.metadata['owner'], core.metadata['created_at'].to_s]
    native_ids.concat(core.participants.values.map(&:id))
    assert(!native_ids.include?(id), 'A room identity reused native or personal metadata')
    assert(!core.discovery_metadata.key?('statistics_room_id'), 'Creation published a private room identity in discovery')
    assert(!JSON.generate(core.discovery_metadata).include?(id), 'Discovery exposed the token under another key')
    assert(JSON.generate(core.discovery_metadata).bytesize <= GameRoomLiveSessionStore::DISCOVERY_BYTES, 'Room identity exhausted the discovery budget')
  end
  h.as('Alice') do
    [h.table, private_room].each { |table| owner.update_room(table, {'status' => 'waiting'}, actor: 'Alice') }
  end
  cores.each do |core|
    assert(!core.discovery_metadata.key?('statistics_room_id'), 'Discovery rebuild published a private room identity')
  end
  h.add_client('Visitor')
  public_rooms = h.transports['Visitor'].discover_rooms
  assert(public_rooms.map { |room| room['__id'] } == [h.table['__id']], 'Private-room discovery visibility changed')
  assert(public_rooms.none? { |room| room.key?('__statistics_room_id') }, 'An unjoined reader learned a room identity')
end

presence_case('joined readers project a detached identity without changing participants or observer roles') do
  h = NativeRoomHarness.new(users: %w[Alice Bob Carol], bots: 1)
  owner = h.transports.fetch('Alice')
  h.as('Carol') { h.transports['Carol'].set_observer(h.table, true, actor: 'Carol') }
  id = h.core.metadata.fetch('statistics_room_id')
  assert(h.table['__statistics_room_id'] == id, 'Room creation did not project its presence identity')
  h.users.each do |user|
    snapshot = h.as(user) { h.transports[user].room_snapshot(h.table) }
    projected = snapshot[:table]['__statistics_room_id']
    assert(projected == id, 'Joined readers disagree about the room presence identity')
    assert(projected.frozen? && !projected.equal?(id), 'Projected room identity shares mutable native metadata')
    assert(snapshot[:members].sort == h.users.sort, 'Room presence lost a connected human or observer')
    assert(snapshot[:observers] == ['Carol'] && snapshot[:bots].length == 1, 'Room presence changed observer or bot roles')
    assert(snapshot[:table]['player_count'] == 3, 'Room presence changed the existing gameplay player count')
    discovered = h.transports[user].discover_rooms.find { |room| room['__id'] == h.table['__id'] }
    assert(discovered['__statistics_room_id'] == id, 'Discovery fallback lost a joined room identity')
  end
  private_room = h.as('Alice') do
    owner.create_room(name: 'Private', game: 'test', owner: 'Alice', game_options: '{}', private_table: true)
  end
  native = h.broker.cores.fetch(private_room['__live_session_id'])
  assert(private_room['__statistics_room_id'] == native.metadata['statistics_room_id'], 'A private room failed identity projection')
  assert(owner.room_snapshot(private_room)[:table]['__statistics_room_id'] == private_room['__statistics_room_id'], 'Private room reread regenerated its identity')
end

require_relative '../games/four_in_a_row'

presence_case('rematches, owner handover and discovery rebuilds preserve identity and native authority') do
  h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
  id = h.table.fetch('__statistics_room_id')
  first = h.start
  h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '3')])
  h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '4')])
  h.assert_converged('room identity gameplay', expected_count: 2)
  assert(h.replay('Alice').accepted_events.length == 2, 'Room identity changed valid gameplay')
  second = h.start
  assert(first['__statistics']['id'] != second['__statistics']['id'], 'Room presence changed the per-match identity contract')
  assert([first, second].none? { |game| game['__statistics']['id'] == id }, 'Room and match identity were coupled')
  assert(h.core.entries.none? { |entry| entry.dig('packet', 'kind') == 'room_created' }, 'Rematch fixture did not trim the original room record')
  h.as('Alice') { h.transports['Alice'].transfer_room_owner(h.table, 'Bob') }
  room = h.as('Bob') { h.transports['Bob'].room_snapshot(h.table)[:table] }
  assert(room['owner'] == 'Bob' && h.core.metadata['owner'] == 'Alice', 'Native owner/founder authority changed')
  assert(room['__statistics_room_id'] == id && h.core.metadata['statistics_room_id'] == id, 'Handover regenerated or discarded the room token')
  anchor = h.core.discovery_metadata[GameRoomTableControl::ANCHOR_KEY]
  assert(anchor && h.repositories['Bob'].session_for_table(room)['__control_ready'], 'Handover lost the owner control anchor')
  begin
    h.as('Alice') { h.transports['Alice'].transfer_room_owner(h.table, 'Alice') }
    raise 'Room presence let the former owner transfer native authority'
  rescue ArgumentError => error
    assert(error.message.include?('Only the table master'), 'Unexpected owner-transfer rejection')
  end
  options = JSON.generate({'custom' => 'unchanged options ' * 100})
  h.as('Bob') do
    h.transports['Bob'].update_room(room, {'game_options' => options, 'statistics_room_id' => SecureRandom.uuid}, actor: 'Bob')
  end
  discovery = h.core.discovery_metadata
  assert(discovery[GameRoomTableControl::ANCHOR_KEY] == anchor, 'Discovery rebuild removed the control anchor')
  assert(discovery.key?('options_z') && JSON.generate(discovery).bytesize <= GameRoomLiveSessionStore::DISCOVERY_BYTES, 'Discovery no longer honors its compressed byte budget')
  assert(!discovery.key?('statistics_room_id') && !JSON.generate(discovery).include?(id), 'Discovery rebuild leaked the stable token')
  h.add_client('Carol')
  assert(h.join('Carol'), 'A late reader could not join after owner handover')
  late = h.as('Carol') { h.transports['Carol'].room_snapshot(h.table)[:table] }
  assert(late['__statistics_room_id'] == id && late['game_options'] == options && late['owner'] == 'Bob', 'Late reader lost the room identity, options or owner')
  third = h.as('Bob') do
    h.repositories['Bob'].start_session(table: room, game: h.game.id, players: h.users,
      options: JSON.generate(h.game.default_options), expected_previous_session_id: second['__id'])
  end
  assert(third['__id'] != second['__id'] && third['__control_ready'], 'The new owner could not start a rematch')
  assert(h.core.metadata['statistics_room_id'] == id, 'New-owner rematch replaced the room identity')
  assert(h.transports['Bob'].room_snapshot(room)[:table]['__statistics_room_id'] == id, 'Rematch projection lost the stable token')
end

presence_case('missing or malformed metadata remains untracked without changing legacy gameplay') do
  canonical = '12345678-abcd-4abc-8abc-123456789abc'
  missing = Object.new
  malformed = [missing, nil, '', 'Alice', 123, {}, [], canonical.upcase, "#{canonical}\n", canonical.delete('-'), "\xff".b]
  malformed.each do |value|
    h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
    if value.equal?(missing)
      h.core.metadata.delete('statistics_room_id')
    else
      h.core.metadata['statistics_room_id'] = value
    end
    original = h.core.metadata.dup
    h.core.discovery_metadata['statistics_room_id'] = canonical
    h.core.entries.first['packet']['data']['__statistics_room_id'] = canonical
    untracked = h.as('Alice') { h.transports['Alice'].room_snapshot(h.table)[:table] }
    assert(!untracked.key?('__statistics_room_id'), 'A stale row or room record replaced missing/malformed authoritative metadata')
    h.start
    h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '3')])
    h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '4')])
    h.users.each do |user|
      snapshot = h.as(user) { h.transports[user].room_snapshot(h.table) }
      assert(!snapshot[:table].key?('__statistics_room_id'), "An untracked room invented/projected an identity: #{value.inspect}")
      assert(snapshot[:table]['owner'] == 'Alice', 'Malformed room metadata changed native authority')
      assert(h.replay(user).accepted_events.length == 2, 'Malformed room identity invalidated otherwise valid gameplay')
      room = h.transports[user].discover_rooms.find { |item| item['__id'] == h.table['__id'] }
      assert(!room.key?('__statistics_room_id'), 'Discovery metadata was used as the identity source')
    end
    h.as('Alice') { h.transports['Alice'].transfer_room_owner(h.table, 'Bob') }
    h.as('Bob') { h.transports['Bob'].room_snapshot(h.table) }
    assert(h.core.metadata == original, 'Legacy/malformed metadata was repaired or backfilled during gameplay')
    assert(!h.core.discovery_metadata.key?('statistics_room_id'), 'Malformed metadata leaked through a discovery update')
    assert(h.repositories['Bob'].session_for_table(h.table)['__control_ready'], 'An untracked room could not hand over native authority')
  end
end

require_relative '../lib/account_saved_games'
require_relative 'support/private_archives'

presence_case('restoring an account save starts a new room identity while preserving match identity and replay') do
  h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
  old_room_id = h.table.fetch('__statistics_room_id')
  h.start
  h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '3')])
  h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '4')])
  owner = h.transports['Alice']
  boundary = owner.freeze_game(h.session)
  snapshot = h.repositories['Alice'].snapshot_for(h.session, force_events: true)
  before = h.game.replay(snapshot.session, snapshot.events, h.repositories['Alice'])
  resources = PrivateArchiveDouble.new
  no_disk = Object.new
  def no_disk.read_json(*); raise 'Unexpected local save read'; end
  def no_disk.update_json(*); raise 'Unexpected local save write'; end
  saves = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources)
  saved = saves.put(game: h.game, table: h.table, snapshot: snapshot, repository: h.repositories['Alice'], now: boundary.created_at)
  archive = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources).fetch(saved['id'])
  assert(!JSON.generate(archive).include?(old_room_id), 'Saved game persisted the old room presence identity')
  owner.deactivate_table(table_id: h.table['__id'])
  ids = [old_room_id]
  2.times do
    table = h.as('Alice') do
      owner.create_room(name: 'Restored room', game: h.game.id, owner: 'Alice', game_options: archive['options'], resume_save_id: archive['id'])
    end
    id = table.fetch('__statistics_room_id')
    assert(!ids.include?(id), 'A new room reused the old or previously restored room identity')
    ids << id
    remote = GameRoomTransport.new(ProgramDouble.new(h.broker.endpoint('Bob', fresh: true)))
    discovered = remote.discover_rooms.find { |row| row['__id'] == table['__id'] }
    assert(remote.establish_membership(table_id: table['__id'], owner: 'Alice', capacity: 8, user: 'Bob', table: discovered), 'Reader could not join the restored room')
    restore = saves.restored_data(archive, game: h.game, table_id: table['__id'])
    restored = h.as('Alice') do
      h.repositories['Alice'].restore_session(table: table, game: h.game.id, players: restore[:players], options: archive['options'], restore: restore)
    end
    assert(restored['__statistics'] == snapshot.session['__statistics'], 'New room identity replaced the restored match identity')
    current = h.repositories['Alice'].snapshot_for(restored, force_events: true)
    after = h.game.replay(current.session, current.events, h.repositories['Alice'])
    assert(after.board == before.board && after.accepted_events.length == 2, 'Room identity changed restored gameplay')
    native = h.broker.cores.fetch(table['__live_session_id'])
    assert(native.metadata['statistics_room_id'] == id, 'Restore overwrote authoritative room metadata')
    assert(remote.room_snapshot(table)[:table]['__statistics_room_id'] == id, 'Restore reader did not get the new room identity')
    assert(!native.discovery_metadata.key?('statistics_room_id'), 'Restoring exposed the room token in discovery')
    owner.deactivate_table(table_id: table['__id'])
  end
end

puts "Room presence identity tests passed: #{$room_presence_identity_cases} cases"
