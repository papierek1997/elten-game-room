# One server read followed by monotonic elapsed time. Changing the OS clock
# or time zone during a race cannot change elapsed time or the daily date.
class GameRoomServerClock
  def initialize(fetch:, monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @fetch, @monotonic = fetch, monotonic
  end

  def synchronize
    stamp = @fetch.call
    raise "Invalid server time" unless stamp.is_a?(Time)
    @epoch, @origin = stamp.to_f, @monotonic.call
    self
  end

  def now
    raise "Server clock has not been synchronized" unless @epoch
    @epoch + @monotonic.call - @origin
  end
end
