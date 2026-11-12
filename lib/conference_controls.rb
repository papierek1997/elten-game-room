require_relative 'game_room_localization'
require_relative 'game_room_key_modifiers'

# Local controls for the native Conference, with no second audio/mute state.
module GameRoomConferenceControls
  using GameRoomLocalization::Translations
  module_function

  def connected?
    defined?(Conference) && Conference.opened? && Conference.channel&.id.to_i.positive?
  end

  def microphone_label
    Conference.muted ? _("Unmute microphone") : _("Mute microphone")
  end

  def toggle_microphone
    unless connected?
      speak(_("You are not connected to a voice conversation."))
      return false
    end
    Conference.muted = !Conference.muted
    speak(Conference.muted ? _("Microphone muted") : _("Microphone unmuted"))
    true
  end

  def build_space
    field = Static.new(_("Channel space"))
    field.add_tip(_("Use the arrow keys to move around the channel space"))
    field.add_tip(_("Use Shift+Left/Right Arrow to rotate"))
    {key_left: [-1, 0], key_right: [1, 0], key_up: [0, -1], key_down: [0, 1]}.each do |key, (x, y)|
      field.on(key) do
        next unless connected?
        play_sound('listbox_focus')
        if y.zero? && GameRoomUI.modifiers_when_pressed(field, key).include?(:shift)
          Conference.turn(x * 45)
        else
          Conference.move(x, y)
        end
      end
    end
    field.bind_context do |menu|
      next unless connected?
      menu.option(_("Read current position"), nil, :q) do
        speak(Conference.get_coordinates.map(&:to_s).join(', ')) if connected?
      end
      menu.option(_("Read channel size"), nil, :e) do
        speak([Conference.channel.width, Conference.channel.height].join(', ')) if connected?
      end
    end
    field
  end
end
