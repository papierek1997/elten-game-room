require "thread"
require_relative "game_statistics_periods"
require_relative "game_statistics_queue"
require_relative "game_statistics_store"
require_relative "game_statistics_identity"

module GameRoomStatistics
  class Service
    MAX_SEEN = 1024

    attr_reader :store, :last_error

    def initialize(program:, user:, queue: nil, store: nil, clock: -> { GameRoomClock.now.to_i },
      current_user: -> { Session.name }, trigger: nil)
      @user = user.is_a?(String) ? user.dup.freeze : user
      @clock, @current_user, @trigger = clock, current_user, trigger
      @seen, @enqueue_mutex = {}, Mutex.new
      @queue = queue || Queue.new(storage: program, user: @user)
      @store = store || Store.new(app_uuid: program.respond_to?(:server_app_uuid) ? program.server_app_uuid : program.class.server_app_uuid,
        user: @user, current_user: current_user)
    rescue StandardError => error
      failed(error)
    end

    def visit
      enqueue("kind" => "visit", "day_key" => day_key(@clock.call))
    rescue StandardError => error
      failed(error)
    end

    def started(session:, game_id:)
      metadata = session.is_a?(Hash) && session["__statistics"]
      return false unless valid_game?(game_id) && Identity.valid?(metadata, require_started_at: true)
      enqueue(match_payload("started", metadata, game_id, metadata["started_at"]))
    rescue StandardError => error
      failed(error)
    end

    def observe(session:, replay:, game_id:, viewer:, participants:)
      return false unless session.is_a?(Hash) && valid_game?(game_id)
      added = started(session: session, game_id: game_id)
      metadata = session["__statistics"]
      finished = replay && replay.finished?
      epoch = completion_epoch(replay) if finished && !session["__aborted"]
      if replay && !session["__aborted"] && human_viewer?(session, viewer, participants)
        today = day_key(@clock.call)
        if !finished || (epoch && day_key(epoch) == today)
          mode = if Identity.valid?(metadata, require_started_at: true)
            metadata["mode"]
          else
            legacy_mode(session, participants)
          end
          added = enqueue("kind" => "player", "game" => game_id, "day_key" => today,
            "mode" => mode) || added
        end
      end
      if Identity.valid?(metadata, require_started_at: true) && epoch
        added = enqueue(match_payload("completed", metadata, game_id, epoch)) || added
      end
      added
    rescue StandardError => error
      failed(error)
    end

    def flush(token = nil)
      check_context!(token)
      entries = @queue.batch(limit: 50)
      check_context!(token)
      return true if entries.empty?
      confirmed = @store.write_batch(entries.map(&:last), cancellation_token: token)
      raise Unavailable, "Statistics upload was not confirmed" unless confirmed == true
      check_context!(token)
      @queue.acknowledge(entries)
      true
    rescue StandardError => error
      failed(error)
    end

    private

    def check_context!(token = nil)
      token.raise_if_cancelled! if token
      unless @user.is_a?(String) && !@user.strip.empty? && GameRoomParticipants.same?(@current_user.call, @user)
        raise Unavailable, "Statistics account changed"
      end
    end

    def failed(error)
      @last_error = error
      begin
        Log.warning("Game Room statistics operation failed") if defined?(Log)
      rescue StandardError
        nil
      end
      false
    end

    def completion_epoch(replay)
      replay.accepted_events.to_a.reverse_each do |event|
        epoch = event.is_a?(Hash) && event["created_at"]
        return epoch if epoch.is_a?(Integer) && epoch.positive?
      end
      nil
    end

    def bot?(session, participant)
      GameRoomParticipants.bot?(participant) || session.fetch("__controllers", {}).any? do |name, controller|
        GameRoomParticipants.same?(name, participant) && controller == "bot"
      end
    end

    def legacy_mode(session, participants)
      players = GameRoomParticipants.unique(participants)
      return "bots" if players.any? { |player| bot?(session, player) }
      players.length == 1 ? "solo" : "humans"
    end

    def human_viewer?(session, viewer, participants)
      GameRoomParticipants.same?(viewer, @user) && GameRoomParticipants.includes?(participants, viewer) &&
        !bot?(session, viewer)
    end

    def valid_game?(game_id)
      game_id.is_a?(String) && /\A[a-z][a-z0-9_]{0,31}\z/.match?(game_id)
    end

    def match_payload(kind, metadata, game_id, epoch)
      {"kind" => kind, "game" => game_id, "day_key" => day_key(epoch),
        "mode" => metadata["mode"], "match" => metadata["id"]}
    end

    def day_key(epoch)
      date = Periods.today(clock: -> { Time.at(epoch) })
      raise ArgumentError, "Statistics date is outside the supported range" unless date.year.between?(1970, 9999)
      date.strftime("%Y%m%d").to_i
    end

    def enqueue(payload)
      check_context!
      key = if payload["match"]
        [payload["kind"], payload["match"]].join(":")
      else
        [payload["kind"], payload["day_key"], payload["game"], payload["mode"]].compact.join(":")
      end
      added = @enqueue_mutex.synchronize do
        check_context!
        return false if @seen[key]
        result = @queue.push(key, payload)
        @seen[key] = true
        @seen.shift while @seen.size > MAX_SEEN
        result
      end
      @trigger.call if added && @trigger
      added
    end
  end
end
