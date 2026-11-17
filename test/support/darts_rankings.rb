require 'monitor'
require_relative 'statistics_tables'
require_relative '../../lib/darts/rankings/service'

module EltenLink
  class Client; end
end

def assert(value, message)
  raise message unless value
end

class DartsPublicMemoryTable < StatisticsMemoryTable
  attr_accessor :actor

  def insert(values)
    super(values.merge('__insertion_user'=>actor.to_s))
  end

  def delete_many(ids)
    selected = rows.select { |row| ids.include?(row['__id']) }
    raise 'deleting another Darts player row' unless selected.all? { |row| row['__insertion_user'].to_s.casecmp?(actor.to_s) }
    rows.reject! { |row| ids.include?(row['__id']) }
    selected.length
  end

  def seed(user, records)
    rows << {'__id'=>(rows.map { |item| item['__id'] }.max || 0) + 1,
      '__insertion_user'=>user, 'version'=>1, 'records_json'=>JSON.generate(records)}
  end
end

class DartsPersonalMemoryTable < DartsPublicMemoryTable; end

class DartsRankingMemoryApi
  attr_reader :table_object, :personal_tables
  attr_accessor :actor

  def initialize
    @table_object = DartsPublicMemoryTable.new
    @personal_tables = {}
    @actor = 'Alice'
  end

  def personal_table(user = actor)
    table = @personal_tables[user.downcase] ||= DartsPersonalMemoryTable.new
    table.actor = user
    table
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

def stored_darts_records(row)
  GameRoomDartsRankings::RecordCodec.decode(row.fetch('records_json'), version:row.fetch('version'))
end

def store_for(api, user, feedback_requested: ->(_key) { false }, on_feedback: nil, on_progression: nil)
  GameRoomDartsRankings::Store.new(app_uuid:'test', user:user, api:api, client:Object.new,
    current_user:-> { user }, feedback_requested:feedback_requested, on_feedback:on_feedback,
    on_progression:on_progression)
end
