require 'monitor'
require_relative '../../support/statistics_tables'
require_relative '../../../lib/darts/rankings/service'

module EltenLink
  class Client; end
end

def assert(value, message)
  raise message unless value
end

class DartsPublicMemoryTable < StatisticsMemoryTable
  attr_accessor :actor

  def upsert(values)
    row = rows.find { |item| item['__insertion_user'].to_s.casecmp?(actor.to_s) }
    if row
      row.merge!(values)
    else
      row = values.merge('__id'=>(rows.map { |item| item['__id'] }.max || 0) + 1,
        '__insertion_user'=>actor.to_s)
      rows << row
    end
    row.dup
  end

  def delete(id)
    index = rows.index do |row|
      row['__id'] == id && row['__insertion_user'].to_s.casecmp?(actor.to_s)
    end
    raise 'deleting another Darts player row' unless index
    rows.delete_at(index)
    true
  end

  def seed(user, records)
    rows << {'__id'=>(rows.map { |item| item['__id'] }.max || 0) + 1,
      '__insertion_user'=>user, 'version'=>1, 'records_json'=>JSON.generate(records)}
  end
end

class DartsPersonalMemoryTable < StatisticsMemoryTable
  def upsert(values)
    if rows.empty?
      rows << values.merge('__id'=>1, '__insertion_user'=>'owner')
    else
      rows.first.merge!(values)
    end
    rows.first.dup
  end
end

class DartsRankingMemoryApi
  attr_reader :table_object, :personal_tables
  attr_accessor :actor

  def initialize
    @table_object = DartsPublicMemoryTable.new
    @personal_tables = {}
    @actor = 'Alice'
  end

  def personal_table(user = actor)
    @personal_tables[user.downcase] ||= DartsPersonalMemoryTable.new
  end

  def schema(*)
    tables = Marshal.load(Marshal.dump(GameRoomDartsRankings::Schema::TABLES))
    tables.each_value do |table|
      table['permissions'] = table['permissions'].to_h { |name| [name, true] }
      table['unique_per_user'] = false unless table.key?('unique_per_user')
    end
    {'data'=>{'server'=>{'tables'=>tables}}}
  end

  def table(_client, _uuid, name)
    if name == GameRoomDartsRankings::Schema::PERSONAL_TABLE
      personal_table
    else
      @table_object.actor = actor
      @table_object
    end
  end
end

class DartsRankingMemoryStorage
  attr_reader :data
  def initialize; @data, @lock = {}, Monitor.new; end
  def read_json(path, default: nil); Marshal.load(Marshal.dump(@data.fetch(path, default))); end
  def update_json(path, default: nil)
    @lock.synchronize do
      value = read_json(path, default: default)
      yield value
      @data[path] = Marshal.load(Marshal.dump(value))
    end
  end
end

def ranking_row(key, score:, time:, total: score, total_time: time, throws: 3, played_at: 1_800_000_000,
  difficulty: 'normal')
  rounds = throws / 3
  {'result_key'=>Digest::SHA256.hexdigest(key), 'difficulty'=>difficulty, 'played_at'=>played_at,
    'day_key'=>GameRoomDartsRankings::Result.day(played_at), 'rounds'=>rounds, 'throw_count'=>throws,
    'total_score'=>total, 'total_time_ms'=>total_time, 'best_round_score'=>score, 'best_round_time_ms'=>time}
end

def result_operation(row, publish:)
  row.merge('kind'=>'darts_result', 'match'=>row.fetch('result_key'), 'publish'=>publish)
end

def single_record_set(row)
  {row.fetch('difficulty')=>{
    'triple'=>[{'key'=>row.fetch('result_key'), 'played_at'=>row.fetch('played_at'),
      'score'=>row.fetch('best_round_score'), 'time_ms'=>row.fetch('best_round_time_ms')}],
    'average'=>[{'key'=>row.fetch('result_key'), 'played_at'=>row.fetch('played_at'),
      'total_score'=>row.fetch('total_score'), 'throw_count'=>row.fetch('throw_count'),
      'total_time_ms'=>row.fetch('total_time_ms')}]
  }}
end

def store_for(api, user, feedback_requested: ->(_key) { false }, on_feedback: nil)
  GameRoomDartsRankings::Store.new(app_uuid:'test', user:user, api:api, client:Object.new,
    current_user:-> { user }, feedback_requested:feedback_requested, on_feedback:on_feedback)
end

api = DartsRankingMemoryApi.new
store = store_for(api, 'Alice')
first = ranking_row('write', score:200, time:5000)
operation = result_operation(first, publish:true)
assert(store.write_batch([operation]) == 1, 'first Darts ranking result was not acknowledged')
assert(store.write_batch([operation]) == 1 && api.table_object.rows.length == 1,
  'retry created another public row for the same Darts player')
stored_public = JSON.parse(api.table_object.rows.first.fetch('records_json'))
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
stored_private = JSON.parse(private_api.personal_table.rows.first.fetch('records_json'))
assert(stored_private.dig('normal', 'triple').map { |entry| entry['score'] } == [230, 222, 210],
  'private Darts records did not retain exactly the best three results')
assert(private_feedback.any? { |value| value.dig('personal_record', 'score') == 230 } &&
  private_feedback.all? { |value| value['placements'].empty? },
  'private records lost personal-best feedback or invented a public place')

%w[easy hard progressive].each_with_index do |difficulty, index|
  row = ranking_row("private-#{difficulty}", score:180 + index, time:4000,
    difficulty:difficulty, played_at:1_800_005_000 + index)
  private_store.write_batch([result_operation(row, publish:false)])
end
stored_variants = JSON.parse(private_api.personal_table.rows.first.fetch('records_json'))
assert(%w[easy normal hard progressive].all? { |difficulty| stored_variants.dig(difficulty, 'triple', 0) },
  'private records for different Darts variants overwrote one another')

private_store.write_batch([{'kind'=>'darts_publish_saved', 'match'=>'a' * 32}])
assert(private_api.table_object.rows.length == 1 &&
  JSON.parse(private_api.table_object.rows.first.fetch('records_json')).dig('normal', 'triple').length == 3,
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
assert(public_schema['visibility'] == 'public' && public_schema['unique_per_user'] == true &&
  public_schema['permissions'] == %w[select insert update delete],
  'public Darts records are not one removable account-owned row')
assert(personal_schema['visibility'] == 'shared' && personal_schema['unique_per_user'] == true &&
  personal_schema['permissions'] == %w[select insert update],
  'private Darts records are not one account-owned non-public row')

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
assert(JSON.generate(maximal).bytesize <= GameRoomDartsRankings::Schema::RECORDS_BYTES,
  'a complete private/public Darts top-three document exceeds its declared server column')

queued = []
writer = Object.new
writer.define_singleton_method(:write_batch) { |values, **_| queued.concat(values); values.length }
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

puts 'PASS Darts rankings: private/public top three, one row per player, opt-in, withdrawal, places and durable operations'
