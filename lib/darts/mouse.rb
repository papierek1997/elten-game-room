# encoding: UTF-8
require_relative '../axel_pong/mouse'

module GameRoomDarts
  # Reuse the audited foreground-window adapter, but translate relative motion
  # into bounded Darts nudges rather than Pong paddle positions.
  class Mouse
    PIXELS_PER_STEP = 12
    MAX_STEPS_PER_FRAME = 3

    def initialize(backend: GameRoomPong::WindowsMouse.new)
      @backend = backend
      suspend
    end

    def sample(active:, capture: active)
      delta = capture ? @backend.sample : nil
      return suspend unless delta

      held = delta[2] == true
      unless active
        @button_blocked = held unless @active
        @button_blocked = false unless held
        @button_held = held
        @active = false
        @x = @y = 0
        return [[], false]
      end
      @button_blocked = held unless @active
      clicked = held && !@button_held && !@button_blocked
      @button_blocked = false unless held
      @button_held = held
      @active = true
      @x += delta[0].to_i
      @y += delta[1].to_i
      commands = []
      horizontal = [@x.abs / PIXELS_PER_STEP, MAX_STEPS_PER_FRAME].min
      vertical = [@y.abs / PIXELS_PER_STEP, MAX_STEPS_PER_FRAME].min
      horizontal.times { commands << (@x.negative? ? :left : :right) }
      vertical.times { commands << (@y.negative? ? :up : :down) }
      @x -= (@x <=> 0) * horizontal * PIXELS_PER_STEP
      @y -= (@y <=> 0) * vertical * PIXELS_PER_STEP
      [commands, clicked]
    end

    def suspend
      @backend.suspend(restore: false) if @backend
      @active = false
      @button_held = @button_blocked = false
      @x = @y = 0
      [[], false]
    end
  end
end
