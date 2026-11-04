require_relative "specifications"
# encoding: UTF-8
require_relative "../game_room_localization"
require_relative 'realtime_information'

module GameSurfaces
  using GameRoomLocalization::Translations


  class PongField < Button
    attr_reader :input
    attr_accessor :on_input_reset
    def initialize(label)
      super(label)
      @press = 0
      @left_press = @right_press = 0
      @left_held = @right_held = false
      @input = { 'move' => 0, 'aim' => 0, 'hit' => false, 'press' => 0,
        'left_press' => 0, 'right_press' => 0 }
    end

    def update
      super
      modified = modifier_held_for_game?
      @press += 1 if unmodified_press?(:key_up, 0x26) || unmodified_press?(:key_space, 0x20)
      @left_press += 1 if !@left_held && unmodified_press?(:key_left, 0x25)
      @right_press += 1 if !@right_held && unmodified_press?(:key_right, 0x27)
      @left_held, @right_held = key_held?(0x25), key_held?(0x27)
      @input = if modified
        { 'move' => 0, 'aim' => 0, 'hit' => false }
      else
        { 'move' => @left_held ? -1 : (@right_held ? 1 : 0),
          'aim' => (@right_held ? 1 : 0) - (@left_held ? 1 : 0),
          'hit' => key_held?(0x26) || key_held?(0x20) }
      end
      @input.merge!('press' => @press, 'left_press' => @left_press, 'right_press' => @right_press)
    end

    def key_processed(key)
      return true if %w[left right up space].include?(key.to_s.sub(/\Akey_/, ''))
      super
    end

    def focus(*args, **options)
      @on_input_reset&.call
      super
    end

    def blur
      @on_input_reset&.call
      super if defined?(super)
    end

    private

    def modifier_held_for_game?
      [0x10, 0x11, 0x12, 0x5B, 0x5C].any? { |code| key_held?(code) }
    end

    def unmodified_press?(key, code)
      return false unless key_pressed?(key)
      # A shortcut can be pressed and released between UI frames. Use the
      # host's press-time modifiers, not only the final held-key snapshot.
      return !modifier_held_for_game? unless respond_to?(:keyboard_modifier_held_when_pressed?, true)
      ![:shift, :control, :option, :command].any? do |modifier|
        keyboard_modifier_held_when_pressed?(code, modifier)
      end
    end
  end

  class PongSurface
    include ActionEmitter
    attr_reader :spec, :snapshot
    attr_accessor :on_pong_command, :on_input_reset, :listening_seat
    def _(source); GameRoomContent.utf8(super(source)); end

    def initialize(spec, state: {})
      @spec = spec
      @field = PongField.new(spec.header)
      @field.on_input_reset = -> { @on_input_reset&.call }
      @field.add_tip(_('Left arrow: move the paddle left.'))
      @field.add_tip(_('Right arrow: move the paddle right.'))
      @field.add_tip(_('Up arrow: serve or return the ball.'))
      @field.add_tip(_('Space: serve or return the ball.'))
      @status = _('Connecting the match.')
    end

    def fields; [@field]; end
    def state; {}; end
    def reusable_for?(spec); spec.is_a?(PongSpec) && spec.game_id == @spec.game_id; end
    def update_spec(spec); @spec = spec; self; end
    def present(snapshot, status); @snapshot, @status = snapshot, status; end

    def input_active?(form)
      return false if form.respond_to?(:game_room_background_help?) && form.game_room_background_help?
      # Only the game field drives the paddle. Arrow keys in chat, history,
      # help, or a different application are not gameplay commands.
      active = form.fields[form.index] == @field
      active &&= $activecontrols.include?(@field) if defined?($activecontrols) && $activecontrols.is_a?(Array)
      active && @spec.viewer != nil && !@spec.finished
    end

    def input(form)
      input_active?(form) ? @field.input : @field.input.merge('move' => 0, 'aim' => 0, 'hit' => false)
    end

    def handle_command(command, _payload = {})
      case command
      when 'echo', 'crowd', 'hurry', 'perspective_first', 'perspective_second', 'perspective_third', 'perspective_fourth'
        @on_pong_command&.call(command)
      when 'scores', 'server', 'position', 'effects'
        speak(RealtimeInformation.pong(command, spec: @spec, snapshot: @snapshot,
          status: @status, listening_seat: @listening_seat))
      end
      true
    end
  end
end
