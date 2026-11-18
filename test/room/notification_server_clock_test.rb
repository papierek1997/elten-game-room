require_relative "../support/invitation_notifications"
require_relative "../support/server_clock"
require_relative "../../lib/table_watch"

ClockNotice = Struct.new(:id,:app_uuid,:type,:sender,:metadata,:created_at,keyword_init:true)
uuid = "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80"
base, elapsed = 1_800_000_000,0.0
clock = game_room_test_clock { base + elapsed }
clock.synchronize
GameRoomClock.instance_variable_set(:@clock,clock)
old_wall = Time.method(:now)
begin
  [-7200,7200].product([-86400,86400]).each do |sender_skew,receiver_skew|
    Time.define_singleton_method(:now) { Time.at(base+receiver_skew) }
    elapsed = 7.0
    metadata = {"invitation_id"=>7,"table_id"=>12,"live_session_id"=>"live-12","sender"=>"Bob",
      "created_at"=>base+sender_skew,"expires_at"=>base+sender_skew+300}
    notice = ClockNotice.new(id:42,app_uuid:uuid,type:"game_room.invitation",sender:"Bob",created_at:base,metadata:metadata)
    gateway = FakeNotificationGateway.new([notice])
    cleaner = InvitationNotifications.new(client: :client,app_uuid:uuid,gateway:gateway)
    row = cleaner.pending(recipient:"Alice").first
    assert(row && row["expires_at"]==base+300,"valid invitation disappeared with clock skew")
    app = EltenGameRoom.allocate
    app.instance_variable_set(:@invitation_notifications,cleaner)
    transport = Object.new
    transport.define_singleton_method(:start) { true }
    app.instance_variable_set(:@transport,transport)
    app.define_singleton_method(:initialize_services) {}
    app.define_singleton_method(:check_server_table_access) { |announce: true| }
    app.define_singleton_method(:run_network_task) { |*_,&block| block.call }
    choice = InvitationRepository::PendingInvitation.new(invitation: row)
    app.define_singleton_method(:load_pending_invitations) { [{invitation:choice}] }
    app.define_singleton_method(:select_notification_invitation_action) { :accept }
    accepted, alerts = [],[]
    app.define_singleton_method(:accept_pending_invitation) { |*_,**_| accepted << true; nil }
    app.define_singleton_method(:alert) { |text| alerts << text }
    app.notification_action(:open_invitation,notice)
    assert(accepted==[true] && alerts.empty?,"notification action falsely reported expired")
    elapsed = 300.0
    app.notification_action(:open_invitation,notice)
    assert(accepted==[true] && alerts.last=="This invitation has expired.","real five-minute expiry was extended")
    assert(cleaner.pending(recipient:"Alice").empty?,"expired invitation listed")

    elapsed = 7.0
    watch = GameRoomTableWatch::Receiver.new(user:"Alice",games:["uno"],uuid:uuid)
    watch.games=["uno"]
    public_notice = ClockNotice.new(id:43,app_uuid:uuid,type:GameRoomTableWatch::TYPE,sender:"Bob",created_at:base,
      metadata:metadata.merge("format"=>1,"game"=>"uno","expires_in"=>50))
    assert(watch.receive(public_notice),"new table announcement rejected sender clock skew")
    elapsed = 50.0
    assert(!watch.visible?(public_notice),"delayed delivery restarted full table announcement TTL")
  end
ensure
  Time.define_singleton_method(:now,old_wall)
end
puts "PASS invitation list/opening and table announcements: sender +/-2h, receiver +/-1 day, original five-minute and reduced delivery expiry"

# Notifications received before startup clock synchronization must wait, not
# expire against the OS clock or lose a previously joined table receipt.
original_available = GameRoomClock.method(:server_available?)
original_contacts = EltenGameRoom.method(:contact_notification_allowed?)
original_presentation = EltenGameRoom.method(:present_deferred_contact_notification)
original_settings = EltenGameRoom.method(:normalized_settings)
EltenGameRoom.contacts_stop
delivered = []
begin
  GameRoomClock.define_singleton_method(:server_available?) { true }
  GameRoomClock.instance_variable_set(:@clock, game_room_test_clock { nil })
  EltenGameRoom.define_singleton_method(:normalized_settings) { EltenGameRoom::DEFAULT_SETTINGS.merge("invitation_notifications"=>"everyone", "table_watch_contacts_only"=>false) }
  EltenGameRoom.define_singleton_method(:contact_notification_allowed?) { |*_, **_| true }
  EltenGameRoom.define_singleton_method(:present_deferred_contact_notification) { |n| delivered << n.id }
  pending_notice = ClockNotice.new(id:88,app_uuid:uuid,type:GameRoomTableWatch::TYPE,sender:"Bob",created_at:base,
    metadata:{"format"=>1,"game"=>"uno","table_id"=>12,"live_session_id"=>"pending-12","created_at"=>base,"expires_at"=>base+300})
  stored = {"resolved"=>{"old-12"=>base+200}}
  watch = GameRoomTableWatch::Receiver.new(user:"Alice",games:["uno"],uuid:uuid,stored:stored)
  watch.games=["uno"]
  EltenGameRoom.instance_variable_set(:@table_watch_receiver,watch)
  presentation = Object.new
  presentation.define_singleton_method(:suppress_default!) { true }
  assert(!EltenGameRoom.contact_notification_received(pending_notice,presentation),"unconfirmed time announced a notice")
  10.times { EltenGameRoom.contacts_tick }
  assert(delivered.empty? && watch.instance_variable_get(:@resolved)==stored["resolved"],"startup OS time expired a queued notice or saved receipt")
  cache = EltenGameRoom.contacts_cache
  assert(!cache.instance_variable_get(:@worker).busy?,"clock deferral fetched contacts with filters disabled")
  elapsed=7.0
  GameRoomClock.instance_variable_set(:@clock,clock)
  10.times { EltenGameRoom.contacts_tick }
  assert(delivered==[88],"notice not released exactly once after time synchronization")
  # Reconnecting unsuccessfully must not revoke a valid invitation.
  app = EltenGameRoom.allocate
  app.define_singleton_method(:initialize_services) {}
  app.define_singleton_method(:check_server_table_access) { |announce: true| }
  app.define_singleton_method(:run_network_task) { |*_, &_| nil }
  app.define_singleton_method(:alert) { |_| raise "Failed connection falsely expired an invitation" }
  app.notification_action(:open_invitation,ClockNotice.new(type:"game_room.invitation"))
ensure
  GameRoomClock.define_singleton_method(:server_available?,original_available)
  EltenGameRoom.define_singleton_method(:contact_notification_allowed?,original_contacts)
  EltenGameRoom.define_singleton_method(:present_deferred_contact_notification,original_presentation)
  EltenGameRoom.define_singleton_method(:normalized_settings,original_settings)
  EltenGameRoom.contacts_stop
end
puts "PASS pre-synchronization delivery: queued once, saved receipts kept, no contact HTTP, failed connection does not expire invitations"
