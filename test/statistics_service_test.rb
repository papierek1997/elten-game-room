require "json"
require "monitor"

module Log
  class << self
    attr_accessor :warnings, :failure

    def warning(message)
      raise failure if failure
      (self.warnings ||= []) << message
    end
  end
end

module EltenLink
  class Client
    def method_missing(*)
      raise "Statistics initialization attempted network I/O"
    end
  end

  module Apps
    def self.schema(*)
      raise "Statistics enqueue attempted network I/O"
    end
  end
end

module StatisticsServiceTests
  class MemoryProgram
    attr_reader :files, :updates
    attr_accessor :failure

    def initialize
      @files, @updates, @lock = {}, 0, Monitor.new
    end

    def read_json(path, default: nil)
      @lock.synchronize { copy(@files.fetch(path, default)) }
    end

    def update_json(path, default: nil)
      @lock.synchronize do
        @updates += 1
        raise @failure if @failure
        value = copy(@files.fetch(path, default))
        yield value
        @files[path] = copy(value)
        copy(value)
      end
    end

    def copy(value)
      JSON.parse(JSON.generate(value))
    end

    def self.server_app_uuid
      "statistics-test-app"
    end
  end

  class Store
    attr_reader :writes, :tokens
    attr_accessor :result, :failure, :on_write

    def initialize
      @writes, @tokens, @result = [], [], true
    end

    def write_batch(payloads, cancellation_token: nil)
      @writes << payloads
      @tokens << cancellation_token
      @on_write.call if @on_write
      raise @failure if @failure
      @result
    end
  end

  class MemoryTable
    attr_reader :rows

    def initialize
      @rows = []
    end

    def select(where:, columns: nil, order: [], limit: 2000, include_access: false)
      rows = @rows.select { |row| where.all? { |key, value| row[key] == value } }
      order.reverse_each do |key, direction|
        rows = rows.sort_by { |row| row[key] }
        rows.reverse! if direction == "desc"
      end
      rows.first(limit).map do |row|
        if columns
          row.select { |key, _| columns.include?(key) }
        else
          include_access ? row.merge("__access" => {"owner" => true}) : row.dup
        end
      end
    end

    def upsert(values)
      @rows << values.merge("__id" => 7) if @rows.empty?
      @rows.first.dup
    end

    def insert(values)
      row = values.merge("__id" => @rows.length + 1)
      @rows << row
      row.dup
    end
  end

  class MemoryApi
    attr_reader :tables

    def initialize
      @tables = GameRoomStatistics::Schema::TABLES.keys.to_h { |name| [name, MemoryTable.new] }
    end

    def schema(*)
      tables = JSON.parse(JSON.generate(GameRoomStatistics::Schema::TABLES))
      tables.each_value { |table| table["permissions"] = table["permissions"].to_h { |name| [name, true] } }
      {"data" => {"server" => {"tables" => tables}}}
    end

    def table(_client, _app_uuid, name)
      @tables.fetch(name)
    end
  end

  class Cancelled < StandardError; end

  class Token
    attr_accessor :cancelled
    attr_reader :checks

    def initialize
      @checks = 0
    end

    def raise_if_cancelled!
      @checks += 1
      raise Cancelled, "Cancelled" if cancelled
    end
  end

  Replay = Struct.new(:finished, :accepted_events, :state) do
    def finished?
      finished
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

    def build(program: MemoryProgram.new, store: Store.new, user: "Alice", **options)
      queue = GameRoomStatistics::Queue.new(storage: program, user: user)
      service = GameRoomStatistics::Service.new(program: program, user: user, queue: queue,
        store: store, clock: -> { Time.utc(2026, 9, 25, 22, 30).to_i },
        current_user: -> { user }, **options)
      [service, queue, program, store]
    end

    def session(mode: "humans")
      {"id" => 918273, "__native_session_id" => "native-private-id", "__controllers" => {},
        "__statistics" => {"id" => "12345678-1234-4234-8234-123456789abc",
          "started_at" => Time.utc(2026, 1, 10, 23, 30).to_i, "mode" => mode}}
    end

    def observe(service, session: self.session, viewer: "Alice", participants: ["Alice", "Bob"],
      replay: Replay.new(false, [], nil), game_id: "war")
      service.observe(session: session, replay: replay, game_id: game_id,
        viewer: viewer, participants: participants)
    end

    def test_reopening_yesterdays_real_four_in_a_row_does_not_create_a_player_day_today
      require_relative "../lib/game_simulation"
      require_relative "../games/four_in_a_row"
      game = GameRoomGames::FourInARow.new
      players = %w[Alice Bob]
      repository = GameRoomSimulation::Repository.new(players)
      snapshot, events = session, []
      yesterday = Time.utc(2026, 9, 25, 21, 59).to_i
      today = Time.utc(2026, 9, 25, 22, 0).to_i
      active = game.replay(snapshot, events, repository)
      [0, 1, 0, 1, 0, 1, 0].each_with_index do |column, index|
        replay = game.replay(snapshot, events, repository)
        status, plan = game.action_for({"kind" => "grid", "action" => "select", "x" => column}, replay, replay.current_player)
        equal(:ok, status)
        command = plan.events.first
        events << {"id" => index + 1, "action" => command.action, "value" => command.value,
          "actor" => replay.current_player, "created_at" => yesterday}
      end
      events << {"id" => 99, "action" => "drop", "value" => "3", "actor" => "Bob", "created_at" => today}
      finished = game.replay(snapshot, events, repository)
      equal(true, finished.finished?)
      equal(nil, finished.state)
      equal(7, finished.accepted_events.length)
      [[snapshot, finished], [snapshot.merge("__aborted" => true), active],
        [snapshot.merge("__aborted" => true), finished],
        [snapshot.reject { |key, _| key == "__statistics" }, finished]].each do |closed_session, replay|
        service, queue, = build
        observe(service, session: closed_session, replay: replay, participants: players, game_id: game.id)
        equal([], queue.batch.map(&:last).select { |row| row["kind"] == "player" })
        equal(nil, service.last_error)
      end
      same_day = game.replay(snapshot, events.map { |event| event.merge("created_at" => today) }, repository)
      [active, same_day].each do |replay|
        service, queue, = build
        observe(service, session: snapshot, replay: replay, participants: players, game_id: game.id)
        equal([20260926], queue.batch.map(&:last).select { |row| row["kind"] == "player" }.map { |row| row["day_key"] })
        equal(nil, service.last_error)
      end
    end

    def test_real_nil_state_replay_uploads_through_the_actual_store_without_private_fields
      require_relative "../lib/game_simulation"
      require_relative "../games/tic_tac_toe"
      game = GameRoomGames::TicTacToe.new
      players = %w[Alice Bob]
      repository = GameRoomSimulation::Repository.new(players)
      snapshot, events = session, []
      epoch = Time.utc(2026, 9, 25, 22, 30).to_i
      [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0]].each_with_index do |(x, y), index|
        replay = game.replay(snapshot, events, repository)
        status, plan = game.action_for({"kind" => "grid", "action" => "select", "x" => x, "y" => y}, replay, replay.current_player)
        equal(:ok, status)
        command = plan.events.first
        events << {"id" => index + 1, "action" => command.action, "value" => command.value,
          "actor" => replay.current_player, "created_at" => epoch}
      end
      events << {"id" => 99, "action" => "place", "value" => "3,3", "actor" => "Bob", "created_at" => epoch + 86400}
      replay = game.replay(snapshot, events, repository)
      equal(nil, replay.state)
      equal(true, replay.finished?)
      equal(5, replay.accepted_events.size)
      api = MemoryApi.new
      store = GameRoomStatistics::Store.new(app_uuid: "offline-app", user: "Alice", client: Object.new,
        api: api, current_user: -> { "Alice" })
      service, queue, = build(store: store)
      equal(true, service.visit)
      equal(true, observe(service, session: snapshot, replay: replay, participants: players, game_id: game.id))
      equal([], api.tables.fetch(GameRoomStatistics::Schema::EVENTS).rows)
      assert(service.flush(Token.new), "Offline Store upload failed: #{service.last_error.inspect}")
      equal([], queue.batch)
      rows = api.tables.fetch(GameRoomStatistics::Schema::EVENTS).rows
      equal(%w[visit started player completed], rows.map { |row| row["kind"] })
      equal(20260926, rows.last["day_key"])
      equal([7, 0, 7, 0], rows.map { |row| row["person"] })
      assert(rows.all? { |row| (row.keys - (GameRoomStatistics::Schema::FIELDS + ["__id"])).empty? }, "Unexpected public activity fields")
      assert(!JSON.generate(rows).match?(/Alice|Bob|native-private-id|12345678-1234/), "Public activity retained private correlation data")
      equal(nil, service.last_error)
    end

    def test_out_of_schema_dates_never_poison_the_pending_batch
      service, queue, = build(clock: -> { Time.utc(1960, 1, 1).to_i })
      equal(false, service.visit)
      equal([], queue.batch)
      future = Time.utc(10_000, 1, 1).to_i
      service, queue, = build
      malformed = session.merge("__statistics" => session["__statistics"].merge("started_at" => future))
      equal(false, service.started(session: malformed, game_id: "war"))
      equal([], queue.batch)
      equal(false, observe(service, replay: Replay.new(true, [{"created_at" => future}], nil)))
      equal(%w[started], queue.batch.map { |_, payload| payload["kind"] })
      assert(queue.batch.all? { |_, payload| payload["day_key"].between?(19700101, 99991231) }, "An invalid date blocked all later uploads")
    end

    def test_overlapping_observers_share_memoization_without_duplicate_disk_writes
      service, queue, program, = build
      entered, release, starting = ::Queue.new, ::Queue.new, ::Queue.new
      queue.define_singleton_method(:push) do |*args|
        entered << true
        release.pop
        super(*args)
      end
      first = Thread.new { service.visit }
      entered.pop
      second = Thread.new { starting << true; service.visit }
      starting.pop
      10_000.times { break if second.status == "sleep"; Thread.pass }
      release << true << true
      equal([false, true], [first.value, second.value].sort_by(&:to_s))
      equal(1, program.updates)
      equal(1, queue.batch.size)
    ensure
      release << true << true if release
      [first, second].compact.each(&:join)
    end

    def test_fresh_storage_restore_acknowledges_the_original_finish_and_uploads_a_later_visit
      api = MemoryApi.new
      stores = 2.times.map do
        GameRoomStatistics::Store.new(app_uuid: "offline-app", user: "Alice", client: Object.new,
          api: api, current_user: -> { "Alice" })
      end
      first, first_queue, = build(store: stores.first)
      replay = Replay.new(true, [{"created_at" => Time.utc(2026, 9, 20).to_i}], nil)
      equal(true, observe(first, replay: replay))
      assert(first.flush, "The first completion did not upload: #{first.last_error.inspect}")
      equal([], first_queue.batch)
      events = api.tables.fetch(GameRoomStatistics::Schema::EVENTS)
      original = events.rows.find { |row| row["kind"] == "completed" }.dup

      restored, queue, = build(store: stores.last)
      later = Replay.new(true, [{"created_at" => Time.utc(2026, 9, 21).to_i}], nil)
      equal(true, observe(restored, session: session.merge("id" => 77), replay: later))
      equal(true, restored.visit)
      assert(restored.flush, "A restored finish blocked the later visit: #{restored.last_error.inspect}")
      equal([], queue.batch)
      equal([original], events.rows.select { |row| row["kind"] == "completed" })
      equal([20260926], events.rows.select { |row| row["kind"] == "visit" }.map { |row| row["day_key"] })
      count = events.rows.length
      equal(true, restored.flush)
      equal(count, events.rows.length)
      equal(nil, restored.last_error)
    end

    def test_restored_match_identity_is_deduplicated_even_if_finish_day_conflicts
      service, queue, program, = build
      first = Replay.new(true, [{"created_at" => Time.utc(2026, 9, 20).to_i}], nil)
      observe(service, replay: first)
      original = queue.batch
      later = Replay.new(true, [{"created_at" => Time.utc(2026, 9, 21).to_i}], nil)
      equal(false, observe(service, session: session.merge("id" => 77), replay: later))
      equal(original, queue.batch)
      restarted, = build(program: program)
      equal(false, observe(restarted, session: session.merge("id" => 88), replay: later))
      equal(original, queue.batch)
      assert(restarted.last_error.is_a?(GameRoomStatistics::ConflictingPayload), "Conflicting restored result was silently rewritten")
    end

    def test_constructor_failure_is_isolated_and_account_identity_is_not_mutable
      [nil, "", "   ", :Alice].each do |user|
        program = MemoryProgram.new
        service = GameRoomStatistics::Service.new(program: program, user: user, store: Store.new,
          current_user: -> { user })
        assert(service.last_error.is_a?(StandardError), "Invalid account was not diagnosed")
        equal(false, service.visit)
        equal(false, service.flush)
        equal(0, program.updates)
      end
      program = MemoryProgram.new
      program.define_singleton_method(:server_app_uuid) { raise IOError, "private construction failure" }
      service = GameRoomStatistics::Service.new(program: program, user: "Alice", current_user: -> { "Alice" },
        clock: -> { Time.utc(2026, 9, 25).to_i })
      assert(service.last_error.is_a?(IOError), "Store construction failure escaped or disappeared")
      equal(true, service.visit)
      equal(false, service.flush)
      equal(1, GameRoomStatistics::Queue.new(storage: program, user: "Alice").batch.size)
      user, current = "Alice", "Alice"
      service, queue, program, = build(user: user, current_user: -> { current })
      user.replace("Bob")
      equal(true, service.visit)
      current = "Bob"
      equal(false, observe(service, viewer: "Bob"))
      equal(1, queue.batch.size)
      equal(1, program.updates)
    end

    def test_default_dependencies_use_program_storage_and_either_uuid_accessor_without_network
      [MemoryProgram.new, Object.new].each do |program|
        unless program.is_a?(MemoryProgram)
          memory = MemoryProgram.new
          program.define_singleton_method(:server_app_uuid) { "instance-test-app" }
          program.define_singleton_method(:read_json) { |*args, **kwargs| memory.read_json(*args, **kwargs) }
          program.define_singleton_method(:update_json) { |*args, **kwargs, &block| memory.update_json(*args, **kwargs, &block) }
        end
        service = GameRoomStatistics::Service.new(program: program, user: "Alice", current_user: -> { "Alice" },
          clock: -> { Time.utc(2026, 9, 25).to_i })
        assert(service.store.is_a?(GameRoomStatistics::Store), "Service did not create its Store dependency")
        equal(program.is_a?(MemoryProgram) ? "statistics-test-app" : "instance-test-app", service.store.instance_variable_get(:@app_uuid))
        equal(true, service.visit)
        queue = GameRoomStatistics::Queue.new(storage: program, user: "Alice")
        equal([{"kind" => "visit", "day_key" => 20260925}], queue.batch.map(&:last))
      end
    end

    def test_in_memory_deduplication_is_bounded_without_losing_persistent_deduplication
      now = Time.utc(2020, 1, 1).to_i
      service, queue, program, = build(clock: -> { now })
      assert(defined?(GameRoomStatistics::Service::MAX_SEEN), "Service memoization has no declared bound")
      limit = GameRoomStatistics::Service::MAX_SEEN
      assert(limit.between?(50, 2048), "Service memoization bound is unreasonable")
      first = now
      (limit + 1).times do
        equal(true, service.visit)
        now += 86400
      end
      updates = program.updates
      now = first
      equal(false, service.visit)
      equal(updates + 1, program.updates)
      equal(limit + 1, queue.batch(limit: 4096).size)
      20.times { equal(false, service.visit) }
      equal(updates + 1, program.updates)
    end

    def test_flush_rechecks_account_and_cancellation_before_network_and_acknowledgement
      [:account, :cancel].each do |kind|
        [:before, :after_read, :after_write].each do |stage|
          current, token = "Alice", Token.new
          service, queue, _program, store = build(current_user: -> { current })
          service.visit
          before = queue.batch
          interrupt = -> { kind == :account ? current = "Bob" : token.cancelled = true }
          if stage == :before
            interrupt.call
          elsif stage == :after_read
            queue.define_singleton_method(:batch) do |limit: 50|
              result = super(limit: limit)
              interrupt.call
              result
            end
          else
            store.on_write = interrupt
          end
          equal(false, service.flush(token))
          equal(before, queue.batch)
          equal(stage == :after_write ? 1 : 0, store.writes.size)
          assert(service.last_error.is_a?(StandardError), "Interrupted upload lost its diagnostic")
        end
      end
      current = "Alice"
      service, queue, program, store = build(current_user: -> { current })
      current = "Bob"
      equal(false, service.visit)
      equal(false, service.started(session: session, game_id: "war"))
      equal(false, observe(service))
      equal([], queue.batch)
      equal(0, program.updates)
      equal([], store.writes)
      current = "ALICE"
      equal(true, service.visit)
      equal(true, service.flush(Token.new))
    end

    def test_failed_or_unconfirmed_flush_never_acknowledges_and_remains_retryable
      [nil, false, :unconfirmed, IOError.new("private upload details")].each do |result|
        service, queue, program, store = build
        service.visit
        before = queue.batch
        if result.is_a?(Exception)
          store.failure = result
        else
          store.result = result
        end
        updates = program.updates
        equal(false, service.flush)
        equal(before, queue.batch)
        equal(updates, program.updates)
        assert(service.last_error.is_a?(StandardError), "Upload failure was not retained")
        store.failure, store.result = nil, true
        equal(true, service.flush)
        equal([], queue.batch)
      end
      service, queue, program, store = build
      service.visit
      before = queue.batch
      program.failure = IOError.new("local acknowledgement failed")
      equal(false, service.flush)
      equal(before, queue.batch)
      equal(1, store.writes.size)
      program.failure = nil
      equal(true, service.flush)
      equal(store.writes.first, store.writes.last)
      equal([], queue.batch)
    end

    def test_flush_delivers_only_one_bounded_batch_and_acknowledges_the_exact_snapshot
      service, queue, program, store = build
      55.times do |index|
        queue.push("fixture-#{index}", {"kind" => "visit", "day_key" => (Date.new(2026, 1, 1) + index).strftime("%Y%m%d").to_i})
      end
      first = queue.batch
      store.on_write = -> { queue.push("during-upload", {"kind" => "visit", "day_key" => 20260927}) }
      token = Object.new
      token.define_singleton_method(:raise_if_cancelled!) { nil }
      assert(service.respond_to?(:flush), "Service cannot flush queued work")
      equal(true, service.flush(token))
      equal([first.map(&:last)], store.writes)
      equal([token], store.tokens)
      equal(6, queue.batch.size)
      equal("fixture-50", queue.batch.first.first)
      equal("during-upload", queue.batch.last.first)
      store.on_write = nil
      equal(true, service.flush)
      equal(false, queue.pending?)
      updates = program.updates
      equal(true, service.flush)
      equal(2, store.writes.size)
      equal(updates, program.updates)
    end

    def test_telemetry_failures_are_private_retryable_and_never_escape
      service, queue, program, = build
      failure = IOError.new("private Alice native-private-id payload")
      Log.warnings = []
      program.failure = failure
      equal(false, service.visit)
      equal(failure, service.last_error)
      equal([], queue.batch)
      equal(false, service.started(session: session, game_id: "war"))
      equal(false, observe(service))
      assert(!Log.warnings.empty?, "Telemetry failure was not diagnosed")
      assert(Log.warnings.all? { |message| !message.match?(/Alice|native|payload|IOError/) }, "Telemetry warning exposed private diagnostics")
      program.failure = nil
      equal(true, service.visit)
      equal(1, queue.batch.size)
      triggered, pending, storage, = build(trigger: -> { raise failure })
      equal(false, triggered.visit)
      equal(failure, triggered.last_error)
      equal(1, pending.batch.size)
      equal(false, triggered.visit)
      equal(1, storage.updates)
      broken_clock, = build(clock: -> { raise failure })
      Log.failure = failure
      equal(false, broken_clock.visit)
      equal(failure, broken_clock.last_error)
      replay = Object.new
      replay.define_singleton_method(:finished?) { raise failure }
      equal(false, observe(service, replay: replay))
    ensure
      Log.failure = nil
    end

    def test_legacy_or_malformed_metadata_counts_player_days_without_inventing_matches
      [[nil, ["Alice"], {}, "solo"], [nil, ["Alice", "Bob"], {}, "humans"],
        [nil, ["Alice", "bot:5:1"], {}, "bots"],
        [{"id" => "not-a-statistics-uuid"}, ["Alice", "Bob"], {"bob" => "bot"}, "bots"]].each do |metadata, players, controllers, mode|
        service, queue, = build
        snapshot = session.merge("__statistics" => metadata, "__controllers" => controllers)
        equal(true, observe(service, session: snapshot, participants: players,
          replay: Replay.new(false, [], nil)))
        equal([{"kind" => "player", "game" => "war", "day_key" => 20260926, "mode" => mode}], queue.batch.map(&:last))
      end
      service, queue, = build
      legacy = session.reject { |key, _| key == "__statistics" }
      equal(false, observe(service, session: legacy, participants: ["Bob"]))
      equal([], queue.batch)
    end

    def test_completion_uses_last_positive_accepted_server_timestamp_and_survives_restore
      service, queue, program, store = build
      finish = Time.utc(2026, 3, 29, 22, 30).to_i
      events = [{"created_at" => finish + 86400}, {"created_at" => finish},
        {"created_at" => 0}, {"created_at" => -1}, {"created_at" => "9999999999"}, {}]
      replay = Replay.new(true, events, nil)
      equal(true, observe(service, replay: replay))
      completions = queue.batch.map(&:last).select { |entry| entry["kind"] == "completed" }
      equal([{"kind" => "completed", "game" => "war", "day_key" => 20260330,
        "mode" => "humans", "match" => session["__statistics"]["id"]}], completions)
      equal(%w[started completed], queue.batch.map { |_, entry| entry["kind"] })
      equal([], store.writes)
      updates = program.updates
      100.times { equal(false, observe(service, replay: replay)) }
      equal(updates, program.updates)
      restored, = build(program: program, store: store)
      equal(false, observe(restored, session: session.merge("id" => 42), replay: replay))
      equal(2, queue.batch.size)
      [[false, false, events], [true, true, events], [true, false, []],
        [true, false, [{"created_at" => 0}, {}]]].each do |finished, aborted, accepted|
        candidate, pending, = build
        observe(candidate, session: session.merge("__aborted" => aborted), replay: Replay.new(finished, accepted, nil))
        assert(pending.batch.none? { |_, item| item["kind"] == "completed" }, "Unconfirmed or aborted replay was counted as completed")
      end
    end

    def test_observe_counts_only_the_current_human_viewer_without_personal_match_linkage
      scenarios = [
        ["alice", ["ALICE", "Bob"], {}, true],
        ["Alice", ["Bob"], {}, false],
        ["Observer", ["Alice", "Bob"], {}, false],
        ["Bob", ["Alice", "Bob"], {}, false],
        ["bot:55:1", ["bot:55:1", "Bob"], {}, false],
        ["Alice", ["Alice", "Bob"], {"ALICE" => "bot"}, false]
      ]
      scenarios.each do |viewer, participants, controllers, counted|
        service, queue, program, store = build
        assert(service.respond_to?(:observe), "Service cannot observe a replay")
        snapshot = session(mode: "bots").merge("__controllers" => controllers)
        equal(true, observe(service, session: snapshot, viewer: viewer, participants: participants))
        players = queue.batch.map(&:last).select { |entry| entry["kind"] == "player" }
        equal(counted ? [{"kind" => "player", "game" => "war", "day_key" => 20260926, "mode" => "bots"}] : [], players)
        writes = program.updates
        100.times { observe(service, session: snapshot, viewer: viewer, participants: participants) }
        equal(writes, program.updates)
        equal([], store.writes)
        assert(!JSON.generate(queue.batch).match?(/Alice|Bob|native|918273/), "Observation leaked a personal match link")
      end
    end

    def test_started_uses_only_valid_metadata_and_never_a_native_identity
      service, queue, _program, store = build
      assert(service.respond_to?(:started), "Service cannot enqueue a tracked start")
      equal(true, service.started(session: session(mode: "bots"), game_id: "war"))
      equal([{"kind" => "started", "game" => "war", "day_key" => 20260111,
        "mode" => "bots", "match" => session["__statistics"]["id"]}], queue.batch.map(&:last))
      restored = session(mode: "bots").merge("id" => 555, "__native_session_id" => "new-private-id")
      equal(false, service.started(session: restored, game_id: "war"))
      valid = session["__statistics"]
      [nil, [], {}, valid.merge("id" => "918273"), valid.merge("mode" => "other"),
        valid.merge("started_at" => 0), valid.merge("started_at" => "123"),
        valid.merge("started_at" => -1), valid.merge("private" => "Alice")].each do |metadata|
        equal(false, service.started(session: session.merge("__statistics" => metadata), game_id: "war"))
      end
      [nil, "", "INVALID", "private-room:Alice"].each do |game|
        equal(false, service.started(session: session, game_id: game))
      end
      equal(1, queue.batch.size)
      equal([], store.writes)
      assert(!JSON.generate(queue.batch).match?(/Alice|native|918273/), "Start leaked a native identity or nickname")
    end

    def test_repeated_and_overlapping_visits_do_not_rewrite_or_retrigger
      triggers = []
      service, queue, program, store = build(trigger: -> { triggers << :work })
      service.visit
      100.times { equal(false, service.visit) }
      equal(1, program.updates)
      other, = build(program: program, store: store, trigger: -> { triggers << :duplicate })
      equal(false, other.visit)
      equal(1, queue.batch.size)
      equal([:work], triggers)
      queue.acknowledge(queue.batch)
      restarted, = build(program: program, store: store)
      equal(false, restarted.visit)
      equal([], queue.batch)
      writes = program.updates
      100.times { restarted.visit }
      equal(writes, program.updates)
    end

    def test_visit_enqueues_only_a_warsaw_day_and_never_uploads
      triggers = []
      service, queue, _program, store = build(trigger: -> { triggers << :work })
      equal(true, service.visit)
      equal([{"kind" => "visit", "day_key" => 20260926}], queue.batch.map(&:last))
      equal([], store.writes)
      equal([:work], triggers)
      equal(store, service.store)
      equal(nil, service.last_error)
    end
  end
end

path = File.expand_path("../lib/game_statistics_service.rb", __dir__)
raise "Statistics service implementation is missing" unless File.file?(path)
require path
suite = StatisticsServiceTests::Suite.new
tests = suite.public_methods.grep(/^test_/).sort
tests = tests.select { |name| ARGV.include?(name.to_s) } unless ARGV.empty?
raise "No statistics service tests selected" if tests.empty?
tests.each { |name| suite.public_send(name) }
puts "PASS statistics service: #{tests.length} tests, #{suite.assertions} assertions"
