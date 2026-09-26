require_relative 'support/native_room_harness'

$statistics_identity_cases = 0

def statistics_case(name)
  yield
  $statistics_identity_cases += 1
  puts "PASS statistics identity: #{name}"
end

def statistics_start_entry(harness)
  harness.core.entries.reverse.find { |entry| entry.dig('packet', 'kind') == 'game_started' }
end

statistics_case('fresh match and same-room rematch have independent, immutable identities') do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  push = h.view('Alice').method(:stack_push)
  h.view('Alice').define_singleton_method(:stack_push) do |packet, message_id:|
    if packet['kind'] == 'game_started'
      packet = packet.merge('data' => packet['data'].merge('created_at' => 1))
    end
    push.call(packet, message_id: message_id)
  end
  first = h.start
  entry = statistics_start_entry(h)
  metadata = first['__statistics']
  assert(metadata.is_a?(Hash), 'A fresh match did not expose statistics metadata')
  wire = entry.dig('packet', 'data', 'statistics')
  assert(wire.keys.sort == %w[id mode], 'A fresh packet exposed more than its anonymous identity and mode')
  assert(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.match?(metadata['id']), 'Match identity is not a random UUID')
  assert(metadata['mode'] == 'humans', 'Two human seats were misclassified')
  assert(metadata['started_at'] == entry['created_at'] && metadata['started_at'] != 1, 'Start time came from the sender instead of the canonical record')
  native_ids = [h.table['__id'].to_s, first['__id'].to_s, h.core.id, entry['message_id']]
  native_ids.concat(h.core.participants.values.map(&:id))
  assert(!native_ids.include?(metadata['id']), 'Statistics reused a room, game, message or participant identity')
  assert(metadata.frozen? && metadata.values.all?(&:frozen?), 'Exposed statistics are mutable')
  remote = h.repositories.fetch('Bob').session_for_table(h.table)['__statistics']
  assert(remote == metadata && !remote.equal?(metadata) && !remote['id'].equal?(metadata['id']), 'Readers share or disagree about match metadata')
  assert(!wire.equal?(metadata) && !wire['id'].equal?(metadata['id']), 'Projection shares mutable packet data')
  again = h.repositories.fetch('Alice').session_for_table(h.table)['__statistics']
  assert(again == metadata && !again.equal?(metadata), 'Rereading regenerated or shared the identity')
  second = h.start
  assert(second['table_id'] == first['table_id'] && h.core.id == native_ids[2], 'Rematch changed the room')
  assert(second['__statistics']['id'] != metadata['id'], 'Same-room rematch reused the previous match identity')
  assert(second['__statistics']['mode'] == 'humans', 'Rematch changed the initial participation mode')
  h.add_client('Carol')
  assert(h.join('Carol'), 'Late reader could not join the retained room')
  assert(h.repositories.fetch('Carol').session_for_table(h.table)['__statistics'] == second['__statistics'], 'Late reader lost metadata after stack cleanup')
end

statistics_case('mode is fixed by the starting seats, including controlled bots and solo play') do
  bots = NativeRoomHarness.new(users: ['Alice'], bots: 1)
  assert(bots.start.dig('__statistics', 'mode') == 'bots', 'Starting with a bot was classified as human play')
  solo = NativeRoomHarness.new(users: ['Alice'])
  assert(solo.start.dig('__statistics', 'mode') == 'solo', 'One starting seat was not classified as solo')
  humans = NativeRoomHarness.new(users: %w[Alice Bob])
  original = humans.start['__statistics']
  humans.as('Alice') do
    humans.transports['Alice'].replace_game_player(humans.table, session_id: humans.session['__id'], player: 'Bob')
  end
  after = humans.repositories['Alice'].session_for_table(humans.table)
  assert(after['__players'].any? { |player| GameRoomParticipants.bot?(player) }, 'Replacement fixture did not install a bot')
  assert(after['__statistics'] == original, 'Replacing a human changed original match metadata')
  identity = GameRoomStatistics::Identity
  controlled = identity.create(players: %w[Alice Bob], controllers: {'Bob' => 'bot'})
  assert(controlled['mode'] == 'bots', 'Bot-controlled human seat was not classified as bots')
  assert(identity.create(players: ['Alice'], controllers: {'Alice' => 'bot'})['mode'] == 'bots', 'Solo mode overrode bot control')
  assert(identity.create(players: ['Alice'], controllers: {'Observer' => 'bot'})['mode'] == 'solo', 'A non-playing controller affected match mode')
  assert(identity.create(players: %w[Alice Bob], controllers: {'Bob' => 'human'})['mode'] == 'humans', 'Human control was counted as a bot')
