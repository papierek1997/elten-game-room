# encoding: UTF-8
require_relative 'specifications'

require_relative '../game_room_localization'

module GameSurfaces
  using GameRoomLocalization::Translations

  class DartsField < Button
    def initialize(label)
      super(label)
      @pending = []
    end

    def update
      super
      return if modifier_held?
      queue(:up) if unmodified_press?(:key_up, 0x26)
      queue(:down) if unmodified_press?(:key_down, 0x28)
      queue(:left) if unmodified_press?(:key_left, 0x25)
      queue(:right) if unmodified_press?(:key_right, 0x27)
      queue(:throw) if unmodified_press?(:key_space, 0x20)
    end

    def take_input
      result, @pending = @pending, []
      result
    end

    def clear_input; @pending.clear; end

    def focus(*arguments, **options)
      clear_input
      super
    end

    def blur
      clear_input
      super if defined?(super)
    end

    def key_processed(key)
      return true if %w[up down left right space].include?(key.to_s.sub(/\Akey_/, ''))
      super
    end

    private

    def queue(command)
      @pending.shift if @pending.length >= 12
      @pending << command
    end

    def modifier_held?
      [0x10, 0x11, 0x12, 0x5b, 0x5c].any? { |code| key_held?(code) }
    end

    def unmodified_press?(name, code)
      return false unless key_pressed?(name)
      return !modifier_held? unless respond_to?(:keyboard_modifier_held_when_pressed?, true)
      ![:shift, :control, :option, :command].any? do |modifier|
        keyboard_modifier_held_when_pressed?(code, modifier)
      end
    end
  end

  class DartsSurface
    include ActionEmitter
    attr_reader :spec
    attr_accessor :on_darts_command

    def _(source); GameRoomContent.utf8(super(source)); end

    def initialize(spec, state: {})
      @spec = spec
      @field = DartsField.new(spec.header)
      @field.add_tip(_('Arrow keys: correct the audio cursor.'))
      @field.add_tip(_('Space: throw after the ready sound.'))
      @field.add_tip(_('The screen reader remains available; ordinary aiming uses positional sounds instead of spoken coordinates.'))
    end

    def fields; [@field]; end
    def state; {}; end
    def reusable_for?(spec); spec.is_a?(DartsSpec) && spec.game_id == @spec.game_id; end
    def update_spec(spec); @spec = spec; self; end

    def input_active?(form)
      return false if form.respond_to?(:game_room_background_help?) && form.game_room_background_help?
      active = form.fields[form.index] == @field
      active &&= $activecontrols.include?(@field) if defined?($activecontrols) && $activecontrols.is_a?(Array)
      active && @spec.active && !@spec.finished
    end

    def input(form)
      input_active?(form) ? @field.take_input : @field.take_input.tap(&:clear)
    end

    def clear_input; @field.clear_input; end

    def handle_command(command, _payload = {})
      case command.to_s
      when 'scores'
        labels = @spec.players.to_a.each_with_index.map do |player, index|
          _('%{player}: %{score}') % {player: player, score: @spec.scores.to_a[index].to_i}
        end
        speak(labels.join('; ') + '.')
      when 'position'
        @on_darts_command&.call('position')
      else
        return false
      end
      true
    end
  end
end
