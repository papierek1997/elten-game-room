require_relative '../../game_statistics_service'
require_relative 'store'
require 'securerandom'

module GameRoomDartsRankings
  class Service < GameRoomStatistics::Service
    PATH = 'darts-rankings-pending.json'.freeze

    def initialize(program:, user:, storage: program, store: nil, queue: nil, **options)
      @feedback, @feedback_keys, @feedback_lock = Queue.new, {}, Mutex.new
      store ||= Store.new(app_uuid: program.respond_to?(:server_app_uuid) ? program.server_app_uuid : program.class.server_app_uuid,
        user: user, current_user: options.fetch(:current_user, -> { Session.name }),
        feedback_requested: ->(key) { feedback_requested?(key) }, on_feedback: ->(value) { confirm_feedback(value) })
      queue ||= GameRoomStatistics::Queue.new(storage: storage, user: user, path: PATH,
        before_write: -> { check_context!(@flush_token) })
      super(program: program, user: user, storage: storage, store: store, queue: queue, **options)
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
      informative = value['personal_record'].is_a?(Hash) || !value.fetch('placements', []).empty?
      @feedback << value if accepted && informative
    end
  end
end