end

def invalid_statistics(valid)
  [nil, [], 'bad', 1, {}, valid.reject { |key, _| key == 'id' }, valid.reject { |key, _| key == 'mode' },
    valid.merge('id' => nil), valid.merge('id' => 1), valid.merge('id' => valid['id'].upcase),
    valid.merge('id' => " #{valid['id']}"), valid.merge('id' => "#{valid['id']}\n"),
    valid.merge('id' => valid['id'].delete('-')), valid.merge('id' => 'native:123'),
    valid.merge('mode' => nil), valid.merge('mode' => 'unknown'), valid.merge('mode' => 'HUMANS'),
    valid.merge('started_at' => nil), valid.merge('started_at' => 0), valid.merge('started_at' => -1),
    valid.merge('started_at' => '123'), valid.merge('started_at' => 123.0), valid.merge('started_at' => true),
    valid.merge('owner' => 'Alice')]
end

statistics_case('optional packet metadata is strict and does not weaken start authority or old-client support') do
  h = NativeRoomHarness.new(users: %w[Alice Bob])
  original = h.start
  packet = statistics_start_entry(h)['packet']
  valid = {'id' => '12345678-abcd-4abc-8abc-123456789abc', 'mode' => 'humans'}
  record = lambda do |value|
    GameRoomLiveSessionStore::Record.new(table_id: h.table['__id'], sequence: 100,
      message_id: SecureRandom.uuid, sender: 'Alice', packet: value, created_at: 123)
  end
  malformed = invalid_statistics(valid)
  malformed.each do |metadata|
    invalid = packet.merge('data' => packet['data'].merge('statistics' => metadata))
    validator = GameRoomLiveSessionStore::RecordValidator.new
    assert(!validator.accept(record.call(invalid), owner: 'Alice', ledger: nil), "Malformed packet statistics were accepted: #{metadata.inspect}")
    h.view('Alice').stack_push(invalid, message_id: SecureRandom.uuid)
  end
  identity = GameRoomStatistics::Identity
  assert(identity.valid?(valid), 'Fresh metadata requires an unavailable server time')
  assert(!identity.valid?(valid, require_started_at: true), 'Archive metadata without its original date was accepted')
  complete = valid.merge('started_at' => 123)
  assert(identity.valid?(complete, require_started_at: true), 'Complete restored metadata was rejected')
  assert(malformed.none? { |metadata| identity.valid?(metadata) }, 'Shared validation accepted malformed metadata')
  assert(!identity.valid?(valid.transform_keys(&:to_sym)), 'Symbol keys were silently normalized')
  assert(!identity.valid?(valid.merge('id' => "\xff".b)), 'Non-ASCII identity was accepted')
  h.view('Bob').stack_push(packet.merge('actor' => 'Bob'), message_id: SecureRandom.uuid)
  h.write('Alice', [GameRoomGames::EventCommand.new(action: 'tick', value: 'after invalid')])
  h.users.each do |user|
    current = h.repositories[user].session_for_table(h.table)
    assert(current['__id'] == original['__id'] && current['__statistics'] == original['__statistics'], 'Malformed or unauthorized metadata replaced the accepted match')
  end
  h.assert_converged('statistics packet rejection', expected_count: 1)
  legacy = packet.merge('data' => packet['data'].reject { |key, _| key == 'statistics' }.merge('session_id' => original['__id'] + 1))
  h.view('Alice').stack_push(legacy, message_id: SecureRandom.uuid)
  h.users.each do |user|
    old = h.repositories[user].session_for_table(h.table)
    assert(old['__id'] == legacy['data']['session_id'], 'Old-client start was rejected')
    assert(!old.key?('__statistics'), 'Old-client start invented a tracked identity')
  end
end

require_relative '../lib/account_saved_games'
require_relative 'support/private_archives'
require_relative '../games/four_in_a_row'

