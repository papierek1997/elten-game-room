require_relative 'engine'

module GameRoomPong
  # Each human owns their paddle/returns/misses; only the owner controls bots.
  # A remote return starts incoming flight at the far baseline. Locally owned
  # human/bot exchanges keep the original uninterrupted full-precision flight.
  class PeerEngine < Engine
    def initialize(side:, authority:, **args)
      super(**args)
      @side, @authority = side, authority
    end

    def strike(side, **args)
      return false unless controls_side?(side)
      serving = @ball['dy'].zero?
      return false unless super
      transition(serving ? 'serve' : 'hit', side)
      true
    end

    # The owner alone rolls Arcade effects. Locally controlled bot matches
    # retain their original within-frame order (before the next bot tracks).
    # Keep the result for broadcast; do not consume the RNG a second time.
    def roll_effects(side)
      @pending_effects = host_effects(side) if @authority && !@bots.empty?
    end

    def host_effects(side)
      if @pending_effects && @pending_effects['side'] == side && @pending_effects['turn'] == @turn
        data, @pending_effects = @pending_effects, nil
        return data
      end
      return unless @authority && @arcade && !@goal
      renewal = @rng.rand < 0.07
      invisible = @rng.rand < 0.07
      data = {'action' => 'effects', 'side' => side, 'turn' => @turn,
        'renew' => renewal, 'invisible' => invisible}
      apply_effects(data)
      data
    end

    def apply_effects(data)
      return false unless data['turn'] <= @turn && !@goal
      side = data['side']
      renew_shield(side) if data['renew']
      if data['turn'] == @turn && data['invisible']
        @invisible = true
        cue('invisible', side)
      end
      true
    end

    def apply_return(data)
      return false unless data['turn'] == @turn + 1 && !@goal
      side = data['side']
      return false unless @turn.zero? ? side == @server && data['action'] == 'serve' :
        incoming?(side) && %w[hit shield_hit].include?(data['action'])
      @turn = data['turn']
      @ball.merge!(data['ball'])
      @ball['x'] = @ball['x'].clamp(MIN_X, MAX_X)
      @ball['y'] = @rotation.team(side).zero? ? 0.0 : DEPTH
      @ball['dy'] = @rotation.team(side).zero? ? 1 : -1
      @previous_inbound = Array.new(@paddles.length)
      @invisible = false unless data['action'] == 'shield_hit'
      if data['action'] == 'serve'
        @controllers.each do |other, bot|
          bot.served(self, opening: other != side && !@bots.include?(side))
        end
      end
      cue(data['action'], side)
      true
    end

    def apply_miss(data)
      return false unless data['turn'] == @turn + 1 && !@goal && incoming?(data['side'])
      Engine.instance_method(:miss).bind(self).call(data['side'])
      true
    end

    def wall_sound(x, y)
      append_cue('wall', nil, x, y)
    end

    def remote_paddle(side, x, edges: nil)
      return super unless @bots.include?(side)
      # A bot makes fractional, sometimes deliberately silent moves. Its
      # position packet is not itself a footstep; the owner supplies the cue.
      move_to(side, x, silent: true)
      @edge_attempts[side] = edges if edges
    end

    def remote_bot_sound(kind, side)
      return unless @bots.include?(side) && !controls_side?(side) && %w[step edge].include?(kind)
      append_cue(kind, side, @ball['x'], @ball['y'])
    end

    def serve_timeout(confirmed: false)
      # A direct serve can cross the owner's authoritative deadline in transit.
      # The owner's confirmed timeout wins that race, but cannot override an
      # already exchanged return or be applied twice.
      late_serve = confirmed && @turn == 1 &&
        @ball['dy'] == (@rotation.team(@server).zero? ? 1 : -1)
      return false unless !@goal && ((@turn.zero? && @ball['dy'].zero?) || late_serve)
      @turn = 0
      @transition = nil
      Engine.instance_method(:miss).bind(self).call(@server)
      true
    end

    def take_transition
      value, @transition = @transition, nil
      value
    end

    private

    def controls_side?(side)
      side == @side || (@authority && @bots.include?(side))
    end

    def miss(side)
      super
      transition('goal', side)
    end

    def shield_return(side)
      super
      transition('shield_hit', side)
    end

    def transition(action, side)
      # Original BD/BS/BQ/BX messages encode thousandths, truncating rather
      # than rounding. Local physics keeps its full precision.
      transmitted = @ball.transform_values { |v| v.is_a?(Float) ? (v * 1000).to_i / 1000.0 : v }
      @transition = {'action' => action, 'side' => side, 'turn' => @turn, 'ball' => transmitted}
    end

    def cue(kind, side)
      return if kind == 'wall' && !@authority
      super
    end

    def append_cue(kind, side, x, y)
      @event_seq += 1
      @events << [@event_seq, kind, side, x, y]
      @events.shift while @events.length > 8
    end
  end
end
