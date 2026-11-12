require_relative '../support/table_watch_runtime'

now = 2_000_000_000
uuid = EltenGameRoom.server_app_uuid
metadata = {'format'=>1, 'game'=>'uno', 'table_id'=>8,
  'live_session_id'=>'room-open-expiry', 'created_at'=>now, 'expires_at'=>now + 300}.freeze
notice = Notice2.new(id:501, app_uuid:uuid, type:GameRoomTableWatch::TYPE,
  sender:'Bob', metadata:metadata)
snapshot = WidgetSnapshot.new(table:{'__id'=>8, '__live_session_id'=>'room-open-expiry',
  'game'=>'uno', 'owner'=>'Bob', 'status'=>'waiting', 'private'=>false}, members:['Bob'])

app = EltenGameRoom.allocate
transport = Object.new
transport.define_singleton_method(:start) { true }
lookups, opened, alerts = [], [], []
lobby = Object.new
lobby.define_singleton_method(:open_table_snapshots) { |**options| lookups << options; [snapshot] }
app.instance_variable_set(:@transport, transport)
app.instance_variable_set(:@lobby, lobby)
app.define_singleton_method(:initialize_services) { nil }
app.define_singleton_method(:record_statistics_visit) { nil }
app.define_singleton_method(:run_network_task) { |*_, **_, &operation| operation.call }
app.define_singleton_method(:open_widget_table) { |value| opened << value }
app.define_singleton_method(:alert) { |text| alerts << text }

previous_receiver = EltenGameRoom.instance_variable_get(:@table_watch_receiver)
begin
  calls, armed = 0, false
  clock = lambda do
    calls += 1 if armed
    armed && calls >= 4 ? now + 300 : now + 299
  end
  receiver = GameRoomTableWatch::Receiver.new(user:'Alice', games:['uno'], uuid:uuid, clock:clock)
  receiver.games = ['uno']
  EltenGameRoom.instance_variable_set(:@table_watch_receiver, receiver)
  armed = true
  assert(app.send(:open_new_table_notification, notice) == true, 'Expired action was not handled')
  assert(calls == 4, 'Fixture did not expire between visibility and the final metadata read')
  assert(lookups.empty? && opened.empty?, 'Expired metadata reached the table lookup or join')
  assert(alerts == ['This table announcement has expired or is no longer available.'],
    'Expiry did not produce one ordinary unavailable explanation')
  assert(notice.metadata.equal?(metadata), 'Fixture mutated the notification instead of advancing time')

  fresh = GameRoomTableWatch::Receiver.new(user:'Alice', games:['uno'], uuid:uuid, clock:-> { now + 299 })
  fresh.games = ['uno']
  EltenGameRoom.instance_variable_set(:@table_watch_receiver, fresh)
  alerts.clear
  app.send(:open_new_table_notification, notice)
  assert(opened == [snapshot] && lookups == [{game:'uno'}] && alerts.empty?,
    'Fresh notice no longer opens the ordinary matching table')
ensure
  EltenGameRoom.instance_variable_set(:@table_watch_receiver, previous_receiver)
end

puts 'PASS table announcement opening at expiry boundary and ordinary fresh join'
