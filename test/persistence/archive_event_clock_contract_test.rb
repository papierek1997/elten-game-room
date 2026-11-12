require_relative '../support/clock_event_contract'
require_relative '../support/card_timeout_restore'
require_relative '../../games/four_in_a_row'

def restored_clock_snapshot(game, saves, row)
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob])
  data = saves.restored_data(row, game: game, table_id: h.table['__id'], now: Time.now.to_i)
  repository = h.repositories['Alice']
  session = h.as('Alice') do
    repository.restore_session(table: h.table, game: game.id, players: data[:players], options: row['options'], restore: data)
  end
  [h, repository.snapshot_for(session)]
end

ClockEventContract.with_server_time do |time|
  game = GameRoomGames::FourInARow.new
  f = ClockEventContract::Fixture.new(game, users: %w[Alice Bob])
  # A native action cannot inject the trusted archive-only clock field. The
  # incoming command can carry extra keys, but projection copies known fields.
  packet = GameRoomEventProtocol.game_action_packet(session_id: f.h.session['__id'], sequence: 1,
    control_epoch: 'initial', actor: 'Alice', events: [{'action' => 'drop', 'value' => '1',
      'move_id' => 'clock-injection', '__game_time' => 9999, 'game_time' => 8888}])
  f.h.view('Alice').stack_push(packet, message_id: 'clock-injection-packet')
  source = f.snapshot
  assert(source.events.length == 1 && source.events.first['action'] == 'drop', 'Native clock injection fixture not accepted')
  assert(f.replay.accepted_events.length == 1 && f.replay.current_player == 'Bob', 'Native clock injection fixture did not advance the game')
  assert(source.events.first.keys.none? { |key| %w[game_time __game_time].include?(key) }, 'Live action injected an archived logical timestamp')
  assert(GameRoomSessionClock.from_server(source.session, 1000, event: source.events.first) == 1000, 'Live action changed the clock')
  original_events = JSON.generate(source.events)
  time.call(1002)
  f.freeze('Alice', true)
  time.call(1062)
  f.freeze('Alice', false)
  time.call(1063)
  f.submit('Bob', {'kind' => 'grid', 'action' => 'select', 'x' => 1, 'y' => 0})
  f.freeze('Alice', true)
  source = f.snapshot
  saves = SavedGames.new(TimedArchiveMemory.new, owner: 'Alice')
  row = saves.put(game: game, table: f.h.table, snapshot: source, repository: f.h.repositories['Alice'], now: 1063)
  assert(JSON.generate(source.events.first(1)) == original_events, 'Saving mutated accepted native events')
  assert(row['events'].map { |event| event['created_at'] } == [1000, 1063], 'Saving overwrote raw timestamps')
  assert(row['events'].map { |event| event['game_time'] } == [1000, 1003], 'Saving used the latest offset for all historical events')

  [nil, -1, 1.0, '1000', [], {}, 2**63, 1004].each do |bad_time|
    bad = JSON.parse(JSON.generate(row))
    bad['events'].first['game_time'] = bad_time
    bad['checksum'] = saves.send(:checksum, bad)
    begin
      saves.validate(bad, game: game)
      raise 'Malformed/future archived event time was accepted'
    rescue ArgumentError
    end
  end
  tampered = JSON.parse(JSON.generate(row))
  tampered['events'].first['game_time'] += 1
  begin
    saves.validate(tampered, game: game)
    raise 'Checksum does not cover event game_time'
  rescue ArgumentError
  end

  time.call(4000)
  h, restored = restored_clock_snapshot(game, saves, row)
  assert(restored.events.map { |event| event['__game_time'] } == [1000, 1003], 'Native archive lost logical event time')
  assert(restored.events.map { |event| GameRoomSessionClock.from_server(restored.session, event['created_at'], event: event) } == [1000, 1003],
    'Native archive deducted the restore offset again')
  assert(ClockEventContract.clock.now(restored.session) == 1003, 'Archive metadata changed the current clock')
  assert(game.replay(restored.session, restored.events, h.repositories['Alice']).board == f.replay.board, 'Clock metadata changed the position')

  # Older canonical archives remain readable without inventing an event offset.
  legacy = JSON.parse(JSON.generate(row))
  legacy['events'].each { |event| event.delete('game_time') }
  legacy['checksum'] = saves.send(:checksum, legacy)
  saves.validate(legacy, game: game)
  _legacy_h, old = restored_clock_snapshot(game, saves, legacy)
  assert(old.events.none? { |event| event.key?('__game_time') }, 'Legacy archive injected internal clock metadata')
  old.events.each do |event|
    assert(GameRoomSessionClock.from_server(old.session, event['created_at'], event: event) ==
      GameRoomSessionClock.from_server(old.session, event['created_at']), 'Legacy timestamp interpretation changed')
  end

  # The independent incoming-record validator rejects invalid public archive
  # metadata as well; the local checksum is not the only boundary.
  store = h.transports['Alice'].instance_variable_get(:@live_store)
  [nil, -1, 1.0, '1000', [], {}, 2**63].each_with_index do |bad_time, index|
    id = "invalid-clock-#{index}"
    event = row['events'].first.merge('game_time' => bad_time)
    h.view('Alice').stack_push({'version' => 2, 'kind' => 'game_archive', 'actor' => 'Alice',
      'data' => {'archive_id' => id, 'index' => 0, 'events' => [event]}}, message_id: id)
    records = store.send(:records_for, h.table['__id'])
    assert(records.none? { |record| record.packet.dig('data', 'archive_id') == id }, 'Malformed network archive clock was accepted')
  end
end

puts 'PASS archive clocks: raw timestamps, event-local offsets, checksum/type/range/future checks, native restore, legacy archives and rejected live/internal clock injection'
