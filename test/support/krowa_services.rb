require_relative "krowa"
require_relative "../../games/krowa_support/server_store"
require_relative "../../games/krowa_support/daily_access"
require_relative "../../games/krowa_support/profile"
require_relative "../../lib/game_audio"

class KrowaTestTables
  attr_accessor :enabled
  def initialize; @tables = {}; @enabled = true; end
  def available?; @enabled; end
  def fetch(name); @tables[name] ||= Table.new; end
  class Table
    attr_reader :rows, :queries
    attr_accessor :fail_after, :lost_ack, :user, :concurrent_first
    def initialize; @rows = []; @queries = []; @user = "Alice"; end
    def insert(values)
      if concurrent_first
        @concurrent_first = false
        insert(values)
      end
      row = values.merge("__id" => @rows.length + 1, "__insertion_user" => user, "__insertion_time" => 1)
      @rows << row
      if lost_ack
        @lost_ack = false
        raise IOError, "acknowledgement lost after server write"
      end
      row
    end
    def insert_many(values)
      values.each_with_index.map do |value, index|
        raise IOError, "partial batch" if fail_after && index >= fail_after
        insert(value)
      end
    end
    def select(where: {}, order: [], limit: 500, offset: 0, **extra)
      @queries << {where: where, order: order, limit: limit, offset: offset}.merge(extra)
      selected = @rows.select { |row| where.all? { |key, value| row[key] == value } }
      if extra[:group_by]
        keys = Array(extra[:group_by])
        selected = selected.group_by { |row| keys.map { |key| row[key] } }.map do |values, members|
          aggregate = keys.zip(values).to_h
          extra.fetch(:aggregates, {}).each do |name, spec|
            values = members.map { |row| row[spec.fetch("column")] }
            aggregate[name] = case spec.fetch("function")
            when "min" then values.min
            when "max" then values.max
            when "count" then values.length
            end
          end
          aggregate
        end
      end
      order.reverse_each { |key, direction| selected = selected.sort_by { |row| row[key] }; selected.reverse! if direction == "desc" }
      selected.drop(offset).first(limit)
    end
  end
end

class KrowaAudioProgram < KrowaTestProgram
  Sound = Struct.new(:volume, :plays, :closed) { def play; self.plays = plays.to_i + 1; end }
  attr_accessor :enabled, :level
  attr_reader :effects, :sounds
  def initialize; super; @enabled = true; @level = 1.0; @effects = []; @sounds = []; end
  def game_room_sound_enabled?(_); enabled; end
  def game_room_sound_volume(_); level; end
  def create_sound_from_asset(_asset, **_); Sound.new.tap { |s| @sounds << s }; end
  def play_sound_from_asset(asset, **options); @effects << [asset, options]; end
  def manage(_); end
  def release(sound, close:); sound.closed = close; end
end
