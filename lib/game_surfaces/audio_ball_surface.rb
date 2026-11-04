require_relative "specifications"
require_relative '../audio_ball/keyboard'
require_relative '../audio_ball/rotation'

require_relative "../game_room_localization"
require_relative 'realtime_information'

module GameSurfaces
  using GameRoomLocalization::Translations


  class AudioBallField < Button
    KEYS = GameRoomAudioBall::Keyboard::KEYS

    def initialize(label)
      super(label)
      GameRoomAudioBall::Keyboard.install
      @pending, @blocked, @down = [], [], []
      @defense_changes, @defense_held, @defense_generation = [], [], 0
    end

    def update
      # A passive task can blur the native control, then quietly resume this
      # same field without focus(). Reacquire only when the field is actually
      # updated again; blur/detach still stop capture outside the game field.
      GameRoomAudioBall::Keyboard.activate(self)
      super
      native = respond_to?(:keyboard_modifier_held_when_pressed?, true)
      # Let the host refresh its normal snapshot before reading our metadata.
      key_pressed?(0x26) if native
      frame = GameRoomAudioBall::Keyboard.frame if native
      # held? in the UI may already see a later Windows state than pressed?.
      # Use the same native snapshot for both, not that asynchronous peek.
      down = if frame
        frame.held
      elsif native && defined?(EltenAPI::KeyboardState)
        KEYS.keys.select { |code| EltenAPI::KeyboardState.held?(code) }
      else
        KEYS.keys.select { |code| key_held?(code) }
      end
      if GameRoomAudioBall::Keyboard::MODIFIERS.any? { |code| key_held?(code) }
        @blocked |= down
        reset_defense_input
      else
        defense_blocked = @blocked.dup
        if frame
          presses = frame.equal?(@last_native_frame) ? [] : frame
        else
          candidates = KEYS.keys.select { |code| !@down.include?(code) && key_pressed?(code) }
          presses = candidates.length == 1 ? [[candidates.first, nil, false]] : []
        end
        presses.each do |code, modified, released|
          @blocked.delete(code) if released
          modified = modified_when_pressed?(code) if modified == nil
          next if @blocked.include?(code) || modified
          @pending.shift if @pending.length == GameRoomAudioBall::Keyboard::MAX_PRESSES
          @pending << KEYS.fetch(code)
        end
        changes = if frame
          frame.equal?(@last_native_frame) ? [] : frame.changes
        else
          (@down - down).map { |code| [code, false, false] } +
            presses.map { |code, modified, _| [code, true, modified || modified_when_pressed?(code)] }
        end
        @defense_reset = true if frame && frame.reset
        changes.each do |code, pressed, modified|
          defense_blocked.delete(code) unless pressed
          next if pressed && defense_blocked.include?(code)
          if @defense_changes.length >= GameRoomAudioBall::Keyboard::MAX_CHANGES
            @defense_changes.shift
            @defense_reset = true
          end
          @defense_changes << [code, pressed, modified].freeze
        end
      end
      @blocked &= down
      @defense_held = (down - @blocked).freeze
      @last_native_frame = frame
      @down = down
    end

    def modified_when_pressed?(code)
      return false unless respond_to?(:keyboard_modifier_held_when_pressed?, true)
      [:shift, :control, :option, :command].any? { |modifier| keyboard_modifier_held_when_pressed?(code, modifier) }
    end

    def take_input
      pending, @pending = @pending, []
      pending
    end

    def take_defense_input
      result = {changes: @defense_changes.freeze, held: @defense_held,
        generation: @defense_generation, reset: !!@defense_reset}.freeze
      @defense_changes, @defense_reset = [], false
      result
    end

    def reset_defense_input
      @defense_changes, @defense_held = [], []
      @defense_generation += 1
      @defense_reset = true
    end

    def clear_input
      @pending.clear
      reset_defense_input
      @blocked = KEYS.keys.select { |code| key_held?(code) }
      @down = @blocked.dup
      @last_native_frame = GameRoomAudioBall::Keyboard.frame
    end

    def focus(*args, **options)
      GameRoomAudioBall::Keyboard.activate(self)
      clear_input
      super
    end

    def blur
      deactivate_input
      super if defined?(super)
    end

    def deactivate_input
      @pending.clear
      reset_defense_input
      GameRoomAudioBall::Keyboard.deactivate(self)
    end

    def key_processed(key)
      return true if %w[up left down right w d s a].include?(key.to_s.sub(/\Akey_/, ''))
      super
    end
  end

  class AudioBallSurface
    include ActionEmitter
    attr_reader :spec, :snapshot, :defense_input
    attr_accessor :on_audio_ball_command

    def _(source); GameRoomContent.utf8(super(source)); end

    def initialize(spec, state: {})
      @spec = spec
      @field = AudioBallField.new(spec.header)
      @field.add_tip(_('Up arrow: choose a defence against the first shot type, or play that shot after preparing.'))
      @field.add_tip(_('W: choose a defence against the first shot type, or play that shot after preparing.'))
      @field.add_tip(_('Left arrow: choose a defence against the second shot type, or play that shot after preparing.'))
      @field.add_tip(_('D: choose a defence against the second shot type, or play that shot after preparing.'))
      @field.add_tip(_('Down arrow: choose a defence against the third shot type, or play that shot after preparing.'))
      @field.add_tip(_('S: choose a defence against the third shot type, or play that shot after preparing.'))
      @field.add_tip(_('Right arrow: prepare a shot while holding the ball before a serve or after a defence.'))
      @field.add_tip(_('A: prepare a shot while holding the ball before a serve or after a defence.'))
      @status = _('Connecting the match.')
    end

    def fields; [@field]; end
    def state; {}; end
    def reusable_for?(spec); spec.is_a?(AudioBallSpec) && spec.game_id == @spec.game_id; end
    def update_spec(spec); @spec = spec; self; end
    def present(snapshot, status); @snapshot, @status = snapshot, status; end

    def handle_command(command, _payload = {})
      case command
      when 'hurry'
        @on_audio_ball_command&.call(command)
      when 'scores', 'server'
        speak(RealtimeInformation.audio_ball(command, spec: @spec, snapshot: @snapshot, status: @status))
      else
        return false
      end
      true
    end

    def input_selected?(form)
      return false if form.respond_to?(:game_room_background_help?) && form.game_room_background_help?

      form.fields[form.index] == @field && @spec.viewer != nil && !@spec.finished
    end

    def input_active?(form)
      active = input_selected?(form)
      active &&= $activecontrols.include?(@field) if defined?($activecontrols) && $activecontrols.is_a?(Array)
      active
    end

    def input(form)
      actions = @field.take_input
      defense = @field.take_defense_input
      active = input_active?(form)
      @defense_input = active ? defense : nil
      active ? actions : []
    end

    def clear_input
      @field.clear_input
    end

    def activate_input
      GameRoomAudioBall::Keyboard.activate(@field)
    end

    def deactivate_input
      @field.deactivate_input
    end
  end
end
