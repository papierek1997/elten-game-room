require_relative "../support/invitation_receipts"
program = Object.new
program.define_singleton_method(:server_app_uuid) { "test-app" }
revoked_keys = []
program.define_singleton_method(:revoke_sent_notification) { |user, key:| revoked_keys << [user, key]; true }
receipts = ReceiptGateway.new
broker = NativeLiveSessionsBroker.new
gateway = DurableNoticeGateway.new
owner = InvitationAppDriver.new(broker, "Owner", gateway)
$game_room_test_user = "Owner"
room = owner.transport.create_room(name: "Receipts", game: "makao", owner: "Owner", game_options: "{}")
repo = owner.instance_variable_get(:@table_activity)
delivery = owner.send(:deliver_table_invitation, room, "Guest")
row = delivery.invitation
metadata = { "invitation_id" => row["__id"], "table_id" => room["__id"],
  "live_session_id" => room["__live_session_id"], "user" => "Guest", "response" => "rejected" }
receipt = Receipt.new(id: 101, app_uuid: "test-app", type: "game_room.invitation_resolved", sender: "Guest", metadata: metadata)
process = ->(notice = receipt) { GameRoomInvitationReceipts.process(program, notice, gateway: receipts, client: :client) }
assert(repo.entries_for(room).map(&:kind) == ["invited"], "sending invitation did not create exactly one room event")
assert(!owner.send(:deliver_table_invitation, room, "Guest").created?, "duplicate send lost its lock")
assert(repo.entries_for(room).length == 1, "duplicate send duplicated history")
assert(process.call, "rejection receipt not consumed")
assert(revoked_keys == [["Guest", GameRoomNotifications.invitation_key(row)]], "resolved invitation was not revoked by its exact native key")
assert(process.call, "duplicate receipt not harmless")
assert(revoked_keys.size == 1, "duplicate receipt repeated keyed revocation")
entries = repo.entries_for(room)
assert(entries.map(&:kind) == %w[invited invitation_rejected], "duplicate or missing invitation events")
assert(entries.map { |entry| repo.text_for(entry, game_name: ->(_id) { "Makao" }) } ==
  ["Owner invited Guest.", "Guest declined Owner's invitation."], "invitation actor or subject is wrong")
assert(repo.merged_history_entries(game_entries: [], game_events: [], activity_entries: entries,
  game_name: ->(_id) { "Makao" }).map(&:category) == [:room, :room], "events not in merged room history")
assert(broker.cores.fetch(room["__live_session_id"]).participants.keys == ["owner"], "rejection joined outsider to room")
assert(!TableActivityRepository::GLOBAL_KINDS.include?("invited") &&
  !TableActivityRepository::GLOBAL_KINDS.include?("invitation_rejected"), "invitation activity leaks into lobby")
assert(owner.send(:deliver_table_invitation, room, "Guest").created?, "rejection kept duplicate-send lock")

# Forged replies cannot clear a valid invitation or fabricate a history event.
new_row = InvitationRepository::SENT.values.find { |item| item["table_id"] == room["__id"] && item["recipient"] == "Guest" }
valid_metadata = metadata.merge("invitation_id" => new_row["__id"])
[["Other", valid_metadata], ["Guest", valid_metadata.merge("live_session_id" => "wrong")],
 ["Guest", valid_metadata.merge("user" => "Other")], ["Guest", valid_metadata.merge("response" => "invented")]].each_with_index do |(sender, meta), index|
  process.call(Receipt.new(id: 200 + index, app_uuid: "test-app", type: receipt.type, sender: sender, metadata: meta))
  assert(InvitationRepository::SENT.values.include?(new_row), "untrusted reply cleared invitation lock")
end
count = repo.entries_for(room).length
foreign = Receipt.new(id: 220, app_uuid: "other-app", type: receipt.type, sender: "Guest", metadata: valid_metadata)
assert(!process.call(foreign) && !receipts.revoked.include?(220), "another application's notification was touched")
$game_room_test_user = "Different account"
assert(!GameRoomInvitationReceipts.process(program, receipt, user: "Owner", gateway: receipts, client: :client), "account change was ignored")
$game_room_test_user = "Owner"
assert(repo.entries_for(room).length == count, "forged reply created history")

# Failed delivery does not invent a sent event or leave a duplicate lock.
before_failure = repo.entries_for(room).length
original_send = owner.method(:send_notification)
owner.define_singleton_method(:send_notification) { |*_args, **_kwargs| raise EltenAPI::LiveSessions::TimeoutError, "failed delivery" }
begin; owner.send(:deliver_table_invitation, room, "Failed guest"); rescue EltenAPI::LiveSessions::TimeoutError; end
owner.define_singleton_method(:send_notification, original_send)
assert(repo.entries_for(room).length == before_failure &&
  InvitationRepository::SENT.values.none? { |item| item["recipient"] == "Failed guest" }, "failed delivery recorded an event or retained a lock")

