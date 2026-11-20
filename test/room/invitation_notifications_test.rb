require_relative "../support/invitation_notifications"

uuid = "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80"
notifications = [
  Notification.new(id: 10, app_uuid: uuid, revoked: false, payload: { "type" => "game_room.invitation", "metadata" => { "invitation_id" => 7, "table_id" => 12 } }),
  Notification.new(id: 11, app_uuid: uuid.upcase, revoked: false, payload: { type: "game_room.invitation", metadata: { invitation_id: 7, table_id: 12 } }),
  Notification.new(id: 12, app_uuid: uuid, revoked: false, payload: { "type" => "game_room.invitation", "metadata" => { "invitation_id" => 8, "table_id" => 13 } }),
  Notification.new(id: 13, app_uuid: "another-app", revoked: false, payload: { "type" => "game_room.invitation", "metadata" => { "invitation_id" => 7, "table_id" => 12 } }),
  Notification.new(id: 14, app_uuid: uuid, revoked: true, payload: { "type" => "game_room.invitation", "metadata" => { "invitation_id" => 7, "table_id" => 12 } }),
  Notification.new(id: 15, app_uuid: uuid, revoked: false, type: "game_room.invitation", metadata: { "invitation_id" => 9, "table_id" => 12 }),
  Notification.new(id: 16, app_uuid: uuid, revoked: false, type: "game_room.invitation_rejected", metadata: { "invitation_id" => 10, "table_id" => 12 })
]
gateway = FakeNotificationGateway.new(notifications)
cleaner = InvitationNotifications.new(client: :client, app_uuid: uuid, gateway: gateway)

count = cleaner.revoke(7)
assert(count == 2, "the cleaner did not report every matching notification")
assert(gateway.listed == [[:client, false, [uuid]]], "the cleaner did not request active notifications for its application")
assert(gateway.revoked_many == [[:client, [10, 11]]], "the cleaner revoked unrelated or incomplete notifications")

table_count = cleaner.revoke_for_table(12)
assert(table_count == 3, "the cleaner did not report every invitation for the joined table")
assert(gateway.revoked_many.last == [:client, [10, 11, 15]], "joined-table cleanup revoked another table or another notification type")
assert(cleaner.revoke_for_table(0) == 0, "an invalid table id triggered notification cleanup")

direct_gateway = FakeNotificationGateway.new([])
direct_cleaner = InvitationNotifications.new(client: :client, app_uuid: uuid, gateway: direct_gateway)
assert(direct_cleaner.revoke(7, notification_id: 42) == 1, "direct notification cleanup failed")
assert(direct_gateway.revoked == [[:client, 42]], "direct cleanup revoked the wrong notification")
assert(direct_gateway.listed.empty?, "direct cleanup performed an unnecessary notification lookup")

assert(direct_cleaner.revoke(0) == 0, "an invalid invitation id triggered cleanup")

# Removing form-wide shortcuts must preserve the independent notification
# entry point, including stale notifications and choosing the exact invitation.

app = EltenGameRoom.allocate
app.instance_variable_set(:@invitation_notifications, cleaner)
transport = Object.new
transport.define_singleton_method(:start) { true }
app.instance_variable_set(:@transport, transport)
app.define_singleton_method(:initialize_services) {}
app.define_singleton_method(:check_server_table_access) { |announce: true| }
app.define_singleton_method(:run_network_task) { |_title, &operation| operation.call }
invitation = InvitationRepository::PendingInvitation.new(invitation: {"__id"=>7, "table_id"=>12, "sender"=>"Bob", "recipient"=>"Alice"})
other = InvitationRepository::PendingInvitation.new(invitation: {"__id"=>8, "table_id"=>13, "sender"=>"Carol", "recipient"=>"Alice"})
choices = [{ invitation: other }, { invitation: invitation }]
app.define_singleton_method(:load_pending_invitations) { choices }
action = :accept
app.define_singleton_method(:select_notification_invitation_action) { action }
received = Struct.new(:id, :sender, :metadata).new(42, "Bob", { "invitation_id" => 7 })
table = { "__id" => 12 }
calls = []
app.define_singleton_method(:accept_pending_invitation) do |selected, notification_id:|
  calls << [:accept, selected.id, notification_id]
  table
