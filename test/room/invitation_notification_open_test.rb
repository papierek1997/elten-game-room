require_relative "../support/invitation_fresh_endpoint"

# Mirrors the host's main-window ordering: schedule a NotificationActionScene,
# mark the notification as read, then create a new program and call its action.
# The integration probe in diagnostics/invitation-open-after-226/reproduce.rb
# also executes these steps using the actual ELTEN methods.
OpenedNotice = Struct.new(:id, :app_uuid, :type, :sender, :metadata, keyword_init: true)

class OpeningInvitationApp < InvitationAppDriver
  attr_accessor :decision, :before_decision
  attr_reader :opened_table
  def initialize(*arguments, **keywords)
    super
    @decision = :accept
  end
  def initialize_services; end
  def check_server_table_access(announce: true); end
  def select_notification_invitation_action
    @before_decision&.call
    @decision
  end
  def run_program_interface(row)
    assert(@invitation_notifications.instance_variable_get(:@opened_notification) == nil,
      "clicked invitation leaked into the ordinary program interface")
    @opened_table = row
  end
end

def opening_scenario(private_table: false, bot_count: 0)
  broker, gateway = NativeLiveSessionsBroker.new, DurableNoticeGateway.new
  owner = OpeningInvitationApp.new(broker, "Owner", gateway)
  $game_room_test_user = "Owner"
  table = owner.transport.create_room(name: "Opened", game: "makao", owner: "Owner",
    game_options: "{}", private_table: private_table, bot_count: bot_count)
  owner.send(:deliver_table_invitation, table, "Guest")
  notice = gateway.rows["Guest"].first
  captured = OpenedNotice.new(id: notice.id, app_uuid: notice.app_uuid,
    type: notice.type, sender: "Owner", metadata: notice.metadata.dup.freeze).freeze
  # ELTEN consumes the main-window notification, not the native authorization.
  gateway.revoke("Guest", notice.id)
  app = OpeningInvitationApp.new(broker, "Guest", gateway, fresh: true)
  $game_room_test_user = "Guest"
  assert(app.transport.pending_invitations.empty?, "test depended on an old endpoint queue")
  assert(app.send(:load_pending_invitations).empty?, "read notification was still listed as active")
  { app: app, owner: owner, broker: broker, gateway: gateway, table: table, captured: captured }
end

def assert_context_cleared(app)
  assert(app.instance_variable_get(:@invitation_notifications).instance_variable_get(:@opened_notification) == nil,
    "opened notification context survived a finished action")
end

def with_invitation_clock
  original = Time.method(:now)
  current = original.call
  Time.define_singleton_method(:now) { current }
  yield ->(seconds) { current += seconds }
ensure
  Time.define_singleton_method(:now, original)
end

