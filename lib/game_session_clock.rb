# Translate the host's already received server time to the founder's game
# epoch. No HTTP, no clock tolerance and no change to saved/wire timestamps.
require_relative "game_room_clock"

class GameRoomSessionClock
  MAX_EVENT_TIME = (2**63 - 1)

  def self.valid_event_time?(value)
    value.is_a?(Integer) && value.between?(0, MAX_EVENT_TIME)
  end

  # Only validated archives provide this logical timestamp. Keep raw server
  # created_at intact; a later restored epoch must not translate it again.
  def self.archived_event(event)
    projected = event.reject { |key, _| key == '__game_time' || key == '__clock_offset' }
    if event.key?('game_time')
      raise ArgumentError, 'Invalid archived event time' unless valid_event_time?(event['game_time'])
      projected['__game_time'] = event['game_time']
    end
    projected
  end

  def self.attach(state, session)
    state[:clock_epoch_offset] = session["__server_started_at"].to_i > 0 && session["created_at"].to_i > 0 ?
      session["created_at"].to_i - session["__server_started_at"].to_i : 0
    state[:clock_offset] = session["__clock_offset"].to_i
    state[:frozen_at] = session["__frozen_at"]
    if session['__round_pause_released'] == true
      state[:round_pause_released] = true
    else
      state.delete(:round_pause_released)
    end
    state
  end

  def self.for_state(state)
    (state[:frozen_at] || GameRoomClock.now).to_f + state[:clock_epoch_offset].to_i - state[:clock_offset].to_i
  end
  def self.from_server(session, time, event: nil)
    archived = event&.fetch('__game_time', nil)
    return archived if valid_event_time?(archived)
    started = session["__server_started_at"].to_i
    epoch = session["created_at"].to_i
    shift = started.positive? && epoch.positive? ? epoch - started : 0
    # A later pause must not move an earlier question/deal backwards in time.
    # Native projections attach the offset accepted at this event's position.
    # Calls without an event translate the current clock (e.g. saving a game).
    offset = event&.fetch('__clock_offset', nil)
    offset = session['__clock_offset'] if offset == nil
    (time + shift - offset.to_i).to_i
  end

  def initialize(sample: -> { GameRoomClock.now if GameRoomClock.synchronized? },
    elapsed: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, wall: -> { GameRoomClock.now })
    @sample, @elapsed, @wall = sample, elapsed, wall
    @lock = Mutex.new
  end

  def now(session)
    now_f(session).to_i
  end

  # Opt-in precision for time-scored games. Existing games keep integer time.
  def now_f(session)
    @lock.synchronize do
      tick = refresh
      offset = session["__clock_offset"].to_i
      frozen = session["__frozen_at"]
      started = session["__server_started_at"].to_i
      if @server_anchor && started.positive? && session["created_at"].to_i.positive?
        current = frozen || (@server_anchor.first + tick - @server_anchor.last)
        current.to_f + session["created_at"].to_i - started - offset
      else
        # Offline/old repository compatibility, still immune to wall-clock
        # changes while the screen is open. The encoder enforces causal time.
        (frozen || (@local_anchor.first + tick - @local_anchor.last)).to_f - offset
      end
    end
  end

  # A push acknowledgement may contain only its sequence number. Until the
  # native metadata arrives, estimate a clock boundary in server time, never
  # label the founder's local wall time as an authoritative server timestamp.
  def server_now
    @lock.synchronize do
      tick = refresh
      anchor = @server_anchor || @local_anchor
      (anchor.first + tick - anchor.last).to_i
    end
  end

  private

  def refresh
    tick = @elapsed.call.to_f
    sample = @sample.call.to_f
    if sample.positive? && sample != @last_sample
      @server_anchor = [sample, tick]
      @last_sample = sample
    end
    @local_anchor ||= [@wall.call.to_f, tick]
    tick
  end
end
