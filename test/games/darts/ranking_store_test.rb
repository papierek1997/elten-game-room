require_relative '../../support/darts_rankings'
api = DartsRankingMemoryApi.new
store = store_for(api, 'Alice')
first = ranking_row('write', score:200, time:5000)
operation = result_operation(first, publish:true)
assert(store.write_batch([operation]) == 1, 'first Darts ranking result was not acknowledged')
assert(store.write_batch([operation]) == 1 && api.table_object.rows.length == 1,
  'retry created another public row for the same Darts player')
stored_public = stored_darts_records(api.table_object.rows.first)
assert(stored_public.dig('normal', 'triple').length == 1,
  'retry duplicated a result inside the public Darts player row')

api = DartsRankingMemoryApi.new
store = store_for(api, 'Alice')
[100, 220, 180, 250].each_with_index do |score, index|
  row = ranking_row("alice-#{index}", score:score, time:5000 - index,
    played_at:1_800_000_100 + index)
  store.write_batch([result_operation(row, publish:true)])
end
assert(api.table_object.rows.length == 1, 'one player occupied more than one physical public Darts row')
alice_triples = store.ranking(difficulty:'normal', category:'triple', fresh:true)
assert(alice_triples.map { |row| row['best_round_score'] } == [250, 220, 180] &&
  alice_triples.all? { |row| row['user'] == 'Alice' },
  "public Darts ranking did not retain exactly the player's best three results: #{alice_triples.inspect}")

api.table_object.seed('Bob', single_record_set(ranking_row('bob-tie', score:250, time:4997,
  played_at:1_800_000_099)))
triple = store.ranking(difficulty:'normal', category:'triple', fresh:true)
assert(triple.first.values_at('place', 'user') == [1, 'Bob'] && triple[1].values_at('place', 'user') == [1, 'Alice'],
  "shared places or their date order changed: #{triple.inspect}")

limit_api = DartsRankingMemoryApi.new
30.times do |index|
  row = ranking_row("limit-#{index}", score:300 - index, time:1000 + index,
    played_at:1_800_001_000 + index)
  limit_api.table_object.seed("Player#{index}", single_record_set(row))
end
limit_store = store_for(limit_api, 'Alice')
assert(limit_store.ranking(difficulty:'normal', category:'triple').length == GameRoomDartsRankings::DISPLAY_LIMIT,
  'the public Darts ranking exposes more than thirty records')

boundary_feedback = []
boundary_store = store_for(limit_api, 'Alice', feedback_requested:->(_key) { true },
  on_feedback:->(value) { boundary_feedback << value })
limit_api.actor = 'Alice'
tied_outside = ranking_row('boundary-alice', score:271, time:1029, played_at:1_800_003_000)
boundary_store.write_batch([result_operation(tied_outside, publish:true)])
assert(boundary_feedback.first['personal_record'] && boundary_feedback.first['placements'].empty?,
  'a thirty-first physical result was announced as present in the displayed top thirty')

private_api = DartsRankingMemoryApi.new
private_feedback = []
private_store = store_for(private_api, 'Alice', feedback_requested:->(_key) { true },
  on_feedback:->(value) { private_feedback << value })
[222, 210, 230, 100].each_with_index do |score, index|
  row = ranking_row("private-#{index}", score:score, time:3456 + index, played_at:1_800_004_000 + index)
  private_store.write_batch([result_operation(row, publish:false)])
end
assert(private_api.table_object.rows.empty?, 'opting out still published a Darts result')
stored_private = stored_darts_records(private_api.personal_table.rows.first)
assert(stored_private.dig('normal', 'triple').map { |entry| entry['score'] } == [230, 222, 210],
  'private Darts records did not retain exactly the best three results')
assert(private_feedback.any? { |value| value.dig('personal_record', 'score') == 230 } &&
  private_feedback.all? { |value| value['placements'].empty? },
  'private records lost personal-best feedback or invented a public place')

progress_api = DartsRankingMemoryApi.new
progress_feedback, progress_updates = [], []
progress_store = store_for(progress_api, 'Alice', feedback_requested:->(_key) { true },
  on_feedback:->(value) { progress_feedback << value }, on_progression:->(value) { progress_updates << value })
