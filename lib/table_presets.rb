require "json"
require_relative "game_content"

# Local configurations, never game/session state or credentials. A preset is
# checked against the current game's options before it can create a table.
require_relative "game_room_localization"

module GameRoomTablePresets
  using GameRoomLocalization::Translations
  KEYS = %w[1 2 3 4 5 6 7 8 9 0].freeze
  MODIFIERS = %i[control option shift].freeze
  BINDINGS = MODIFIERS.flat_map { |modifier| KEYS.map { |key| [key, modifier].freeze } }.freeze
  COUNT = BINDINGS.length
  module_function

  def slots(values)
    source = values.is_a?(Array) ? values : []
    Array.new(COUNT) do |index|
      value = source[index]
      value.is_a?(Hash) ? JSON.parse(JSON.generate(value)) : nil
    end
  end

  def build(game, configuration, name: nil)
    options = game.new_game_options(configuration.fetch(:game_options))
    {"game" => game.id, "name" => GameRoomContent.utf8(name || game.name).strip,
      "options" => options,
      "private_table" => configuration.fetch(:private_table) == true || game.private_table_required?(options)}
  end

  def valid?(entry, game)
    return false unless entry.is_a?(Hash) && game && entry["game"] == game.id
    return false unless entry["options"].is_a?(Hash) && [true, false].include?(entry["private_table"])
    options = game.new_game_options(entry["options"])
    options == entry["options"] && game.validation_error(options) == nil
  rescue ArgumentError, TypeError, NoMethodError
    false
  end

  def label(index, entry)
    "#{shortcut(index)}: #{title(entry)}"
  end

  def title(entry)
    title = entry && GameRoomContent.utf8(entry["name"]).strip
    title = GameRoomContent.utf8(entry["game"]) if entry && title.empty?
    title = GameRoomContent.utf8(_("Not assigned")) unless entry
    title
  end

  def shortcut(index)
    key, modifier = BINDINGS.fetch(index)
    "#{ {control: 'Ctrl', option: 'Alt', shift: 'Shift'}.fetch(modifier) }+#{key}"
  end

  def pressed?(control, key, modifier)
    return control.send(:main_shortcut_pressed?, key, first: true) if modifier == :control
    return false unless control.respond_to?(:keyboard_binding_pressed?, true)
    code, = control.send(:keyboard_code, key)
    control.send(:keyboard_binding_pressed?, [code, modifier], first: true)
  end

  def pressed_slot(control)
    BINDINGS.index { |key, modifier| pressed?(control, key, modifier) }
  end

  def consume_key(control)
    control.send(:getkeychar) if control.respond_to?(:getkeychar, true)
    EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
  end
end
