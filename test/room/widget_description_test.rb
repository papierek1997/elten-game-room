require_relative '../support/widget_presets'
require_relative '../support/localization'

GameRoomTestLocalization.use_language('pl')
app = EltenGameRoom.allocate
app.define_singleton_method(:initialize_services) {}
app.define_singleton_method(:widget_active?) { true }
app.define_singleton_method(:game_room_settings) { {'table_presets' => []} }
widget = app.send(:build_widget_control)
active = true
widget.instance_variable_set(:@active, -> { active })
widget.instance_variable_set(:@loader, -> { raise 'Description fetched table data' })
widget.instance_variable_set(:@opener, ->(*) { raise 'Description joined a table' })
widget.instance_variable_set(:@refresh_at, Float::INFINITY)
snapshots = %w[farkle uno].map { |id| WidgetSnapshot.new(table: {'game' => id}) }
widget.instance_variable_set(:@snapshots, snapshots)
widget.options = ['Farkle, Alice', 'UNO, Bob']
widget.index = 0
widget.extend(EltenAPI::UI)
first, pressed, modifiers = true, 'o', [:control]
consumed = 0
widget.define_singleton_method(:keyboard_code) { |key| [key.to_s.upcase.ord, false] }
widget.define_singleton_method(:raw_key_first_pressed?) { |key| first && key == pressed.upcase.ord }
widget.define_singleton_method(:raw_key_pressed?) { |key| key == pressed.upcase.ord }
widget.define_singleton_method(:keyboard_modifier_held_when_pressed?) { |_, modifier| modifiers.include?(modifier) }
widget.define_singleton_method(:key_pressed?) { |_| false }
widget.define_singleton_method(:getkeychar) { consumed += 1; '' }

$spoken_messages.clear
widget.update
assert($spoken_messages == [app.send(:game_lobby_label, 'farkle')], 'Ctrl+O did not describe selected game exactly once')
assert(consumed == 1 && widget.index == 0, 'Ctrl+O reached list search or moved focus')
first = false
20.times { widget.update }
assert($spoken_messages.length == 1, 'Held Ctrl+O repeats the description')
first = true
[[], [:shift], [:control, :shift], [:control, :option]].each do |held|
  modifiers = held
  widget.update
end
assert($spoken_messages.length == 1, 'Other modifiers activated Ctrl+O')

menu = FakeMenu.new
widget.context(menu, false)
item = menu.options.find { |row| row.first == 'Opis gry' }
assert(item && item[2] == 'o', 'Context menu does not expose the real shortcut')
assert(widget.get_tips.any? { |tip| tip.include?('Ctrl+O') && tip.include?('Opis gry') }, 'F1 lacks description shortcut')
widget.index = 1
item.last.call
assert($spoken_messages.last == app.send(:game_lobby_label, 'uno'), 'Context menu cached the previous table')
assert(widget.options == ['Farkle, Alice', 'UNO, Bob'], 'Widget rows now contain automatic descriptions')

count = $spoken_messages.length
modifiers = [:control]
active = false
widget.update
item.last.call
assert($spoken_messages.length == count, 'Description speaks outside the widget')
active = true
widget.instance_variable_set(:@snapshots, [])
widget.update
item.last.call
assert($spoken_messages.length == count, 'Empty widget reads a stale game')
widget.instance_variable_set(:@snapshots, snapshots)
[:@entry_refresh, :@creating].each do |guard|
  widget.instance_variable_set(guard, true)
  widget.update
  item.last.call
  assert($spoken_messages.length == count, 'Description interrupts entry or a modal operation')
  widget.instance_variable_set(guard, false)
end
global = FakeMenu.new
widget.context(global, true)
assert(global.options.empty?, 'Widget description became a global ELTEN shortcut')
widget.close
item.last.call
assert($spoken_messages.length == count, 'Closed widget still speaks')
puts 'PASS widget Ctrl+O: native modifier/first-press handling, current selection, context menu/help, empty/hidden/busy/closed states and no I/O'
