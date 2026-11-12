# No Form dependency: history's data model is also used by headless executors.
# Resolve input only when a native control asks about an actual key event.
module GameRoomUI
  # Form events carry the modifiers held at dispatch, which may already differ
  # from the key press within the same frame. Keep matching and text-field
  # gating on one press snapshot; reading it never consumes the native input.
  def self.modifiers_when_pressed(control, key, include_insert: false)
    name = key.to_s.sub(/\Akey_/, '')
    code = case name
    when 'comma', ',', '<' then 0xbc
    when 'period', '.', '>' then 0xbe
    when 'semicolon', ';', ':' then 0xba
    else
      resolved = key.is_a?(Integer) ? key : name.to_sym
      EltenAPI::KeyboardScheme.key_code(resolved) || control.__send__(:keyboard_code, resolved).first
    end
    raise ArgumentError, "unknown shortcut key: #{key}" if code == nil || code == 0

    modifiers = []
    modifiers << :shift if control.__send__(:keyboard_modifier_held_when_pressed?, code, :shift)
    modifiers << :control if control.__send__(:keyboard_modifier_held_when_pressed?, code, EltenAPI::KeyboardScheme.main_modifier)
    modifiers << :alt if control.__send__(:keyboard_modifier_held_when_pressed?, code, :option)
    if include_insert
      state = EltenAPI::KeyboardState.state_when_pressed(code)
      inserted = state ? state[0x2d] == true : control.__send__(:raw_key_held?, :key_insert)
      modifiers << :insert if inserted
    end
    modifiers.sort
  end
end
