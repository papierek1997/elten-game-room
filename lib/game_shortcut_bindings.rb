require_relative 'game_room_localization'
require_relative 'game_room_key_modifiers'

# One source for validation, key matching and game-field help. It does not
# know a session or submit moves; the screen supplies key consumption/action.
module GameRoomShortcutBindings
  using GameRoomLocalization::Translations
  def self.normalize(shortcuts)
    result = shortcuts.to_a
    if result.any? { |shortcut| !shortcut.is_a?(GameRoomGames::GameShortcut) }
      raise ArgumentError, "a game shortcut must be a GameShortcut"
    end
    keys = result.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
    raise ArgumentError, "game shortcut keys must be unique" if keys.uniq.length != keys.length

    result
  end

  def self.bind(form, fields, shortcuts, consume:, &handler)
    form.game_shortcut_fields = fields.dup if form.respond_to?(:game_shortcut_fields=)
    shortcut_by_key = shortcuts.group_by(&:key)
    shortcut_signatures = shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
    shortcut_keys = shortcut_by_key.keys
    form.game_named_shortcut_keys = shortcut_keys if form.respond_to?(:game_named_shortcut_keys=)
    if shortcut_signatures.uniq.length != shortcut_signatures.length
      raise ArgumentError, "game shortcut combinations must be unique"
    end
    fields.each do |field|
      if field.respond_to?(:game_shortcut_signatures=)
        field.game_shortcut_signatures = shortcut_signatures
      elsif field.respond_to?(:game_shortcut_keys=)
        field.game_shortcut_keys = shortcut_keys
      end
    end
    tips = shortcuts.map do |shortcut|
      GameRoomContextHelp.shortcut_tip(key_label(shortcut), shortcut.label)
    end
    GameRoomContextHelp.replace(fields, tips, source: :game)
    if form.respond_to?(:game_shortcut_signatures=)
      form.game_shortcut_signatures = shortcut_signatures
    elsif form.respond_to?(:game_shortcut_keys=)
      form.game_shortcut_keys = shortcut_keys
    end
    shortcut_by_key.each do |key, candidates|
      form.on(("key_" + key).to_sym) do
        modifiers = GameRoomUI.modifiers_when_pressed(form, key.to_sym)
        shortcut = candidates.find { |candidate| candidate.modifiers.to_a.sort == modifiers }
        next if shortcut == nil

        consume.call(key)
        handler.call(shortcut)
      end
    end
  end

  def self.key_label(shortcut)
    modifiers = shortcut.modifiers.to_a
    shifted_character = if modifiers.include?(:shift)
      GameSurfaces::SHIFTED_DIGIT_CHARACTERS[shortcut.key.to_s]
    end
    key = shifted_character || case shortcut.key.to_s
    when 'space' then _("Space")
    when 'semicolon' then ';'
    when 'comma' then ','
    else shortcut.key.to_s.upcase
    end
    prefixes = []
    prefixes << _("Ctrl") if modifiers.include?(:control)
    prefixes << _("Alt") if modifiers.include?(:alt)
    prefixes << _("Shift") if modifiers.include?(:shift) && shifted_character == nil
    (prefixes + [key]).join("+")
  end

end
