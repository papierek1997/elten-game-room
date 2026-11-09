require_relative '../support/axel_pong_doubles_lobby'
require_relative '../support/table_lifecycle_controls_2'

app = PongDoublesLobbyApp.new
table = app.lobby.create_table(name: 'Role conflicts', game: 'axelpong', owner: 'Alice', game_options: '{}').table
PongDoublesLobbyTest.join(app, table, 'Bob')
snapshot = app.lobby.snapshot_for(table, force: true)
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new,
  user_items: RoomPresentation.user_rows(snapshot.members, observers: snapshot.observers, owner: 'Alice', players: [], active: false))
allowed = true
actions, denied = [], []
GameRoomParticipantMenu.bind(layout, available: -> { allowed ? [:manage_roles] : [] },
  room: -> { snapshot }, control_denied: ->(text) { denied << text }) do |action, participant|
  actions << [action, participant]
  app.send(:change_observer_mode, table, action, participant)
end
layout.users.index = snapshot.members.index('Bob')
menu = LifecycleMenu.new
layout.users.context(menu)
item = menu.items.find { |label, key, _| label == 'Make Bob an observer for the next game' && key == 'P' }
assert(item, 'Selected-person role action has no Ctrl+Shift+P')
tips = layout.users.game_room_context_help_provider.call
assert(tips.any? { |tip| tip.include?('Ctrl+Shift+P') }, 'Role shortcut missing from contextual F1 help')

# A menu may outlive its selected member. The real repository and Program
# boundary must reject it without raising out of the table screen.
app.broker.endpoint('Bob').sessions.first.leave
before = table.dup
item.last.call
assert(actions == [[:make_observer, 'Bob']], 'Role command lost the captured identity')
assert(app.notices.last == 'This person is no longer at the table. Their role was not changed.', 'Departure conflict did not produce a localized UI message')
assert(table == before && app.opened_tables.empty?, 'A failed role choice replaced/closed the table')

# Reject a stale command before dispatch when its live UI snapshot changes.
snapshot.members.delete('Bob')
item.last.call
assert(actions.size == 1 && denied.last == 'This action is not available now.', 'Stale participant menu was dispatched twice')
assert(GameRoomParticipantMenu.participant_role_action(available: [:manage_roles], room: snapshot, participant: 'Alice') == :make_observer,
  'Host shortcut did not target self')
assert(GameRoomParticipantMenu.participant_role_action(available: [], room: snapshot, participant: 'Bob').nil?, 'Non-host received role shortcut')

# Only the explicitly typed operational conflicts are caught. Programming
# errors still propagate instead of being mislabeled as a departed player.
lobby = Object.new
lobby.define_singleton_method(:set_observer) { |*_args| raise ArgumentError, 'invalid internal argument' }
app.instance_variable_set(:@lobby, lobby)
begin
  app.send(:change_observer_mode, table, :make_observer, 'Bob')
  raise 'Programming error was swallowed'
rescue ArgumentError => error
  raise unless error.message == 'invalid internal argument'
end
puts 'PASS observer shortcut, dynamic help, stale row, departure conflict and programming-error boundary'
