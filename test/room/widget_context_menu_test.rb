require_relative '../support/widget_presets'

saved = Array.new(30)
saved[0] = {'game'=>'makao', 'name'=>'Makao prywatne'}
saved[10] = {'game'=>'uno', 'name'=>'UNO szybkie'}
saved[29] = {'game'=>'mille_bornes', 'name'=>'1000 mil'}
created = []
widget = GameRoomWidget::TableList.new(loader: -> { [] }, opener: ->(*) {}, labeler: ->(*) {}, id_for: ->(*) {},
  creator: ->(slot) { created << slot }, invitations: -> {}, roster: ->(*) { [] }, table_options: ->(*) { {} },
  presets: -> { saved }, worker: WidgetManualWorker.new, clock: -> { 0 })
menu = FakeMenu.new
widget.context(menu, false)
rows = menu.options.map { |label, _, key, _| [label, key] }
assert(rows == [
  ['Read the table variant and settings', 'r'], ['Read the table participants', 'w'],
  ['Accept invitation', 'j'], ['Create a new table', 'n'],
  ['Makao prywatne', '1'], ['UNO szybkie', :alt_1], ['1000 mil', :shift_0]
], "wrong menu labels/shortcuts: #{rows.inspect}")
menu.options.last(3).each { |item| item.last.call }
assert(created == [0, 10, 29], 'menu lost preset indices')
saved[0] = nil
saved[5] = {'game'=>'chess', 'name'=>'Szachy'}
menu = FakeMenu.new
widget.context(menu, false)
assert(menu.options.none? { |item| item.first == 'Makao prywatne' }, 'removed preset cached in menu')
assert(menu.options.any? { |item| item.first == 'Szachy' && item[2] == '6' }, 'new preset not visible')
global = FakeMenu.new
widget.context(global, true)
assert(global.options.empty?, 'widget commands leaked outside widget')
assert(GameRoomTablePresets.title({'game'=>'uno', 'name'=>' '}) == 'uno', 'empty title has no fallback')
widget.close
puts 'PASS widget menu: native shortcuts, named assigned presets only, dynamic edits and original slot actions'
