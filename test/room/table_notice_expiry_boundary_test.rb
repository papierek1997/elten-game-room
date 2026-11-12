require_relative '../support/table_watch'

metadata = {'format'=>1, 'game'=>'uno', 'table_id'=>12,
  'live_session_id'=>'room-expiry-boundary', 'created_at'=>1000, 'expires_at'=>1300}.freeze
notice = WatchNotice.new(id:7, app_uuid:'uuid', type:GameRoomTableWatch::TYPE,
  sender:'Bob', metadata:metadata)

now = 1299
receiver = GameRoomTableWatch::Receiver.new(user:'Alice', games:['uno'], uuid:'uuid', clock:-> { now })
receiver.games = ['uno']
assert(receiver.receive(notice), 'Unexpired notice was not delivered')
assert(!receiver.receive(notice) && receiver.visible?(notice), 'Ordinary duplicate semantics changed')

now = 1300
expired = GameRoomTableWatch::Receiver.new(user:'Alice', games:['uno'], uuid:'uuid', clock:-> { now })
assert(!expired.receive(notice), 'Already expired notice was delivered')

# Only time advances: visible? and received? see the same valid notification,
# then its unchanged expiry is reached before receive's final data read.
calls, armed = 0, false
clock = lambda do
  calls += 1 if armed
  armed && calls >= 6 ? 1300 : 1299
end
boundary = GameRoomTableWatch::Receiver.new(user:'Alice', games:['uno'], uuid:'uuid', clock:clock)
boundary.games = ['uno']
armed = true
assert(boundary.receive(notice) == false, 'Expiry during receipt was not safely ignored')
assert(calls == 6, 'Fixture did not reach expiry on the final receipt validation')
assert(notice.metadata.equal?(metadata) && notice.metadata['expires_at'] == 1300,
  'Fixture changed the notification instead of advancing time')

puts 'PASS table notice receipt at expiry boundary, ordinary delivery, duplicate and already-expired controls'
