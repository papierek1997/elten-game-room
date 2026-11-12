require_relative "../support/native_live_sessions"

class RetentionRaceSession
  attr_reader :metadata, :discovery_metadata, :id, :stack_callback

  def initialize(table_id, native_id: nil)
    @metadata, @discovery_metadata = {"owner" => "Alice"}, {}
    @id, @closed = native_id || "session-#{table_id}-#{object_id}", false
  end

  def owner?; false; end
  def closed?; @closed; end
  def leave; @closed = true; @closed_callback&.call(:left); true; end
  def on_closed(&block); @closed_callback = block; end
  def on_stack_message(**_options, &block); @stack_callback = block; end
  def on_stack_gap; end
end

def race_attach(store, id, native_id: nil)
  native = RetentionRaceSession.new(id, native_id: native_id)
  store.send(:attach_session, id, native)
  native
end

def race_prune(store, id)
  store.deactivate_room(id)
  100.upto(110) do |other|
    race_attach(store, other)
    store.deactivate_room(other)
  end
  assert(!store.instance_variable_get(:@rooms).key?(id), "race setup did not evict the original collection")
end

def race_start(store, id, session_id)
  store.send(:ingest_record, id, sequence: 1, message_id: "start-#{session_id}", sender: "Alice", created_at: 1,
    packet: {"version" => 2, "kind" => "game_started", "actor" => "Alice", "data" => {
      "session_id" => session_id, "game" => "uno", "options" => "{}", "players" => %w[Alice Bob], "created_at" => 1
    }})
end

failures = []

# Deterministically schedule leave/pruning at the exact point after the native
# callback checked membership, but before ingest_record acquires its mutex.
store = GameRoomLiveSessionStore.new(Object.new)
native = race_attach(store, 1)
race_start(store, 1, 123)
ingest = store.method(:ingest_record)
gate = -> { race_prune(store, 1) }
store.define_singleton_method(:ingest_record) do |*args, **options|
  scheduled = gate
  gate = nil
  scheduled&.call
  ingest.call(*args, **options)
end
sender = Struct.new(:user).new("Alice")
info = Struct.new(:sequence, :id, :created_at).new(2, "late-action", 2)
native.stack_callback.call(sender, {"version" => 2, "kind" => "game_action", "actor" => "Alice", "data" => {
  "session_id" => 123, "sequence" => 0, "events" => [{"action" => "draw", "value" => "", "move_id" => "late"}]
}}, info)
rebuilt = (GameRoomLiveSessionStore::Retention::ROOM_MAPS + [:rooms]).select do |map|
  store.instance_variable_get("@#{map}").key?(1)
end
puts "Late callback recreated maps: #{rebuilt.inspect}"
failures << "late callback recreated an evicted room" unless rebuilt.empty?

# Pruning resets numeric generation counters. An older validator must not
# publish into a new collection that coincidentally has the same generation.
module RetentionRaceValidationGate
  class << self; attr_accessor :callback; end
  def accept(record, **options)
    accepted = super
    scheduled = RetentionRaceValidationGate.callback
    RetentionRaceValidationGate.callback = nil
    scheduled&.call
    accepted
  end
end
GameRoomLiveSessionStore::RecordValidator.prepend(RetentionRaceValidationGate)
store = GameRoomLiveSessionStore.new(Object.new)
race_attach(store, 1)
race_start(store, 1, 123)
RetentionRaceValidationGate.callback = lambda do
  race_prune(store, 1)
  race_attach(store, 1)
  race_start(store, 1, 456)
end
old = store.send(:records_for, 1).map { |record| record.packet.dig("data", "session_id") }
current = store.send(:records_for, 1).map { |record| record.packet.dig("data", "session_id") }
puts "Validator snapshot/current after generation reuse: #{old.inspect}/#{current.inspect}"
assert(old == [123], "race setup did not retain the old reader's snapshot")
failures << "old validator published into the new collection" unless current == [456]

# A retained collection can outlive membership. A validation without a current
# owner must not become the cache for a subsequent native membership.
store = GameRoomLiveSessionStore.new(Object.new)
original = race_attach(store, 1)
race_start(store, 1, 789)
store.deactivate_room(1)
store.send(:records_for, 1)
race_attach(store, 1, native_id: original.id)
current = store.send(:records_for, 1).map { |record| record.packet.dig("data", "session_id") }
puts "Rejoined retained collection: #{current.inspect}"
failures << "inactive validation hid the rejoined game" unless current == [789]

raise failures.join("; ") unless failures.empty?
puts "PASS retention races: atomic native-source check, collection identity and membership-aware validation cache"
