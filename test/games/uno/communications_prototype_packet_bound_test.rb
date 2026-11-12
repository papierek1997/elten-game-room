require_relative '../../support/uno_communications_prototype'
include GameRoomTest::Assertions

proto = UnoCommunicationsFixture::Proto

# Injected trusted receipts test the offline prototype's admission boundary,
# not ELTEN's network. Both delivery and recovery must check before retaining.
[:delivery, :recovery].product([1, 2]).each do |path, sequence|
  harness = UnoCommunicationsFixture::Harness.new
  client = harness.clients.fetch('Alice')
  endpoint = harness.endpoints.fetch('Alice')
  oversized = proto::Receipt.new(identity: client.identity, sequence: sequence,
    sender: 'Bob', request_id: 'oversized', data: 'x' * (proto::MAX_PACKET_BYTES + 1))
  if path == :delivery
    endpoint.push(oversized)
  else
    endpoint.define_singleton_method(:recover_after) { |_cursor| [sequence, [oversized]] }
  end
  assert_raises(proto::CapacityExceeded) { path == :delivery ? client.tick : client.recover }
  assert_equal(0, client.cursor, 'Oversized receipt advanced the accepted prefix')
  assert(client.events.empty? && client.fault, 'A bound failure changed the game or left input open')
  %i[@buffer @receipts @requests].each do |variable|
    assert(client.instance_variable_get(variable).empty?, "Oversized bytes reached #{variable}")
  end
  assert_equal(:failed, harness.command('Alice', 'deal'), 'Faulted receipt intake reopened input')
end

harness = UnoCommunicationsFixture::Harness.new
client = harness.clients.fetch('Alice')
receipt = proto::Receipt.new(identity: client.identity, sequence: 1, sender: 'Bob',
  request_id: 'byte-bound', data: 'ą' * proto::MAX_PACKET_BYTES)
harness.endpoints.fetch('Alice').push(receipt)
assert_raises(proto::CapacityExceeded) { client.tick }
assert(client.instance_variable_get(:@receipts).empty?, 'The byte limit was treated as a character limit')

harness = UnoCommunicationsFixture::Harness.new
client = harness.clients.fetch('Alice')
receipt = proto::Receipt.new(identity: client.identity, sequence: 1, sender: 'Bob',
  request_id: 'at-bound', data: 'x' * proto::MAX_PACKET_BYTES)
harness.endpoints.fetch('Alice').push(receipt)
client.tick
assert_equal(1, client.cursor, 'A malformed but bounded packet left a gap')
assert_equal(:malformed, client.last_outcome.fetch(:status))
assert_equal(nil, client.fault)
assert_equal(proto::MAX_PACKET_BYTES, client.instance_variable_get(:@receipts).fetch(1).data.bytesize)

harness = UnoCommunicationsFixture::Harness.new
client = harness.clients.fetch('Alice')
receipt = proto::Receipt.new(identity: client.identity, sequence: 1, sender: 'B' * 65,
  request_id: 'metadata-bound', data: '{}')
harness.endpoints.fetch('Alice').push(receipt)
assert_raises(proto::ProtocolError) { client.tick }
assert(client.instance_variable_get(:@receipts).empty?, 'Unbounded sender metadata was retained')
puts 'PASS offline UNO prototype bounds receipt bytes and sender metadata before buffering or journal retention'
