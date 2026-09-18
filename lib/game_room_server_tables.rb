require "thread"

class GameRoomServerTables
  STAMP_REQUIRED = "apps.tables.stamp_required".freeze

  # Keep the access decision shared even by repositories holding cached handles.
  # Skipped writes return nil; they must never be reported as successful writes.
  class Table
    def initialize(provider, table)
      @provider = provider
      @table = table
    end

    def select(**options)
      @provider.perform(default: []) { @table.select(**options) }
    end

    def insert(values)
      @provider.perform { @table.insert(values) }
    end

    def insert_many(values)
      @provider.perform(default: []) { @table.insert_many(values) }
    end

    def update(id, values)
      @provider.perform { @table.update(id, values) }
    end
  end
  private_constant :Table

  attr_reader :access_state, :last_error

  def initialize(program, client: nil, table_app_uuids: {})
    @server_app_uuid = program.server_app_uuid.to_s
    raise ArgumentError, "ELTEN Game Room server application is not declared" if @server_app_uuid.empty?

    @table_app_uuids = table_app_uuids.to_h.transform_keys(&:to_s).transform_values(&:to_s).freeze
    raise ArgumentError, "a table server application UUID must not be empty" if @table_app_uuids.values.any?(&:empty?)

    # Repository calls run inside Tasks.run workers. A context-free client waits
    # without trying to drive the ELTEN UI loop from that worker thread.
    @client = client || EltenLink::Client.new
    @tables = {}
    @raw_tables = {}
    @mutex = Mutex.new
    reset_access!
  end

  def fetch(name)
    key = name.to_s
    raise ArgumentError, "a server table requires a name" if key.empty?

    @mutex.synchronize { @tables[key] ||= Table.new(self, raw_table(key)) }
  end

  def available?
    @access_state == :available
  end

  def stamp_required?
    @access_state == :stamp_required
  end

  def reset_access!
    @mutex.synchronize { reset_access_state }
  end

  # Every application entry probes again, regardless of the previous result or
  # the client's developer mode. The server also permits the author without a stamp.
  def check_access(username:)
    @mutex.synchronize do
      reset_access_state
      begin
        raw_table("game_room_users").select(where: { "username" => username.to_s }, limit: 1)
        @access_state = :available
        true
      rescue EltenLink::Error => error
        record_failure(error)
        false
      end
    end
  end

  def perform(default: nil)
    @mutex.synchronize do
      return default if !available?

      begin
        yield
      rescue EltenLink::Error => error
        record_failure(error)
        raise
      end
    end
  end

  private

  def raw_table(name)
    @raw_tables[name] ||= EltenLink::Apps.table(@client, @table_app_uuids.fetch(name, @server_app_uuid), name)
  end

  def reset_access_state
    @access_state = :unchecked
    @last_error = nil
  end

  def record_failure(error)
    @last_error = error
    @access_state = error.code.to_s == STAMP_REQUIRED ? :stamp_required : :unavailable
  end
end
