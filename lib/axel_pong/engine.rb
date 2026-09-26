# encoding: UTF-8
require_relative 'keyboard'
require_relative 'rotation'

module GameRoomPong
  # One original 16 ms simulation frame, without UI, sockets or global clocks.
  # X is shared by both players. Only depth is reversed for side 1.
  class Engine
    STEP = 0.016
    WIDTH = 30.0
    DEPTH = 20.0
    MIN_X = 1.0
    MAX_X = 29.0
    MAX_LATERAL = 0.25
    BASE_SPEED = [0.05, 0.1, 0.15, 0.2, 0.235, 0.323].freeze
    BOT_SPEED = [0.05, 0.1, 0.15, 0.2, 0.253, 0.323].freeze
    BASE_LATERAL = [0.008, 0.02, 0.03, 0.04, 0.047, 0.06].freeze
    BOT_LATERAL = [0.008, 0.02, 0.03, 0.04, 0.051, 0.065].freeze
    WALL = [0.25, 0.30, 0.50, 0.70, 0.85, 0.85].freeze
    INC_MIN = [0.08, 0.08, 0.04, 0.02, 0.02, 0.02].freeze
    INC_MAX = [0.20, 0.15, 0.08, 0.05, 0.05, 0.05].freeze

    attr_reader :paddles, :ball, :tick, :server, :goal, :invisible,
      :shields, :level, :base_speed, :events, :now_ms, :edge_attempts, :rotation, :turn

    def initialize(level: 2, arcade: false, automatic: false, rally: 0, rng: Random.new, bots: [],
        first_server: 0, paddles: nil, shields: nil, guest: nil, movement_feedback: nil, teams: [0, 1])
      raise ArgumentError, 'invalid Pong difficulty' unless (1..6).include?(level)
      @level, @arcade, @rng = level, arcade, rng
      @rotation = Rotation.new(teams: teams, rally: rally, first_server: first_server)
      @turn = 0
      count = @rotation.teams.length
      @automatic = automatic.is_a?(Array) ? automatic.map { |value| value == true } : [automatic == true] * count
      @bots = bots.freeze
      @base_speed = (@bots.empty? ? BASE_SPEED : BOT_SPEED)[level - 1]
      @server = @rotation.server
      @guest = guest
      @paddles = paddles ? paddles.dup : Array.new(count, 15.0)
      @step_distance = movement_feedback ? movement_feedback.fetch(:distance).dup : Array.new(count, 0.0)
      @last_step_ms = movement_feedback ? movement_feedback.fetch(:last_ms).dup : Array.new(count, 0)
      @ball = { 'x' => 15.0, 'y' => @rotation.team(@server).zero? ? 0.0 : DEPTH,
        'speed' => 0.0, 'lateral' => 0.0, 'dx' => 0, 'dy' => 0 }
      @tick = 0
      @keyboard = Array.new(count) { KeyboardMovement.new }
      @last_press = Array.new(count, 0)
      @pointer_seq = Array.new(count, 0)
      @pointer_edges = Array.new(count, 0)
      @edge_attempts = Array.new(count, 0)
      @hit_held = Array.new(count, false)
      @shields = shields ? shields.dup : Array.new(count, 0)
      @shield_fraction = 0.0
      @now_ms = 0
      @controllers = {}
      @inputs = Array.new(count) { {} }
      @control_held = Array.new(count, false)
      @released_at = Array.new(count)
      @previous_inbound = Array.new(count)
      @invisible = false
      @events = []
      @event_seq = 0
      @goal = nil
    end

    def register_bot(side, controller); @controllers[side] = controller; end

    def automatic_for(side, enabled); @automatic[side] = enabled == true; end

    def movement_feedback
      { distance: @step_distance.dup, last_ms: @last_step_ms.dup }
    end

    def step(inputs, now_ms: nil)
      return if @goal
      @tick += 1
      previous_ms = @now_ms
      @now_ms = now_ms || @tick * 16
      @inputs = inputs
      tick_shields([@now_ms - previous_ms, 0].max) unless @ball['dy'].zero?
      # Original order: contact/flight, bot serve, human input, bot tracking,
      # automatic return. A bot cannot move into reach on the contact frame.
      advance_ball
      return if @goal
      @controllers.each_value { |bot| bot.prepare(self) } if @ball['dy'].zero?
      @paddles.each_index do |side|
        next if @bots.include?(side) || !controls_side?(side)
        input = inputs[side] || {}
        pointer_frame = pointer_frame?(side, input)
        if pointer_frame
          pointer_keyboard(side, input)
        else
          move_input(side, input)
        end
        pressed = input.key?('press') ? input['press'] > @last_press[side] : (input['hit'] == true && !@hit_held[side])
        @last_press[side] = input['press'] if input.key?('press')
        @hit_held[side] = input['hit'] == true
        strike(side, aim: input.fetch('aim', input.fetch('move', 0))) if pressed
        finish_pointer_frame(side, input) if pointer_frame
      end
      @controllers.each_value { |bot| bot.track(self) }
      @paddles.each_index do |side|
        # The original remembers release in HandleInput, after ball contact.
        held = control_active?(side)
        @released_at[side] = @now_ms if @control_held[side] && !held
        @control_held[side] = held
        next unless @automatic[side] && !@bots.include?(side) && controls_side?(side) && incoming?(side)
        distance = distance_to(side)
        next if (@ball['x'] - @paddles[side]).abs > [4.0, hit_width(side)].min
        strike(side) if distance < 6 && distance <= [6.0, 1 + @ball['speed'] * 2].min
      end
    end

    # Repositioning remains possible between points, but hits are consumed by
    # the client, not queued until the next serve becomes available.
    def position(inputs, now_ms: nil)
      @now_ms = now_ms if now_ms
      @paddles.each_index do |side|
        move_input(side, inputs[side] || {}) if controls_side?(side) && !@bots.include?(side)
      end
    end

    def move_input(side, input)
      if pointer_frame?(side, input)
        pointer_keyboard(side, input)
        finish_pointer_frame(side, input)
        return
      end
      position = input['paddle']
      if position.is_a?(Numeric) && position.finite? && position.between?(MIN_X, MAX_X)
        # MouseControl already applies original keyboard/mouse repeat cadence.
        # A repeated position packet is idempotent, not another paddle step.
        @keyboard[side].sync(input)
        move_to(side, position)
      else
        @keyboard[side].step(input).each { |direction| move_to(side, @paddles[side] + direction) }
      end
    end

    def pointer_frame?(side, input)
      input['pointer_seq'].is_a?(Integer) && input['pointer_seq'] > @pointer_seq[side] &&
        input['pointer_before'].is_a?(Numeric) && input['pointer_before'].finite? &&
        input['pointer_before'].between?(MIN_X, MAX_X) &&
        input['paddle'].is_a?(Numeric) && input['paddle'].finite? &&
        input['paddle'].between?(MIN_X, MAX_X) &&
        input['pointer_edges'].is_a?(Integer) && input['pointer_edges'] >= 0
    end

    def finish_pointer_frame(side, input)
      @pointer_seq[side] = input['pointer_seq']
      move_to(side, input['paddle'])
      edges = input.fetch('pointer_edges', 0)
      cue('edge', side) if edges > @pointer_edges[side]
      @pointer_edges[side] = edges
    end

    def pointer_keyboard(side, input)
      @keyboard[side].sync(input)
      if input['pointer_keys'].is_a?(Array) && input['pointer_start'].is_a?(Numeric)
        # Preserve both DOWN edges even if their final displacement is zero.
        # This bounded path precedes the click/strike and mouse displacement.
        move_to(side, input['pointer_start'], silent: true)
        input['pointer_keys'].each { |direction| move_to(side, @paddles[side] + direction) }
      end
      move_to(side, input['pointer_before'])
    end

    def move(side, direction)
      move_input(side, 'move' => direction)
    end

    def move_to(side, x, silent: false)
      old = @paddles[side]
      @paddles[side] = x.clamp(MIN_X, MAX_X)
      return if silent
      @step_distance[side] += (@paddles[side] - old).abs
      audible = if @bots.include?(side)
        @step_distance[side] >= 1.0 && @now_ms - @last_step_ms[side] >= 50
      else
        @paddles[side] != old
      end
      if audible
        cue('step', side)
        @last_step_ms[side] = @now_ms
        @step_distance[side] = @bots.include?(side) ? @step_distance[side] - 1.0 : 0.0
      end
      cue('edge', side) if old == @paddles[side] && old != x
    end

    # Original received P: an interior position is a step; either boundary is
    # a border cue. Periodic position packets are NOT additional attempts.
    # Carry the cumulative border counter so a lost packet can recover the
    # latest attempt, without playing a backlog or sounding on every snapshot.
    def remote_paddle(side, x, edges: nil)
      changed = @paddles[side] != x
      attempted = edges && edges > @edge_attempts[side]
      move_to(side, x, silent: true)
      if changed || attempted
        cue([MIN_X, MAX_X].include?(@paddles[side]) ? 'edge' : 'step', side)
      end
      @edge_attempts[side] = edges if edges
    end

    def strike(side, aim: 0, bot: false, lateral_scale: 1.0, force: false)
      return false if @goal
      if @ball['dy'].zero?
        return false unless side == @server
        @ball['x'] = @paddles[side]
        @ball['y'] = @rotation.team(side).zero? ? 0.0 : DEPTH
        @ball['speed'] = @base_speed * 1.2
        @ball['dx'] = aim
        @ball['lateral'] = if aim.zero?
          0.0
        elsif bot
          BOT_LATERAL[@level - 1]
        else
          [MAX_LATERAL, 0.03 + (@paddles[side] - 15).abs * 0.02].min
        end
        @ball['dy'] = @rotation.team(side).zero? ? 1 : -1
        @invisible = false
        @previous_inbound = Array.new(@paddles.length)
        @controllers.each { |other, controller| controller.served(self, opening: other != side && !bot) }
        @turn += 1
        cue('serve', side)
        return true
      end
      return false unless incoming?(side)
      distance = distance_to(side)
      return false unless distance < 6
      delta = @ball['x'] - @paddles[side]
      return false if !bot && !force && delta.abs > hit_width(side)
      @ball['dx'] = delta.abs < (bot ? 0.3 : 0.15) ? 0 : (delta.positive? ? 1 : -1)
      @ball['lateral'] = @ball['dx'].zero? ? 0.0 :
        [MAX_LATERAL * lateral_scale, (0.03 + delta.abs * 0.035 * (bot ? 1 : 1.6)) * lateral_scale].min
      @ball['speed'] += uniform(@base_speed * INC_MIN[@level - 1], @base_speed * INC_MAX[@level - 1])
      @ball['lateral'] += uniform(0.0035, 0.005) * lateral_scale
      @ball['lateral'] = [@ball['lateral'], MAX_LATERAL * lateral_scale].min if bot
      @ball['dy'] = @rotation.team(side).zero? ? 1 : -1
      @previous_inbound[side] = nil
      @turn += 1
      cue('hit', side)
      @invisible = false
      roll_effects(side)
      true
    end

    def roll_effects(side)
      if @arcade
        renew_shield(side) if @rng.rand < 0.07
        if @rng.rand < 0.07
          @invisible = true
          cue('invisible', side)
        end
      end
    end

    def incoming?(side)
      (!@rotation.doubles? || side == @rotation.hitter(@turn)) &&
        @ball['dy'] == (@rotation.team(side).zero? ? -1 : 1)
    end

    def distance_to(side); @rotation.team(side).zero? ? @ball['y'] : DEPTH - @ball['y']; end

    def hit_width(side)
      width = Array(@guest).include?(side) ? 4.5 : 4.0
      return width unless @automatic[side]
      network = !@guest.nil?
      moving = control_active?(side)
      width += 0.35 if network
      width += 0.25 if network && !moving
      width += 0.5 if network && (@ball['x'] <= 2 || @ball['x'] >= WIDTH - 2)
      width += 0.55 if (network || !@bots.empty?) && incoming?(side) && distance_to(side) <= 1.15
      width + release_bonus(side)
    end

    def control_active?(side)
      (@inputs[side] || {}).fetch('move', 0) != 0
    end

    def release_bonus(side)
      released = @released_at[side]
      return 0.0 unless released && incoming?(side) && distance_to(side) <= 1.6
      age = @now_ms - released
      return 0.0 unless age.between?(0, 220)
      0.35 * [1.0 - age / 220.0, ((1.6 - distance_to(side)) / 1.6).clamp(0, 1)].max
    end

    def snapshot
      state = { 'tick' => @tick, 'p' => @paddles.map { |x| x.round(4) },
        'b' => @ball.transform_values { |v| v.is_a?(Float) ? v.round(5) : v },
        'server' => @server, 'goal' => @goal, 'invisible' => @invisible,
        'shields' => @shields.dup, 'edges' => @edge_attempts.dup,
        'fx' => @events.last(8).map(&:dup) }
      state.merge!('teams' => @rotation.teams.dup, 'receiver' => @rotation.receiver) if @rotation.doubles?
      state
    end

    private

    def controls_side?(_side); true; end

    def renew_shield(side)
      @rotation.members(@rotation.team(side)).each { |member| @shields[member] = (10 / STEP).round }
      cue('shield_on', side)
    end

    def tick_shields(elapsed_ms)
      @shield_fraction += elapsed_ms / 16.0
      ticks = @shield_fraction.floor
      @shield_fraction -= ticks
      @shields.each_index do |side|
        next unless @shields[side] > 0
        @shields[side] = [0, @shields[side] - ticks].max
        if @shields[side].zero? && @rotation.members(@rotation.team(side)).all? { |member| @shields[member].zero? }
          cue('shield_off', side)
        end
      end
    end

    def recover_automatic(side)
      return false unless @automatic[side]
      width = hit_width(side)
      dx = (@paddles[side] - @ball['x']).abs
      return strike(side, force: true) if dx <= width
      previous = @previous_inbound[side]
      y = distance_to(side)
      return false unless previous && previous[1] > y && previous[1] >= 1 && y <= 1
      t = (previous[1] - 1) / (previous[1] - y)
      return false unless t.between?(0, 1)
      travel = (@ball['x'] - previous[0]).abs
      x = previous[0] + (@ball['x'] - previous[0]) * t
      sweep = (@paddles[side] - x).abs - width - (travel * 0.35).clamp(0.25, 0.8)
      direct = dx - width
      moving = control_active?(side)
      recently_active = moving || release_bonus(side) > 0
      supported = !@guest.nil? || !@bots.empty?
      border = @paddles[side] <= 1.01 || @paddles[side] >= WIDTH - 1.01
      speed = @ball['speed']
      allowed = sweep <= 0
      if supported
        allowed ||= (x <= 2.4 || x >= WIDTH - 2.4) && sweep <= 0.09 && direct <= 0.35
        allowed ||= speed >= 0.28 && y <= 1.08 && sweep <= 0.14 && direct <= 0.50 && travel >= 0.07 && recently_active
        allowed ||= speed >= 0.34 && y <= 1.02 && sweep <= (border ? 0.24 : 0.20) && direct <= (border ? 0.46 : 0.45) && moving
        allowed ||= border && speed >= 0.26 && y <= 1.02 && travel <= 0.16 && sweep <= 0.8 && direct <= 1.1 && (recently_active || (sweep <= 0.45 && direct <= 0.70))
        allowed ||= !@bots.empty? && y <= 1.02 && sweep <= 0.24 && direct <= 0.52 && recently_active
      end
      return false unless allowed
      @ball['x'] = x.clamp(MIN_X, MAX_X)
      strike(side, force: true)
    end

    def miss(side)
      @turn += 1
      @goal = 1 - @rotation.team(side)
      @ball['dy'] = 0
      @invisible = false
      cue('goal', @goal)
    end

    def shield_return(side)
      @ball['dy'] *= -1
      @ball['y'] = @rotation.team(side).zero? ? 1.0 : DEPTH - 1
      @ball['dx'] = 0
      @ball['lateral'] = 0.0
      @ball['speed'] += uniform(@base_speed * INC_MIN[@level - 1], @base_speed * INC_MAX[@level - 1])
      @turn += 1
      cue('shield_hit', side)
    end

    def advance_ball
      return if @ball['dy'].zero?
      target = @rotation.doubles? ? @rotation.hitter(@turn) : (@ball['dy'].positive? ? 1 : 0)
      distance = distance_to(target)
      boundary = @bots.include?(target) ? distance <= 0 : distance < 1
      if boundary && controls_side?(target)
        if @bots.include?(target)
          @controllers[target]&.contact(self)
          return advance_motion if !incoming?(target)
        else
          return if recover_automatic(target)
          if (@inputs[target] || {})['hit'] && (@ball['x'] - @paddles[target]).abs <= hit_width(target)
            return if strike(target, force: true)
          end
        end
        if @shields[target] > 0
          shield_return(target)
        else
          miss(target)
        end
        return
      end
      advance_motion
    end

    def advance_motion
      return if @ball['dy'].zero?
      target = @rotation.doubles? ? @rotation.hitter(@turn) : (@ball['dy'].positive? ? 1 : 0)
      old = [@ball['x'], distance_to(target)]
      # A remote outgoing ball waits at the far baseline for a return event,
      # but its lateral movement continues, as in the active original code.
      if controls_side?(target) || distance_to(target) > 0
        @ball['y'] += @ball['speed'] * @ball['dy']
      end
      ratio = @ball['speed'] / @base_speed
      scale = ratio > [1.4, 0.115 / @base_speed].max ? [ratio, 2.8].min : 1.0
      lateral = @ball['lateral'] * scale
      lateral = [lateral, scale > 1 ? MAX_LATERAL * 2.8 : MAX_LATERAL].min
      @ball['x'] += lateral * @ball['dx']
      if (@ball['x'] < MIN_X && @ball['dx'] == -1) || (@ball['x'] > MAX_X && @ball['dx'] == 1)
        @ball['dx'] *= -1
        @ball['lateral'] = [@ball['lateral'] * WALL[@level - 1], MAX_LATERAL].min
        cue('wall', nil)
      end
      @ball['lateral'] = [@ball['lateral'] * 0.985, MAX_LATERAL].min unless @ball['dx'].zero?
      @previous_inbound[target] = old
    end

    def cue(kind, side)
      @edge_attempts[side] += 1 if kind == 'edge' && side != nil
      @event_seq += 1
      @events << [@event_seq, kind, side, @ball['x'].round(3), @ball['y'].round(3)]
      @events.shift while @events.length > 8
    end

    def uniform(a, b); a + @rng.rand * (b - a); end
  end
end