# Rejection executes the production reply sender, with no second visible notice
# and no separate local alert. Private authorization is also removed normally.
private_room = owner.transport.create_room(name: "Private receipts", game: "makao", owner: "Owner", game_options: "{}", private_table: true)
private_invitation = owner.send(:deliver_table_invitation, private_room, "Private guest").invitation
guest = InvitationAppDriver.new(broker, "Private guest", gateway, fresh: true)
guest.instance_variable_set(:@invitations, InvitationRepository.new(transport: guest.transport,
  notification_source: ->(recipient, now) { guest.instance_variable_get(:@invitation_notifications).pending(recipient: recipient, now: now) },
  response_sender: ->(invitation, response) { guest.send(:deliver_invitation_response, invitation, response) }))
$game_room_test_user = "Private guest"
pending = guest.send(:load_pending_invitations).first[:invitation]
assert(guest.send(:reject_pending_invitation, pending), "production private rejection failed")
assert(guest.sent.map(&:first) == ["game_room.invitation_resolved"] && guest.alerts.empty?, "rejection sent a second visible notice or alert")
assert(guest.transport.discover_rooms(include_private: true).none? { |table| table["__id"] == private_room["__id"] }, "rejection retained private access")
$game_room_test_user = "Owner"
reply_type, reply_metadata, _ttl = guest.sent.first
process.call(Receipt.new(id: 225, app_uuid: "test-app", type: reply_type, sender: "Private guest", metadata: reply_metadata))
assert(repo.entries_for(private_room).map(&:kind) == %w[invited invitation_rejected], "private invitation history was lost")
assert(!InvitationRepository::SENT.values.include?(private_invitation), "private rejection did not unlock sender")

# A lost HTTP reply, without realtime delivery, still produces one stable record.
broker.automatic_delivery = false
view = broker.endpoint("Owner").sessions.find { |session| session.id == room["__live_session_id"] }
view.fail_next_push = :after
retry_receipt = Receipt.new(id: 230, app_uuid: "test-app", type: receipt.type, sender: "Guest", metadata: valid_metadata)
begin
  process.call(retry_receipt)
  raise "lost reply did not reproduce"
rescue EltenAPI::LiveSessions::TimeoutError
end
assert(!receipts.revoked.include?(230), "failed history write consumed durable reply")
assert(InvitationRepository::SENT.values.include?(new_row), "failed history write discarded retry state")
process.call(retry_receipt)
assert(repo.entries_for(room).count { |entry| entry.kind == "invitation_rejected" && entry.invitation_id == new_row["__id"] } == 1,
  "lost reply duplicated rejection history")
attempt_ids = view.instance_variable_get(:@push_attempts).last(2).map(&:first)
assert(attempt_ids.uniq.length == 1, "retry changed the native activity message identity")
broker.automatic_delivery = true

# Revoking a receipt may also fail after history has already succeeded.
another = owner.send(:deliver_table_invitation, room, "Guest").invitation
last_receipt = Receipt.new(id: 240, app_uuid: "test-app", type: receipt.type, sender: "Guest",
  metadata: metadata.merge("invitation_id" => another["__id"]))
receipts.error = EltenAPI::LiveSessions::TimeoutError.new("offline revoke")
begin; process.call(last_receipt); rescue EltenAPI::LiveSessions::TimeoutError; end
receipts.error = nil
process.call(last_receipt)
assert(repo.entries_for(room).count { |entry| entry.kind == "invitation_rejected" && entry.invitation_id == another["__id"] } == 1,
  "retrying receipt cleanup duplicated history")

# Closed rooms need no reopen/join; the reply still unlocks another invitation.
closed_row = owner.send(:deliver_table_invitation, room, "Guest").invitation
view.close
closed_receipt = Receipt.new(id: 250, app_uuid: "test-app", type: receipt.type, sender: "Guest",
  metadata: metadata.merge("invitation_id" => closed_row["__id"]))
assert(process.call(closed_receipt), "closed room escaped receipt handling")
assert(!InvitationRepository::SENT.values.include?(closed_row), "closed room kept invitation lock")
assert(broker.cores.fetch(room["__live_session_id"]).closed, "receipt reopened a closed room")

# Old visible rejection duplicates are removed, but cannot invent an event.
legacy = Receipt.new(id: 260, app_uuid: "test-app", type: "game_room.invitation_rejected", sender: "Guest", metadata: { "user" => "Guest" })
assert(process.call(legacy) && receipts.revoked.include?(260), "legacy rejection duplicate was not consumed")
puts "Invitation room history, authentication, duplicate/lost replies, outsider rejection and closed rooms: OK"