def statistics_save_fixture
  h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
  h.broker.automatic_delivery = false
  push = h.view('Alice').method(:stack_push)
  h.view('Alice').define_singleton_method(:stack_push) do |packet, message_id:|
    result = push.call(packet, message_id: message_id)
    entry = h.core.entries.find { |item| item['message_id'] == message_id }
    entry['created_at'] = 1_700_000_000
    result.merge('created_at' => entry['created_at'])
  end
  h.start
  h.write('Alice', [GameRoomGames::EventCommand.new(action: 'drop', value: '3')])
  h.write('Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: '4')])
  h.as('Alice') do
    h.transports['Alice'].replace_game_player(h.table, session_id: h.session['__id'], player: 'Bob')
  end
  boundary = h.transports['Alice'].freeze_game(h.session)
  snapshot = h.repositories['Alice'].snapshot_for(h.session, force_events: true)
  resources = PrivateArchiveDouble.new
  no_disk = Object.new
  def no_disk.read_json(*); raise 'Unexpected local save read'; end
  def no_disk.update_json(*); raise 'Unexpected local save write'; end
  saves = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources)
  row = saves.put(game: h.game, table: h.table, snapshot: snapshot, repository: h.repositories['Alice'], now: boundary.created_at)
  [h, saves, resources, no_disk, row, snapshot]
end

statistics_case('account save and repeated restore preserve the original ID, mode and date') do
  h, saves, resources, no_disk, row, snapshot = statistics_save_fixture
  metadata = snapshot.session['__statistics']
  assert(row['statistics'] == metadata, 'Saving discarded original match metadata')
  assert(row['statistics'].frozen? && row['statistics'].values.all?(&:frozen?), 'Save retained mutable metadata')
  assert(!row['statistics'].equal?(metadata) && !row['statistics']['id'].equal?(metadata['id']), 'Save shares session metadata')
  assert(row['id'] != metadata['id'], 'Statistics reused the saved archive identity')
  assert(saves.validate(row, game: h.game) == row, 'Metadata was appended after the checksum')
  before = h.game.replay(snapshot.session, snapshot.events, h.repositories['Alice'])
  owner = h.transports['Alice']
  owner.deactivate_table(table_id: h.table['__id'])
  other = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources)
  archive = other.fetch(row['id'])
  assert(archive['statistics'] == metadata, 'Account download lost statistics metadata')
  2.times do
    bots = archive['players'].select { |player| GameRoomParticipants.bot?(player) }
    table = owner.create_room(name: 'Restored statistics fixture', game: h.game.id, owner: 'Alice', game_options: archive['options'],
      bot_count: bots.length, bot_names: bots.map { |bot| GameRoomParticipants.bot_name_token(bot) }, resume_save_id: archive['id'])
    remote = GameRoomTransport.new(ProgramDouble.new(h.broker.endpoint('Bob', fresh: true)))
    discovered = remote.discover_rooms.find { |item| item['__id'] == table['__id'] }
    assert(remote.establish_membership(table_id: table['__id'], owner: 'Alice', capacity: 8, user: 'Bob', table: discovered), 'Reader could not join restoration')
    restore = other.restored_data(archive, game: h.game, table_id: table['__id'], now: row['saved_at'] + 86_400)
    assert(restore[:statistics] == metadata, 'Restore preparation replaced original metadata')
    assert(restore[:statistics].frozen? && restore[:statistics].values.all?(&:frozen?), 'Restore metadata is mutable')
    assert(!restore[:statistics].equal?(archive['statistics']) && !restore[:statistics]['id'].equal?(archive['statistics']['id']), 'Restore shares downloaded metadata')
    session = h.as('Alice') do
      h.repositories['Alice'].restore_session(table: table, game: h.game.id, players: restore[:players], options: archive['options'], restore: restore)
    end
    assert(session['__id'] != h.session['__id'] && table['__live_session_id'] != h.table['__live_session_id'], 'Restore reused native identities')
    assert(session['__statistics'] == metadata, 'Restore created a new tracked match or recomputed the mode/date')
    assert(session['__statistics']['mode'] == 'humans' && session['__players'].any? { |player| GameRoomParticipants.bot?(player) }, 'Restore did not preserve the original human mode after replacement')
    assert(session['__statistics']['started_at'] != session['__server_started_at'], 'Restore test does not distinguish original and resumed start dates')
    native = h.broker.cores.fetch(table['__live_session_id'])
    start = native.entries.find { |item| item.dig('packet', 'kind') == 'game_started' }
    assert(start.dig('packet', 'data', 'statistics') == metadata, 'Restored start packet lost archive identity/date')
    assert(start.dig('packet', 'data', 'archive_id') != metadata['id'], 'Statistics reused native import identity')
    current = h.repositories['Alice'].snapshot_for(session, force_events: true)
    after = h.game.replay(current.session, current.events, h.repositories['Alice'])
    assert(after.board == before.board && after.accepted_events.length == 2, 'Statistics changed restored replay')
    reader = GameRepository.new(ProgramDouble.new(h.broker.endpoint('Bob')), transport: remote, server_tables: {})
    assert(reader.session_for_table(table)['__statistics'] == metadata, 'Remote restore reader disagrees about original metadata')
    repeated = h.as('Alice') do
      h.repositories['Alice'].restore_session(table: table, game: h.game.id, players: restore[:players], options: archive['options'], restore: restore)
    end
    assert(repeated['__id'] == session['__id'] && repeated['__statistics'] == metadata, 'Repeated resume regenerated a match')
    h.as('Alice') do
      h.repositories['Alice'].append_events(session: session, sequence: h.repositories['Alice'].next_sequence(session, current.events),
        actor: 'Alice', events: [GameRoomGames::EventCommand.new(action: 'drop', value: '5')])
    end
    remote_snapshot = reader.snapshot_for(reader.session_for_table(table), force_events: true)
    assert(h.game.replay(remote_snapshot.session, remote_snapshot.events, reader).accepted_events.length == 3, 'Next restored move failed')
    assert(remote_snapshot.session['__statistics'] == metadata, 'Next move changed tracked identity')
    archive['statistics']['id'].replace('changed after preparation')
    assert(restore[:statistics] == metadata && session['__statistics'] == metadata, 'Downloaded archive mutation escaped into the running game')
    archive = other.fetch(row['id'])
    owner.deactivate_table(table_id: table['__id'])
  end
