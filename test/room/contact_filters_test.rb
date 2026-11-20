require_relative "../support/host_source"
require_relative "../support/settings_widget"
require_relative "../support/native_notification_mute"
require 'timeout'

# Real host objects and list grouping, offline; no altered installed client.
host = File.join(EltenTestHost.root, "src/eapi")
require_relative '../support/app_notification_models'
def p_(_context, text); text; end
require File.join(host, "notificationgroups.rb")
HostContactNotice = Struct.new(:id, :cat, :app_uuid, :date, :update_time, :revoked, :payload, :alert, keyword_init: true)
CONTACT_RUNTIME = TestTaskRuntime.new('contact-test')
module Programs
  def self.notification_program(_uuid); EltenGameRoom; end
  def self.runtime_for(_program); CONTACT_RUNTIME; end
end
module EltenAPI::NotificationService
  class << self
    attr_accessor :rows, :active_reads
    def active_notifications
      self.active_reads = active_reads.to_i + 1
      rows || []
    end
  end
end
user = "Alice"
Session.define_singleton_method(:name) { user }
Session.define_singleton_method(:notifications_update) { }
uuid = "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80"
EltenGameRoom.define_singleton_method(:server_app_uuid) { uuid }
EltenGameRoom.define_singleton_method(:name) { "Game Room" }
settings = EltenGameRoom::DEFAULT_SETTINGS.merge("invitation_notifications" => "contacts", "table_watch_contacts_only" => true)
EltenGameRoom.define_singleton_method(:normalized_settings) { settings }
EltenGameRoom.contacts_stop
started, release = Queue.new, Queue.new
reads = []
names = ["Bob"]
EltenLink::Contacts.define_singleton_method(:list) do |_client|
  reads << [Thread.current, Programs.current_runtime, Session.name]
  started << true
  release.pop
  names.dup
end
now = Time.now.to_i
notice = lambda do |id, sender, type = "game_room.invitation"|
  HostContactNotice.new(id: id, cat: "app", app_uuid: uuid, date: now, revoked: false, alert: "",
    payload: { "sender" => sender, "type" => type, "metadata" => {
      "sender" => sender, "table_name" => "Room", "game_name" => "UNO", "format" => 1,
      "game" => "uno", "table_id" => id, "live_session_id" => "room-#{id}", "created_at" => now, "expires_at" => now + 300 } })
end
rows = [notice.call(10, "Bob"), notice.call(11, "Eve"), notice.call(12, "Bob", GameRoomTableWatch::TYPE), notice.call(13, "Eve", GameRoomTableWatch::TYPE)]
EltenAPI::NotificationService.rows = rows
receiver = GameRoomTableWatch::Receiver.new(user: user, games: ["uno"], uuid: uuid)
receiver.games = ["uno"]
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
helper = Object.new.extend(NotificationGroups)
GameRoomInvitationReceipts.install(EltenGameRoom)
delivered = []
$notifications_callback = ->(event) { delivered << event }
audio = []
EltenGameRoom.define_singleton_method(:play_sound_from_asset) { |name, volume:| audio << [name, volume] }

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
rows.each do |row|
  _, _, presentation = Programs.receive_app_notification(row)
  assert(presentation.default_suppressed? && presentation.sound.nil?, "unknown/foreign sender leaked speech/audio")
end
initial_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
assert(initial_elapsed < 0.75, "initial notification UI calls blocked behind contact read: #{initial_elapsed}s")
# Dispatch scheduling is not time spent grouping notifications on the UI.
Timeout.timeout(3) { started.pop }
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
250.times do
  assert(helper.build_notification_groups(rows).empty?, "unknown contacts left a visible notification row")
  EltenGameRoom.contacts_tick
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
assert(reads.length == 1 && reads[0][0] != Thread.current && reads[0][1].equal?(CONTACT_RUNTIME), "read duplicated, ran on UI or lost runtime")
assert(elapsed < 0.75 && delivered.empty? && audio.empty?, "slow contact read blocked the UI or announced too early")
assert(initial_elapsed + elapsed < 0.75, "combined UI notification calls blocked behind contact read: #{initial_elapsed + elapsed}s")
release << true
wait_background_work(EltenGameRoom.contacts_cache.instance_variable_get(:@worker)) or raise "read hung"
EltenGameRoom.contacts_tick
assert(delivered.map { |e| e["id"] }.sort == [10, 12] && audio.length == 2, "first contact notification lost/duplicated after loading")
assert(helper.build_notification_groups(rows).flat_map(&:ids).sort == [10, 12], "main/history list shows strangers or loses contacts")
reads_before_idle = EltenAPI::NotificationService.active_reads.to_i
20.times { EltenGameRoom.contacts_tick }
assert(EltenAPI::NotificationService.active_reads.to_i == reads_before_idle,
  "empty contact ticks scan active native notifications")
