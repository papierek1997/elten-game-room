require_relative "../support/table_watch_runtime"
module EltenAPI
  module NotificationService
    class << self
      attr_accessor :rows, :reads, :revoked
      def active_notifications
        self.reads = reads.to_i + 1
        rows || []
      end
      def revoke_active_notifications(ids)
        self.revoked = ids
      end
    end
  end
end
EltenAPI::NotificationService.rows = []
now = 2_000_000_000
uuid = EltenGameRoom.server_app_uuid
session_id = "cP44FMhoJwxaQ80Rm02_JY0K9QxAsveo"
notice = Notice2.new(id: 500, app_uuid: uuid, type: GameRoomTableWatch::TYPE, sender: "Bob",
  metadata: { "format" => 1, "game" => "uno", "table_id" => 8, "live_session_id" => session_id,
    "created_at" => now, "expires_at" => now + 300 })
receiver = GameRoomTableWatch::Receiver.new(user: "Alice", games: ["uno"], uuid: uuid, clock: -> { now })
receiver.games = ["uno"]
EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
EltenGameRoom.instance_variable_set(:@table_watch_loader, nil)
EltenGameRoom.instance_variable_set(:@table_watch_pruned, {})
row = { "__id" => 8, "__live_session_id" => session_id, "game" => "uno", "owner" => "Bob", "status" => "waiting", "private" => false }
snapshot = WidgetSnapshot.new(table: row, members: ["Bob"])
rows = [snapshot]
app = EltenGameRoom.allocate
transport = Object.new
transport.define_singleton_method(:start) { true }
lobby = Object.new
lobby.define_singleton_method(:open_table_snapshots) { |**_| rows }
app.instance_variable_set(:@transport, transport)
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:initialize_services) { nil }
app.define_singleton_method(:run_network_task) { |*_, **_, &block| block.call }
opened = []
alerts = []
app.define_singleton_method(:open_widget_table) { |value| opened << value }
app.define_singleton_method(:alert) { |text| alerts << text }

app.send(:open_new_table_notification, notice)
assert(opened == [snapshot], "fresh endpoint did not use ordinary widget join")
opened.clear
app.define_singleton_method(:run_network_task) { |*_, **_| nil }
app.send(:open_new_table_notification, notice)
assert(opened.empty? && receiver.visible?(notice), "network failure expired an active notice")

app.define_singleton_method(:run_network_task) do |*_, **_, &block|
  result = block.call
  now += 301
  result
end
app.send(:open_new_table_notification, notice)
assert(opened.empty? && alerts.last.include?("expired"), "slow lookup bypassed expiry")
now -= 301
app.define_singleton_method(:run_network_task) { |*_, **_, &block| block.call }
row["private"] = true
app.send(:open_new_table_notification, notice)
assert(opened.empty? && !receiver.visible?(notice), "announcement granted private access")

# Extension stop must not leave a closed sender reused on restart. Startup
# preference loading is finite, outside the UI, and is not repeated by ticks.
fake_sender = Object.new
closed = false
fake_sender.define_singleton_method(:close) { closed = true }
EltenGameRoom.instance_variable_set(:@table_watch_sender, fake_sender)
EltenGameRoom.table_watch_stop
assert(closed && EltenGameRoom.instance_variable_get(:@table_watch_sender).nil?, "stop retained a closed sender")
assert(EltenGameRoom.instance_variable_get(:@table_watch_loader).nil?, "stop retained closed loader")
receiver.games = nil
loads = 0
repository = Object.new
repository.define_singleton_method(:load) { |_user| loads += 1; ["uno"] }
EltenGameRoom.define_singleton_method(:table_watch_repository) { repository }
EltenGameRoom.table_watch_start
loader = EltenGameRoom.instance_variable_get(:@table_watch_loader)
assert(loader && wait_background_work(loader), "finite startup load did not finish")
EltenGameRoom.table_watch_tick
assert(receiver.games == ["uno"] && loads == 1, "startup settings not applied")
idle_games = ["uno"]
idle_games.define_singleton_method(:to_a) { raise "idle tick built a Settings snapshot" }
receiver.games = idle_games
EltenAPI::NotificationService.reads = 0
50.times { EltenGameRoom.table_watch_tick }
assert(loads == 1, "ticks poll notification preferences")
assert(EltenAPI::NotificationService.reads == 50, "table-notice cleanup cadence changed")
pruned = (0...2050).to_h { |id| [id, true] }
EltenGameRoom.instance_variable_set(:@table_watch_pruned, pruned)
EltenGameRoom.table_watch_tick
assert(pruned.size == 2048 && !pruned.key?(0) && !pruned.key?(1) && pruned.key?(2),
  "table-notice cleanup did not retain the newest bounded history")
EltenGameRoom.table_watch_stop
EltenGameRoom.table_watch_start
assert(EltenGameRoom.instance_variable_get(:@table_watch_loader).nil?, "loaded settings refetched on restart")
puts "Table notices: fresh-instance join, slow expiry, private guard, offline read, lifecycle and no polling: OK"

# Cold native time must defer notification presentation, not permanently fail
# the independent one-shot preference read.
require_relative '../support/server_clock'
original_clock = GameRoomClock.instance_variable_get(:@clock)
sample = nil
GameRoomClock.instance_variable_set(:@clock, game_room_test_clock { sample })
begin
  receiver.games = nil
  EltenGameRoom.table_watch_start(refresh: true)
  cold_loader = EltenGameRoom.instance_variable_get(:@table_watch_loader)
  wait_background_work(cold_loader)
  assert(EltenGameRoom.table_watch_preferences_snapshot == {state: :ready, games: ['uno']},
    'Cold server clock disabled the startup preference load')
  shared_clock = GameRoomTableWatch::Clock.new
  assert(!shared_clock.ready?, 'Cold native clock was accepted')
  sample = now.to_f
  assert(shared_clock.ready? && shared_clock.call == now, 'Clock readiness required reopening the application')
ensure
  EltenGameRoom.table_watch_stop
  GameRoomClock.instance_variable_set(:@clock, original_clock)
end
puts 'PASS cold native clock: preferences load independently; notification clock becomes ready without restart'