end

def statistics_argument_error(message)
  begin
    yield
  rescue ArgumentError
    return
  end
  raise message
end

statistics_case('saved metadata is validated even with a recomputed checksum and never normalized') do
  h, saves, resources, _no_disk, row, snapshot = statistics_save_fixture
  malformed = invalid_statistics(row['statistics']) + [row['statistics'].reject { |key, _| key == 'started_at' }]
  malformed.each do |metadata|
    invalid = row.merge('statistics' => metadata)
    invalid['checksum'] = saves.send(:checksum, invalid)
    statistics_argument_error("Saved malformed metadata accepted: #{metadata.inspect}") { saves.validate(invalid, game: h.game) }
    statistics_argument_error('Restoring accepted malformed saved metadata') { saves.restored_data(invalid, game: h.game, table_id: 999) }
    bad_snapshot = snapshot.dup
    bad_snapshot.session = snapshot.session.merge('__statistics' => metadata)
    statistics_argument_error('Saving accepted malformed session metadata') do
      saves.put(game: h.game, table: h.table, snapshot: bad_snapshot, repository: h.repositories['Alice'])
    end
  end
  assert(resources.list(timeout: 1).length == 1, 'Invalid metadata wrote an account archive')
  changed = row.merge('statistics' => row['statistics'].merge('mode' => 'bots'))
  statistics_argument_error('Checksum did not cover statistics metadata') { saves.validate(changed, game: h.game) }
end

