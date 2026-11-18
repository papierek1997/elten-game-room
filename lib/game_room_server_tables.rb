require "thread"

class GameRoomServerTables
  STAMP_REQUIRED = "apps.tables.stamp_required".freeze

  # The UI entry check also gates managed workers. Binding an unrelated widget's
  # unchecked provider must not replace a confirmed application-entry decision.
  module Runtime
    def server_table_access=(tables)
      runtime = app_runtime
      @server_table_access = runtime && [runtime, Session.name.to_s.downcase.freeze, tables].freeze
    end

    def server_table_access
      access = @server_table_access
      access[2] if access && access[0].equal?(app_runtime) && !access[1].empty? &&
        Session.name.to_s.casecmp?(access[1])
    end

    def server_tables_available?
      server_table_access&.available? == true
    end
  end

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
      @provider.perform { @table.insert_many(values) }
    end

    def update(id, values)
      @provider.perform { @table.update(id, values) }
    end
  end
  private_constant :Table

  def initialize(program, client: nil)
    @server_app_uuid = program.server_app_uuid.to_s
    raise ArgumentError, "ELTEN Game Room server application is not declared" if @server_app_uuid.empty?

    # Repository calls run inside Tasks.run workers. A context-free client waits
    # without trying to drive the ELTEN UI loop from that worker thread.
    @client = client || EltenLink::Client.new
    @tables = {}
    @raw_tables = {}
    @mutex = Mutex.new
    @operation_mutex = Mutex.new
    @access_generation = 0
    reset_access!
  end

  def fetch(name)
    key = name.to_s
    raise ArgumentError, "a server table requires a name" if key.empty?

    @mutex.synchronize { @tables[key] ||= Table.new(self, raw_table(key)) }
  end

  def available?
    access_state == :available
  end

  def stamp_required?
    access_state == :stamp_required
  end

  def access_state
    @mutex.synchronize { @access_state }
  end

  def last_error
    @mutex.synchronize { @last_error }
  end

  def reset_access!
    @mutex.synchronize { reset_access_state }
  end

  # Every application entry probes again, regardless of the previous result or
  # the client's developer mode. The server also permits the author without a stamp.
  def check_access(username:)
    generation, table = @mutex.synchronize do
      reset_access_state
      [@access_generation, raw_table("game_room_users")]
    end
    @operation_mutex.synchronize do
      return false unless @mutex.synchronize { @access_generation == generation }
      begin
        table.select(where: { "username" => username.to_s }, limit: 1)
        @mutex.synchronize do
          return false unless @access_generation == generation

          @access_state = :available
          true
        end
      rescue EltenLink::Error => error
        @mutex.synchronize { record_failure(error) if @access_generation == generation }
        false
      end
    end
  end

  def perform(default: nil)
    generation = @mutex.synchronize { @access_generation }
    @operation_mutex.synchronize do
      return default unless @mutex.synchronize { @access_generation == generation && @access_state == :available }

      begin
        yield
      rescue EltenLink::Error => error
        @mutex.synchronize { record_failure(error) if @access_generation == generation }
        raise
      end
    end
  end

  private

  def raw_table(name)
    @raw_tables[name] ||= EltenLink::Apps.table(@client, @server_app_uuid, name)
  end

  def reset_access_state
    @access_generation += 1
    @access_state = :unchecked
    @last_error = nil
  end

  def record_failure(error)
    @last_error = error
    @access_state = error.code.to_s == STAMP_REQUIRED ? :stamp_required : :unavailable
  end
end
