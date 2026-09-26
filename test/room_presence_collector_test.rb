require "json"
require "thread"

path = File.expand_path("../lib/game_room_presence_collector.rb", __dir__)
raise "Room presence collector is missing" unless File.file?(path)
require path

def assert(value, message)
  raise message unless value
end

class PresenceStorage
  def initialize
    @data, @lock = {}, Mutex.new
  end

  def update_json(path, default:)
    @lock.synchronize do
      value = JSON.parse(JSON.generate(@data.fetch(path, default)))
      yield value
      @data[path] = JSON.parse(JSON.generate(value))
      value
    end
  end
end

storage = PresenceStorage.new
first = GameRoomPresence::Collector.reporter_key(storage: storage, user: "Alice")
second = GameRoomPresence::Collector.reporter_key(storage: storage, user: "ALICE")
other = GameRoomPresence::Collector.reporter_key(storage: storage, user: "Bob")
assert(first.match?(/\A[0-9a-f]{64}\z/) && first == second && first != other,
  "Reporter identity is not stable per account and independent of nickname spelling")
assert(first != GameRoomPresence::Collector.reporter_key(storage: PresenceStorage.new, user: "Alice"),
  "Independent installations reused a reporter identity")
class PresenceStoreSpy
  attr_reader :writes

  def initialize
    @writes = []
  end

  def publish(rooms, cancellation_token: nil)
    @writes << JSON.parse(JSON.generate(rooms))
    true
  end
end

store = PresenceStoreSpy.new
syncs = 0
current = "Alice"
collector = GameRoomPresence::Collector.new(user: "Alice", store: store,
  current_user: -> { current }, synchronize_clock: -> { syncs += 1 })
assert(collector.heartbeat && store.writes.empty? && syncs == 0, "Loading the application published idle presence")
Snapshot = Struct.new(:table, :members, :bots, :observers, keyword_init: true)
room = Snapshot.new(table: {"__statistics_room_id" => "11111111-1111-4111-8111-111111111111",
  "game" => "tic_tac_toe", "private" => true, "status" => "waiting", "name" => "Private title", "__id" => 123},
  members: %w[Alice Bob ALICE], bots: GameRoomParticipants.bots_for(123, 1), observers: ["Bob"])
registration = collector.register { |_token| [room] }
assert(collector.heartbeat, "Presence heartbeat failed")
reported = store.writes.last.first
assert(reported == {"room_key" => Digest::SHA256.hexdigest(room.table["__statistics_room_id"]),
  "game" => "tic_tac_toe", "private_room" => true, "people" => 2, "playing" => false},
  "Presence did not count connected humans and observers without bot seats")
assert(!JSON.generate(store.writes).match?(/Alice|Bob|Private title|11111111|123/),
  "Private names, native identifiers or unhashed room identity entered presence data")
registration.close
registration.close
assert(collector.heartbeat && store.writes.last == [], "Closing the source did not clear its current rooms")
count = store.writes.length
collector.heartbeat
assert(store.writes.length == count, "Idle presence was rewritten indefinitely")
registration = nil
registration = collector.register { |_token| registration.close; [room] }
collector.heartbeat
assert(store.writes.length == count, "A source closed during refresh still renewed its presence")
registration = collector.register { |_token| [room] }
collector.heartbeat
count = store.writes.length
registration.close
broken = collector.register { |_token| nil }
assert(collector.heartbeat == false && store.writes.length == count, "A failed snapshot was published as an empty room list")
broken.close
bad_room = room.dup
bad_room.members = nil
broken = collector.register { |_token| [bad_room] }
assert(collector.heartbeat == false && store.writes.length == count, "Missing membership was published as everyone leaving")
broken.close
current = "Bob"
assert(collector.heartbeat == false && store.writes.length == count, "A different account cleared the old account's presence")
current = "Alice"
token = Object.new
token.define_singleton_method(:raise_if_cancelled!) { raise IOError, "Cancelled" }
assert(collector.heartbeat(token) == false && store.writes.length == count, "Cancelled presence performed a write")
collector.heartbeat
assert(store.writes.last == [], "Recovered presence did not clear the departed room")
puts "PASS room presence identity, membership, privacy, cleanup, cancellation and failure isolation"
