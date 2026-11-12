require "json"
require_relative "game_room_background"
require_relative "network_errors"
require_relative "game_room_clock"
require_relative "notification_time"
require_relative "table_variant"
require_relative "table_query_snapshot"

# Public interests, not saved games. Identity always comes from the server's
# immutable insertion author. A forged username can never subscribe somebody.
module GameRoomTableWatch
  TYPE = "game_room.table_created".freeze
  TABLE = "table_watch_preferences".freeze
  SCHEMA = {
    "visibility" => "public",
    "columns" => { "username" => "string:64", "format" => "integer", "games" => "string:2048" },
    "permissions" => %w[select insert update delete],
    "indexes" => [["username"]], "limits" => { "max_select_limit" => 1000 }
  }.freeze

  # The host owns the sample, monotonic anchor and account changes. Keep only
  # the receiver's callable/readiness interface, never a second clock cache.
  class Clock
    def initialize(source: GameRoomClock)
      @source = source
    end

    def call
      @source.now
    end

    def ready?
      !@source.server_available? || @source.synchronized?
    end
  end

  class Preferences
    COLUMNS = %w[__id __insertion_user username format games].freeze
    def initialize(table, games:)
      @table, @games = table, games.map(&:to_s)
      @query_snapshot = GameRoomTableQuerySnapshot.new
    end

    def all
      canonical(read_rows).values
    end

    def load(user)
      row = own_rows(user).first
      row ? selected(row) : []
    end

    def save(user, games)
      wanted = Array(games).map(&:to_s).uniq.sort & @games
      values = { "username" => user.to_s, "format" => 1, "games" => JSON.generate(wanted) }
      raise ArgumentError, "Too many watched games" if values["games"].bytesize > 2048
      rows = own_rows(user)
      if rows.empty?
        @table.insert(values)
        # Concurrent first registrations are reconciled by the same minimum ID.
        rows = own_rows(user)
      end
      raise IOError, "Table notification preferences could not be saved" if rows.empty?
      main = rows.first
      changes = values.reject { |key, value| main[key].to_s == value.to_s }
      @table.update(main["__id"].to_i, changes) unless changes.empty?
      rows.drop(1).map { |row| row["__id"].to_i }.each_slice(100) do |ids|
        count = @table.delete_many(ids)
        # A partial/uncertain delete is not confirmation. A later save reads
        # the remaining owned duplicates again; never include a foreign row.
        raise IOError, "Duplicate preference deletion was not confirmed" unless count == ids.length
      end
      wanted
    ensure
      @query_snapshot.invalidate
    end

    def recipients(game, online:, sender:)
      present = online.to_a.to_h { |name| [name.to_s.downcase, name.to_s] }
      present.delete(sender.to_s.downcase)
      return [] if present.empty?
      @query_snapshot.fetch { all }.filter_map do |row|
        user = row["__insertion_user"].to_s
        present[user.downcase] if !user.casecmp?(sender.to_s) && selected(row).include?(game.to_s)
      end.uniq(&:downcase)
    end

    private

    def own_rows(user)
      # Account spelling is canonical on ELTEN. Never trust the supplied name
      # alone when changing/deleting a row, including duplicate cleanup.
      rows = read_rows(where: { "username" => user.to_s })
      rows.select { |row| valid_identity?(row) && row["__insertion_user"].casecmp?(user.to_s) }.sort_by { |row| row["__id"].to_i }
    end

    def read_rows(where: {})
      latest = preference_rows(where: where, order: [["__id", "desc"]], limit: 1).first
      return [] unless latest

      upper, previous, rows = latest.fetch("__id"), 0, []
      loop do
        page = preference_rows(where: where.merge("__id" => {"gte" => previous + 1}),
          order: [["__id", "asc"]], limit: 1000)
        break if page.empty?

        unless page.first.fetch("__id") > previous &&
            page.each_cons(2).all? { |first, second| first.fetch("__id") < second.fetch("__id") }
          raise IOError, "Table notification preference pagination did not advance"
        end
        rows.concat(page.take_while { |row| row.fetch("__id") <= upper })
        previous = page.last.fetch("__id")
        # As in the registry, short pages are not EOF. Stable IDs avoid skips
        # after deletion, and the initial upper ID excludes later insertions.
        break if previous >= upper
      end
      rows
    end

    def preference_rows(where:, order:, limit:)
      rows = @table.select(where: where, columns: COLUMNS, order: order, limit: limit)
      unless rows.is_a?(Array) && rows.length <= limit && rows.all? do |row|
          row.is_a?(Hash) && row["__id"].is_a?(Integer) && row["__id"].positive? &&
            where.all? { |key, value| key == "__id" || row[key] == value }
        end
        raise IOError, "Invalid table notification preference response"
      end
      rows
    end

    def canonical(rows)
      rows.sort_by { |row| row["__id"].to_i }.each_with_object({}) do |row, result|
        next unless valid_identity?(row)
        result[row["__insertion_user"].downcase] ||= row
      end
    end

    def valid_identity?(row)
      row.is_a?(Hash) && row["__id"].to_i > 0 && !row["__insertion_user"].to_s.empty? &&
        row["username"].to_s.casecmp?(row["__insertion_user"].to_s)
    end

    def selected(row)
      return [] unless row["format"].to_i == 1 && row["games"].to_s.bytesize <= 2048
      value = JSON.parse(row["games"].to_s)
      value.is_a?(Array) ? value.grep(String).uniq & @games : []
    rescue JSON::ParserError
      []
    end
  end

  # Tiny, content-free diagnostic buffer; inspecting it never performs I/O.
  module Timing
    @samples = []
    @mutex = Mutex.new
    def self.measure(stage)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      @mutex.synchronize do
        @samples << { stage: stage, milliseconds: elapsed }
        @samples.shift while @samples.length > 128
      end
    end
    def self.samples; @mutex.synchronize { @samples.map(&:dup) }; end
  end

  # Only resolved/joined rooms need durable suppression of a late delivery.
  # One in-flight write and one replaceable snapshot, never a thread per notice.
  class ReceiptWriter
    def initialize(runtime: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, &write)
      @runtime, @clock, @write = runtime, clock, write
      @mutex = Mutex.new
      @pending, @running, @closed, @failures, @retry_at = nil, false, false, 0, 0
    end

    def enqueue(value)
      snapshot = { "resolved" => value.fetch("resolved", {}).dup.freeze }.freeze
      @mutex.synchronize do
        return false if @closed
        @pending = snapshot
        @failures = 0
        dispatch
      end
      true
    end

    def tick
      @mutex.synchronize { dispatch unless @closed }
    end

    def close
      @mutex.synchronize do
        @closed = true
        dispatch # Finite pending writes may finish, without joining on the UI.
      end
    end

    private

    def dispatch
      return if @running || !@pending || @failures >= 3 || @clock.call < @retry_at
      @running = true
      @thread = Thread.new do
        Thread.current.report_on_exception = false
        begin
          if @runtime && defined?(Programs) && Programs.respond_to?(:with_runtime)
            Programs.with_runtime(@runtime) { drain }
          else
            drain
          end
        rescue StandardError => error
          # A disposed host runtime may reject entering its context before
          # drain starts. Do not leave the writer permanently marked busy.
          @mutex.synchronize { failed_attempt }
          Log.warning("Game Room table receipt runtime failed: #{error.class}") if defined?(Log)
        end
      end
    rescue StandardError => error
      # Thread creation itself can fail. dispatch runs under @mutex.
      failed_attempt
      Log.warning("Game Room table receipt worker failed: #{error.class}") if defined?(Log)
    end

    def failed_attempt
      @failures += 1
      @retry_at = @clock.call + 5
      @running = false
    end

    def drain
      loop do
        snapshot = @mutex.synchronize do
          value = @pending
          @pending = nil
          @running = false unless value
          value
        end
        break unless snapshot
        begin
          Timing.measure(:resolved_write) { @write.call(snapshot) }
          @mutex.synchronize { @failures = 0; @retry_at = 0 }
        rescue StandardError => error
          @mutex.synchronize do
            @pending ||= snapshot
            failed_attempt
          end
          Log.warning("Game Room resolved table notice write failed: #{error.class}") if defined?(Log)
          break
        end
      end
    end
  end

  # No HTTP or disk write on receipt. The host remembers delivery IDs and
  # primes old notifications silently on startup; local seen is extra RAM-only
  # deduplication by table. Legacy stored seen remains readable, not rewritten.
  class Receiver
    attr_accessor :games
    attr_reader :user

    def initialize(user:, games:, uuid:, stored: {}, persist: ->(_data) {}, clock: nil)
      @user, @allowed, @uuid, @persist, @clock = user.to_s, games.map(&:to_s), uuid.to_s, persist, clock || Clock.new
      @games = nil # Unknown until the one startup server read completes.
      @seen = stored.is_a?(Hash) ? stored.fetch("seen", {}).dup : {}
      @resolved = stored.is_a?(Hash) ? stored.fetch("resolved", {}).dup : {}
      @seen = {} unless @seen.is_a?(Hash)
      @resolved = {} unless @resolved.is_a?(Hash)
      @seen.select! do |_key, value|
        value.is_a?(Hash) && %w[id expires].all? { |key| GameRoomNotificationTime.integer_value?(value[key]) }
      end
      @resolved.select! { |_key, expiry| GameRoomNotificationTime.integer_value?(expiry) }
      trim
    end

    def data(notification)
      return nil if @clock.respond_to?(:ready?) && !@clock.ready?
      return nil unless notification.type.to_s == TYPE && notification.app_uuid.to_s.casecmp?(@uuid)
      value = notification.metadata
      return nil unless value.is_a?(Hash) && value["format"] == 1 && @allowed.include?(value["game"])
      # The server returns opaque URL-safe tokens (including '-' and '_'),
      # not UUIDs. Bound and validate the target without guessing its layout;
      # opening still verifies the exact session, table, owner and visibility.
      session_id = value["live_session_id"]
      return nil unless session_id.is_a?(String) && session_id.match?(/\A[A-Za-z0-9_-]{1,256}\z/)
      return nil unless value["table_id"].is_a?(Integer) && value["table_id"] > 0
      expiry, created = value["expires_at"], value["created_at"]
      return nil unless expiry.is_a?(Integer) && created.is_a?(Integer) && expiry - created == 300
      created = GameRoomNotificationTime.created_at(notification) || created
      expiry = GameRoomNotificationTime.expires_at(notification, value)
      return nil unless expiry > @clock.call && created <= @clock.call + 60
      sender = notification.sender.to_s
      return nil if sender.empty? || sender.length > 64 || sender.match?(/[\x00-\x1f]/) || sender.casecmp?(@user)
      value.merge("created_at" => created, "expires_at" => expiry)
    end

    def visible?(notification)
      value = data(notification)
      return false unless value
      return false if @games && !@games.include?(value["game"])
      key = value["live_session_id"]
      return false if @resolved[key].to_i > @clock.call
      entry = @seen[key]
      !entry.is_a?(Hash) || entry["id"].to_i == notification.id.to_i
    end

    def received?(notification)
      value = data(notification)
      value && @seen[value["live_session_id"]].is_a?(Hash)
    end

    def receive(notification)
      return false unless visible?(notification) && !received?(notification)
      value = data(notification)
      return false unless value
      @seen[value["live_session_id"]] = { "id" => notification.id.to_i, "expires" => value["expires_at"] }
      trim
      true
    end

    def resolve(session_id)
      @resolved[session_id.to_s] = @clock.call + 300
      save
    end

    private

    def trim
      if @clock.respond_to?(:ready?) && !@clock.ready?
        # Do not erase saved receipts using the provisional OS clock while
        # the extension's first background synchronization is still pending.
        @seen = @seen.to_a.last(1024).to_h
        @resolved = @resolved.to_a.last(1024).to_h
        return
      end
      @seen = @seen.select { |_key, value| value.is_a?(Hash) && value["expires"].to_i > @clock.call }.to_a.last(1024).to_h
      @resolved = @resolved.select { |_key, expiry| expiry.to_i > @clock.call }.to_a.last(1024).to_h
    end

    def save
      trim
      @persist.call({ "resolved" => @resolved.dup })
    rescue StandardError => error
      Log.warning("Game Room table notice receipt could not be saved: #{error.class}") if defined?(Log)
    end
  end

  # A single paced queue for this app/account. Each finite HTTP operation runs
  # off the UI thread. Uncertain writes are never retried as successful delivery
  # is unknowable; only an explicit 429 may be retried after backoff.
  class Sender
    def initialize(user:, repository:, online:, send_notice:, worker: nil, current_user: -> { Session.name }, clock: nil, variant: ->(_row) { nil })
      @user, @repository, @online, @send_notice = user.to_s, repository, online, send_notice
      @variant = variant
      @worker = worker || GameRoomBackground::Work.new(runtime: defined?(Programs) ? Programs.current_runtime : nil)
      @current_user, @clock, @queue, @seen = current_user, clock || Clock.new, [], {}
      @next_at = 0.0
    end

    def enqueue(row)
      return false unless row.is_a?(Hash) && row["owner"].to_s.casecmp?(@user) && row["status"] == "waiting"
      return false if row["private"] == true || !row["resume_save_id"].to_s.empty?
      key = row["__live_session_id"].to_s
      return false if key.empty? || @seen[key] || @queue.length >= 4
      @seen[key] = @clock.call
      @seen.delete_if { |_id, at| @clock.call - at > 600 }
      now = @clock.call.to_i
      @queue << { metadata: { "format" => 1, "game" => row["game"], "table_id" => row["__id"].to_i,
        "live_session_id" => key, "created_at" => now, "expires_at" => now + 300, "variant" => @variant.call(row) }, recipients: nil }
      true
    end

    def cancel(session_id)
      @queue.reject! { |job| job[:metadata]["live_session_id"] == session_id.to_s }
    end

    def tick
      return close unless @current_user.call.to_s.casecmp?(@user)
      return if @clock.respond_to?(:ready?) && !@clock.ready?
      if (result = @worker.take)
        value, error = result
        if error
          @next_at = @clock.call + GameRoomNetworkErrors.retry_delay(error, normal: 15, rate_limit: 60)
          limited = error.respond_to?(:status) && error.status.to_i == 429
          limited ||= error.respond_to?(:code) && error.code.to_s == "rate_limits.exceeded"
          if @operation && limited && @operation[:kind] == :send && @operation[:attempt].to_i < 1 && @queue.include?(@operation[:job])
            @operation[:job][:recipients].unshift([@operation[:recipient], 1])
          elsif @operation && @operation[:kind] == :load && !limited && !GameRoomNetworkErrors.transient?(error)
            @queue.delete(@operation[:job])
          end
          # A transient recipient lookup failure has not sent anything. Leave
          # that job pending for retry; permanent denial/expiry/cancel win.
          Log.warning("Game Room table notices failed: #{error.class}") if defined?(Log)
        elsif @operation && @operation[:kind] == :load && @queue.include?(@operation[:job])
          @operation[:job][:recipients] = value.map { |name| [name, 0] }
        end
        @operation = nil
      end
      return if @worker.closed? || @worker.busy? || @clock.call < @next_at
      @queue.reject! { |job| job[:metadata]["expires_at"] <= @clock.call || job[:recipients] == [] }
      job = @queue.first
      return unless job
      if job[:recipients] == nil
        if GameRoomBackground.admit(@worker) { @repository.recipients(job[:metadata]["game"], online: @online.call, sender: @user) }
          @operation = { kind: :load, job: job }
        end
      else
        recipient, attempt = job[:recipients].first
        started = GameRoomBackground.admit(@worker) do
          # Queue cancellation or account change can race the worker dispatch.
          if @queue.include?(job) && @current_user.call.to_s.casecmp?(@user)
            @send_notice.call(recipient, job[:metadata], [job[:metadata]["expires_at"] - @clock.call.to_i, 0].max)
          end
        end
        if started
          job[:recipients].shift
          @operation = { kind: :send, job: job, recipient: recipient, attempt: attempt }
          @next_at = @clock.call + 0.5
        end
      end
    end

    def close
      @queue.clear
      @worker.close
    end
  end
end
