# encoding: UTF-8
require 'digest'
require_relative 'scoring'

module GameRoomDarts
  # Local aiming physics. Only the final bounded coordinate and active time are
  # published; replay never depends on frame rate or a private input trace.
  class Engine
    LOCK_SECONDS = 1.0
    DEADLINE_WARNING_SECONDS = 3
    STEP_SECONDS = 0.02
    MAX_CATCH_UP_STEPS = 600
    START_RADIUS_MIN = 650.0
    START_RADIUS_MAX = 800.0
    PROFILES = {
      'easy' => {step: 78.0, jitter: 5.0, hold: 0.45, drift: 31.0},
      'normal' => {step: 82.0, jitter: 12.0, hold: 0.25, drift: 47.0},
      'hard' => {step: 86.0, jitter: 22.0, hold: 0.10, drift: 67.0}
    }.freeze

    attr_reader :x, :y, :throw_index, :started_at, :ready_at, :difficulty,
      :last_nudge_blocked

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
    end

    def reset(seed:, throw_index:, difficulty:, time_limit:, timeout_result:)
      @throw_index = Integer(throw_index)
      @difficulty = PROFILES.key?(difficulty.to_s) ? difficulty.to_s : 'normal'
      @profile = PROFILES.fetch(@difficulty)
      @time_limit = Integer(time_limit)
      @timeout_result = timeout_result.to_s == 'zero' ? 'zero' : 'auto'
      material = "#{seed}:#{@throw_index}:darts"
      @random = Random.new(Digest::SHA256.hexdigest(material)[0, 16].to_i(16))
      @heading = @random.rand * Math::PI * 2
      start_radius = START_RADIUS_MIN + @random.rand * (START_RADIUS_MAX - START_RADIUS_MIN)
      @x = Math.cos(@heading) * start_radius
      @y = Math.sin(@heading) * start_radius
      @started_at = @clock.call.to_f
      @ready_at = @started_at + LOCK_SECONDS
      @last_step = @started_at
      @stable_until = @started_at
      @inward_until = 0.0
      @finished = false
      @last_nudge_blocked = false
      self
    end

    def ready?(now = @clock.call)
      !@finished && now.to_f >= @ready_at
    end

    def finished?; @finished == true; end

    def active_time_ms(now = @clock.call)
      [[((now.to_f - @ready_at) * 1_000).round, 0].max, maximum_active_ms].min
    end

    def maximum_active_ms
      @time_limit.positive? ? @time_limit * 1_000 : 600_000
    end

    def timed_out?(now = @clock.call)
      @time_limit.positive? && now.to_f >= @ready_at + @time_limit
    end

    def deadline_warning(now = @clock.call)
      return nil unless @time_limit.positive? && ready?(now)

      remaining = @ready_at + @time_limit - now.to_f
      return nil unless remaining.positive? && remaining <= DEADLINE_WARNING_SECONDS

      remaining.ceil.clamp(1, DEADLINE_WARNING_SECONDS)
    end

    def step(now = @clock.call)
      return self if @finished
      now = now.to_f
      steps = [((now - @last_step) / STEP_SECONDS).floor, MAX_CATCH_UP_STEPS].min
      steps.times do
        @last_step += STEP_SECONDS
        drift_step(@last_step) if @last_step >= @stable_until
      end
      # A long covered interval may exceed the catch-up budget. The timeout is
      # authoritative; skip stale cosmetic frames instead of burning the CPU.
      @last_step = now if steps == MAX_CATCH_UP_STEPS && @last_step < now - STEP_SECONDS
      self
    end

    def nudge(dx, dy, now = @clock.call)
      @last_nudge_blocked = false
      return false if @finished
      dx, dy = dx.to_i.clamp(-1, 1), dy.to_i.clamp(-1, 1)
      return false if dx.zero? && dy.zero?

      before_x, before_y = @x, @y
      magnitude = @profile[:step] + random_signed(@profile[:jitter])
      diagonal = !dx.zero? && !dy.zero? ? Math.sqrt(0.5) : 1.0
      @x = (@x + dx * magnitude * diagonal).clamp(-Scoring::BOARD_LIMIT.to_f, Scoring::BOARD_LIMIT.to_f)
      @y = (@y + dy * magnitude * diagonal).clamp(-Scoring::BOARD_LIMIT.to_f, Scoring::BOARD_LIMIT.to_f)
      @last_nudge_blocked = (!dx.zero? && @x == before_x) || (!dy.zero? && @y == before_y)
      @stable_until = now.to_f + @profile[:hold]
      true
    end

    def finish(now = @clock.call, automatic: false)
      return nil if @finished || (!automatic && !ready?(now))
      step(now)
      @finished = true
      x, y = @x.round, @y.round
      x = y = Scoring::BOARD_LIMIT if automatic && @timeout_result == 'zero'
      {
        index: @throw_index,
        x: x,
        y: y,
        time_ms: active_time_ms(now),
        automatic: automatic == true
      }
    end

    def position
      [@x, @y]
    end

    private

    def drift_step(now)
      radius = Math.sqrt(@x * @x + @y * @y)
      if radius > 1.0
        radial = Math.atan2(@y, @x)
      else
        radial = @heading
      end
      @inward_until = now + 0.12 + @random.rand * 0.20 if now >= @inward_until && @random.rand < 0.005
      direction = now < @inward_until ? -1.0 : 1.0
      lateral = random_signed(0.85)
      # The inner high-value zones move faster, but the outward component is
      # never perfectly straight and occasional brief reversals stay possible.
      centre_factor = 1.0 + 0.9 * (1.0 - [radius / Scoring::BOARD_LIMIT, 1.0].min)
      distance = @profile[:drift] * centre_factor * STEP_SECONDS
      @x += Math.cos(radial) * distance * direction + Math.cos(radial + Math::PI / 2) * distance * lateral
      @y += Math.sin(radial) * distance * direction + Math.sin(radial + Math::PI / 2) * distance * lateral
      @x = @x.clamp(-Scoring::BOARD_LIMIT.to_f, Scoring::BOARD_LIMIT.to_f)
      @y = @y.clamp(-Scoring::BOARD_LIMIT.to_f, Scoring::BOARD_LIMIT.to_f)
    end

    def random_signed(scale)
      (@random.rand * 2.0 - 1.0) * scale
    end
  end
end
