require_relative "../support/invitation_receipts"
require_relative "../support/table_watch"
require "timeout"

now, user = 1000.0, "Receipt guest"
worker = WatchWorker.new
outbox = InvitationResponseOutbox.new(worker: worker,clock: -> { now },current_user: -> { user })
broker = NativeLiveSessionsBroker.new
gateway = DurableNoticeGateway.new
owner = InvitationAppDriver.new(broker,"Receipt owner",gateway)
$game_room_test_user = "Receipt owner"
room = owner.transport.create_room(name: "Audit delivery",game: "makao",owner: "Receipt owner",game_options: "{}")
invitation = owner.send(:deliver_table_invitation,room,user).invitation
guest = InvitationAppDriver.new(broker,user,gateway,fresh: true)
attempts, fail_send = 0, true
original = guest.method(:send_notification)
guest.define_singleton_method(:send_notification) do |*args, **kwargs|
  attempts += 1
  raise EltenAPI::LiveSessions::TimeoutError, "before receipt delivery" if fail_send
  original.call(*args,**kwargs)
end
guest.instance_variable_set(:@invitations,InvitationRepository.new(transport: guest.transport,
  notification_source: ->(recipient,time) { guest.instance_variable_get(:@invitation_notifications).pending(recipient: recipient,now: time) },
  response_sender: ->(row,response) { guest.send(:deliver_invitation_response,row,response) },response_outbox: outbox))
$game_room_test_user = user
pending = guest.send(:load_pending_invitations).first[:invitation]
assert(guest.send(:reject_pending_invitation,pending), "decision not retained when delivery offline")
guest.instance_variable_get(:@invitations).respond(pending,recipient: user,response: "rejected")
assert(attempts == 1 && gateway.rows[user].all?(&:revoked), "decision re-sent or notice not consumed")
outbox.tick
assert(!worker.busy?, "receipt retried without backoff")
now += 14; outbox.tick
assert(!worker.busy?, "receipt backoff too short")
fail_send = false
now += 1; outbox.tick; worker.finish; outbox.tick
assert(attempts == 2 && guest.sent.length == 1, "pending reply not delivered exactly once")
reply = guest.sent.last
$game_room_test_user = "Receipt owner"
receipt = Receipt.new(id: 901,app_uuid: "test-app",type: reply[0],sender: user,metadata: reply[1])
program = Object.new
program.define_singleton_method(:server_app_uuid) { "test-app" }
program.define_singleton_method(:revoke_sent_notification) { |_user, key:| true }
receipt_gateway = ReceiptGateway.new
2.times do |index|
  duplicate = receipt.dup
  duplicate.id = 901 + index
  GameRoomInvitationReceipts.process(program,duplicate,gateway: receipt_gateway,client: :client)
end
assert(owner.instance_variable_get(:@table_activity).entries_for(room).map(&:kind) == %w[invited invitation_rejected], "duplicate/missing room event after retry")
assert(owner.send(:deliver_table_invitation,room,user).created?, "recovered response did not unlock sender")

# Rejection/acceptance is immutable even when a fresh program sees the same
# receipt identity. Other accounts must not inherit or send pending work.
row = invitation.merge("__id"=>901)
limited = EltenAPI::LiveSessions::TimeoutError.new("HTTP 429")
def limited.status; 429; end
calls = 0
outbox.submit(row,"accepted") { |_,_| calls += 1; raise limited }
now += 59; outbox.tick
assert(!worker.busy?, "429 backoff not respected")
now += 1; outbox.tick
assert(worker.busy?, "429 receipt never retried")
worker.finish(limited); outbox.tick
now += 60; user = "another account"; outbox.tick
assert(!worker.busy? && calls == 1, "old account sent a receipt")
user = "Receipt guest"
outbox.submit(row.merge("__id"=>902),"rejected") { |_,_| calls += 1; raise limited }
now += 301; outbox.tick
assert(!worker.busy?, "expired receipt was retried")

permanent = ArgumentError.new("recipient not authorized")
begin
  outbox.submit(row.merge("__id"=>903),"rejected") { raise permanent }
  raise "permanent send error swallowed"
rescue ArgumentError => error
  assert(error.equal?(permanent), "permanent error changed")
end
now += 60; outbox.tick
assert(!worker.busy?, "permanent send error retried")

# The actual worker, not just a scheduler double: a blocked network send must
# not keep the UI tick on the call stack. The gate is local and deterministic.
entered, release = Queue.new, Queue.new
background = InvitationResponseOutbox.new(clock: -> { now },current_user: -> { user })
first = true
background.submit(row.merge("__id"=>904),"rejected") do
  if first
    first = false
    raise EltenAPI::LiveSessions::TimeoutError, "offline"
  end
  entered << true
  release.pop
end
now += 15
Timeout.timeout(2) { background.tick }
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
Thread.pass while entered.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
assert(!entered.empty?, "background retry did not start")
release << true

# Loading recipients is a safe read. Do not lose an announcement before the
# first send, but still cancel it on expiry, table closure or account switch.
[Limited.new("HTTP 429"), EltenAPI::LiveSessions::TimeoutError.new("connection lost")].each do |error|
  now = 2000
  worker = WatchWorker.new
  sent = []
  repo = Object.new
  repo.define_singleton_method(:recipients) { |*_,**_| ["Recipient"] }
  sender = GameRoomTableWatch::Sender.new(user: "Host",repository: repo,online: -> { ["Recipient"] },
    worker: worker,current_user: -> { "Host" },clock: -> { now },send_notice: ->(*args) { sent << args })
  table = {"owner"=>"Host","status"=>"waiting","game"=>"uno","__id"=>7,"__live_session_id"=>"load-retry"}
  assert(sender.enqueue(table), "table not queued")
  sender.tick; worker.finish(error); sender.tick
  delay = error.respond_to?(:status) ? 60 : 15
  now += delay-1; sender.tick
  assert(!worker.busy?, "recipient read retried too soon")
  now += 1; sender.tick
  assert(worker.busy?, "recipient lookup dropped")
  worker.finish; sender.tick; worker.finish; sender.tick
  assert(sent.length == 1 && !sender.enqueue(table), "recovered table duplicated or lost")
  now += 1
  table = table.merge("__live_session_id"=>"cancel-retry")
  sender.enqueue(table); sender.tick; worker.finish(error); sender.tick
  sender.cancel("cancel-retry"); now += 61; sender.tick
  assert(!worker.busy?, "closed table retry")
  table = table.merge("__live_session_id"=>"expired-retry")
  sender.enqueue(table); sender.tick; worker.finish(error); sender.tick
  now += 301; sender.tick
  assert(!worker.busy? && sent.length == 1, "expired table retry")
end
puts "PASS delivery: decision/delivery split, reply retry/backoff/identity/history, account and expiry isolation; recipient-load recovery without duplicate sends"
