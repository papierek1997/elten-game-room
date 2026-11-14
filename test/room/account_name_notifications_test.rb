require_relative '../support/table_notice_presentation'

GameRoomLocalization.boot(settings: {}, host_language: 'en')
notice = FakeNotification.new('Bob')
notice.metadata['game'] = 'uno'
notice.metadata['sender_display_name'] = 'Old Bob'
presentation = EltenGameRoom.map_notification(notice)
body = presentation.instance_variable_get(:@options).fetch(:body)
assert(body.include?('Bob invites') && !body.include?('Old Bob') && !presentation.default_suppressed,
  'An old invitation alias replaced the authenticated sender')
assert(notice.sender == 'Bob' && notice.metadata['sender'] == 'Bob', 'Presentation rewrote the envelope')
notice.metadata['sender'] = 'Alice'
assert(EltenGameRoom.map_notification(notice).default_suppressed, 'Ignoring aliases bypassed sender validation')

now = 2_000_000_000
receiver = GameRoomTableWatch::Receiver.new(user: 'Alice', games: ['uno'], uuid: EltenGameRoom.server_app_uuid, clock: -> { now })
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
table_notice = Notice2.new(id: 99, app_uuid: EltenGameRoom.server_app_uuid, type: GameRoomTableWatch::TYPE, sender: 'Bob', metadata: {
  'format'=>1, 'game'=>'uno', 'table_id'=>15, 'live_session_id'=>'account-notice-room',
  'created_at'=>now, 'expires_at'=>now+300, 'sender_display_name'=>'Old Bob'})
presentation = EltenGameRoom.map_notification(table_notice)
title = presentation.instance_variable_get(:@options).fetch(:title)
assert(title.start_with?('Bob,') && !title.include?('Old Bob'), 'A new-table notice still uses its old alias')

invite_notice = Notice2.new(id: 100, app_uuid: EltenGameRoom.server_app_uuid, type: 'game_room.invitation', sender: 'Bob', metadata: {
  'game'=>'uno', 'table_id'=>15, 'invitation_id'=>22, 'live_session_id'=>'account-notice-room',
  'created_at'=>now, 'expires_at'=>now+300, 'sender'=>'Bob', 'sender_display_name'=>'Old Bob'})
gateway = Object.new
gateway.define_singleton_method(:list) { |*, **| [invite_notice] }
pending = InvitationNotifications.new(client: :fixture, app_uuid: EltenGameRoom.server_app_uuid,
  gateway: gateway, current_user: -> { 'Alice' }).pending(recipient: 'Alice', now: now).first
assert(pending && pending['sender'] == 'Bob' && !pending.key?('sender_display_name'), 'Pending invitations retain alias data')
picker = EltenGameRoom.allocate
lobby = Object.new
lobby.define_singleton_method(:capacity_of) { |_| 8 }
picker.instance_variable_set(:@lobby, lobby)
snapshot = Struct.new(:table, :participant_count).new({'game'=>'uno', 'name'=>'Room'}, 2)
label = picker.send(:pending_invitation_label, invitation: InvitationRepository::PendingInvitation.new(invitation: pending), snapshot: snapshot)
assert(label.include?('invited by Bob') && !label.include?('Old Bob'), 'The invitation picker still displays an old alias')
puts 'PASS old aliases ignored in invitation/new-table notices and pending picker; authenticated sender checks preserved'
