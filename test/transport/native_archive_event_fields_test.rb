require_relative '../support/native_room_harness'
require_relative '../support/dice_games'
require_relative '../../lib/saved_game_archive'

class NativeEventFieldsArchive < GameRoomSavedGameArchive
  private

  def persist(_row); end
end

game = GameRoomGames::DicePoker.new
players = %w[Alice Bob]
source_session = {'__id'=>19, '__players'=>players,
  'options'=>JSON.generate(game.default_options)}
source_events = [{'id'=>1, 'sequence'=>1, 'actor'=>'Alice', 'action'=>'roll',
  'value'=>'1,2,3,4,5', 'created_at'=>1}]
source_repository = DiceGamesSupport::Repository.new(players)
archive = NativeEventFieldsArchive.new(nil, owner:'Alice')
row = archive.put(game:game, table:{'owner'=>'Alice', 'name'=>'Saved dice'},
  snapshot:Struct.new(:session, :events).new(source_session, source_events),
  repository:source_repository, now:100)
assert(row.fetch('events').length == 1, 'Normal dice archive fixture did not contain its accepted move')

cases = [[nil, nil], ['game_time', 1], ['__server_random', true],
  ['__server_pool', {'operation'=>'take'}], ['__payload', {'action'=>'roll'}],
  ['__game_time', 9000], ['__clock_offset', []], ['unknown_field', 'extra']]

cases.each do |key, value|
  h = NativeRoomHarness.new(game:game, users:players)
  data = archive.restored_data(row, game:game, table_id:h.table['__id'], now:200)
  data.fetch(:events).first[key] = value if key
  repository = h.repositories.fetch('Alice')
  restored = h.as('Alice') do
    # Same native owner-authenticated upload path as an ordinary restore.
    # Simulate an altered sender packet AFTER the local file validation;
    # the independent incoming-record boundary must still reject it.
    repository.restore_session(table:h.table, game:game.id, players:data[:players],
      options:row['options'], restore:data)
  end
  invalid = key && key != 'game_time'
  h.users.each do |user|
    remote = h.repositories.fetch(user).session_for_table(h.table, force:true)
    if remote
      snapshot = h.repositories.fetch(user).snapshot_for(remote)
      replay = game.replay(snapshot.session, snapshot.events, h.repositories.fetch(user))
      assert(!invalid, "Noncanonical native archive reached the reducer: #{key}")
      assert(replay.accepted_events.length == 1 && replay.state[:rolls] == 1,
        'Canonical native archive changed its game state')
      if key == 'game_time'
        assert(snapshot.events.first['__game_time'] == value,
          'Canonical native archive lost its validated logical timestamp')
      end
    else
      assert(invalid, "Canonical native archive could not be restored: #{key}")
    end
    if invalid
      store = h.transports.fetch(user).instance_variable_get(:@live_store)
      accepted = store.send(:records_for, h.table['__id'])
      assert(accepted.none? { |record| record.packet['kind'] == 'game_archive' },
        "Incoming native validation retained noncanonical event metadata: #{key}")
    end
  end
  assert(invalid ? restored.nil? : restored != nil, 'Restore acknowledgement disagreed with validated native history')
end

puts 'Native archive canonical event fields: normal/timed imports converge; native proof, payload and unknown keys are rejected before replay: OK'
