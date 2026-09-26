require "securerandom"
require "digest"
require "thread"
require_relative "game_participants"
require_relative "game_room_clock"
require_relative "game_room_presence_identity"

module GameRoomPresence
  class Collector
    def self.reporter_key(storage:, user:)
      name = user.to_s.downcase
      raise ArgumentError, "Missing room presence account" if name.empty?
      result = storage.update_json("room-presence-client.json", default: {"version" => 1, "accounts" => {}}) do |data|
        raise IOError, "Invalid room presence client state" unless data.is_a?(Hash) && data["version"] == 1 && data["accounts"].is_a?(Hash)
        data["accounts"][name] ||= SecureRandom.hex(32)
        key = data["accounts"][name]
        raise IOError, "Invalid room presence reporter key" unless key.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(key)
      end
      raise IOError, "Room presence identity was not persisted" unless result.is_a?(Hash)
      result.fetch("accounts").fetch(name).dup.freeze
    end

    class Registration
      def initialize(collector)
        @collector = collector
      end

      def close
        @collector.unregister(self)
      end
    end

    attr_reader :last_error

    def initialize(user:, store: nil, store_factory: nil, enabled: -> { true }, current_user: -> { Session.name }, synchronize_clock: -> { GameRoomClock.synchronize })
      @user, @store, @store_factory = user.to_s.dup.freeze, store, store_factory
      @enabled = enabled
      @current_user, @synchronize_clock = current_user, synchronize_clock
      @sources, @sources_lock, @upload_lock, @store_lock = {}, Mutex.new, Mutex.new, Mutex.new
      @published = false
    end

    def store
      @store_lock.synchronize { @store ||= @store_factory.call }
    end

    def register(&provider)
      raise ArgumentError, "A room presence source is required" unless provider
      registration = Registration.new(self)
      @sources_lock.synchronize { @sources[registration] = provider }
      registration
    end

    def unregister(registration)
      @sources_lock.synchronize { @sources.delete(registration) }
      nil
    end

    def heartbeat(token = nil)
      @upload_lock.synchronize do
        return true unless @enabled.call
        check_context!(token)
        sources = @sources_lock.synchronize { @sources.to_a }
        snapshots = sources.flat_map do |registration, provider|
          return true unless @enabled.call
          check_context!(token)
          next [] unless @sources_lock.synchronize { @sources.key?(registration) }
          value = provider.call(token)
          raise IOError, "Room presence source did not return a snapshot list" unless value.is_a?(Array)
          @sources_lock.synchronize { @sources.key?(registration) } ? value : []
        end
        check_context!(token)
        rooms = snapshots.filter_map { |snapshot| room_values(snapshot) }
        return true if rooms.empty? && !@published
        return true unless @enabled.call
        check_context!(token)
        @synchronize_clock.call
        check_context!(token)
        return true unless @enabled.call
        target = store
        return true unless @enabled.call
        confirmed = target.publish(rooms, cancellation_token: token)
        raise IOError, "Room presence upload was not confirmed" unless confirmed == true
        check_context!(token)
        @published = !rooms.empty?
        @last_error = nil
        true
      end
    rescue StandardError => error
      @last_error = error
      begin
        Log.warning("Game Room presence update failed: #{error.class}") if defined?(Log)
      rescue StandardError
        nil
      end
      false
    end

    private

    def check_context!(token)
      token&.raise_if_cancelled!
      raise IOError, "Room presence account changed" unless !@user.empty? && GameRoomParticipants.same?(@current_user.call, @user)
    end

    def room_values(snapshot)
      table = snapshot.table
      return nil unless table.is_a?(Hash) && Identity.valid?(table["__statistics_room_id"]) &&
        %w[waiting playing].include?(table["status"])
      raise IOError, "Room membership is unavailable" unless snapshot.members.is_a?(Array)
      members = GameRoomParticipants.unique(snapshot.members).select { |name| GameRoomParticipants.human?(name) }
      return nil unless GameRoomParticipants.includes?(members, @user)
      {"room_key" => Digest::SHA256.hexdigest(table["__statistics_room_id"]), "game" => table["game"],
        "private_room" => table["private"] == true, "people" => members.length, "playing" => table["status"] == "playing"}
    end
  end
end
