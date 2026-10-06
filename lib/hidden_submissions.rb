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
        root[REVISION_KEY] = before.fetch(REVISION_KEY, 0).to_i + 1
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
        normalize_root(read_snapshot_file(path))
      end
      snapshots.max_by { |root| root.fetch(REVISION_KEY, 0).to_i }
    rescue SystemCallError, IOError
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
    rescue Errno::ENOENT, JSON::ParserError
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

    def normalize_root(root)
      value = root.is_a?(Hash) ? root : {}
      entries = value["entries"]
      value["entries"] = {} if !entries.is_a?(Hash)
      value
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
        state["entries"] ||= {}
        key = entry_key(envelope.session_id, envelope.round_id, envelope.user)
        old = state["entries"][key]
        versions = old == nil ? {} : old.fetch("versions", {}).dup
        versions[old["commitment"]] = old.reject { |name, _| name == "versions" } if old != nil
        state["entries"][key] = serialize(envelope).merge("versions" => versions)
      end
      envelope
    end

    def reveal(session_id:, round_id:, user:, commitment: nil)
      data = @storage.read.fetch("entries", {})[entry_key(session_id, round_id, user)]
      if data != nil && commitment != nil && data["commitment"] != commitment
        data = data.fetch("versions", {})[commitment]
      end
      data == nil ? nil : deserialize(data)
    end

    def discard(session_id:, round_id:, user:)
      removed = false
      @storage.update do |state|
        entries = state["entries"] ||= {}
        removed = entries.delete(entry_key(session_id, round_id, user)) != nil
      end
      removed
    rescue StorageError
      # The reveal is already confirmed. Retaining an old local envelope is
      # harmless; a cleanup failure must not stop scoring or the next question.
      false
    end

    def verify(envelope)
      Commitment.valid?(
        payload: envelope.payload,
        nonce: envelope.nonce,
        commitment: envelope.commitment
      )
    end

    private

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
end
