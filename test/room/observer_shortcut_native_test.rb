require_relative '../support/duck_challenge_native'
require_relative '../../lib/participant_menu'
require_relative '../../lib/room_presentation'
require_relative '../../lib/game_layout'
require EltenTestHost.file('src/ui/controls/menu.rb')
Object.const_set(:Menu, EltenAPI::Controls.const_get(:Menu)) unless defined?(Menu)
require EltenTestHost.file('src/eapi/mainmenu.rb')

driver = DuckChallengeNativeDriver.new
snapshot = Struct.new(:members, :observers).new(%w[Alice Bob], [])
def snapshot.observer?(user); observers.include?(user); end
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new,
  user_items: RoomPresentation.user_rows(snapshot.members, owner: 'Alice', players: [], active: false))
layout.users.index = 1
layout.form.index = layout.form.fields.index(layout.users)
actions, available = [], [:manage_roles]
GameRoomParticipantMenu.bind(layout, available: -> { available }, room: -> { snapshot }) do |action, person|
  actions << [action, person]
end
layout.form.game_room_background_help_enabled = true
layout.form.focus
press = -> do
  driver.frame(layout.form, [[0x11,true],[0x10,true],[0x50,true,driver.raw([0x11,0x10,0x50])]], held: [0x11,0x10,0x50])
  keyprocs
  driver.frame(layout.form, [[0x50,false],[0x10,false],[0x11,false]])
end
press.call
assert(actions == [[:make_observer, 'Bob']], 'Native Ctrl+Shift+P did not target the selected person')
snapshot.observers << 'Bob'
press.call
assert(actions.last == [:make_player, 'Bob'] && actions.size == 2, 'Native role shortcut did not offer returning to play')
layout.users.index = 0
press.call
assert(actions.last == [:make_observer, 'Alice'] && actions.size == 3, 'Native role shortcut did not target the table master')
snapshot.observers << 'Alice'
press.call
assert(actions.last == [:make_player, 'Alice'] && actions.size == 4, 'Native role shortcut did not return the table master to play')
layout.form.index = layout.form.fields.index(layout.chat)
layout.chat.set_text('Keep this draft')
press.call
assert(actions.size == 4 && layout.chat.text == 'Keep this draft', 'Role shortcut leaked to chat')
layout.form.index = layout.form.fields.index(layout.users)
available.clear
press.call
assert(actions.size == 4, 'Role shortcut remained active after the owner lost permission')
$activecontrols = []
puts 'PASS native observer shortcut: selected identity, both roles, chat isolation and dynamic permissions'