rows.each { |row| Programs.receive_app_notification(row) }
assert(delivered.length == 2 && audio.length == 2, "ticks or native redelivery repeated a deferred notice")

# Use the authenticated envelope sender, not a name supplied in metadata.
forged = notice.call(14, "Eve")
forged.payload["metadata"]["sender"] = "Bob"
assert(Programs.receive_app_notification(forged).last.default_suppressed?, "forged metadata bypassed contact filter")
settings = settings.merge("invitation_notifications" => "everyone", "table_watch_contacts_only" => false)
assert(Programs.receive_app_notification(forged).last.default_suppressed?, "everyone mode announced a mismatching sender")
assert(helper.build_notification_groups([forged]).empty?, "everyone mode listed a mismatching sender")
assert(helper.build_notification_groups(rows).flat_map(&:ids).sort == [10, 11, 12, 13], "disabled filters still hide people")
assert(reads.length == 1, "disabling filters fetches contacts")

# Account changes discard pending work, and a late old-user response is ignored.
settings = settings.merge("invitation_notifications" => "contacts")
EltenGameRoom.contacts_cache.snapshot(force: true)
Timeout.timeout(3) { started.pop }
old = EltenGameRoom.contacts_cache
row = notice.call(20, "Bob")
EltenAPI::NotificationService.rows << row
Programs.receive_app_notification(row)
user = "Carol"
new_cache = EltenGameRoom.contacts_cache
assert(new_cache != old && new_cache.user == "carol", "cache reused across accounts")
release << true
wait_background_work(old.instance_variable_get(:@worker))
EltenGameRoom.contacts_tick
assert(delivered.length == 2, "old account's queued notification was delivered")
assert(new_cache.instance_variable_get(:@contacts).nil?, "old response populated new account")

# Nothing is announced after being removed or expiring while awaiting contacts.
user = "Alice"
EltenGameRoom.contacts_stop
rows = [notice.call(30, "Bob"), notice.call(31, "Bob"), notice.call(32, "Bob")]
rows[1].payload["metadata"]["expires_at"] = now - 1
EltenAPI::NotificationService.rows = rows
rows.each { |r| Programs.receive_app_notification(r) }
Timeout.timeout(3) { started.pop }
EltenAPI::NotificationService.rows = rows.drop(1)
GameRoomTest::NativeNotificationMute.with_mode(1) do
  release << true
  wait_background_work(EltenGameRoom.contacts_cache.instance_variable_get(:@worker))
  EltenGameRoom.contacts_tick
end
EltenGameRoom.contacts_tick
assert(delivered.length == 2 && audio.length == 2, "expired/dismissed/DND notification was later announced")
EltenGameRoom.contacts_stop
$notifications_callback = nil

# Exercise the real host's normal speech delivery as well as its callback path.
# No window is opened: only the final speaker/sound sinks are recorded.
load File.join(host, "common/activity.rb")
EltenGameRoom.include(EltenAPI::Common)
speech = []
EltenGameRoom.define_method(:speak) { |text, **options| speech << [text, options, Thread.current] }
EltenGameRoom.define_method(:play_sound) { |_sound| raise "unexpected host sound" }
settings = settings.merge("invitation_notifications" => "everyone")
native_notice = Programs.app_notification_from(notice.call(40, "Bob"))
EltenGameRoom.present_deferred_contact_notification(native_notice)
assert(speech.length == 1 && speech[0][0].include?("Bob") &&
  speech[0][1] == {stop: false, break_sequence: false} && speech[0][2] == Thread.current,
  "native deferred delivery lost speech, interrupted speech, or left the UI thread")
puts "PASS host contacts: delayed first delivery, actual groups, runtime, duplicates, envelope sender, opt-out, account switch, expiry/dismissal/DND; 250 UI/group ticks #{(elapsed * 1000).round(2)} ms"
