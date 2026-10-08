require_relative '../support/native_room_harness'
require_relative '../support/log'

h = NativeRoomHarness.new(users: %w[Alice Bob])
repositories = h.users.to_h do |user|
  [user, TableActivityRepository.new(server_tables: Object.new, transport: h.transports.fetch(user))]
end
limit = TableActivityRepository::MESSAGE_MAX_LENGTH
assert(limit == 2000, 'Chat must accept five times the previous 400-character limit')
h.broker.deliver
h.broker.automatic_delivery = false
delivered = []
h.view('Bob').on_stack_message(with_metadata: true) { |_, _, info| delivered << info.sequence }
messages = ['a' * limit, 'ż' * limit, '界' * limit, '🎲' * limit,
  ('"\\' * limit)[0, limit], ('Zażółć gęślą jaźń. ' * 150)[0, limit].rstrip,
  "First\n\tsecond\r\nthird\u0000" ]
expected = messages.map { |text| repositories['Alice'].send(:normalize_message, text) }
assert(expected.first(6) == messages.first(6), 'Valid text was shortened or altered before sending')
largest = 0
messages.each_with_index do |message, index|
  before = h.core.entries.length
  entry = h.as('Alice') { repositories['Alice'].append(table: h.table, kind: 'chat', message: message) }
  assert(entry.message == expected[index], "Message #{index} was truncated or corrupted at submission")
  assert(h.core.entries.length == before + 1, 'A long chat message generated more than one stack write')
  encoded = JSON.generate(h.core.entries.last.fetch('packet'))
  largest = [largest, encoded.bytesize].max
  assert(encoded.bytesize <= GameRoomLiveSessionStore::STACK_ENTRY_BYTES, 'Long Unicode message exceeds the native packet limit')
end
assert(delivered.empty?, 'Broker delivered callbacks despite the simulated delay')
h.broker.deliver(user: 'Bob', duplicate: true)
assert(delivered.length == messages.length * 2 && delivered.uniq.length == messages.length,
  "Scenario did not deliver each delayed message twice: #{delivered.inspect}")
received = repositories['Bob'].entries_for(h.table)
assert(received.map(&:message) == expected, 'Recipient truncated, reordered or duplicated a message')
assert(received.all? { |entry| entry.actor == 'Alice' }, 'Long chat changed sender identity')

h.broker.automatic_delivery = true
overlong = 'ą' * (limit + 1)
entry = h.as('Bob') { repositories['Bob'].append(table: h.table, kind: 'chat', message: overlong) }
assert(entry.message.length == limit && entry.message.valid_encoding?, 'Repository limit splits a Unicode character')
assert(repositories['Alice'].entries_for(h.table).last.message == 'ą' * limit, 'Receive path has a different limit')
before = h.core.entries.length
begin
  h.as('Bob') { repositories['Bob'].append(table: h.table, kind: 'chat', message: " \n\t ") }
  raise 'Empty chat was sent'
rescue ArgumentError => error
  assert(error.message == 'A chat message cannot be empty', 'Unexpected validation failure')
end
assert(h.core.entries.length == before, 'Rejected chat still wrote a record')

# The same limit applies before and after a match starts, without new tables.
h.start
entry = h.as('Alice') { repositories['Alice'].append(table: h.table, kind: 'chat', message: 'ć' * limit) }
assert(repositories['Bob'].entries_for(h.table).last.message == entry.message, 'Active game truncated chat')
assert(entry.message.length == limit, 'Active game restored the old limit')
puts "PASS chat: #{limit} characters, Unicode/emoji/escaping, one write, delayed/duplicate delivery, both directions and lobby/game; largest packet #{largest} bytes"
