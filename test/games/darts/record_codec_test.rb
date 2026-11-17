require_relative '../../support/darts_rankings'

codec = GameRoomDartsRankings::RecordCodec
records = GameRoomDartsRankings::Result::DIFFICULTIES.to_h do |difficulty|
  [difficulty, {'triple'=>3.times.map do |i|
    {'key'=>Digest::SHA256.hexdigest("#{difficulty}:triple:#{i}"), 'played_at'=>253_402_214_399,
      'score'=>300 - i, 'time_ms'=>1_800_000}
  end, 'average'=>3.times.map do |i|
    {'key'=>Digest::SHA256.hexdigest("#{difficulty}:average:#{i}"), 'played_at'=>253_402_214_399,
      'total_score'=>30_000 - i, 'throw_count'=>300, 'total_time_ms'=>180_000_000}
  end}]
end
json = codec.encode(records, unlocked_level:5)
declared_maximum = GameRoomDartsRankings::Schema::RECORDS_BYTES
assert(json.bytesize <= declared_maximum && declared_maximum <= 4096,
  "maximum-width Darts records exceed the real column: #{json.bytesize}")
assert(codec.decode(json, version:2) == records, 'compact encoding lost a key, score, time or scope')
assert(codec.decode_document(json, version:2).unlocked_level == 5, 'private progression was not retained inside the document')
assert(GameRoomDartsRankings::Schema::COLUMNS == {'version'=>'integer', 'records_json'=>'string:4096'} &&
  GameRoomDartsRankings::Schema::PERSONAL_COLUMNS == GameRoomDartsRankings::Schema::COLUMNS,
  'version two requires a destructive column/schema migration')
legacy = single_record_set(ranking_row('old-record', score:250, time:1234))
assert(codec.decode(JSON.generate(legacy), version:1) == legacy, 'existing published records changed during decoding')
store = store_for(DartsRankingMemoryApi.new, 'Alice')
assert(store.send(:validate_record_set!, records), 'the maximum-width fixture is not valid production data')
invalid = [nil, [], {'normal'=>[]}, {'normal'=>{'unknown'=>[]}},
  {'normal'=>{'triple'=>[['A' * 43, 1, 100]]}},
  {'normal'=>{'triple'=>[['!' * 43, 1, 100, 1000]]}},
  {'normal'=>{'triple'=>[['A' * 42 + 'B', 1, 100, 1000]]}}]
invalid.each do |value|
  begin
    codec.decode(JSON.generate({'r'=>value}), version:2)
    raise "Malformed compact records were accepted: #{value.inspect}"
  rescue GameRoomDartsRankings::RecordCodec::Invalid
  end
end
[-1, 0, 1, 6, nil, '5'].each do |level|
  begin
    codec.decode(JSON.generate({'r'=>{}, 'u'=>level}), version:2)
    raise "Invalid progression level accepted: #{level.inspect}"
  rescue GameRoomDartsRankings::RecordCodec::Invalid
  end
end
puts "PASS Darts record codec: all seven scopes and 42 maximum-width records fit #{json.bytesize}/4096 bytes, lossless legacy/v2 decoding"
