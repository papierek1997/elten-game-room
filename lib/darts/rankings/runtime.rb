require_relative 'service'
require_relative '../../game_room_analytics_storage'

module GameRoomDartsRankings
  module Runtime
    def darts_rankings_service
      return unless respond_to?(:app_runtime) && (runtime = app_runtime) && !Session.name.to_s.empty?
      @darts_rankings_lock ||= Mutex.new
      @darts_rankings_lock.synchronize do
        user = Session.name.to_s
        identity = user.downcase
        if @darts_rankings_context && (!@darts_rankings_context[0].equal?(runtime) || @darts_rankings_context[1] != identity)
          close_darts_rankings_context
        end
        unless @darts_rankings_service
          @darts_rankings_context = [runtime, identity.freeze].freeze
          context = @darts_rankings_context
          enabled = -> { @darts_rankings_context.equal?(context) && app_runtime.equal?(runtime) && Session.name.to_s.casecmp?(user) }
          job = nil
          service = Service.new(program: self, user: user, storage: GameRoomAnalyticsStorage.new(self), enabled: enabled,
            trigger: -> { job&.request })
          next nil if service.last_error
          job = GameRoomAnalyticsJob.new(trigger: -> { @statistics_extension ? @statistics_extension.trigger('darts_rankings_upload') : false },
            enabled: enabled, persist_during_retry: true, last_error: -> { service.last_error }) do |token, upload|
            service.flush(token, upload: upload)
            service.work_status
          end
          @darts_rankings_service, @darts_rankings_job = service, job
          job.request
        end
        @darts_rankings_service
      end
    rescue StandardError
      nil
    end

    def darts_rankings_tick
      @darts_rankings_job&.tick
    end

    def run_darts_rankings_job(token)
      @darts_rankings_job&.run(token) if darts_rankings_service
    end

    def stop_darts_rankings
      @darts_rankings_lock ||= Mutex.new
      @darts_rankings_lock.synchronize { close_darts_rankings_context }
    end

    private

    def close_darts_rankings_context
      @darts_rankings_job&.close
      @darts_rankings_service&.close
      @darts_rankings_context = @darts_rankings_service = @darts_rankings_job = nil
    end
  end
end