premature = ranking_row('premature-master', score:300, time:3000, total:800, total_time:9000,
  throws:9, difficulty:'expert')
progress_store.write_batch([result_operation(premature, publish:false)])
assert(progress_store.highest_unlocked_difficulty == 'hard',
  'an Expert result skipped the required Hard unlock step')
[
  ['unlock-expert', 'hard', 850, 'expert'],
  ['unlock-master', 'expert', 800, 'master'],
  ['unlock-legendary', 'master', 750, 'legendary']
].each_with_index do |(key, difficulty, total, expected), index|
  row = ranking_row(key, score:300 - index, time:3000, total:total, total_time:9000,
    throws:9, difficulty:difficulty, played_at:1_800_004_500 + index)
  progress_store.write_batch([result_operation(row, publish:false)])
  assert(progress_store.highest_unlocked_difficulty == expected,
    "#{expected} was not unlocked by its exact three-round threshold")
end
assert(progress_feedback.map { |value| value['unlocked_difficulty'] }.compact == %w[expert master legendary] &&
  progress_updates.include?('legendary'), 'unlock feedback or account progression was lost')

legacy_api = DartsRankingMemoryApi.new
legacy_api.personal_table.seed('Alice', single_record_set(ranking_row('legacy', score:200, time:4000)))
assert(store_for(legacy_api, 'Alice').highest_unlocked_difficulty == 'hard',
  'a version-one personal snapshot did not migrate to the legacy Hard entitlement')

concurrent_progress_api = DartsRankingMemoryApi.new
concurrent_progress_table = concurrent_progress_api.personal_table
[
  [ranking_row('progress-hard', score:180, time:4000), 2],
  [ranking_row('progress-expert', score:190, time:3900), 3]
].each_with_index do |(candidate, level), index|
  concurrent_progress_table.rows << {'__id'=>index + 1, '__insertion_user'=>'Alice', 'version'=>2,
    'records_json'=>GameRoomDartsRankings::RecordCodec.encode(single_record_set(candidate), unlocked_level:level)}
end
concurrent_progress_store = store_for(concurrent_progress_api, 'Alice')
assert(concurrent_progress_store.highest_unlocked_difficulty == 'expert',
  'concurrent personal snapshots lowered the highest Darts unlock')
candidate = ranking_row('progress-compact', score:200, time:3800, played_at:1_800_004_900)
concurrent_progress_store.write_batch([result_operation(candidate, publish:false)])
assert(concurrent_progress_table.rows.length == 1 &&
  GameRoomDartsRankings::RecordCodec.decode_document(concurrent_progress_table.rows.first['records_json'], version:2).unlocked_level == 3,
  'compaction lost an unlock retained by another concurrent snapshot')

%w[easy hard progressive].each_with_index do |difficulty, index|
  row = ranking_row("private-#{difficulty}", score:180 + index, time:4000,
    difficulty:difficulty, played_at:1_800_005_000 + index)
  private_store.write_batch([result_operation(row, publish:false)])
end
stored_variants = stored_darts_records(private_api.personal_table.rows.first)
assert(%w[easy normal hard progressive].all? { |difficulty| stored_variants.dig(difficulty, 'triple', 0) },
  'private records for different Darts variants overwrote one another')

private_store.write_batch([{'kind'=>'darts_publish_saved', 'match'=>'a' * 32}])
assert(private_api.table_object.rows.length == 1 &&
  stored_darts_records(private_api.table_object.rows.first).dig('normal', 'triple').length == 3,
  'explicit publication did not copy the saved private top three')
published_before = private_api.table_object.rows.first.fetch('records_json')
new_private = ranking_row('private-after-disable', score:299, time:2000, played_at:1_800_006_000)
private_store.write_batch([result_operation(new_private, publish:false)])
assert(private_api.table_object.rows.first.fetch('records_json') == published_before,
  'disabling new publications changed results that were already public')
private_store.write_batch([{'kind'=>'darts_withdraw', 'match'=>'b' * 32}])
assert(private_api.table_object.rows.empty? && !private_api.personal_table.rows.empty?,
  'withdrawing public Darts results removed private records or left the public row')

