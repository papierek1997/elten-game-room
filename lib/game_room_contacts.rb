require_relative "game_room_background"
require_relative "network_errors"

module GameRoomContacts
  # All callers, including the widget worker, share one finite network read.
  # The mutex protects memory only; it is never held by the network operation.
  class Cache
    TTL = 60.0
    attr_reader :user

    def initialize(user:, loader:, runtime: nil, worker: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @user, @loader, @clock = user.to_s.strip.downcase, loader, clock
      @worker = worker || GameRoomBackground::Work.new(runtime: runtime)
      @lock = Mutex.new
      @contacts, @loaded_at, @retry_at, @revision = nil, nil, 0.0, 0
    end

    def snapshot(force: false)
      @lock.synchronize do
        collect
        if !@user.empty? && !@worker.closed? && !@worker.busy? && @clock.call >= @retry_at &&
            (force || @forced || @loaded_at == nil || @clock.call - @loaded_at >= TTL)
          @forced = true if force
          GameRoomBackground.admit(@worker) do
            values = @loader.call
            raise TypeError, "Invalid contact list" unless values.is_a?(Array)
            values.each_with_object({}) { |name, set| set[name.to_s.strip.downcase] = true unless name.to_s.strip.empty? }.freeze
          end
        end
        @forced ? nil : @contacts
      end
    end

    def include?(name)
      contacts = snapshot
      contacts == nil ? nil : contacts.key?(name.to_s.strip.downcase)
    end

    # The existing extension tick drains completions, but does not poll contacts.
    def revision
      @lock.synchronize { collect; @revision }
    end

    def close
      @lock.synchronize { @worker.close; @contacts = nil }
    end

    private

    def collect
      return if @worker.closed?
      result = @worker.take
      return unless result
      contacts, error = result
      @forced = false
      if error
        @retry_at = @clock.call + GameRoomNetworkErrors.retry_delay(error, normal: 15.0, rate_limit: 60.0)
        Log.warning("Game Room contacts could not be loaded: #{error.class}") if defined?(Log)
      else
        @revision += 1 if @contacts != contacts
        @contacts, @loaded_at, @retry_at = contacts, @clock.call, 0.0
      end
    end
  end

  # Only live receipts are deferred, never mapping/list/history reads.
  class Pending
    LIMIT = 256
    EMPTY_ENTRIES = [].freeze

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock, @entries, @settled = clock, {}, {}
    end

    def key(notification)
      [notification.app_uuid.to_s.downcase, notification.id.to_i]
    end

    def settled?(notification)
      trim
      @settled.key?(key(notification))
    end

    def add(notification, active: false)
      trim
      return if notification.id.to_i <= 0 || settled?(notification)
      @entries[key(notification)] ||= [notification, @clock.call + 300, active]
      @entries.shift while @entries.size > LIMIT
    end

    def entries
      trim
      return EMPTY_ENTRIES if @entries.empty?
      @entries.values
    end

    def finish(notification)
      @entries.delete(key(notification))
      @settled[key(notification)] = @clock.call + 300
      @settled.shift while @settled.size > LIMIT
    end

    private

    def trim
      now = @clock.call
      @entries.delete_if { |_key, entry| entry[1] <= now }
      @settled.delete_if { |_key, expiry| expiry <= now }
    end
  end
end
