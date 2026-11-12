require_relative '../support/clock_event_contract'
require_relative '../support/card_timeout_restore'
require_relative '../../games/four_in_a_row'

# Internal native-projection clock fields are not part of the saved format.
# Only its validated public game_time field may become trusted replay time.
ClockEventContract.with_server_time do |time|
  game = GameRoomGames::FourInARow.new
  fixture = ClockEventContract::Fixture.new(game, users: %w[Alice Bob])
  fixture.submit('Alice', {'kind'=>'grid','action'=>'select','x'=>0,'y'=>0})
  time.call(1004)
  fixture.freeze('Alice', true)
  source = fixture.snapshot
  saves = SavedGames.new(TimedArchiveMemory.new, owner:'Alice')
  original = saves.put(game:game, table:fixture.h.table, snapshot:source,
    repository:fixture.h.repositories['Alice'], now:1004)
  [false,true].product([99_999,{'invalid'=>'type'},[]]).each do |keep_public_time,internal_offset|
    row = JSON.parse(JSON.generate(original))
    event = row['events'].first
    event.delete('game_time') unless keep_public_time
    event['__game_time'] = 44
    event['__clock_offset'] = internal_offset
    row['checksum'] = saves.send(:checksum,row)
    rejected = false
    begin
      saves.validate(row,game:game)
    rescue ArgumentError => error
      rejected = error.message == 'Invalid saved event'
    end
    assert(rejected, 'Serialized native-only clock fields passed the canonical archive boundary')
    event.delete('__game_time')
    event.delete('__clock_offset')
    row['checksum'] = saves.send(:checksum,row)
    saves.validate(row,game:game)
    time.call(2000)
    h = NativeRoomHarness.new(game:game, users:%w[Alice Bob])
    data = saves.restored_data(row,game:game,table_id:h.table['__id'],now:2000)
    repo = h.repositories['Alice']
    session = h.as('Alice') do
      repo.restore_session(table:h.table,game:game.id,players:data[:players],options:row['options'],restore:data)
    end
    snapshot = repo.snapshot_for(session)
    archived = snapshot.events.first
    assert(!archived.key?('__clock_offset'),
      'A serialized internal __clock_offset became trusted native replay metadata')
    expected = keep_public_time ? 1000 : GameRoomSessionClock.from_server(snapshot.session,1000)
    assert(GameRoomSessionClock.from_server(snapshot.session,1000,event:archived) == expected,
      'Internal archive metadata changed the declared public or legacy clock contract')
    assert(archived.fetch('__game_time',nil) == (keep_public_time ? 1000 : nil),
      'An archive supplied its own internal logical timestamp')
    assert(archived['created_at'] == 1000,'Archive sanitization mutated the raw server timestamp')
  end
end
puts 'PASS native archive clock metadata: internal offsets cannot override validated public or legacy timestamps'
