require_relative '../support/native_room_harness'
require_relative '../../games/four_in_a_row'

def retention_state(h, user)
  store = h.transports.fetch(user).instance_variable_get(:@live_store)
  [store, store.send(:room_state, h.table.fetch('__id'))]
end

def assert_retired(store, session)
  begin
    store.game_events(session, read_only: true)
    raise 'A retired game became an empty/partial replay'
  rescue GameRoomNetworkErrors::GamePaused
  end
end

h = NativeRoomHarness.new(game: GameRoomGames::FourInARow.new, users: %w[Alice Bob])
owner = h.transports.fetch('Alice')
chat = owner.append_activity(table: h.table, kind: 'chat', actor: 'Alice', message: 'keep this conversation')
old_session = old_action = nil
6.times do |round|
  h.start
  7.times do |move|
    h.write(move.even? ? 'Alice' : 'Bob', [GameRoomGames::EventCommand.new(action: 'drop', value: move.even? ? '1' : '2')])
  end
  h.assert_converged("completed normal rematch #{round + 1}", expected_count: 7)
  assert(h.replay('Alice').winner == 'Alice', 'The ordinary game did not finish')
  h.users.each do |user|
    store, room = retention_state(h, user)
    assert(room.records.count { |row| row.packet['kind'] == 'game_action' } == 7,
      'A rematch retained earlier game payloads locally')
    assert(room.record_keys.size == room.records.size && room.message_records.size == room.records.size,
      'Compaction left redundant receipt/key entries')
    assert(store.activity_records(h.table).any? { |row| row['__id'] == chat['__id'] }, 'Compaction erased retained chat')
    assert_retired(store, old_session) if old_session
  end
  old_session ||= h.session.dup
  old_action ||= retention_state(h, 'Alice').last.records.find { |row| row.packet['kind'] == 'game_action' }
end
store, room = retention_state(h, 'Alice')
before = room.records.size
late = store.send(:ingest_record, h.table['__id'], sequence: old_action.sequence,
  message_id: old_action.message_id, sender: old_action.sender, packet: old_action.packet,
  created_at: old_action.created_at, source_session: h.view('Alice'))
assert(late.nil? && room.records.size == before, 'A delayed callback resurrected a compacted game payload')
h.add_client('Carol')
assert(h.join('Carol'), 'A cold client could not join the compacted room')
current = h.repositories['Carol'].session_for_table(h.table)
assert(current['__id'] == h.session['__id'] && h.transports['Carol'].game_events(current).size == 7,
  'A cold client did not recover the complete current game')

# Even an empty previous game must retire before the unchanged warm-cache
# return. There may be no obsolete action row to remove or generation to bump.
empty = NativeRoomHarness.new(users: %w[Alice Bob])
empty.start
previous = empty.session.dup
empty_store, = retention_state(empty, 'Alice')
assert(empty_store.game_events(previous, read_only: true).empty?, 'The fixture was not empty')
empty.start
2.times { assert_retired(empty_store, previous) }

# Current imported moves remain complete. Only a later confirmed rematch can
# retire their payload, while the accepted old start still reserves its ID.
archived = NativeRoomHarness.new(users: %w[Alice Bob])
archive = (1..18).map { |id| {'id' => id * 100, 'sequence' => id, 'actor' => 'Alice',
  'action' => 'play', 'value' => "archived #{id}", 'created_at' => 1000 + id} }
restored = archived.as('Alice') do
  archived.repositories['Alice'].restore_session(table: archived.table, game: 'test', players: archived.users,
    options: '{}', restore: {events: archive, clock_offset: 0})
end
archive_store, archive_room = retention_state(archived, 'Alice')
assert(archive_store.game_events(restored).map { |row| row['value'] } == archive.map { |row| row['value'] },
  'Compaction changed the current imported replay')
assert(archive_room.records.any? { |row| row.packet['kind'] == 'game_archive' }, 'The current archive was removed')
archived.start
archive_store.send(:records_for, archived.table['__id'])
assert(archive_room.records.none? { |row| row.packet['kind'] == 'game_archive' }, 'A later rematch retained the old archive')
assert_retired(archive_store, restored)
random = SecureRandom.method(:random_number)
candidate = ([restored['__id'], archived.session['__id']].max % 1_999_999_999) + 1
candidate += 1 while [restored['__id'], archived.session['__id']].include?(candidate)
values = [restored['__id'] - 1, candidate - 1]
begin
  SecureRandom.define_singleton_method(:random_number) { |_limit| values.shift || raise('Unexpected identifier retry') }
  assert(archive_store.send(:unused_game_identifier, archived.table['__id']) == candidate,
    'An ID belonging to a compacted imported game was reused')
ensure
  SecureRandom.define_singleton_method(:random_number, random)
end

# A failed server trim is not permission to discard local evidence.
failed = NativeRoomHarness.new(users: %w[Alice Bob])
failed.start
failed.write('Alice', [GameRoomGames::EventCommand.new(action: 'tick', value: 'retained')])
failed_store, failed_room = retention_state(failed, 'Alice')
floor = failed.core.trimmed_through
failed.view('Alice').fail_next_trim = :before
failed.start
failed_store.send(:records_for, failed.table['__id'])
assert(failed.core.trimmed_through == floor && failed_room.records.any? { |row| row.packet['kind'] == 'game_action' },
  'A failed trim speculatively discarded the previous game')
failed.start
failed_store.send(:records_for, failed.table['__id'])
assert(failed_room.records.none? { |row| row.packet['kind'] == 'game_action' }, 'A later confirmed trim did not compact')

# An acknowledged-via-read move stays available until its existing recovery
# consumer has received the record. This is a real lost native push reply.
recovery = NativeRoomHarness.new(users: %w[Alice Bob])
recovery.start
recover_session = recovery.session.dup
recovery.broker.automatic_delivery = false
recovery.view('Bob').fail_next_push = :after
begin
  recovery.write('Bob', [GameRoomGames::EventCommand.new(action: 'tick', value: 'uncertain')])
  raise 'The recovery fixture did not lose its push acknowledgement'
rescue EltenAPI::LiveSessions::TimeoutError
end
recovery_store, recovery_room = retention_state(recovery, 'Bob')
assert(recovery_room.pending_move&.uncertain, 'The real uncertain move was not retained')
recovery.broker.deliver(user: 'Bob')
assert(recovery_room.recovered_moves.one?, 'The delayed real receipt did not confirm the uncertain move')
recovery.start
recovery.repositories['Bob'].session_for_table(recovery.table, force: true)
assert(recovery_room.recovered_moves.one?, 'The read did not confirm the uncertain move')
assert(recovery_room.records.any? { |row| row.packet['kind'] == 'game_action' }, 'Compaction erased unconsumed recovery evidence')
recovered = recovery_store.consume_recovered_game_events(recover_session)
assert(recovered.one? && recovered.first['value'] == 'uncertain', 'The existing recovery consumer lost its move')
recovery_store.send(:records_for, recovery.table['__id'])
assert(recovery_room.records.none? { |row| row.packet['kind'] == 'game_action' }, 'Consumed recovery evidence prevented compaction')

puts 'PASS local rematch compaction: normal games, chat, cold reader, delayed rows, empty warm cache, archives, IDs, failed trim and lost-ACK recovery'
