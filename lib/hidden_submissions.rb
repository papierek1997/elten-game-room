require "digest"
require "json"
require "securerandom"
require "monitor"
require "fileutils"

module HiddenSubmissions
  class StorageError < StandardError; end

  Envelope = Struct.new(
    :session_id,
    :round_id,
    :user,
    :payload,
    :nonce,
    :commitment,
    keyword_init: true
  )

  module Commitment
    module_function

    def create(payload, nonce: SecureRandom.hex(32))
      normalized = normalize(payload)
      digest = Digest::SHA256.hexdigest("#{nonce}\0#{JSON.generate(normalized)}")
      [digest, nonce.to_s, normalized]
    end

    def valid?(payload:, nonce:, commitment:)
      calculated, = create(payload, nonce: nonce)
      secure_compare(calculated, commitment.to_s)
    end

    def normalize(value)
      case value
      when Hash
        normalized_keys = value.keys.map(&:to_s)
        if normalized_keys.uniq.length != normalized_keys.length
          raise ArgumentError, "hidden submission payload has duplicate normalized keys"
        end
        normalized_keys.sort.each_with_object({}) do |key, result|
          original = value.keys.find { |candidate| candidate.to_s == key }
          result[key] = normalize(value[original])
        end
      when Array
        value.map { |item| normalize(item) }
      when String, Integer, Float, TrueClass, FalseClass, NilClass
        value
      else
        raise ArgumentError, "hidden submission payload must be JSON-compatible"
      end
    end

    def secure_compare(first, second)
      return false if first.bytesize != second.bytesize

      difference = 0
      first.bytes.zip(second.bytes) { |left, right| difference |= left ^ right }
      difference == 0
    end
    private_class_method :secure_compare
  end

  class MemoryStorage
    def initialize
      @state = { "entries" => {} }
    end

    def read
      Marshal.load(Marshal.dump(@state))
    end

    def update
      yield @state
      read
    end
  end

  class ProgramStorage
    DEFAULT_PATH = "hidden_submissions.json"
    REVISION_KEY = "storage_revision"
    COORDINATORS_LOCK = Monitor.new

    def initialize(program, path: DEFAULT_PATH)
      @program = program
      @path = path.to_s
      # Program instances delegate file storage to their program class in
      # ELTEN. Coordinate that shared file, not just one screen's instance.
      # The class also bounds the lifetime to this loaded application.
      owner = program.class.respond_to?(:data_path) ? program.class : program
      @coordinator = COORDINATORS_LOCK.synchronize do
        stores = owner.instance_variable_get(:@game_room_hidden_submission_stores)
        if stores == nil
          stores = {}
          owner.instance_variable_set(:@game_room_hidden_submission_stores, stores)
        end
        stores[@path] ||= { lock: Monitor.new, retry_at: 0.0, warned: false }
      end
    end

    def read
      @coordinator[:lock].synchronize { read_snapshot }
    end

    def update(&block)
      @coordinator[:lock].synchronize do
        before = read_snapshot
        root = Marshal.load(Marshal.dump(before))
        block.call(root)
        # In particular, discard after an already-confirmed reveal is a no-op.
        return root if root == before

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) < @coordinator[:retry_at]
          raise StorageError, "Cannot save hidden answers on this device."
        end
        root[REVISION_KEY] = before.fetch(REVISION_KEY, 0) + 1
        persist_snapshot(root)
        root
      end
    end

    private

    def paths
      # Resolving an installed Program's data path can reparse its package.
      # Ask the host once, retaining its path validation and private directory;
      # do not cache the answers themselves, which another screen may update.
      @coordinator[:paths] ||= begin
        path = @program.data_path(@path).to_s
        [path.freeze, (path + ".recovery.json").freeze].freeze
      end
    end

    def read_snapshot
      # A newer recovery snapshot supersedes the original, including deletions.
      # This also works after reopening the screen or restarting ELTEN.
      snapshots = paths.map do |path|
        validate_root!(read_snapshot_file(path))
      end
      snapshots.max_by { |root| root.fetch(REVISION_KEY, 0) }
    rescue SystemCallError, IOError, JSON::ParserError
      raise StorageError, "Cannot read hidden answers on this device."
    end

    def persist_snapshot(root)
      paths.each do |path|
        begin
          write_snapshot_file(path, root)
          @coordinator[:retry_at] = 0.0
          @coordinator[:warned] = false
          return
        rescue SystemCallError, IOError
          # Do not delete/truncate the original to make Windows rename work.
          # The second path has the same private app-storage permissions.
        end
      end
      # No sleeps or network retries. Repeated automatic checks must not hammer
      # a directory which is temporarily unwritable.
      @coordinator[:retry_at] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
      unless @coordinator[:warned]
        Log.warning("ELTEN Game Room: cannot update local hidden answer storage.") if defined?(Log)
        @coordinator[:warned] = true
      end
      raise StorageError, "Cannot save hidden answers on this device."
    end

    def read_snapshot_file(path)
      JSON.parse(File.binread(path))
    rescue Errno::ENOENT
      { "entries" => {} }
    end

    def write_snapshot_file(path, root)
      FileUtils.mkdir_p(File.dirname(path))
      temporary = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
      File.binwrite(temporary, JSON.generate(root).encode(Encoding::UTF_8))
      FileUtils.mv(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    def validate_root!(root)
      unless root.is_a?(Hash) && root["entries"].is_a?(Hash) &&
          root.fetch(REVISION_KEY, 0).is_a?(Integer) && root.fetch(REVISION_KEY, 0) >= 0
        raise StorageError, "Cannot read hidden answers on this device."
      end
      root
    end
  end

  class Vault
    def initialize(storage)
      @storage = storage
    end

    def prepare(session_id:, round_id:, user:, payload:, nonce: nil)
      # A lost acknowledgement must not destroy the envelope whose commitment
      # may already be on the server. Reuse identical submissions and retain
      # older versions if the user edited an answer before retrying.
      previous = reveal(session_id: session_id, round_id: round_id, user: user)
      normalized_payload = Commitment.normalize(payload)
      return previous if previous != nil && previous.payload == normalized_payload

      digest, actual_nonce, normalized = Commitment.create(
        payload,
        nonce: nonce || SecureRandom.hex(32)
      )
      envelope = Envelope.new(
        session_id: session_id.to_i,
        round_id: round_id.to_s,
        user: user.to_s,
        payload: normalized,
        nonce: actual_nonce,
        commitment: digest
      )
      @storage.update do |state|
        entries = entries_for(state)
        key = entry_key(envelope.session_id, envelope.round_id, envelope.user)
        old = entry_for(entries, key)
        versions = old == nil ? {} : old.fetch("versions", {}).dup
        versions[old["commitment"]] = old.reject { |name, _| name == "versions" } if old != nil
        entries[key] = serialize(envelope).merge("versions" => versions)
      end
      envelope
    end

    def reveal(session_id:, round_id:, user:, commitment: nil)
      data = entry_for(entries_for(@storage.read), entry_key(session_id, round_id, user))
      if data != nil && commitment != nil && data["commitment"] != commitment
        data = data.fetch("versions", {})[commitment]
      end
      data == nil ? nil : deserialize(data)
    end

    def discard(session_id:, round_id:, user:)
      removed = false
      @storage.update do |state|
        entries = entries_for(state)
        key = entry_key(session_id, round_id, user)
        entry_for(entries, key)
        removed = entries.delete(key) != nil
      end
      removed
    rescue StorageError
      # The reveal is already confirmed. Retaining an old local envelope is
      # harmless; a cleanup failure must not stop scoring or the next question.
      false
    end

    # The receipt was reconstructed from accepted game events. Compare and
    # remove in the same storage transaction so a newer uncertain submission
    # cannot be erased between a read and a later discard.
    def discard_confirmed(session_id:, receipts:)
      complete = true
      @storage.update do |state|
        entries = entries_for(state)
        receipts.each do |round_id, user, commitment|
          key = entry_key(session_id, round_id, user)
          data = entry_for(entries, key)
          next unless data
          if data["commitment"] == commitment
            entries.delete(key)
          else
            complete = false
          end
        end
      end
      complete
    rescue StorageError
      false
    end

    # A worker may reconcile durable answers after its game object was
    # recreated. Return only this account/session's current envelopes; older
    # versions and other games/accounts are not a cleanup authority.
    def envelopes(session_id:, user:, round_prefix:)
      entries_for(@storage.read).values.filter_map do |data|
        validate_entry!(data)
        next unless data["session_id"] == session_id.to_i &&
          data["user"].to_s.downcase == user.to_s.downcase &&
          data["round_id"].to_s.start_with?(round_prefix)
        deserialize(data)
      end
    end

    def verify(envelope)
      Commitment.valid?(
        payload: envelope.payload,
        nonce: envelope.nonce,
        commitment: envelope.commitment
      )
    end

    private

    def entries_for(state)
      unless state.is_a?(Hash) && state["entries"].is_a?(Hash)
        raise StorageError, "Cannot read hidden answers on this device."
      end
      state["entries"]
    end

    def entry_for(entries, key)
      return nil unless entries.key?(key)

      data = entries[key]
      validate_entry!(data)
      data
    end

    def validate_entry!(data)
      validate_envelope!(data)
      versions = data.fetch("versions", {})
      raise StorageError, "Cannot read hidden answers on this device." unless versions.is_a?(Hash)

      versions.each_value { |version| validate_envelope!(version) }
    end

    def validate_envelope!(data)
      unless data.is_a?(Hash) && data["session_id"].is_a?(Integer) && data.key?("payload") &&
          %w[round_id user nonce commitment].all? { |name| data[name].is_a?(String) }
        raise StorageError, "Cannot read hidden answers on this device."
      end
    end

    def entry_key(session_id, round_id, user)
      Digest::SHA256.hexdigest([session_id.to_i, round_id.to_s, user.to_s.downcase].join("\0"))
    end

    def serialize(envelope)
      {
        "session_id" => envelope.session_id,
        "round_id" => envelope.round_id,
        "user" => envelope.user,
        "payload" => envelope.payload,
        "nonce" => envelope.nonce,
        "commitment" => envelope.commitment
      }
    end

    def deserialize(data)
      Envelope.new(
        session_id: data["session_id"].to_i,
        round_id: data["round_id"].to_s,
        user: data["user"].to_s,
        payload: data["payload"],
        nonce: data["nonce"].to_s,
        commitment: data["commitment"].to_s
      )
    end
  end

  # Public commitments, not private answers, survive subsequent rounds in the
  # replay. The existing session worker reconciles them even when a guest no
  # longer has an automatic action, or the game has already ended.
  module Cleanup
    def self.start(state, session)
      state[:answer_cleanup] = {
        session_id: (session["__id"] || session["id"]).to_i,
        receipts: {}
      }
    end

    def self.confirm(state, round_id, commitments)
      proof = state[:answer_cleanup]
      return unless proof && !commitments.empty?
      round = proof[:receipts][round_id] ||= {}
      commitments.each { |user, commitment| round[user.to_s.downcase] = commitment }
    end

    def cleanup_session_answers(replay, session_id:, actors:, hidden_submissions:)
      proof = replay.state[:answer_cleanup]
      return unless hidden_submissions && proof && session_id.positive? && proof[:session_id] == session_id
      users = actors.map { |actor| actor.to_s.downcase }.uniq
      receipts = proof[:receipts].flat_map do |round_id, commitments|
        commitments.filter_map { |user, digest| [round_id, user, digest] if users.include?(user) }
      end
      return if receipts.empty?
      checked = @confirmed_answer_cleanup
      return if checked && checked[0] == session_id && checked[1].equal?(hidden_submissions) && checked[2] == receipts
      if hidden_submissions.discard_confirmed(session_id: session_id, receipts: receipts)
        @confirmed_answer_cleanup = [session_id, hidden_submissions, receipts]
      end
    end
  end
end