[false, true].each do |private_table|
  scenario = opening_scenario(private_table: private_table)
  app, table, gateway = scenario.values_at(:app, :table, :gateway)
  # Include an unrelated active invitation and an unrelated read invitation.
  metadata = scenario[:captured].metadata.merge("invitation_id" => 345678)
  other = gateway.send("Guest", metadata)
  read_other = gateway.send("Guest", metadata.merge("invitation_id" => 345679))
  gateway.revoke("Guest", read_other.id)
  assert(app.notification_action(:open_invitation, scenario[:captured]), "host action was not handled")
  assert(app.opened_table && app.opened_table["__id"] == table["__id"], "opened invite failed: #{app.alerts} #{app.errors}")
  assert(app.alerts.empty?, "successful invitation displayed an error")
  assert_context_cleared(app)
  assert(app.send(:load_pending_invitations).empty?, "accepted opened invitation was resurrected")
  assert(other.revoked, "successful entry missed other invitations to the same table")
  assert(read_other.revoked, "test unexpectedly modified a read notification")

  scenario = opening_scenario(private_table: private_table)
  app = scenario[:app]
  app.decision = :reject
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table == nil && app.alerts.empty?, "opened rejection failed or produced a duplicate alert: #{app.alerts}")
  assert_context_cleared(app)
  if private_table
    assert(app.transport.discover_rooms(include_private: true).empty?, "rejection retained private authorization")
  end

  scenario = opening_scenario(private_table: private_table)
  app = scenario[:app]
  app.decision = nil
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table == nil && app.alerts.empty?, "cancel responded to an invitation")
  assert_context_cleared(app)
  app.decision = :accept
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table, "reopening a read notification lost a still-valid invitation")

  scenario = opening_scenario(private_table: private_table, bot_count: 7)
  app = scenario[:app]
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table == nil && app.alerts.last == "This table is full.", "full room misreported: #{app.alerts}")
  assert_context_cleared(app)

  scenario = opening_scenario(private_table: private_table)
  app = scenario[:app]
  # A room disappearing while the accept/reject list is open must be rechecked.
  app.before_decision = -> { scenario[:broker].cores.fetch(scenario[:table]["__live_session_id"]).closed = true }
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table == nil && app.alerts.last == "This table is no longer available.", "closed table was joined")
  assert_context_cleared(app)

  scenario = opening_scenario(private_table: private_table)
  app = scenario[:app]
  scenario[:gateway].error = EltenAPI::LiveSessions::TimeoutError.new("offline")
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table == nil && app.errors.length == 1, "network failure was treated as success/expiry")
  assert_context_cleared(app)
  scenario[:gateway].error = nil
  app.notification_action(:open_invitation, scenario[:captured])
  assert(app.opened_table, "transient failure invalidated the captured invitation")

  scenario = opening_scenario(private_table: private_table)
  app = scenario[:app]
  expired = OpenedNotice.new(**scenario[:captured].to_h.merge(
    metadata: scenario[:captured].metadata.merge("expires_at" => Time.now.to_i))).freeze
  app.notification_action(:open_invitation, expired)
  assert(app.opened_table == nil && app.alerts.last == "This invitation has expired.", "expiry boundary was extended")
  assert_context_cleared(app)

  with_invitation_clock do |advance|
    scenario = opening_scenario(private_table: private_table)
    app = scenario[:app]
    app.before_decision = -> { advance.call(scenario[:captured].metadata["expires_at"] - Time.now.to_i) }
    app.notification_action(:open_invitation, scenario[:captured])
    assert(app.opened_table == nil && app.alerts.last == "This invitation has expired.", "expiry during selection was not rechecked")
    assert_context_cleared(app)
  end

  scenario = opening_scenario(private_table: private_table)
  app = scenario[:app]
  mismatch = OpenedNotice.new(**scenario[:captured].to_h.merge(
    metadata: scenario[:captured].metadata.merge("live_session_id" => "not-the-invited-session"))).freeze
  app.notification_action(:open_invitation, mismatch)
  assert(app.opened_table == nil, "captured payload bypassed native session identity")
  assert_context_cleared(app)
end

scenario = opening_scenario(private_table: true)
core = scenario[:broker].cores.fetch(scenario[:table]["__live_session_id"])
core.invitations.delete("guest")
scenario[:app].notification_action(:open_invitation, scenario[:captured])
assert(scenario[:app].opened_table == nil, "app notification granted private access without a native invitation")
assert_context_cleared(scenario[:app])

# The exception for reading applies ONLY to the explicitly opened notification.
scenario = opening_scenario
notifications = scenario[:app].instance_variable_get(:@invitation_notifications)
clicked = scenario[:gateway].rows["Guest"].first
assert(notifications.pending(recipient: "Guest").empty?, "ordinary listing resurrected read notifications")
notifications.with_opened(clicked) do
  assert(notifications.pending(recipient: "Guest").length == 1, "explicitly opened read notice was rejected")
end
assert_context_cleared(scenario[:app])
wrong_app = OpenedNotice.new(**scenario[:captured].to_h.merge(app_uuid: "another-app"))
wrong_type = OpenedNotice.new(**scenario[:captured].to_h.merge(type: "game_room.invitation_rejected"))
[wrong_app, wrong_type].each do |notice|
  notifications.with_opened(notice) { assert(notifications.pending(recipient: "Guest").empty?, "unrelated notification became an invitation") }
end
begin
  notifications.with_opened(scenario[:captured]) { raise "diagnostic exception" }
rescue RuntimeError
  assert_context_cleared(scenario[:app])
end
puts "Opened/read notifications: fresh public/private acceptance, rejection, cancellation, TTL, identity, authorization and network recovery passed"

# A native table notification must ignore tournament entries in the shared
# Ctrl+J list, including when its own table has already disappeared.
scenario = opening_scenario
app = scenario[:app]
app.define_singleton_method(:load_pending_invitations) { [{tournament_invitation: {'token' => 'unrelated'}}] }
app.notification_action(:open_invitation, scenario[:captured])
assert(app.alerts.last == 'This table is no longer available.', 'Mixed invitations did not handle the stale native table')
assert_context_cleared(app)
puts 'PASS native notification ignores unrelated tournament invitations in the common picker'
