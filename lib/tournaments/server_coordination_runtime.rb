require_relative 'tournament_start_runtime'
require_relative 'server_coordination'

module GameRoomTournaments
  module ServerCoordinationRuntime
    include TournamentStartRuntime

    def start_tournament_coordination(program)
      @tournament_runtime_program=program
      configure_tournament_coordination
    end

    def configure_tournament_coordination
      stop_tournament_coordination
      # Extensions are loaded before ELTEN logs in. A missing account/token is
      # normal here; the existing extension tick starts us after authentication.
      return unless Session.logged?
      account=Publication::Data.account(Session.name).downcase
      @tournament_runtime_account=account
      @tournament_runtime_epoch=SecureRandom.uuid
      workspace=ServerWorkspace.new(program:@tournament_runtime_program,registry:const_get(:GAME_REGISTRY),
        user:-> {Session.name},alert:->(message){raise ProposalNotice::Unavailable,message},backend_uuid:server_app_uuid)
      context=-> {{'account'=>Session.name.to_s.downcase,'account_epoch'=>@tournament_runtime_epoch,
        'backend_identity'=>workspace.backend_identity}}
      clock=-> {GameRoomClock.now.to_i}

      configure_tournament_starts(source:->(reference){workspace.start_notice_source_on_worker(publication_ref:reference)},
        context:context,clock:clock,registry:const_get(:GAME_REGISTRY))
      configure_tournament_events(source:->(reference,kind,phase_id){workspace.event_notice_source_on_worker(publication_ref:reference,kind:kind,phase_id:phase_id)},
        context:context,clock:clock,registry:const_get(:GAME_REGISTRY))
      @tournament_coordinator=ServerCoordination.new(workspace:workspace,user:-> {Session.name},clock:clock,
        worker:GameRoomBackground::Work.new(runtime:app_runtime),
        wake:->(recipient,reference){send_notification(recipient,type:ServerCoordination::TYPE,
          metadata:{'version'=>1,'backend_identity'=>workspace.backend_identity,'publication_ref'=>reference,'recipient'=>recipient.downcase},expires_in:120)},
        partners_changed:->(reference,change){
          begin
            send_tournament_event(kind:'partnership',publication_ref:reference,change_key:change['key'],change_index:change['index'])
          rescue ProposalNotice::Stale
            nil
          end
        },phase_finished:->(reference,phase_id){
          begin
            send_tournament_event(kind:'phase_finished',publication_ref:reference,phase_id:phase_id)
          rescue ProposalNotice::Stale
            nil
          end
        },finished:->(reference){
          begin
            send_tournament_event(kind:'finished',publication_ref:reference)
          rescue ProposalNotice::Stale
            nil
          end
        },started:->(reference){
          begin
            send_tournament_start_notices(publication_ref:reference)
          rescue ProposalNotice::Stale
            # An unavailable start does not stop match coordination.
            nil
          end
        })
      @tournament_coordinator.bootstrap
    rescue Publication::Invalid=>error
      @tournament_runtime_account=nil
      Log.warning("Tournament setup unavailable: #{error.class}") if defined?(Log)
    end

    def stop_tournament_coordination
      @tournament_coordinator&.close
      @tournament_coordinator=nil
      @tournament_runtime_account=nil
      @tournament_runtime_epoch=nil
      @tournament_runtime_error=nil
      @tournament_coordination_tick_at=nil
      stop_tournament_starts
    end

    def tournament_busy?
      program=GameRoomSingleInstance.active_program
      transport=program&.instance_variable_get(:@transport)
      !!(transport && transport.current_room(Session.name))
    end

    def tournament_changed(reference)
      @tournament_coordinator&.changed(reference,broadcast:true)
    end

    def tournament_view_revision(reference)
      coordinator=@tournament_coordinator
      [coordinator&.object_id,coordinator&.view_revision(reference)]
    end

    def tournament_view_snapshot(reference)
      @tournament_coordinator&.view_snapshot(reference)
    end

    def refresh_tournament_deadlines
      @tournament_coordinator&.bootstrap
    end

    def receive_tournament_change(notification)
      return if notification.respond_to?(:revoked) && notification.revoked
      return unless notification.app_uuid.to_s.downcase==server_app_uuid.to_s.downcase
      metadata=notification.metadata.to_h
      return unless metadata.keys.sort==%w[backend_identity publication_ref recipient version] && metadata['version']==1 &&
        metadata['recipient'].to_s.downcase==Session.name.to_s.downcase && metadata['backend_identity']=="elten-tournaments:#{server_app_uuid}"
      @tournament_coordinator&.changed(metadata['publication_ref'],sender:notification.sender)
    rescue Publication::Invalid
      false
    end

    def tournament_coordination_tick
      return unless @tournament_runtime_program
      # The host extension and covered-table presenter share one cadence and
      # worker. Native parallel windows suspend extension ticks, not this local
      # pump. Never run a second coordinator or perform its I/O on the UI thread.
      lock=(@tournament_coordination_tick_lock ||= Mutex.new)
      return unless lock.try_lock
      begin
        unless Session.logged?
          stop_tournament_coordination if @tournament_runtime_account || @tournament_coordinator || @tournament_start_inbox
          return
        end
        configure_tournament_coordination if @tournament_runtime_account!=Session.name.to_s.downcase
        now=Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @tournament_coordination_tick_at && now-@tournament_coordination_tick_at<1.0
        @tournament_coordination_tick_at=now
        @tournament_coordinator&.tick
        @tournament_coordinator&.take_observed_references&.each do |reference|
          @tournament_event_inboxes&.each_value { |inbox| inbox.refresh(reference) }
        end
        error=@tournament_coordinator&.last_error
        if error && !error.equal?(@tournament_runtime_error)
          @tournament_runtime_error=error
          Log.warning("Tournament coordination: #{error.class}: #{error.message}") if defined?(Log)
        end
      ensure
        lock.unlock
      end
    rescue GameRoomNetworkErrors::ClockUnavailable
      # The ordinary startup clock callback will make the next local tick ready.
      nil
    end
  end
end