end
app.define_singleton_method(:reject_pending_invitation) do |selected, notification_id:|
  calls << [:reject, selected.id, notification_id]
end
app.define_singleton_method(:revoke_invitation_notification) do |id, notification_id:|
  calls << [:revoke, GameRoomInvitationIdentity.id(id), notification_id]
end
app.define_singleton_method(:run_program_interface) { |row| calls << [:open, row] }
app.define_singleton_method(:alert) { |message| calls << [:alert, message] }

assert(app.notification_action(:unrelated, received) == false, "unrelated notification opened an invitation")
assert(app.notification_action(:open_invitation, received) == true, "invitation notification was not handled")
assert(calls == [[:accept, 7, 42], [:open, table]], "notification accepted the wrong invitation or failed to open its table")
calls.clear
action = :reject
app.notification_action(:open_invitation, received)
assert(calls == [[:reject, 7, 42]], "rejecting a notification opened a table or lost the invitation id")
calls.clear
action = nil
app.notification_action(:open_invitation, received)
assert(calls.empty?, "cancelling a notification acted on the invitation")
choices.delete_if { |choice| choice[:invitation].id == 7 }
app.notification_action(:open_invitation, received)
assert(calls == [[:revoke, 7, 42], [:alert, "This table is no longer available."]], "missing table was not distinguished from an expired invitation")

# Joining from the ordinary table list must resolve any pending invitation for
# that exact table and clear its notification without touching other tables.
join_app = EltenGameRoom.allocate
joined_table = { "__id" => 12, "status" => "waiting" }
join_snapshot = LobbyRepository::TableSnapshot.new(table: joined_table, members: ["Alice"], bots: [], observers: [])
pending = InvitationRepository::PendingInvitation.new(invitation: {
  "__id" => 70, "table_id" => 12, "sender" => "Bob", "recipient" => "Alice"
})
join_calls = []
join_lobby = Object.new
join_lobby.define_singleton_method(:table_id) { |row| row["__id"].to_i }
join_lobby.define_singleton_method(:join_table) do |row, user, announce:|
  join_calls << [:join, row["__id"], user, announce]
  LobbyRepository::JoinResult.new(table: row, status: :joined, members: ["Alice", user])
end
join_invitations = Object.new
join_invitations.define_singleton_method(:pending_for) do |recipient, tables:|
  join_calls << [:pending, recipient, tables.map { |row| row["__id"] }]
  [pending]
end
join_invitations.define_singleton_method(:respond) do |invitation, recipient:, response:|
  join_calls << [:respond, invitation.id, recipient, response]
end
join_notifications = Object.new
join_notifications.define_singleton_method(:revoke_for_table) do |table_id, live_session_id: nil|
  join_calls << [:revoke_table, table_id]
  1
end
join_app.instance_variable_set(:@lobby, join_lobby)
join_app.instance_variable_set(:@invitations, join_invitations)
join_app.instance_variable_set(:@invitation_notifications, join_notifications)
native_transport = Object.new
native_transport.define_singleton_method(:live_store?) { true }
native_transport.define_singleton_method(:invitation_account_identity) { [self, 'Alice'] }
join_app.instance_variable_set(:@transport, native_transport)
join_app.define_singleton_method(:run_network_task) { |_title, &operation| operation.call }
join_app.define_singleton_method(:establish_invited_table_transport) do |row|
  join_calls << [:transport, row["__id"]]
  :joined
end

joined = join_app.send(:join_table_snapshot, join_snapshot)
assert(joined.entered? && join_calls.include?([:transport, 12]), "ordinary native table-list joining did not succeed")
assert(join_calls.include?([:respond, 70, "Alice", "accepted"]), "joining did not resolve the invitation for that table")
assert(join_calls.include?([:revoke_table, 12]), "joining did not clear the notification for that table")

puts "Invitation notification tests passed"
