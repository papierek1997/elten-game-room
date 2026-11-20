module GameRoomTest
  # Explicit access evidence for UI-only fixtures. It is not a table backend:
  # a test which unexpectedly performs table I/O must still fail.
  class ServerTableAccess
    attr_accessor :access_state, :last_error

    def initialize(state)
      raise ArgumentError, 'Unknown access state' unless [:unchecked, :available, :stamp_required, :unavailable].include?(state)
      @access_state = state
    end

    def available?; access_state == :available; end
    def stamp_required?; access_state == :stamp_required; end
    def fetch(name); raise "Unexpected table read in UI fixture: #{name}"; end
  end
end
