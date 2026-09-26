require "json"
require "monitor"

module StatisticsQueueTests
  class MemoryStorage
    attr_reader :files, :reads, :updates
    attr_accessor :next_failure, :before_update

    def initialize
      @files, @reads, @updates = {}, [], []
      @lock = Monitor.new
    end

    def read_json(path, default: nil)
      @lock.synchronize do
        @reads << path
        copy(@files.fetch(path, default))
      end
    end

    def update_json(path, default: nil)
      @lock.synchronize do
        @updates << path
        failure, @next_failure = @next_failure, nil
        return false if failure == :refuse
        return nil if failure == :nil
        raise IOError, "Write failed before commit" if failure == :before
        callback, @before_update = @before_update, nil
        callback.call if callback
        value = copy(@files.fetch(path, default))
        yield value
        @files[path] = copy(value)
        raise IOError, "Write completed but acknowledgement was lost" if failure == :after
        copy(value)
      end
    end

    def copy(value)
      JSON.parse(JSON.generate(value))
    end
  end

  class Suite
    attr_reader :assertions

    def initialize
      @assertions = 0
    end

    def assert(value, message)
      @assertions += 1
      raise message unless value
    end

    def equal(expected, actual)
      assert(expected == actual, "Expected #{expected.inspect}, got #{actual.inspect}")
    end

    def raises(error_class)
      @assertions += 1
      begin
        yield
      rescue error_class => error
        return error
      end
      raise "Expected #{error_class}"
    end

    def test_acknowledgement_survives_restart_and_never_changes_another_account
      storage = MemoryStorage.new
      alice = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      bob = GameRoomStatistics::Queue.new(storage: storage, user: "Bob")
      payload = {"kind" => "finish"}
      alice.push("shared-key", payload)
      bob.push("shared-key", payload)
      snapshot = alice.batch
      replay = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      equal(snapshot, replay.batch)
      assert(replay.respond_to?(:acknowledge), "Queue cannot acknowledge a delivered batch")
      equal(1, replay.acknowledge(snapshot))
      equal(0, replay.acknowledge(snapshot))
      equal([], alice.batch)
      equal(snapshot, bob.batch)
      equal(false, alice.push("shared-key", payload))
      raises(GameRoomStatistics::ConflictingPayload) { alice.push("shared-key", {"kind" => "visit"}) }
      equal(1, bob.size)
    end

    def test_acknowledged_history_keeps_only_the_latest_2048_keys
      storage = MemoryStorage.new
      acknowledged = (0...2047).to_h { |index| ["old-#{index}", {"value" => index}] }
      storage.files["statistics-pending.json"] = {"version" => 1, "accounts" => {
        "Alice" => {"pending" => {}, "acknowledged" => acknowledged}
      }}
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      3.times { |index| queue.push("new-#{index}", {"value" => index}) }
      equal(3, queue.acknowledge(queue.batch))
      remembered = storage.files.fetch("statistics-pending.json").fetch("accounts").fetch("Alice").fetch("acknowledged")
      equal(2048, remembered.size)
      equal("old-2", remembered.keys.first)
      equal("new-2", remembered.keys.last)
      equal(false, queue.push("old-2", {"value" => 2}))
      equal(0, queue.acknowledge([["old-2", {"value" => 2}]]))
      queue.push("new-3", {"value" => 3})
      equal(1, queue.acknowledge(queue.batch))
      equal(true, queue.push("old-2", {"value" => 2}))
      equal(false, queue.push("old-3", {"value" => 3}))
    end

    def test_stale_acknowledgement_cannot_remove_a_newer_different_payload
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      queue.push("old", {"value" => 1})
      snapshot = queue.batch
      storage.before_update = -> do
        storage.update_json("statistics-pending.json") do |state|
          state["accounts"]["Alice"]["pending"]["old"] = {"value" => 1.0}
        end
      end
      equal(0, queue.acknowledge(snapshot + [["unknown", {}]]))
      equal([["old", {"value" => 1.0}]], queue.batch)
      equal({}, storage.files["statistics-pending.json"]["accounts"]["Alice"]["acknowledged"])
      raises(GameRoomStatistics::ConflictingPayload) { queue.push("old", {"value" => 1}) }
      equal(1, queue.acknowledge(queue.batch * 2))
      equal(0, queue.acknowledge(snapshot))
      raises(GameRoomStatistics::ConflictingPayload) { queue.push("old", {"value" => 1}) }
    end

    def test_acknowledge_validates_the_entire_snapshot_before_storage
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      queue.push("keep", {"value" => 1})
      before = storage.copy(storage.files)
      updates = storage.updates.size
      [nil, {}, [["unknown", nil]], [["keep"]], [["keep", {}, "extra"]],
        [["keep", {"value" => 1}], ["", {}]], [["keep", {"value" => []}]]].each do |entries|
        raises(GameRoomStatistics::InvalidQueueData) { queue.acknowledge(entries) }
        equal(before, storage.files)
      end
      equal(updates, storage.updates.size)
    end

    def test_failed_or_uncertain_storage_writes_are_retryable
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      [:refuse, :nil, :before].each do |failure|
        storage.next_failure = failure
        raises(IOError) { queue.push("retry", {"value" => 1}) }
        equal([], queue.batch)
      end
      storage.next_failure = :after
      raises(IOError) { queue.push("retry", {"value" => 1}) }
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      equal(false, queue.push("retry", {"value" => 1}))
      snapshot = queue.batch
      [:refuse, :nil, :before].each do |failure|
        storage.next_failure = failure
        raises(IOError) { queue.acknowledge(snapshot) }
        equal(snapshot, queue.batch)
      end
      storage.next_failure = :after
      raises(IOError) { queue.acknowledge(snapshot) }
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      equal([], queue.batch)
      equal(0, queue.acknowledge(snapshot))
      equal(false, queue.push("retry", {"value" => 1}))
    end

    def test_corrupt_state_is_rejected_without_repair_or_data_loss
      assert(defined?(GameRoomStatistics::InvalidQueueState), "Queue cannot distinguish corrupt state")
      valid_account = {"pending" => {}, "acknowledged" => {}}
      roots = [nil, [], false, 3, {}, {"version" => 2, "accounts" => {}},
        {"version" => 1.0, "accounts" => {}}, {"version" => 1, "accounts" => nil},
        {"version" => 1, "accounts" => {}, "extra" => true}]
      accounts = [nil, [], {}, {"pending" => {}, "acknowledged" => [], "extra" => 1},
        {"pending" => [], "acknowledged" => {}}, {"pending" => {}, "acknowledged" => []},
        {"pending" => {"bad" => nil}, "acknowledged" => {}},
        {"pending" => {"bad" => {"nested" => []}}, "acknowledged" => {}},
        {"pending" => {"" => {}}, "acknowledged" => {}},
        {"pending" => {}, "acknowledged" => {"x" * 161 => {}}},
        {"pending" => {"same" => {}}, "acknowledged" => {"same" => {}}},
        {"pending" => (0...4097).to_h { |i| [i.to_s, {}] }, "acknowledged" => {}},
        {"pending" => {}, "acknowledged" => (0...2049).to_h { |i| [i.to_s, {}] }}]
      accounts.each { |account| roots << {"version" => 1, "accounts" => {"Alice" => account}} }
      roots << {"version" => 1, "accounts" => {"" => valid_account}}
      roots << {"version" => 1, "accounts" => {"Alice" => valid_account, "Bob" => nil}}
      roots.each do |root|
        storage = MemoryStorage.new
        storage.files["statistics-pending.json"] = root
        before = storage.copy(storage.files)
        queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
        [-> { queue.batch }, -> { queue.pending? }, -> { queue.size },
          -> { queue.push("new", {}) }, -> { queue.acknowledge([]) }].each do |operation|
          raises(GameRoomStatistics::InvalidQueueState, &operation)
          equal(before, storage.files)
        end
      end
    end

    def test_batch_is_ordered_bounded_and_detached
      storage = MemoryStorage.new
      user = "Alice"
      queue = GameRoomStatistics::Queue.new(storage: storage, user: user)
      user.replace("Bob")
      key, payload = "first", {"value" => "original"}
      queue.push(key, payload)
      key.replace("changed")
      payload["value"].replace("changed")
      59.times { |index| queue.push("key-#{index}", {"value" => index}) }
      equal(50, queue.batch.size)
      equal([], queue.batch(limit: 0))
      equal(["first", "key-0"], queue.batch(limit: 2).map(&:first))
      equal(60, queue.batch(limit: 4096).size)
      [-1, 1.5, "2", nil, false, 4097].each do |limit|
        raises(GameRoomStatistics::InvalidQueueData) { queue.batch(limit: limit) }
      end
      batch = queue.batch(limit: 1)
      batch.first[0].replace("changed")
      batch.first[1]["value"].replace("changed")
      batch.clear
      equal([["first", {"value" => "original"}]], queue.batch(limit: 1))
      equal([], GameRoomStatistics::Queue.new(storage: storage, user: "Bob").batch)
    end

    def test_user_and_entry_keys_are_validated_without_coercion
      storage = MemoryStorage.new
      [nil, "", "   ", :Alice, 12].each do |user|
        raises(GameRoomStatistics::InvalidQueueData) { GameRoomStatistics::Queue.new(storage: storage, user: user) }
      end
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      [nil, "", :key, 12, "x" * 161, "\xff".force_encoding("UTF-8")].each do |key|
        raises(GameRoomStatistics::InvalidQueueData) { queue.push(key, {}) }
      end
      equal([], storage.updates)
      key = "x" * 160
      equal(true, queue.push(key, {}))
      equal([[key, {}]], queue.batch)
    end

    def test_push_rejects_non_scalar_or_non_json_data_before_storage
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      object = Object.new
      def object.to_json(*)
        raise "Arbitrary object serialization was invoked"
      end
      disguised = Object.new
      def disguised.class
        Integer
      end
      def disguised.to_json(*)
        raise "Arbitrary object serialization was invoked"
      end
      invalid = [[], nil, "payload", {kind: "visit"}, {"x" => object}, {"x" => disguised}, {"x" => :symbol},
        {"x" => []}, {"x" => {}}, {"x" => Float::NAN}, {"x" => Float::INFINITY},
        {"x" => "\xff".force_encoding("UTF-8")}]
      invalid.each do |payload|
        raises(GameRoomStatistics::InvalidQueueData) { queue.push("invalid", payload) }
      end
      equal([], storage.updates)
      payload = {"text" => "value", "integer" => 1, "float" => 1.5, "yes" => true, "no" => false, "empty" => nil}
      equal(true, queue.push("valid", payload))
      equal([["valid", payload]], queue.batch)
    end

    def test_pending_capacity_rejects_overflow_without_losing_entries
      storage = MemoryStorage.new
      pending = (0...4095).to_h { |index| ["key-#{index}", {"value" => index}] }
      storage.files["statistics-pending.json"] = {"version" => 1, "accounts" => {
        "Alice" => {"pending" => pending, "acknowledged" => {}}
      }}
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      equal(true, queue.push("last", {"value" => 4095}))
      equal(4096, queue.size)
      equal(false, queue.push("last", {"value" => 4095}))
      assert(defined?(GameRoomStatistics::QueueFull), "Queue has no explicit capacity failure")
      before = storage.copy(storage.files)
      raises(GameRoomStatistics::QueueFull) { queue.push("overflow", {"value" => 4096}) }
      equal(before, storage.files)
      bob = GameRoomStatistics::Queue.new(storage: storage, user: "Bob")
      equal(true, bob.push("bob-first", {"value" => 1}))
      queue.acknowledge([["key-0", {"value" => 0}]])
      equal(true, queue.push("after-ack", {"value" => 1}))
      equal(4096, queue.size)
    end

    def test_duplicate_push_is_idempotent_and_conflicts_do_not_overwrite
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      payload = {"kind" => "visit", "day_key" => 20260925}
      equal(true, queue.push("same", payload))
      equal(false, queue.push("same", payload.to_a.reverse.to_h))
      raises(GameRoomStatistics::ConflictingPayload) { queue.push("same", {"kind" => "other"}) }
      equal([["same", payload]], queue.batch)
    end

    def test_push_persists_per_exact_account_without_changing_payload
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      payload = {"kind" => "visit", "day_key" => 20260925}
      assert(queue.respond_to?(:push), "Queue cannot persist an entry")
      equal(true, queue.push("visit-1", payload))
      equal([["visit-1", payload]], queue.batch)
      equal(true, queue.pending?)
      equal(1, queue.size)
      equal([["visit-1", payload]], GameRoomStatistics::Queue.new(storage: storage, user: "Alice").batch)
      equal([], GameRoomStatistics::Queue.new(storage: storage, user: "alice").batch)
      equal([], GameRoomStatistics::Queue.new(storage: storage, user: "Bob").batch)
      equal(["statistics-pending.json"], storage.updates)
      equal(1, storage.files.fetch("statistics-pending.json").fetch("version"))
      equal(["Alice"], storage.files.fetch("statistics-pending.json").fetch("accounts").keys)
      peer = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      storage.before_update = -> { peer.push("peer", {"kind" => "finish"}) }
      equal(true, queue.push("after-peer", {"kind" => "start"}))
      equal(["visit-1", "peer", "after-peer"], queue.batch.map(&:first))
      threads = 4.times.map do
        Thread.new do
          local = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
          12.times.map { |index| local.push("concurrent-#{index}", {"value" => index}) }
        end
      end
      equal(12, threads.flat_map(&:value).count(true))
      equal(15, queue.size)
      snapshot = queue.batch
      deliveries = 4.times.map { Thread.new { peer.acknowledge(snapshot) } }
      equal(15, deliveries.map(&:value).sum)
      equal(false, queue.pending?)
    end

    def test_empty_queue_does_not_write
      storage = MemoryStorage.new
      queue = GameRoomStatistics::Queue.new(storage: storage, user: "Alice")
      equal([], queue.batch)
      equal(false, queue.pending?)
      equal(0, queue.size)
      equal([], storage.updates)
      equal({}, storage.files)
    end
  end
end

path = File.expand_path("../lib/game_statistics_queue.rb", __dir__)
raise "Statistics queue implementation is missing" unless File.file?(path)
require path
suite = StatisticsQueueTests::Suite.new
tests = suite.public_methods.grep(/^test_/).sort
tests.each { |name| suite.public_send(name) }
puts "PASS statistics queue: #{tests.length} tests, #{suite.assertions} assertions"
