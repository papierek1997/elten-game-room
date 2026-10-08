require_relative '../support/rules_native_navigation'

layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new, phase: :waiting)
field = layout.chat
assert(field.is_a?(EltenAPI::Controls.const_get(:EditBox)), 'Chat test does not use native EditBox')
assert(field.max_length == TableActivityRepository::MESSAGE_MAX_LENGTH && field.max_length == 2000,
  'Chat editor and repository have different limits')
field.define_singleton_method(:play_sound) { |*| }
['a', 'ż', '界', '🎲'].each do |character|
  text = character * 1999
  field.set_text('')
  field.einsert(text)
  field.einsert(character)
  assert(field.text == character * 2000, 'Native editing cannot reach the new Unicode limit')
  field.einsert(character)
  assert(field.text == character * 2000, 'Native typing accepts a message the repository would truncate')
  field.set_text('')
  field.einsert(character * 2000)
  assert(field.text.length == 2000, 'Native paste still stops at the old limit')
end
layout.form.index = layout.form.fields.index(field)
draft = field.text
[:active, :finished, :waiting].each do |phase|
  layout.update(view_spec: GameRoomLayout::ViewSpec.new, history_items: [], user_items: [], users_header: '', phase: phase)
  assert(layout.chat.equal?(field) && field.text == draft && field.max_length == 2000, 'Phase change replaced or truncated chat')
  assert(layout.focus_location == [:chat, 0], 'Phase change moved chat focus')
end
puts 'PASS native chat editor with binary sources: typing/paste to 2000, Unicode limits, lobby/game/rematch draft and focus'
