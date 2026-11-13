require_relative '../support/table_notice_presentation'

GameRoomLocalization.boot(settings: {}, host_language: 'en')
notice = FakeNotification.new('Bob')
notice.metadata['game'] = 'uno'
notice.metadata['sender_display_name'] = 'Jan Nowak'
presentation = EltenGameRoom.map_notification(notice)
body = presentation.instance_variable_get(:@options).fetch(:body)
assert(body.include?('Jan Nowak invites') && !presentation.default_suppressed, 'invitation did not show full display name')
assert(GameRoomInvitationIdentity.notification_sender(notice, notice.metadata) == 'Bob', 'alias became invitation identity')
assert(notice.sender == 'Bob' && notice.metadata['sender'] == 'Bob', 'presentation rewrote authenticated envelope')
notice.metadata['sender_display_name'] = ''
body = EltenGameRoom.map_notification(notice).instance_variable_get(:@options).fetch(:body)
assert(body.include?('Bob invites'), 'empty notification name lost login fallback')
notice.metadata['sender_display_name'] = 'Jan Nowak'
notice.metadata['sender'] = 'Alice'
assert(EltenGameRoom.map_notification(notice).default_suppressed, 'display name bypassed envelope sender check')

now = 2_000_000_000
receiver = GameRoomTableWatch::Receiver.new(user: 'Alice', games: ['uno'], uuid: EltenGameRoom.server_app_uuid, clock: -> { now })
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
table_notice = Notice2.new(id: 99, app_uuid: EltenGameRoom.server_app_uuid, type: GameRoomTableWatch::TYPE, sender: 'Bob', metadata: {
  'format' => 1, 'game' => 'uno', 'table_id' => 15, 'live_session_id' => 'name-notice-room',
  'created_at' => now, 'expires_at' => now + 300, 'sender_display_name' => 'Jan Nowak'})
presentation = EltenGameRoom.map_notification(table_notice)
title = presentation.instance_variable_get(:@options).fetch(:title)
assert(title.start_with?('Jan Nowak,'), 'new-table notice lost full sender name')
assert(table_notice.sender == 'Bob', 'new-table presentation replaced authenticated sender')

invite_notice = Notice2.new(id: 100, app_uuid: EltenGameRoom.server_app_uuid, type: 'game_room.invitation', sender: 'Bob', metadata: {
  'game' => 'uno', 'table_id' => 15, 'invitation_id' => 22, 'live_session_id' => 'name-notice-room',
  'created_at' => now, 'expires_at' => now + 300, 'sender' => 'Bob', 'sender_display_name' => 'Jan Nowak'})
gateway = Object.new
gateway.define_singleton_method(:list) { |*, **| [invite_notice] }
pending = InvitationNotifications.new(client: :fixture, app_uuid: EltenGameRoom.server_app_uuid,
  gateway: gateway, current_user: -> { 'Alice' }).pending(recipient: 'Alice', now: now).first
assert(pending && pending['sender'] == 'Bob' && pending['sender_display_name'] == 'Jan Nowak',
  'notification-backed pending invitation lost its sender alias or identity')
picker = EltenGameRoom.allocate
lobby = Object.new
lobby.define_singleton_method(:capacity_of) { |_| 8 }
picker.instance_variable_set(:@lobby, lobby)
snapshot = Struct.new(:table, :participant_count).new({'game' => 'uno', 'name' => 'Room'}, 2)
label = picker.send(:pending_invitation_label, invitation: InvitationRepository::PendingInvitation.new(invitation: pending), snapshot: snapshot)
assert(label.include?('invited by Jan Nowak') && pending['sender'] == 'Bob', 'invitation picker did not show full name independently of global discovery')

class DisplayNameSaveApp < EltenGameRoom; end
app = DisplayNameSaveApp.allocate
stored = EltenGameRoom::DEFAULT_SETTINGS.merge('display_name' => 'Old Name')
fail_save = true
app.define_singleton_method(:update_json) do |_, default:, &edit|
  draft = Marshal.load(Marshal.dump(stored))
  edit.call(draft)
  raise IOError, 'unconfirmed settings write' if fail_save
  stored = draft
end
GameRoomParticipants.configure_display_name(account: Session.name, name: 'Old Name')
begin
  app.send(:update_game_room_settings) { |settings| settings['display_name'] = 'New Name' }
  raise 'Failed write was reported as saved'
rescue IOError
  assert(GameRoomParticipants.local_display_name == 'Old Name', 'failed save published display name')
end
fail_save = false
app.send(:update_game_room_settings) { |settings| settings['display_name'] = 'New Name' }
assert(stored['display_name'] == 'New Name' && GameRoomParticipants.local_display_name == 'New Name', 'confirmed settings write did not publish name')
puts 'PASS full display names in invitation/new-table notices, unchanged authenticated identity, empty fallback and sender-conflict refusal'
