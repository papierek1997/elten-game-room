require_relative '../../game_statistics_service'
require_relative 'store'
require 'securerandom'

module GameRoomDartsRankings
  class Service < GameRoomStatistics::Service
    PATH = 'darts-rankings-pending.json'.freeze

    def initialize(program:, user:, storage: program, store: nil, queue: nil, **options)
      @feedback, @feedback_keys, @feedback_lock = Queue.new, {}, Mutex.new
      @progression_lock = Mutex.new
      @highest_unlocked_difficulty = GameRoomDarts::Difficulty::BASE_HIGHEST
      @progression_synced = false
      store ||= Store.new(app_uuid: program.respond_to?(:server_app_uuid) ? program.server_app_uuid : program.class.server_app_uuid,
        user: user, current_user: options.fetch(:current_user, -> { Session.name }),
        enabled: options.fetch(:enabled, -> { true }),
        feedback_requested: ->(key) { feedback_requested?(key) }, on_feedback: ->(value) { confirm_feedback(value) },
        on_progression: ->(value) { update_progression(value) })
      queue ||= GameRoomStatistics::Queue.new(storage: storage, user: user, path: PATH,
        before_write: -> { check_context!(@flush_token) })
      super(program: program, user: user, storage: storage, store: store, queue: queue, **options)
    end

    def flush(token = nil, upload: true)
      result = super
      if result && upload && !progression_synced? && @store.respond_to?(:highest_unlocked_difficulty)
        update_progression(@store.highest_unlocked_difficulty(cancellation_token: token))
      end
      result
    rescue StandardError => error
      failed(error)
    end

    def highest_unlocked_difficulty
      @progression_lock.synchronize { @highest_unlocked_difficulty }
    end

    def unlocked_difficulties
      GameRoomDarts::Difficulty.unlocked_ids(highest_unlocked_difficulty)
    end

    def observe(session:, replay:, viewer:, publish: false)
      marked = false
      check_context!
      result = Result.from_replay(session: session, replay: replay, viewer: viewer)
      return false unless result
      key = result.fetch('result_key')
      marked = @feedback_lock.synchronize do
        next false if @feedback_keys.key?(key)
        @feedback_keys[key] = true
      end
      added = enqueue(result.merge('kind'=>'darts_result', 'match'=>result.fetch('result_key'),
        'publish'=>publish == true))
      @feedback_lock.synchronize { @feedback_keys.delete(key) } if marked && !added
      added
    rescue StandardError => error
      @feedback_lock.synchronize { @feedback_keys.delete(key) } if marked && defined?(key) && key
      failed(error)
    end

    def take_feedback
      values = []
      loop { values << @feedback.pop(true) }
    rescue ThreadError
      values
    end

    def publish_saved_records
      enqueue_account_operation('darts_publish_saved')
    rescue StandardError => error
      failed(error)
    end

    def withdraw_public_records
      enqueue_account_operation('darts_withdraw')
    rescue StandardError => error
      failed(error)
    end

    private

    def enqueue_account_operation(kind)
      enqueue({'kind'=>kind, 'match'=>SecureRandom.hex(16)})
    end

    def feedback_requested?(key)
      @feedback_lock.synchronize { @feedback_keys.key?(key) }
    end

    def confirm_feedback(value)
      return unless value.is_a?(Hash)
      accepted = @feedback_lock.synchronize { @feedback_keys.delete(value['result_key']) }
      informative = value['personal_record'].is_a?(Hash) || value['unlocked_difficulty'].is_a?(String) ||
        !value.fetch('placements', []).empty?
      @feedback << value if accepted && informative
    end

    def update_progression(value)
      @progression_lock.synchronize do
        @highest_unlocked_difficulty = GameRoomDarts::Difficulty.highest(@highest_unlocked_difficulty, value)
        @progression_synced = true
      end
    end

    def progression_synced?
      @progression_lock.synchronize { @progression_synced }
    end
  end
end