public_schema = GameRoomDartsRankings::Schema::TABLES.fetch(GameRoomDartsRankings::Schema::TABLE)
personal_schema = GameRoomDartsRankings::Schema::TABLES.fetch(GameRoomDartsRankings::Schema::PERSONAL_TABLE)
assert(public_schema['visibility'] == 'public' && public_schema['unique_per_user'] == false &&
  public_schema['permissions'] == %w[select insert delete],
  'public Darts snapshots may be overwritten or cannot be compacted')
assert(personal_schema['visibility'] == 'shared' && personal_schema['unique_per_user'] == false &&
  personal_schema['permissions'] == %w[select insert delete],
  'private Darts snapshots are public, mutable or cannot be compacted')

maximal = GameRoomDartsRankings::Result::DIFFICULTIES.to_h do |difficulty|
  scope = GameRoomDartsRankings::Store::CATEGORIES.to_h do |category|
    entries = GameRoomDartsRankings::RECORDS_PER_PLAYER.times.map do |index|
      row = ranking_row("max-#{difficulty}-#{category}-#{index}", score:300 - index, time:1000 + index,
        difficulty:difficulty, played_at:1_800_010_000 + index)
      single_record_set(row).dig(difficulty, category, 0)
    end
    [category, entries]
  end
  [difficulty, scope]
end
assert(GameRoomDartsRankings::RecordCodec.encode(maximal).bytesize <= GameRoomDartsRankings::Schema::RECORDS_BYTES,
  'a complete private/public Darts top-three document exceeds its declared server column')
widest = GameRoomDartsRankings::Result::DIFFICULTIES.to_h do |difficulty|
  [difficulty, {
    'triple'=>3.times.map { |i| {'key'=>i.to_s * 64, 'played_at'=>253_402_214_399, 'score'=>300 - i, 'time_ms'=>1_800_000} },
    'average'=>3.times.map { |i| {'key'=>i.to_s * 64, 'played_at'=>253_402_214_399,
      'total_score'=>30_000 - i, 'throw_count'=>300, 'total_time_ms'=>180_000_000} }
  }]
end
encoded_widest = GameRoomDartsRankings::RecordCodec.encode(widest, unlocked_level:5)
assert(store.send(:validate_record_set!, widest) && encoded_widest.bytesize <= 4096 &&
  GameRoomDartsRankings::RecordCodec.decode(encoded_widest, version:2) == widest &&
  GameRoomDartsRankings::Schema::COLUMNS.fetch('records_json') == 'string:4096' &&
  GameRoomDartsRankings::Schema::PERSONAL_COLUMNS == {'version'=>'integer', 'records_json'=>'string:4096'},
  'Maximum-length valid Darts records exceed the server-supported string column')

queued = []
writer = Object.new
writer.define_singleton_method(:write_batch) { |values, **_| queued.concat(values); values.length }
writer.define_singleton_method(:highest_unlocked_difficulty) { |**_| 'master' }
program = Object.new
program.define_singleton_method(:server_app_uuid) { 'test' }
storage = DartsRankingMemoryStorage.new
service = GameRoomDartsRankings::Service.new(program:program, user:'Alice', storage:storage, store:writer,
  current_user:-> { 'Alice' })
assert(service.publish_saved_records && service.withdraw_public_records,
  'public Darts account operations could not be staged')
service.flush
assert(queued.map { |entry| entry['kind'] } == %w[darts_publish_saved darts_withdraw] &&
  queued.all? { |entry| /\A[0-9a-f]{32}\z/.match?(entry['match']) },
  'background ranking queue did not preserve ordered publish/withdraw operations')
assert(service.highest_unlocked_difficulty == 'master',
  'background ranking synchronization did not restore the account unlock')

puts 'PASS Darts rankings: private/public top three, compact snapshots, opt-in, withdrawal, places and durable operations'

[4, 3].each do |throws|
  invalid = {'normal'=>{'average'=>[{'key'=>'e' * 64, 'played_at'=>1_800_000_000,
    'total_score'=>301, 'throw_count'=>throws, 'total_time_ms'=>1000}]}}
  begin
    store.send(:validate_record_set!, invalid)
    raise 'An incomplete round or an average above 100 was accepted'
  rescue GameRoomDartsRankings::Unavailable
  end
end
