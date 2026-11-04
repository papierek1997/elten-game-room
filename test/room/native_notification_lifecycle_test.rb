require_relative '../support/table_watch_runtime'
require_relative '../support/assertions'
require_relative '../support/app_notification_models'
include GameRoomTest::Assertions
require EltenTestHost.file('src/eapi/program_notifications.rb')

now = 1_800_000_000
original_now, original_synced = GameRoomClock.method(:now), GameRoomClock.method(:synchronized?)
GameRoomClock.define_singleton_method(:now) { now.to_f }
GameRoomClock.define_singleton_method(:synchronized?) { true }
uuid = EltenGameRoom.server_app_uuid
def notice(uuid, id, type, metadata, sender: 'Bob', created: 1_800_000_000)
  Programs::AppNotification.new(id: id, app_uuid: uuid, type: type, sender: sender,
    created_at: created, metadata: metadata, fallback_text: '')
end
begin
  metadata = {'invitation_id'=>7, 'table_id'=>12, 'live_session_id'=>'native-12', 'sender'=>'Bob',
    'created_at'=>now, 'expires_at'=>now+300, 'expires_in'=>300}
  invitation = notice(uuid, 10, 'game_room.invitation', metadata)
  lifecycle = EltenGameRoom.notification_lifecycle(invitation)
  assert(lifecycle.is_a?(Programs::NotificationLifecycle), 'Application did not declare a native lifecycle')
  assert_equal(60.0, lifecycle.interval, 'Lifecycle uses an excessive polling cadence')
  assert(lifecycle.expires_after_receipt.nil?, 'Receipt changed the original five-minute deadline')
  assert(lifecycle.callback.call(invitation), 'A current invitation was removed')
  now += 300
  assert_equal(false, lifecycle.callback.call(invitation), 'An expired invitation was kept')
  GameRoomClock.define_singleton_method(:synchronized?) { false }
  assert(lifecycle.callback.call(invitation), 'A cold clock was treated as confirmed expiry')
  GameRoomClock.define_singleton_method(:synchronized?) { true }
  assert(EltenGameRoom.notification_lifecycle(notice('other-app', 11, invitation.type, metadata)).nil?, 'Another application acquired our lifecycle')
  assert(EltenGameRoom.notification_lifecycle(notice(uuid, 12, 'other.type', {})).nil?, 'An unrelated notification acquired our lifecycle')

  now -= 300
  token = 'invitation-token'
  inbox = Object.new
  dismissed = false
  verified = nil
  inbox.define_singleton_method(:dismissed?) { |value| value == token && dismissed }
  inbox.define_singleton_method(:verified) { |_id| verified }
  EltenGameRoom.instance_variable_set(:@tournament_event_inboxes, {'registration'=>inbox})
  tournament = notice(uuid, 13, 'game_room.tournament_registration', {'event_id'=>token})
  policy = EltenGameRoom.notification_lifecycle(tournament)
  assert(policy.callback.call(tournament), 'Pending verification was treated as a stale invitation')
  dismissed = true
  assert_equal(false, policy.callback.call(tournament), 'Confirmed cancellation did not invalidate the tournament invitation')
  dismissed = false
  verified = [{'metadata'=>tournament.metadata, 'expires_at'=>now}, 'bob']
  assert_equal(false, policy.callback.call(tournament), 'A confirmed expired tournament proof was retained')
  verified[1] = 'different-sender'
  assert(policy.callback.call(tournament), 'A different sender supplied invalidation evidence')

  sender = Object.new
  delivered, revoked = [], []
  sender.define_singleton_method(:send_notification) { |recipient, **options| delivered << [recipient, options]; true }
  sender.define_singleton_method(:revoke_sent_notification) { |recipient, key:| revoked << [recipient, key]; true }
  reference = {'__id'=>7, 'table_id'=>12, 'live_session_id'=>'native-12', 'sender'=>Session.name, 'recipient'=>'Bob'}
  sent_metadata = metadata.merge('sender'=>Session.name)
  GameRoomNotifications.deliver(sender, 'Bob', type: invitation.type, metadata: sent_metadata, expires_in: 300)
  key = delivered.last[1].fetch(:key)
  assert_equal(GameRoomNotifications.invitation_key(reference), key, 'Send and revoke disagree on the exact invitation key')
  assert_equal(300, delivered.last[1][:expires_in], 'Native key changed invitation lifetime')
  GameRoomNotifications.revoke_invitation(sender, reference)
  assert_equal([['Bob', key]], revoked, 'Keyed revocation targeted a different recipient/event')
  %w[__id table_id live_session_id recipient].each do |field|
    changed = reference.merge(field => (reference[field].is_a?(Integer) ? reference[field] + 1 : "different-#{reference[field]}"))
    assert(GameRoomNotifications.invitation_key(changed) != key, 'A different invitation scope shares the same key')
  end
  assert_equal(false, GameRoomNotifications.revoke_invitation(sender, reference.merge('sender'=>'Someone else')), 'A foreign sender was allowed to revoke')
  assert_equal(1, revoked.length, 'A foreign-sender operation performed a write')
  repository = InvitationRepository.new
  one = repository.create(table:{'__id'=>81,'__live_session_id'=>'closed'}, sender:Session.name, recipient:'Bob', now:now).invitation
  two = repository.create(table:{'__id'=>81,'__live_session_id'=>'closed'}, sender:Session.name, recipient:'Carol', now:now).invitation
  retained = repository.create(table:{'__id'=>81,'__live_session_id'=>'other-native'}, sender:Session.name, recipient:'Bob', now:now).invitation
  GameRoomNotifications.revoke_closed_table(sender, {'__id'=>81,'__live_session_id'=>'closed'})
  assert_equal([['Bob',GameRoomNotifications.invitation_key(one)],['Carol',GameRoomNotifications.invitation_key(two)]], revoked.last(2),
    'Closed-table cleanup did not keep exact recipient/session identities')
  assert(InvitationRepository::SENT.values.include?(retained) && !InvitationRepository::SENT.values.include?(one),
    'Closed-table cleanup removed another session or kept confirmed cancelled invites')
  event_key = GameRoomNotifications.key(type:'game_room.tournament_started', metadata:{'event_id'=>'first', 'title'=>'Before'},sender:'Alice',recipient:'Bob')
  assert_equal(event_key, GameRoomNotifications.key(type:'game_room.tournament_started', metadata:{'title'=>'After', 'event_id'=>'first'},sender:'alice',recipient:'bob'),
    'A title change, metadata order or user-name case changed the event identity')
  assert(event_key != GameRoomNotifications.key(type:'game_room.tournament_started', metadata:{'event_id'=>'second'},sender:'Alice',recipient:'Bob'),
    'Distinct tournament events share a revocation key')

  # Exercise the actual native sender/revoker adapter, replacing only HTTP.
  require EltenTestHost.file('src/eltenlink/apps.rb')
  http = []
  client = Object.new
  client.define_singleton_method(:api_data) { |*arguments, **options| http << [arguments, options]; {} }
  EltenLink::Apps.notify(client, appid: uuid, user: 'Bob', type: invitation.type,
    metadata: sent_metadata, expires_in: 300, key: key)
  EltenLink::Apps.revoke_notification(client, appid: uuid, user: 'Bob', key: key)
  assert_equal(%w[POST PATCH], http.map { |request| request[0][0] }, 'Native delivery/revocation methods changed')
  assert_equal([key, key], http.map { |request| request[0][2].fetch('key') }, 'Native transport lost the common event key')
  assert_equal(300, http.first[0][2].fetch('expires_in'), 'Native transport changed invitation validity')
ensure
  GameRoomClock.define_singleton_method(:now, original_now)
  GameRoomClock.define_singleton_method(:synchronized?, original_synced)
  EltenGameRoom.remove_instance_variable(:@tournament_event_inboxes) if EltenGameRoom.instance_variable_defined?(:@tournament_event_inboxes)
end
puts 'PASS native 3.0.5 notification declarations, pure lifecycle checks, expiry, cancellation, scoped keys and authenticated revocation'
