require_relative "game_room_analytics_storage"
require_relative "game_room_analytics_job"
require_relative "game_room_server_tables"

# Factories are memory-only. All file resolution, snapshots and HTTP remain on
# the application's managed worker. Account/runtime changes invalidate old jobs.
module GameRoomAnalyticsRuntime
  include GameRoomServerTables::Runtime

  def analytics_enabled?
    return false if $developer_mode == true
    # Preserve pre-entry widget collection. Once the entry probe has a provider,
    # its unchecked/denied decision also suspends already captured workers.
    tables = server_table_access
    !tables || tables.available?
  end

  def statistics_service
    with_analytics_context do |context, enabled|
      unless @statistics_service
        job = nil
        service = GameRoomStatistics::Service.new(program: self, storage: analytics_storage,
          user: context[1], enabled: enabled, trigger: -> { job&.request })
        next nil if service.last_error
        job = GameRoomAnalyticsJob.new(trigger: -> { @statistics_extension ? @statistics_extension.trigger("statistics_upload") : false },
          enabled: enabled, persist_during_retry: true, last_error: -> { service.last_error }) do |token, upload|
          service.flush(token, upload: upload)
          service.work_status
        end
        @statistics_service, @statistics_job = service, job
        # One startup check also discovers durable work from the previous run.
        job.request
      end
      @statistics_service
    end
  rescue StandardError
    nil
  end

  def room_presence_collector
    with_analytics_context do |context, enabled|
      unless @presence_collector
        job = nil
        storage = analytics_storage
        collector = GameRoomPresence::Collector.new(user: context[1], enabled: enabled,
          trigger: -> { job&.request }, store_factory: -> {
            reporter = GameRoomPresence::Collector.reporter_key(storage: storage, user: context[1], valid: enabled)
            GameRoomPresence::Store.new(app_uuid: server_app_uuid, user: context[1], reporter_key: reporter)
          })
        job = GameRoomAnalyticsJob.new(trigger: -> { @statistics_extension ? @statistics_extension.trigger("room_presence") : false },
          enabled: enabled, delay: 1, heartbeat: GameRoomPresence::Collector::HEARTBEAT_SECONDS,
          last_error: -> { collector.last_error }) do |token, _upload|
          collector.heartbeat(token)
          collector.work_status
        end
        @presence_collector, @presence_job = collector, job
      end
      @presence_collector
    end
  rescue StandardError
    nil
  end

  def analytics_tick
    return unless analytics_enabled?
    statistics_service
    room_presence_collector
    @statistics_job&.tick
    @presence_job&.tick
  end

  def run_statistics_job(token)
    @statistics_job&.run(token) if statistics_service
  end

  def run_presence_job(token)
    @presence_job&.run(token) if room_presence_collector
  end

  def stop_analytics
    @analytics_lock ||= Mutex.new
    @analytics_lock.synchronize do
      close_analytics_context
      @analytics_context = @analytics_storage = nil
    end
  end

  private

  def analytics_storage
    @analytics_storage ||= GameRoomAnalyticsStorage.new(self)
  end

  def with_analytics_context
    return unless analytics_enabled? && respond_to?(:app_runtime) && (runtime = app_runtime)
    user = Session.name.to_s.downcase
    return if user.empty?
    @analytics_lock ||= Mutex.new
    @analytics_lock.synchronize do
      unless @analytics_context && @analytics_context[0].equal?(runtime) && @analytics_context[1] == user
        @analytics_storage = nil unless @analytics_context && @analytics_context[0].equal?(runtime)
        close_analytics_context
        @analytics_context = [runtime, user.freeze].freeze
      end
      context = @analytics_context
      enabled = -> { @analytics_context.equal?(context) && analytics_enabled? && app_runtime.equal?(runtime) && Session.name.to_s.downcase == user }
      yield context, enabled
    end
  end

  def close_analytics_context
    @statistics_job&.close
    @presence_job&.close
    @statistics_service&.close
    @presence_collector&.close
    @statistics_job = @presence_job = @statistics_service = @presence_collector = nil
  end
end