statistics_case('restore validates and snapshots statistics before callbacks or stack writes') do
  h = NativeRoomHarness.new(users: ['Alice'])
  owner = h.transports['Alice']
  valid = {'id' => '12345678-abcd-4abc-8abc-123456789abc', 'mode' => 'humans', 'started_at' => 123}
  callbacks = 0
  restore = {events: [], clock_offset: 0, before_publish: ->(_id) { callbacks += 1 }}
  malformed = invalid_statistics(valid) + [valid.reject { |key, _| key == 'started_at' }]
  malformed.each do |metadata|
    before = h.core.entries.length
    statistics_argument_error('Direct restore accepted malformed statistics') do
      h.as('Alice') do
        owner.start_game(table: h.table, game: 'test', players: ['Alice'], options: '{}', actor: 'Alice', restore: restore.merge(statistics: metadata))
      end
    end
    assert(h.core.entries.length == before && callbacks.zero?, 'Invalid restore wrote a checkpoint/archive or invoked its publication callback')
  end
  source = JSON.parse(JSON.generate(valid))
  restored = restore.merge(statistics: source, before_publish: ->(_id) { source['id'].replace('changed during publication') })
  session = h.as('Alice') do
    owner.start_game(table: h.table, game: 'test', players: ['Alice'], options: '{}', actor: 'Alice', restore: restored)
  end
  assert(session['__statistics'] == valid, 'Restore metadata was not captured before the publication callback')
  assert(statistics_start_entry(h).dig('packet', 'data', 'statistics') == valid, 'Callback mutation reached the start packet')
end

statistics_case('metadata copies only accept a valid canonical fallback time') do
  source = {'id' => '12345678-abcd-4abc-8abc-123456789abc', 'mode' => 'solo'}
  [0, -1, '123', 123.0, true, []].each do |time|
    statistics_argument_error('Invalid fallback statistics time was accepted') { GameRoomStatistics::Identity.copy(source, started_at: time) }
  end
  copy = GameRoomStatistics::Identity.copy(source, started_at: 123)
  assert(!source.key?('started_at') && copy['started_at'] == 123, 'Copy changed the source instead of supplying canonical time')
  assert(copy.frozen? && copy.values.all?(&:frozen?), 'Canonical metadata copy is mutable')
  assert(GameRoomStatistics::Identity.copy(copy, started_at: 456) == copy, 'Canonical fallback overwrote the saved date')
end

statistics_case('old saves remain playable and untracked through download, restore and another save') do
  h, saves, resources, no_disk, _row, snapshot = statistics_save_fixture
  identity = GameRoomStatistics::Identity
  create = identity.method(:create)
  identity.define_singleton_method(:create) { |**_arguments| raise 'Old save created a tracking identity' }
  begin
    legacy_snapshot = snapshot.dup
    legacy_snapshot.session = snapshot.session.reject { |key, _| key == '__statistics' }
    legacy = saves.put(game: h.game, table: h.table, snapshot: legacy_snapshot, repository: h.repositories['Alice'])
    assert(!legacy.key?('statistics'), 'Saving an old session invented statistics metadata')
    other = AccountSavedGames.new(no_disk, owner: 'Alice', resources: resources)
    archive = other.fetch(legacy['id'])
    assert(!archive.key?('statistics'), 'Downloading an old save invented statistics metadata')
    owner = h.transports['Alice']
    owner.deactivate_table(table_id: h.table['__id'])
    bots = archive['players'].select { |player| GameRoomParticipants.bot?(player) }
    table = owner.create_room(name: 'Legacy statistics fixture', game: h.game.id, owner: 'Alice', game_options: archive['options'],
      bot_count: bots.length, bot_names: bots.map { |bot| GameRoomParticipants.bot_name_token(bot) }, resume_save_id: archive['id'])
    restore = other.restored_data(archive, game: h.game, table_id: table['__id'])
    assert(!restore.key?(:statistics), 'Old restore preparation invented statistics metadata')
    session = h.as('Alice') do
      h.repositories['Alice'].restore_session(table: table, game: h.game.id, players: restore[:players], options: archive['options'], restore: restore)
    end
    assert(!session.key?('__statistics'), 'Old restore was counted as a new match')
    native = h.broker.cores.fetch(table['__live_session_id'])
    start = native.entries.find { |item| item.dig('packet', 'kind') == 'game_started' }
    assert(!start['packet']['data'].key?('statistics'), 'Old restore emitted tracking metadata')
    current = h.repositories['Alice'].snapshot_for(session, force_events: true)
    assert(h.game.replay(current.session, current.events, h.repositories['Alice']).accepted_events.length == 2, 'Old save did not restore its accepted moves')
    saved_again = other.put(game: h.game, table: table, snapshot: current, repository: h.repositories['Alice'])
    assert(!saved_again.key?('statistics'), 'Resaving an old match invented tracking metadata')
  ensure
    identity.define_singleton_method(:create, create)
  end
end

puts "Statistics identity tests passed: #{$statistics_identity_cases} cases"
