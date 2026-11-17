# encoding: UTF-8
require_relative 'keyboard'

module GameRoomPong
  # A local Windows input adapter. No hook, window subclass, capture, thread,
  # event pump or change to the host's keyboard handling is needed.
  class WindowsMouse
    def self.supported?; /mswin|mingw/ =~ RUBY_PLATFORM; end

    def initialize(api: nil, window: -> { defined?($wnd) ? $wnd : nil })
      @api, @window = api, window
    end

    def available?
      return false if @failed
      @api ||= Native.new if self.class.supported?
      @api != nil
    rescue StandardError, LoadError
      @failed = true
      false
    end

    def sample
      return nil unless available?
      hwnd = @window.call.to_i
      unless hwnd != 0 && @api.foreground == hwnd && !@api.modified?
        suspend
        return nil
      end
      point, centre = @api.position, @api.centre(hwnd)
      unless point && centre
        suspend
        return nil
      end
      # Re-anchor after activation, resizing or changing monitors. Motion from
      # another application/control must never become a paddle movement.
      fresh = @anchor != centre || @hwnd != hwnd
      @restore ||= point
      previous = fresh ? point : @anchor
      # Only reposition while this exact ELTEN window is still foreground.
      return suspend unless @api.foreground == hwnd && @api.warp(*centre)
      @anchor, @hwnd = centre, hwnd
      delta = fresh ? [0, 0] : [point[0] - previous[0], point[1] - previous[1]]
      delta + [@api.left_down?]
    rescue StandardError
      suspend
      nil
    end

    def suspend(restore: true)
      # Never move the cursor in the application the user has switched to.
      # Nor overwrite mouse motion already made after leaving our playfield.
      if restore && @api && @restore && @hwnd && @api.foreground == @hwnd && @api.position == @anchor
        @api.warp(*@restore)
      end
      nil
    rescue StandardError
      nil
    ensure
      @restore = @anchor = @hwnd = nil
    end

    class Native
      def initialize
        require 'fiddle'
        @dll = Fiddle.dlopen('user32.dll')
        abi = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
        ptr, int = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT
        bind = ->(name, args, result) { Fiddle::Function.new(@dll[name], args, result, abi) }
        @foreground = bind.call('GetForegroundWindow', [], ptr)
        @get_pos = bind.call('GetCursorPos', [ptr], int)
        @set_pos = bind.call('SetCursorPos', [int, int], int)
        @rect = bind.call('GetClientRect', [ptr, ptr], int)
        @screen = bind.call('ClientToScreen', [ptr, ptr], int)
        @key = bind.call('GetAsyncKeyState', [int], Fiddle::TYPE_SHORT)
        @point, @bounds = "\0".b * 8, "\0".b * 16
      end

      def foreground; @foreground.call.to_i; end
      def modified?; [0x10, 0x11, 0x12, 0x5b, 0x5c].any? { |key| (@key.call(key) & 0x8000) != 0 }; end
      def left_down?; (@key.call(0x01) & 0x8000) != 0; end
      def position
        @get_pos.call(@point) != 0 ? @point.unpack('l<2') : nil
      end
      def warp(x, y); @set_pos.call(x, y) != 0; end
      def centre(hwnd)
        return nil if @rect.call(hwnd, @bounds).zero?
        left, top, right, bottom = @bounds.unpack('l<4')
        return nil if right <= left || bottom <= top
        @point.replace([(left + right) / 2, (top + bottom) / 2].pack('l<2'))
        @screen.call(hwnd, @point) != 0 ? @point.unpack('l<2') : nil
      end
    end
  end

  # Behaviour checked against the original audio-mode mouse input bytecode:
  # dx >= 2, abs(dx) > abs(dy) + 1, immediate first/reversed step, then a
  # four-frame delay and one step per three motion frames. Idle grace: 90 ms.
  # Distance/speed of a large mouse sweep never teleports the paddle.
  class MouseControl
    attr_reader :position, :clicks, :clicked

    def initialize(backend: WindowsMouse.new)
      @backend = backend
      @clicks = @motion_sequence = @edges = 0
      @keyboard = KeyboardMovement.new
      suspend
    end

    def sample(active:)
      delta = active ? @backend.sample : nil
      return suspend unless delta
      held = delta[2] == true
      @button_blocked = held unless @active
      @button_blocked = false unless held
      @clicked = held && !@button_held && !@button_blocked
      @clicks += 1 if @clicked
      @button_held = held
      @active = true
      @dx += delta[0]
      @dy += delta[1]
    end

    def active?; @active; end
    def held?; active? && @button_held && !@button_blocked; end
    def reset_rally; @edges = 0; suspend; end

    def step(input, position:, now_ms:)
      unless active?
        @keyboard.sync(input)
        return input
      end
      @position ||= position
      start = @position
      keys = @keyboard.step(input)
      keys.each { |direction| nudge(direction, keyboard: true) }
      # Audio-mode original: keyboard movement, hit, THEN mouse movement.
      # Keyboard priority only belongs to its separate graphical mouse mode.
      before_mouse = @position
      horizontal = @dx.abs >= 2 && @dx.abs > @dy.abs + 1
      idle = !@last_motion || now_ms - @last_motion > 90 || now_ms < @last_motion
      if horizontal
        wanted = @dx < 0 ? -1 : 1
        @last_motion = now_ms
        if wanted != @mouse_dir || idle
          @mouse_dir, @mouse_tick = wanted, 0
          nudge(wanted)
        else
          @mouse_tick += 1
          nudge(wanted) if @mouse_tick > 4 && (@mouse_tick - 4) % 3 == 0
        end
      elsif idle
        @mouse_dir, @mouse_tick = 0, 0
      end
      @motion_sequence += 1
      @stepped = true
      input.merge('paddle' => @position, 'pointer_before' => before_mouse,
        'pointer_seq' => @motion_sequence, 'pointer_edges' => @edges,
        'pointer_start' => start, 'pointer_keys' => keys)
    end

    def finish_frame
      @dx = @dy = 0 if @stepped
      @stepped = false
    end

    def suspend(reset_keyboard: true)
      @backend.suspend
      @active = @stepped = false
      @clicked = @button_held = @button_blocked = false
      @position = @last_motion = nil
      @dx = @dy = @mouse_dir = @mouse_tick = 0
      @keyboard.reset_repeat if reset_keyboard
      nil
    end

    private

    def nudge(direction, keyboard: false)
      next_position = (@position + direction).clamp(1.0, 29.0)
      @edges += 1 if next_position == @position && !keyboard
      @position = next_position
    end
  end
end
