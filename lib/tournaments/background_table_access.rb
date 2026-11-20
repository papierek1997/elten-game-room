require_relative '../game_room_server_tables'
require_relative 'tables_gateway'

module GameRoomTournaments
  # The first ordinary SDK request is the access check. Only a definitive
  # launcher-stamp refusal suspends work; unknown access and outages do not.
  class BackgroundTableAccess
    def initialize(current:, checked_tables:)
      @current, @checked_tables = current, checked_tables
      @lock = Mutex.new
    end

    def current?
      @current.call
    end

    def blocked?
      @lock.synchronize do
        state, check = latest_check
        update_refusal(state, check)
        !@refusal.nil?
      end
    end

    def perform
      assert_current!
      confirmed_at_start = @lock.synchronize do
        state, check = latest_check
        update_refusal(state, check)
        raise TablesGateway::Unavailable, 'Protected tournament tables require a launcher stamp' if @refusal
        [state, check]
      end
      result = yield
      assert_current!
      result
    rescue EltenLink::Error => error
      if error.respond_to?(:code) && error.code.to_s == GameRoomServerTables::STAMP_REQUIRED && current?
        @lock.synchronize do
          state, check = latest_check
          # A request already in flight cannot invalidate a newer success.
          @refusal ||= check unless state == :available && [state, check] != confirmed_at_start
        end
      end
      raise
    end

    private

    def latest_check
      tables = @checked_tables.call
      state, generation = tables&.access_snapshot
      [state, [tables, generation]]
    end

    def update_refusal(state, check)
      @refusal = check if state == :stamp_required
      @refusal = nil if state == :available && @refusal != check
    end

    def assert_current!
      raise TablesGateway::ContextChanged, 'Tournament login changed' unless current?
    end
  end
end
