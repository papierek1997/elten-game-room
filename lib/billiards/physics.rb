# frozen_string_literal: true
require_relative 'geometry'
require 'digest'
require 'thread'

module GameRoomBilliards
  Ball = Struct.new(:id, :x, :y, :vx, :vy, :wx, :wy, :wz, :status, keyword_init: true) do
    def initialize(id:, x:, y:, vx: 0.0, vy: 0.0, wx: 0.0, wy: 0.0, wz: 0.0, status: :table)
      super
    end
    def on_table?; status == :table; end
    def speed; Math.hypot(vx, vy); end
  end
  ShotResult = Struct.new(:balls, :events, :duration, :steps, :head_crossings, keyword_init: true)

  class Physics
    class LimitExceeded < StandardError; end
    GRAVITY = 9.81
    SLIDING = 0.2
    ROLLING = 0.015
    BALL_RESTITUTION = 0.94
    RAIL_RESTITUTION = 0.8
    STOP = 0.003
    CACHE_LIMIT = 4 * 1024 * 1024
    @cache, @cache_bytes, @cache_lock = {}, 0, Mutex.new

    # Cache only pure physics, never authentication or move acceptance. Every
    # caller gets a copy; the complete position, geometry and shot form the key.
    def self.simulate(table, balls, shot, accurate: false, cue_id: 0)
      key = Digest::SHA256.digest(Marshal.dump([table, balls, shot, accurate, cue_id]))
      encoded = @cache_lock.synchronize { @cache[key] }
      return Marshal.load(encoded) if encoded
      result = new(table, accurate: accurate).shoot(balls, shot, cue_id: cue_id)
      encoded = Marshal.dump(result).freeze
      @cache_lock.synchronize do
        unless @cache.key?(key) || encoded.bytesize > CACHE_LIMIT
          while @cache.any? && (@cache.length >= 64 || @cache_bytes + encoded.bytesize > CACHE_LIMIT)
            @cache_bytes -= @cache.shift.last.bytesize
          end
          @cache[key] = encoded
          @cache_bytes += encoded.bytesize
        end
      end
      result
    end

    def initialize(table, accurate: false)
      @table, @step = table, 1.0 / (accurate ? 480 : 240)
      @radius = table.radius
      @rail_bounds = table.rails.map do |ax, ay, bx, by, _|
        [[ax, bx].min - @radius, [ax, bx].max + @radius, [ay, by].min - @radius, [ay, by].max + @radius]
      end
    end

    def self.valid_shot?(shot)
      shot.is_a?(Hash) && shot.keys.sort == %w[angle power side top] &&
        shot.values.all? { |v| v.is_a?(Integer) } && shot['angle'].between?(0, 35_999) &&
        shot['power'].between?(1, 1000) && shot['top'].between?(-100, 100) && shot['side'].between?(-100, 100) &&
        shot['top'] ** 2 + shot['side'] ** 2 <= 10_000
    end

    def self.launch_angle(shot)
      shot['angle'] / 100.0 - shot['side'] * 0.012
    end

    def shoot(balls, shot, cue_id: 0)
      raise ArgumentError, 'Invalid billiards shot' unless self.class.valid_shot?(shot)
      @balls = balls.map(&:dup)
      cue = @balls.find { |b| b.id == cue_id && b.on_table? }
      raise ArgumentError, 'Missing cue ball' unless cue
      # A horizontal impulse at the tip offset gives I = 2mr²/5 angular
      # momentum. Squirt is a fixed approximate cue deflection, not random error.
      degrees = self.class.launch_angle(shot)
      dx, dy = Geometry.direction(degrees)
      speed = shot['power'] / 1000.0 * 6.0
      cue.vx, cue.vy = dx * speed, dy * speed
      spin = shot['top'] / 100.0 * speed / @radius * 1.4
      cue.wx, cue.wy = -dy * spin, dx * spin
      cue.wz = -shot['side'] / 100.0 * speed / @radius
      @time, @events, steps, crossings = 0.0, [], 0, []
      @head_crossed = false
      record(:cue, cue, speed: speed)
      loop do
        active = @balls.select { |b| b.on_table? && (b.speed > 0 || Math.hypot(b.wx, b.wy) > 0 || b.wz.abs > 0) }
        break if active.empty?
        if active.all? { |b| b.vx.zero? && b.vy.zero? && b.wx.zero? && b.wy.zero? }
          @time += active.map { |b| b.wz.abs / 9.0 }.max
          active.each { |b| stop(b) }
          break
        end
        raise LimitExceeded, 'Billiards simulation did not settle' if steps >= 50_000 || @time >= 60
        speed = active.map(&:speed).max
        dt = speed > 0 ? [@step, @radius * 0.22 / speed].min : @step
        active.each do |ball|
          old_x, old_y = ball.x, ball.y
          advance(ball, dt)
          track_boundaries(ball, old_x, old_y, @time + dt) if @table.telemetry?
          @head_crossed = true if ball.id == 0 && old_x <= @table.width / 4 && ball.x > @table.width / 4
          if @table.discipline == 'nine' && ball.id != 0 && old_x >= @table.width / 4 && ball.x < @table.width / 4
            crossings << ball.id unless crossings.include?(ball.id)
          end
        end
        @time += dt
        # Iteration also resolves neighbouring contacts in a tightly packed rack.
        3.times do
          @balls.each_with_index do |a, i|
            next unless a.on_table?
            ((i + 1)...@balls.length).each do |j|
              b = @balls[j]
              next if a.vx.zero? && a.vy.zero? && b.vx.zero? && b.vy.zero?
              collide(a, b) if b.on_table? && (a.x - b.x).abs <= @radius * 2 && (a.y - b.y).abs <= @radius * 2
            end
            cushions(a) unless a.vx.zero? && a.vy.zero?
          end
        end
        @balls.each do |ball|
          next unless ball.on_table?
          pocket = @table.pocket_at(ball.x, ball.y)
          if pocket
            record(:pocket, ball, pocket: pocket, speed: ball.speed)
            ball.status = :potted
            stop(ball)
          elsif ball.x < -0.15 || ball.x > @table.width + 0.15 || ball.y < -0.15 || ball.y > @table.height + 0.15
            raise LimitExceeded, 'Ball escaped the table geometry'
          end
        end
        steps += 1
      end
      @balls.each { |b| b.x = b.x.round(9); b.y = b.y.round(9) }
      ShotResult.new(balls: @balls, events: @events, duration: @time.round(6), steps: steps, head_crossings: crossings)
    end

    private

    def track_boundaries(ball, x, y, time)
      {head: @table.head_string, middle: @table.width / 2, baulk: @table.baulk_line}.each do |line, boundary|
        next unless x < boundary && ball.x >= boundary || x > boundary && ball.x <= boundary
        record(:crossing, ball, line: line, direction: ball.x > x ? :right : :left, t: time.round(6))
      end
      return unless @table.discipline == 'carom'
      4.times do |zone|
        if @table.inside_zone?(x, y, zone) && !@table.inside_zone?(ball.x, ball.y, zone)
          record(:zone_exit, ball, zone: zone, t: time.round(6))
        end
      end
    end

    def stop(ball)
      ball.vx = ball.vy = ball.wx = ball.wy = ball.wz = 0.0
    end

    def advance(ball, dt)
      elapsed = dt
      ux, uy = ball.vx - @radius * ball.wy, ball.vy + @radius * ball.wx
      slip = Math.hypot(ux, uy)
      if slip > 1e-8
        sliding_time = [dt, slip / (3.5 * SLIDING * GRAVITY)].min
        ax, ay = -SLIDING * GRAVITY * ux / slip, -SLIDING * GRAVITY * uy / slip
        ball.x += ball.vx * sliding_time + ax * sliding_time ** 2 / 2
        ball.y += ball.vy * sliding_time + ay * sliding_time ** 2 / 2
        ball.vx += ax * sliding_time
        ball.vy += ay * sliding_time
        ball.wx += 2.5 * ay / @radius * sliding_time
        ball.wy -= 2.5 * ax / @radius * sliding_time
        dt -= sliding_time
      end
      if dt > 1e-12
        speed = ball.speed
        if speed > STOP
          duration = [dt, speed / (ROLLING * GRAVITY)].min
          factor = [speed - ROLLING * GRAVITY * duration, 0.0].max / speed
          ball.x += ball.vx * (1 + factor) / 2 * duration
          ball.y += ball.vy * (1 + factor) / 2 * duration
          ball.vx *= factor
          ball.vy *= factor
        else
          ball.vx = ball.vy = 0.0
        end
        ball.wx, ball.wy = -ball.vy / @radius, ball.vx / @radius
      end
      # Vertical spin does not propel a ball on a flat cloth.
      decay = 9.0 * elapsed
      ball.wz = ball.wz > 0 ? [ball.wz - decay, 0.0].max : [ball.wz + decay, 0.0].min
      stop(ball) if ball.speed < STOP && Math.hypot(ball.wx, ball.wy) * @radius < STOP && ball.wz.abs < 0.02
    end

    def collide(a, b)
      dx, dy = b.x - a.x, b.y - a.y
      distance = Math.hypot(dx, dy)
      return if distance > @radius * 2 || distance < 1e-12
      nx, ny = dx / distance, dy / distance
      penetration = @radius * 2 - distance
      if penetration > 0
        a.x -= nx * (penetration / 2 + 1e-10); a.y -= ny * (penetration / 2 + 1e-10)
        b.x += nx * (penetration / 2 + 1e-10); b.y += ny * (penetration / 2 + 1e-10)
      end
      closing = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
      return if closing <= 1e-7
      impulse = (1 + BALL_RESTITUTION) * closing / 2
      tx, ty = -ny, nx
      slip = (b.vx - a.vx) * tx + (b.vy - a.vy) * ty - @radius * (a.wz + b.wz)
      tangential = (slip / 7).clamp(-0.04 * impulse, 0.04 * impulse)
      a.vx += -impulse * nx + tangential * tx; a.vy += -impulse * ny + tangential * ty
      b.vx += impulse * nx - tangential * tx; b.vy += impulse * ny - tangential * ty
      a.wz += 2.5 * tangential / @radius
      b.wz += 2.5 * tangential / @radius
      extra = {b: b.id, speed: closing}
      extra.merge!(bx: b.x.round(6), by: b.y.round(6)) if @table.telemetry?
      extra[:head_crossed] = @head_crossed if %w[eight nine].include?(@table.discipline) && (a.id == 0 || b.id == 0)
      record(:ball, a, **extra)
    end

    def cushions(ball)
      @table.rails.each_with_index do |rail, index|
        min_x, max_x, min_y, max_y = @rail_bounds[index]
        next unless ball.x.between?(min_x, max_x) && ball.y.between?(min_y, max_y)
        distance, px, py = Geometry.distance_to_segment(ball.x, ball.y, rail)
        next if distance >= @radius || distance < 1e-12
        nx, ny = (ball.x - px) / distance, (ball.y - py) / distance
        ball.x += nx * (@radius - distance + 1e-10)
        ball.y += ny * (@radius - distance + 1e-10)
        normal = ball.vx * nx + ball.vy * ny
        next unless normal < -1e-7
        impulse = -(1 + RAIL_RESTITUTION) * normal
        tx, ty = -ny, nx
        slip = ball.vx * tx + ball.vy * ty - ball.wz * @radius
        tangent = (-slip / 3.5).clamp(-0.18 * impulse, 0.18 * impulse)
        ball.vx += impulse * nx + tangent * tx
        ball.vy += impulse * ny + tangent * ty
        ball.wz -= 2.5 * tangent / @radius
        nose = !@table.pockets.empty? && ([px, py] == rail.first(2) || [px, py] == rail[2, 2])
        extra = {}
        if @table.telemetry?
          side = rail.last == :jaw ? {left: px.abs, right: (px - @table.width).abs, bottom: py.abs, top: (py - @table.height).abs}.min_by { |_, distance| distance }.first : rail.last
          extra[:cushion] = side
        end
        record(:rail, ball, rail: nose ? :jaw : rail.last, speed: -normal, **extra)
      end
    end

    def record(kind, ball, **extra)
      raise LimitExceeded, 'Too many billiards contacts' if @events.length >= 4096
      @events << {kind: kind, a: ball.id, t: @time.round(6), x: ball.x.round(6), y: ball.y.round(6)}.merge(extra)
      @events.last[:order] = @events.length - 1 if @table.telemetry?
    end
  end
end
