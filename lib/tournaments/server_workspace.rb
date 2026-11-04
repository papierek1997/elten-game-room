# encoding: UTF-8
require_relative 'public_service'
require_relative 'tables_gateway'
require_relative 'operation_journal'
require_relative 'server_schedule_store'
require_relative 'server_phase_store'
require_relative 'phase_description'
require_relative 'tournament_finish_summary'
require_relative 'ordinary_match_service'
require_relative 'server_readiness_service'
require_relative 'server_proposal_service'
require_relative 'tournament_lifecycle'
require_relative 'tournament_retention'
require_relative 'server_capacity'
require_relative 'server_participant_lease'
require_relative '../game_room_localization'
require_relative '../game_content'

module GameRoomTournaments
  # Official application storage adapter. No schema deployment or fallback.
  class ServerWorkspace
    using GameRoomLocalization::Translations
    APP_UUID = '468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80'.freeze
    IDENTITY = "elten-tournaments:#{APP_UUID}".freeze
    Data = Publication::Data
    ERRORS = [Publication::Invalid, PublicService::Error, TablesGateway::Error,
      OperationJournal::Error, ServerPlanArchive::ContextChanged, ServerPlanArchive::Unconfirmed, OrdinaryMatchService::Blocked,
      GameRoomNetworkErrors::ClockUnavailable, ServerParticipantLease::Busy, IOError, SystemCallError].freeze
    attr_reader :actor, :last_error, :registry

    def backend_identity; @identity; end

    def read_operation(&block)
      account!
      with_read_scope(&block)
    end

    class Provider
      def initialize(app_uuid: APP_UUID)
        @app_uuid=app_uuid
        @client = EltenLink::Client.new
      end
      def available?; true; end
      def fetch(name)
        raise ArgumentError, 'Not a tournament table' unless (TablesGateway::TABLES + ['tournament_plan_documents']).include?(name)
        EltenLink::Apps.table(@client, @app_uuid, name)
      end
    end

    def initialize(program:, registry:, user:, alert:, clock: -> { GameRoomClock.now.to_i }, provider_factory: nil, backend_uuid: APP_UUID, backend_identity: nil,
        readiness_clock: -> {GameRoomClock.now.to_i})
      @program, @registry, @user, @alert, @clock, @provider_factory = program, registry, user, alert, clock, provider_factory
      @identity = backend_identity || "elten-tournaments:#{backend_uuid}"
      @provider_factory ||= -> { Provider.new(app_uuid: backend_uuid) }
      @actor = Data.account(user.call).dup.freeze
      @readiness_clock=readiness_clock
      @owner = @actor.downcase.freeze
      @changed = false
    end

    def experimental_ui?; false; end

    def mode_label
      GameRoomContent.utf8(_("Shared tournaments"))
    end

    def load
      access do
        @service.directory_snapshot.fetch(:model).to_h
      end
    end

    def invite_to_tournament(id, recipient, intent)
      membership_change(id, input: [id, recipient, intent]) do |copy|
        @service.invite(tournament_id: copy[0], recipient: copy[1], intent_id: copy[2])
      end
    end

    def decline_tournament_invitation(id, key, intent)
      membership_change(id, input: [id, key, intent]) do |copy|
        @service.decline_invitation(tournament_id: copy[0], invitation_key: copy[1], intent_id: copy[2])
      end
    end

    private def retained_directory(directory, progress: false)
      now=@clock.call
      model=directory.fetch(:model)
      prefetch_directory_documents(directory,now) if progress
      rows=model.to_h.fetch('announcements').filter_map do |original|
        row=original.dup
        history=model.retention_history(row.fetch('__id'))
        state=TournamentRetention.evaluate(history,now:now)
        # Mutations only need the more expensive result projection once the
        # baseline deadline has elapsed. The directory already needs results
        # to distinguish completed tournaments from running ones.
        if TournamentTiming.registration_closed?(row,now) && (progress || state[:expired])
          reader=nil
          begin
            reference={'author'=>row['__insertion_user'],'publication_key'=>row['publication_key']}
            root=@service.server_schedule_source(publication_ref:reference,directory:directory)
            current=phase_store(reference,root_source:-> {account!;root}).current
            reader=OrdinaryMatchService.new(program:@program,registry:@registry,lobby:nil,games:nil,transport:nil,
              table:@provider.fetch('tournament_plan_documents'),journal:ordinary_journal,source:-> {account!;current},user:method(:account!))
            view=reader.result_view(allow_incomplete_forfeits:false)
            views=current.fetch('phase_history',[]).map{|phase|phase.fetch('view')} + [view]
            times=views.flat_map{|phase|phase.fetch('progress_times',[])}
            # Missing/partial evidence is never evidence of abandonment.
            if views.any?{|phase|phase['results'].any? && phase.fetch('progress_times',[]).empty?}
              raise ServerPlanArchive::Unconfirmed,'Result time is unavailable'
            end
            state=TournamentRetention.evaluate(history,now:now,progress:times,completed_at:view['completed_at'])
            row['sporting_completed']=true if view['completed'] && !state[:expired]
            row['sporting_completed_at']=view['completed_at'] if view['completed_at']
          rescue Publication::Invalid, OrdinaryMatchService::Blocked, ServerPlanArchive::Unconfirmed => error
            row['plan_error']=error.respond_to?(:code) ? error.code.to_s : 'unconfirmed'
            unless error.respond_to?(:code) && %i[no_players too_few_players incomplete_pairs].include?(error.code)
              state={expired:false,expires_at:nil}
            end
          ensure
            reader&.close
          end
        end
        next if state[:expired]
        row['expires_at']=state[:expires_at] if state[:expires_at] && !row['sporting_completed']
        row
      end
      directory.merge(model:model.with_retained_announcements(rows),evidence_model:model)
    end

    private def prefetch_directory_documents(directory,now)
      keys=[]
      reader=nil
      directory.fetch(:model).to_h.fetch('announcements').each do |row|
        next unless TournamentTiming.registration_closed?(row,now)
        reference={'author'=>row['__insertion_user'],'publication_key'=>row['publication_key']}
        begin
          root=@service.server_schedule_source(publication_ref:reference,directory:directory)
          reader ||= OrdinaryMatchService.new(program:@program,registry:@registry,lobby:nil,games:nil,transport:nil,
            table:@provider.fetch('tournament_plan_documents'),journal:ordinary_journal,source:nil,user:method(:account!))
          keys << phase_store(reference).first_document_key(root)
          keys.concat(reader.result_document_keys(root.fetch('candidate'),root.fetch('tournament_id')))
          while keys.size >= 96
            ServerDocumentRows.read_keys(@provider.fetch('tournament_plan_documents'),keys.shift(96),guard:method(:account!))
          end
        rescue Publication::Invalid
          # The normal per-tournament projection below presents the actual
          # error. An unplannable row supplies no keys to the prefetch.
          next
        end
      end
      ServerDocumentRows.read_keys(@provider.fetch('tournament_plan_documents'),keys,guard:method(:account!)) unless keys.empty?
    rescue Publication::Invalid
      # Prefetch is only a read optimization. The normal projection retains
      # per-tournament error handling, including malformed/oversized evidence.
      nil
    ensure
      reader&.close
    end
    # The shared pure planner uses fresh server registration evidence. This is
    # an observed candidate, not a sealed roster or permission to play.
    def schedule_candidate(publication_ref:, context: nil, lease: nil)
      guard = context && -> { context.current?(lease) }
      access(input: publication_ref, guard: guard) do |reference|
        begin
          candidate = @service.schedule_candidate(publication_ref: reference, scoped: true).to_h
          game = @registry.build(candidate.fetch('game_id'))
          if game.team_size(candidate.fetch('game_options'), player_count: candidate.fetch('players_per_match')) == 2
            next {reason: :incomplete_pairs}.freeze
          end
          candidate
        rescue Publication::Invalid => error
          raise unless [:registration_open, :no_players, :too_few_players, :too_many_players,
            :plan_too_large, :unsupported_format, :invalid_group_configuration, :unresolved_source_diagnostics, :missing_publication].include?(error.code)
          {reason: error.code}.merge(error.details.empty? ? {} : {details: error.details}).freeze
        end
      end
    end
    def operations
      access do
        rows = @journal.list + plan_journal.list + ordinary_journal.list + readiness_journal.list + proposal_journal.list + phase_journal.list + participant_lease_journal.list
        raise OperationJournal::Conflict, :ambiguous_operation if rows.map { |row| row['id'] }.uniq.size != rows.size
        Data.freeze_tree(rows)
      end
    end

    def change_phase(tournament_id:,action:,intent_id:,expected_generation:)
      result=access do
        @service.change_phase(tournament_id:tournament_id,action:action,intent_id:intent_id,expected_generation:expected_generation)
      end
      if result && result['status']=='confirmed'
        row=load&.fetch('announcements')&.find{|item|item['__id']==tournament_id}
        signal_change({'author'=>row['__insertion_user'],'publication_key'=>row['publication_key']}) if row
      end
      result
    end

    def ordinary_service(publication_ref:, lobby:, games:, transport:)
      access(input: publication_ref) do |reference|
        ordinary_service_on_worker(publication_ref:reference,lobby:lobby,games:games,transport:transport)
      end
    end

    # Operations reconciliation already runs on a Tasks worker; no nested task.
    def ordinary_service_on_worker(publication_ref:, lobby:, games:, transport:)
      account!
      compose
      # Construction grants no authority. Its first entry/result operation
      # authenticates the publication and roster through server_source; reading
      # them here would repeat that work in a separate worker scope.
      reference=Data.freeze_tree(ScheduleSource.reference(publication_ref))
      OrdinaryMatchService.new(program:@program,registry:@registry,lobby:lobby,games:games,transport:transport,
        table:@provider.fetch('tournament_plan_documents'),journal:ordinary_journal,
        source:-> {account!; server_source(reference)},user:method(:account!),
        completed_source:-> do
          account!
          phase_store(reference,root_source:-> {evidence_source(reference)}).current
        end,
        read_scope:method(:with_read_scope),
        entry_guard:method(:authorize_entry_on_worker),changed:method(:signal_change),
        rankings_observer: (@program.method(:record_tournament_ranking) if @program.respond_to?(:record_tournament_ranking,true)))
    end

    def authorize_entry_on_worker(candidate,match,binding)
      account!
      ServerReadScope.refresh!
      source=server_source(candidate.fetch('publication_ref'))
      current=source.fetch('candidate')
      raise OrdinaryMatchService::Blocked,:source_changed unless current==candidate
      ServerMatchWindow.current(candidate,@readiness_clock.call,deadline_at:source['deadline_at'])
      # Consent is the ordinary invitation acceptance. Presence, planned
      # seats/options and the one-game binding are checked by the table service.
      true
    end

    def entry_status_on_worker(publication_ref:,match_id:,leg:)
      account!; compose
      service=ordinary_service_on_worker(publication_ref:publication_ref,lobby:nil,games:nil,transport:nil)
      service.entry_status(match_id:match_id,leg:leg)
    ensure
      service&.close
    end

    def signal_change(reference)
      @program.class.tournament_changed(reference) if @program.class.respond_to?(:tournament_changed)
    end

    def current_match_window(candidate)
      ServerMatchWindow.current(candidate,@readiness_clock.call)
    end

    def coordination_view_on_worker(publication_ref:)
      account!;compose
      reference=stored_reference(publication_ref)
      source=server_source(reference)
      service=ordinary_service_on_worker(publication_ref:reference,lobby:nil,games:nil,transport:nil)
      view=service.result_view
      if !view['completed'] && %w[groups_knockout knockout].include?(source['candidate']['format'])
        begin
          source=phase_store(reference).advance(expected_schedule_id:source['candidate']['schedule_id'])
          service.close
          service=ordinary_service_on_worker(publication_ref:reference,lobby:nil,games:nil,transport:nil)
          view=service.result_view
        rescue Publication::Invalid=>error
          raise unless %i[phase_results_incomplete group_tie_requires_resolution tournament_completed].include?(error.code)
        end
      end
      Data.freeze_tree(source.merge('results'=>view))
    ensure
      service&.close
    end
    def shared_schedule(publication_ref:, context: nil, lease: nil, include_results: false, games: nil, transport: nil, include_match_status: false)
      guard = context ? -> { context.current?(lease) } : -> { true }
      access(input: publication_ref, guard: guard) do |reference|
        begin
          source = -> { server_source(reference) }
          # Avoid even opening the plan table/journal before the deadline or
          # when registration evidence cannot produce a valid candidate.
          source.call
          journal = plan_journal
          table = @provider.fetch('tournament_plan_documents')
          account!
          schedule = ServerScheduleStore.new(table: table, journal: journal, user: method(:account!), source: source, guard: guard).synchronize
          next schedule unless include_results
          # Both readers use this operation's provider and bounded read scope.
          # The observed plan is never passed to an entry/write as authority.
          reader = OrdinaryMatchService.new(program: @program, registry: @registry, lobby: nil, games: games, transport: transport,
            table: table, journal: ordinary_journal, source: source, user: method(:account!))
          view = reader.result_view(include_match_status: include_match_status)
          raise Publication::Invalid, :source_changed unless view['schedule_id'] == schedule['candidate']['schedule_id']
          Data.freeze_tree(schedule.merge('results' => view))
        rescue Publication::Invalid => error
          raise unless [:registration_open, :no_players, :too_few_players, :too_many_players,
            :plan_too_large, :unsupported_format, :invalid_group_configuration, :unresolved_source_diagnostics, :missing_publication, :incomplete_pairs].include?(error.code)
          {reason: error.code}.merge(error.details.empty? ? {} : {details: error.details}).freeze
        ensure
          reader&.close
        end
      end
    end

    # A list needs the deterministic plan and verified results, not another
    # persisted copy of the observed candidate. Legacy plan journals remain
    # recoverable through shared_schedule; opening a list never creates one.
    def schedule_overview(publication_ref:, context: nil, lease: nil, games: nil, transport: nil, include_match_status: false)
      guard = context ? -> { context.current?(lease) } : -> { true }
      access(input: publication_ref, guard: guard) do |reference|
        begin
          source = -> { server_source(reference) }
          observed = source.call
          reader = OrdinaryMatchService.new(program: @program, registry: @registry, lobby: nil, games: games, transport: transport,
            table: @provider.fetch('tournament_plan_documents'), journal: ordinary_journal, source: source, user: method(:account!))
          view = reader.result_view(include_match_status: include_match_status)
          raise Publication::Invalid, :source_changed unless view['schedule_id'] == observed['candidate']['schedule_id']
          Data.freeze_tree(observed.slice('candidate', 'phase_history').merge('storage' => 'observed', 'results' => view))
        rescue Publication::Invalid => error
          raise unless [:registration_open, :no_players, :too_few_players, :too_many_players,
            :plan_too_large, :unsupported_format, :invalid_group_configuration, :unresolved_source_diagnostics, :missing_publication, :incomplete_pairs].include?(error.code)
          {reason: error.code}.merge(error.details.empty? ? {} : {details: error.details}).freeze
        ensure
          reader&.close
        end
      end
    end

    def shared_readiness(publication_ref:, available: nil, intent_id: nil, context: nil, lease: nil)
      guard = context ? -> {context.current?(lease)} : -> {true}
      result=access(input:publication_ref,guard:guard) do |reference|
        source = -> {server_source(reference)}
        source.call
        service = ServerReadinessService.new(table:@provider.fetch('tournament_plan_documents'),journal:readiness_journal,
          user:method(:account!),source:source,clock:@readiness_clock,guard:guard)
        available.nil? ? service.snapshot : service.set_available(available:available,intent_id:intent_id)
      end
      if result && !available.nil? && @program.class.respond_to?(:tournament_availability_changed)
        @program.class.tournament_availability_changed(publication_ref,available)
      end
      result
    end
    def advance_phase(publication_ref:,expected_schedule_id:,context:nil,lease:nil)
      guard=context ? -> {context.current?(lease)} : -> {true}
      access(input:[publication_ref,expected_schedule_id],guard:guard) do |values|
        reference=stored_reference(values[0])
        begin
          phase_store(reference,guard).advance(expected_schedule_id:values[1])
        rescue Publication::Invalid=>error
          raise unless [:phase_results_incomplete,:group_tie_requires_resolution,:tournament_completed,:unsupported_format,:phase_changed,:not_registered].include?(error.code)
          {reason:error.code}.freeze
        end
      end
    end
    def start_notice_source(publication_ref:)
      access(input:publication_ref) do |reference|
        start_notice_source_on_worker(publication_ref:reference)
      end
    end
    def shared_proposal(publication_ref:,match_id:,leg:,action:'read',token:nil,intent_id:nil,context:nil,lease:nil)
      raise ArgumentError,'Unknown pilot action' unless %w[read propose accept decline].include?(action)
      guard=context ? -> {context.current?(lease)} : -> {true}
      result=access(input:[publication_ref,match_id,leg,token,intent_id],guard:guard) do |values|
        reference,id,match_leg,expected,intent=values
        if action=='read'
          proposal_view_on_worker(publication_ref:reference,match_id:id,leg:match_leg,guard:guard)
        else
          proposal_on_worker(publication_ref:reference,match_id:id,leg:match_leg,action:action,token:expected,intent_id:intent,guard:guard)
        end
      end
      signal_change(publication_ref) if result && action!='read'
      if result && (result.fetch('accepted',[]).include?(@owner) || result.fetch('declined',[]).include?(@owner)) &&
          @program.class.respond_to?(:forget_tournament_invitation)
        @program.class.forget_tournament_invitation(result['token'])
      end
      result
    end

    def proposal_view_on_worker(publication_ref:,match_id:,leg:,guard:-> {true})
      value=proposal_on_worker(publication_ref:publication_ref,match_id:match_id,leg:leg,guard:guard)
      begin
        entry=entry_status_on_worker(publication_ref:publication_ref,match_id:match_id,leg:leg)
        value.merge('table_available'=>!entry['binding'].nil?)
      rescue OrdinaryMatchService::Blocked=>error
        raise unless error.code==:result_already_recorded
        value.merge('state'=>'completed','table_available'=>false)
      end
    end

    # Used only from managed work. No nested Tasks.run, alerts or UI callbacks.
    def directory_on_worker
      account!; compose
      @service.list
    end

    def notification_context_on_worker(publication_ref:)
      account!;compose
      @service.notification_context(publication_ref:publication_ref)
    end

    def start_notice_source_on_worker(publication_ref:)
      account!;compose
      result=@service.start_notice_source(publication_ref:stored_reference(publication_ref))
      account!
      result
    end

    def event_notice_source_on_worker(publication_ref:,kind:,phase_id:nil)
      account!;compose
      reference=stored_reference(publication_ref)
      value=@service.notification_context(publication_ref:reference)
      value=value.reject { |key,_| key=='partner_changes' } unless kind=='partnership'
      return value unless %w[finished phase_finished].include?(kind) && value['publication']
      # Rendering/validating a notice is read-only. Only the coordinator may
      # advance a sporting phase; a notice must not race its plan publication.
      view=coordination_source_on_worker(publication_ref:reference)
      if kind=='phase_finished'
        transition=PhaseDescription.transitions(view).find{|entry|entry['phase_id']==phase_id}
        transition=transition.merge('phase'=>PhaseDescription.label_data(transition['phase']),
          'next_phase'=>PhaseDescription.label_data(transition['next_phase'])) if transition
        return value.merge('transition'=>transition)
      end
      candidate=view.fetch('candidate')
      reader=ordinary_service_on_worker(publication_ref:reference,lobby:nil,games:nil,transport:nil)
      results=reader.result_view
      summary=TournamentFinishSummary.build(candidate:candidate,results:results,
        history:view.fetch('phase_history',[]),usernames:value['usernames'])
      value.merge(summary).merge('results'=>results.slice('completed','completed_at'))
    ensure
      reader&.close
    end

    def coordination_source_on_worker(publication_ref:)
      account!; compose
      server_source(stored_reference(publication_ref))
    end

    def readiness_on_worker(publication_ref:,available:nil,intent_id:nil)
      account!; compose
      service=proposal_service(stored_reference(publication_ref),-> {true}).last
      available.nil? ? service.snapshot : service.set_available(available:available,intent_id:intent_id)
    end

    def proposal_on_worker(publication_ref:,match_id:,leg:,action:'read',token:nil,intent_id:nil,guard:-> {true})
      account!; compose
      service,readiness=proposal_service(stored_reference(publication_ref),guard)
      match={match_id:match_id,leg:leg}
      case action
      when 'read' then service.snapshot(**match)
      when 'propose'
        ensure_match_entry_idle!
        source=coordination_source_on_worker(publication_ref:publication_ref)
        subject=lease_subject(source.fetch('candidate'),{'match_id'=>match_id,'leg'=>leg})
        previous=participant_lease_on_worker.state
        raise ServerParticipantLease::Busy,'Another match reserves this account' if previous && previous['subject']!=subject
        result=service.propose(**match,intent_id:intent_id)
        acquire_invitation_lease(publication_ref,match,result['token']) if result['accepted'].include?(@owner)
        # Deliver only after the authenticated invitation exists. A failed
        # delivery never repeats the invitation write or fabricates consent.
        if result['sender']==@owner && @program.class.respond_to?(:send_tournament_proposal)
          source=coordination_source_on_worker(publication_ref:publication_ref)
          (result['players']-result['accepted']).each do |person|
            @program.class.send_tournament_proposal({'version'=>2,'stage'=>'consent','backend_identity'=>backend_identity,
              'publication_ref'=>source['candidate']['publication_ref'],'schedule_id'=>source['candidate']['schedule_id'],
              'match_id'=>match_id,'leg'=>leg,'token'=>result['token'],'recipient'=>person})
          end
        end
        result
      when 'accept','decline'
        if action=='accept'
          ensure_match_entry_idle!
          current=service.snapshot(**match)
          raise Publication::Invalid,:proposal_changed unless current['token']==token && %w[awaiting_consent consented].include?(current['state'])
          acquire_invitation_lease(publication_ref,match,token)
        end
        result=service.respond(**match,token:token,accept:action=='accept',intent_id:intent_id)
        if action=='decline'
          participant_lease_on_worker.release(token:token)
        end
        result
      else raise ArgumentError,'Unknown proposal action'
      end
    end

    def ensure_match_entry_idle!
      if @program.class.respond_to?(:tournament_busy?) && @program.class.tournament_busy?
        raise OrdinaryMatchService::Blocked,:already_at_another_table
      end
    end

    def acquire_invitation_lease(reference,match,token)
      source=coordination_source_on_worker(publication_ref:reference)
      subject=lease_subject(source.fetch('candidate'),{'match_id'=>match[:match_id],'leg'=>match[:leg]})
      leases=participant_lease_on_worker
      previous=leases.state
      # A newly accepted invitation for this same fixture replaces only our
      # own obsolete reservation. It must never steal a different match.
      if previous && previous['subject']==subject && previous['token']!=token
        leases.release(token:previous['token'])
      end
      leases.acquire(subject:subject,token:token)
    end

    def participant_lease_on_worker
      account!;compose
      ServerParticipantLease.new(table:@provider.fetch('tournament_plan_documents'),journal:participant_lease_journal,
        user:method(:account!),clock:@readiness_clock)
    end
    def join(id); membership_change(id){@service.join(tournament_id:id)}; end
    def set_partner(id, account, partner, intent)
      values=Data.freeze_tree(Data.copy([id,account,partner,intent]))
      membership_change(id){@service.set_partner(tournament_id:values[0],account:values[1],partner:values[2],intent_id:values[3])}
    end
    def partnership_action(id, action, partner, request_key, intent)
      membership_change(id, input: [id, action, partner, request_key, intent]) do |values|
        @service.partnership_action(tournament_id: values[0], action: values[1], partner: values[2],
          request_key: values[3], intent_id: values[4])
      end
    end

    def complete_partnerships_on_worker(publication_ref:)
      account!; compose
      row = @service.publication(publication_ref: stored_reference(publication_ref))
      @service.complete_partnerships(tournament_id: row['__id'])
    end
    def remove_participant(id, account)
      values=Data.freeze_tree(Data.copy([id,account]))
      membership_change(id){@service.remove_participant(tournament_id:values[0],account:values[1])}
    end
    def withdraw(id); membership_change(id){@service.withdraw(tournament_id:id)}; end
    def reconcile(id)
      access(input: id) do |copy|
        next participant_lease_on_worker.reconcile(copy) if participant_lease_journal.fetch(copy)
        phase_record=phase_journal.fetch(copy)
        if phase_record
          document=StrictJson.parse(phase_record['values']['document_json'],max_nesting:12)
          reference=document.fetch('publication_ref')
          begin
            next phase_store(stored_reference(reference)).reconcile(copy)
          rescue Publication::Invalid=>error
            raise unless error.code==:missing_publication
            # A complete phase may make the old tournament expire during its
            # final acknowledgement. Only read back that exact stored intent;
            # never finish missing parts using an expired publication.
            next phase_store(reference,root_source:-> {evidence_source(reference)}).reconcile(copy,completed_only:true)
          end
        end
        proposal_record=proposal_journal.fetch(copy)
        if proposal_record
          document=StrictJson.parse(proposal_record['values']['document_json'],max_nesting:12)
          next proposal_service(stored_reference(document.fetch('publication_ref')),-> {true}).first.reconcile(copy)
        end
        readiness_record = readiness_journal.fetch(copy)
        if readiness_record
          document=StrictJson.parse(readiness_record['values']['document_json'],max_nesting:12)
          reference=stored_reference(document.fetch('publication_ref'))
          next ServerReadinessService.new(table:@provider.fetch('tournament_plan_documents'),journal:readiness_journal,
            user:method(:account!),source:-> {server_source(reference)},clock:@readiness_clock).reconcile(copy)
        end
        ordinary_record=ordinary_journal.fetch(copy)
        if ordinary_record
          raise OrdinaryMatchService::Blocked,:match_service_unavailable unless @program.respond_to?(:reconcile_ordinary_tournament_operation)
          next @program.reconcile_ordinary_tournament_operation(ordinary_record)
        end
        plan_record = plan_journal.fetch(copy)
        if plan_record
          document = StrictJson.parse(plan_record['values']['document_json'], max_nesting: 12)
          reference = document.fetch('publication_ref')
          row = @service.list.fetch('announcements').find { |item| item['__insertion_user'].downcase == reference['author'] && item['publication_key'] == reference['publication_key'] }
          raise Publication::Invalid, :missing_publication unless row
          reference = reference.merge('author' => row['__insertion_user'])
          next ServerScheduleStore.new(table: @provider.fetch('tournament_plan_documents'), journal: plan_journal,
            user: method(:account!), source: -> { server_source(reference) }).reconcile(copy)
        end
        record = @service.reconcile(operation_id: copy)
        if record['kind'] == 'publication' && record['status'] == 'confirmed'
          record = record.merge('organizer_registration' => @service.register_creator(publication_record: record)).freeze
        end
        record
      end
    end

    def publish(**values)
      access(input: values.transform_keys(&:to_s)) do |copy|
        raise Publication::Invalid, :unsupported_withdrawal_timezone unless copy['timezone'] == 'UTC'
        copy=with_capacity(copy)
        publication_content!(copy)
        record = @service.publish(**copy.transform_keys(&:to_sym))
        record.merge('organizer_registration' => @service.register_creator(publication_record: record)).freeze
      end
    end

    def edit_tournament(**values)
      membership_change(values.fetch(:tournament_id),input:values.transform_keys(&:to_s)) do |copy|
        copy=with_capacity(copy)
        publication_content!(copy, amendment: true)
        @service.edit_tournament(**copy.transform_keys(&:to_sym))
      end
    end

    def delete_tournament(id, intent, generation)
      membership_change(id,input:[id,intent,generation]) do |copy|
        @service.delete_tournament(tournament_id: copy[0], intent_id: copy[1], expected_generation: copy[2])
      end
    end

    private

    def membership_change(id,input:nil)
      reference=nil
      result=access(input:input) do |copy|
        row=@service.list['announcements'].find{|item|item['alias_ids'].include?(id)}
        reference={'author'=>row['__insertion_user'].downcase,'publication_key'=>row['publication_key']} if row
        yield copy
      end
      signal_change(reference) if reference && result
      result
    end

    def lease_subject(candidate,match)
      {'publication_ref'=>candidate.fetch('publication_ref'),'schedule_id'=>candidate.fetch('schedule_id'),
        'match_id'=>match.fetch('match_id'),'leg'=>match.fetch('leg')}
    end

    def participant_lease_journal
      account!
      @participant_lease_journal ||= OperationJournal.new(directory:File.join(@program.data_path,
        'tournaments-'+Digest::SHA256.hexdigest(@identity)[0,16],'participant-lease-journals'),
        owner:@owner,backend_identity:@identity+':participant-leases-v1')
    end

    def with_capacity(values)
      draft=values.fetch('draft')
      values.merge('draft'=>draft.merge('participant_limit'=>draft.fetch('participant_limit',16)))
    end

    def stored_reference(reference)
      row=@service.publication(publication_ref:reference)
      reference.merge('author'=>row['__insertion_user'])
    end

    def proposal_journal
      account!
      @proposal_journal ||= OperationJournal.new(directory:File.join(@program.data_path, 'tournaments-' + Digest::SHA256.hexdigest(@identity)[0,16],'tournament-pilot-proposal-journals'),
        owner:@owner,backend_identity:@identity+':pilot-proposals-v1')
    end

    def proposal_service(reference,guard)
      source=-> {server_source(reference)}
      source.call
      table=@provider.fetch('tournament_plan_documents')
      readiness=ServerReadinessService.new(table:table,journal:readiness_journal,user:method(:account!),
        source:source,clock:@readiness_clock,guard:guard)
      service=ServerProposalService.new(table:table,journal:proposal_journal,user:method(:account!),
        source:source,readiness:readiness,clock:@readiness_clock,guard:guard,registry:@registry)
      [service,readiness]
    end

    def readiness_journal
      account!
      @readiness_journal ||= OperationJournal.new(directory:File.join(@program.data_path, 'tournaments-' + Digest::SHA256.hexdigest(@identity)[0,16],'tournament-shared-readiness-journals'),
        owner:@owner,backend_identity:@identity+':shared-readiness-v1')
    end

    def ordinary_journal
      account!
      return @ordinary_journal if @ordinary_journal
      @ordinary_journal=OperationJournal.new(directory:File.join(@program.data_path, 'tournaments-' + Digest::SHA256.hexdigest(@identity)[0,16],'tournament-ordinary-match-journals'),
        owner:@owner,backend_identity:@identity+':ordinary-match-v1')
      account!
      @ordinary_journal
    end

    def server_source(reference)
      phase_store(reference).current
    end

    def evidence_source(reference)
      account!
      @service.server_schedule_source(publication_ref:reference,evidence_only:true)
    end

    def phase_journal
      account!
      @phase_journal ||= OperationJournal.new(directory:File.join(@program.data_path, 'tournaments-' + Digest::SHA256.hexdigest(@identity)[0,16],'tournament-server-phase-journals'),
        owner:@owner,backend_identity:@identity+':sporting-phases-v1')
    end

    def phase_store(reference,guard=-> {true},root_source:nil)
      table=@provider.fetch('tournament_plan_documents')
      root_source ||= -> {account!;@service.server_schedule_source(publication_ref:reference)}
      reader=->(candidate,root) do
        fixed=-> do
          account!
          fresh=root_source.call
          fresh=fresh.merge('candidate'=>fresh['candidate'].reject{|key,_|key=='observed_at'})
          raise Publication::Invalid,:source_changed unless fresh==root
          root.merge('candidate'=>candidate)
        end
        ordinary=OrdinaryMatchService.new(program:@program,registry:@registry,lobby:nil,games:nil,transport:nil,
          table:table,journal:ordinary_journal,source:fixed,user:method(:account!))
        begin
          ordinary.result_view
        ensure
          ordinary.close
        end
      end
      ServerPhaseStore.new(table:table,journal:phase_journal,user:method(:account!),source:root_source,results:reader,guard:guard)
    end

    def plan_journal
      account!
      return @plan_journal if @plan_journal
      directory = File.join(@program.data_path, 'tournaments-' + Digest::SHA256.hexdigest(@identity)[0,16], 'tournament-server-schedule-journals')
      account!
      @plan_journal = OperationJournal.new(directory: directory, owner: @owner, backend_identity: @identity + ':candidate-documents-v1')
      account!
      @plan_journal
    end

    def publication_content!(values, amendment: false)
      fields = %w[draft rules registration_opens_at registration_closes_at timezone]
      content = Publication.from_draft(registry: @registry, publication_key: 'server-trial-preflight',
        **values.slice(*fields).transform_keys(&:to_sym)).to_row
      ServerCapacity.validate!(registry:@registry,game_id:content['game'],settings:JSON.parse(content['settings_json']))
      limits = {'title' => 1024, 'rules' => 2048, 'settings_json' => 2048, 'schedule_json' => 2048}
      if limits.any? { |key, limit| content.fetch(key).bytesize > limit } ||
          (amendment && JSON.generate(content).bytesize + 64 > 2048)
        raise Publication::Invalid, :server_trial_payload_limit
      end
    end

    def account!
      value = Data.account(@user.call).downcase
      @changed = true unless value == @owner
      raise TablesGateway::ContextChanged, 'Account changed' if @changed
      @actor
    rescue Publication::Invalid
      @changed = true
      raise TablesGateway::ContextChanged, 'Account unavailable'
    end

    def compose
      return if @service
      account!
      provider = ServerReadScope::Provider.new(@provider_factory.call,read_scope_identity)
      @provider = provider
      gateway = TablesGateway.new(server_tables: provider, user: method(:account!), operation_error_classes: [EltenLink::Error])
      directory = File.join(@program.data_path, 'tournaments-' + Digest::SHA256.hexdigest(@identity)[0,16], 'tournament-server-trial-journals')
      account!
      @journal = OperationJournal.new(directory: directory, owner: @owner, backend_identity: @identity)
      account!
      @service = PublicService.new(gateway: gateway, journal: @journal, registry: @registry,
        user: method(:account!), backend_identity: @identity, clock: @clock, retention: method(:retained_directory))
    end

    def access(input: nil, guard: nil)
      account!
      raise TablesGateway::Cancelled, 'View changed' if guard && !guard.call
      copy = Data.freeze_tree(Data.copy(input, max_bytes: 262_144, max_depth: 12, max_nodes: 16_384))
      result = EltenAPI::Tasks.run(title: GameRoomContent.utf8(_("Tournaments")), ui: :none, cancellable: false) do
        account!
        raise TablesGateway::Cancelled, 'View changed' if guard && !guard.call
        compose
        value = with_read_scope { yield copy }
        account!
        raise TablesGateway::Cancelled, 'View changed' if guard && !guard.call
        value
      end
      account!
      raise TablesGateway::Cancelled, 'View changed' if guard && !guard.call
      @last_error = nil
      result
    rescue *(ERRORS + (defined?(EltenLink::Error) ? [EltenLink::Error] : [])) => error
      @last_error = error
      message = if error.is_a?(Publication::Invalid) && error.code == :server_trial_payload_limit
        _("Tournament fields are limited to 2048 bytes. Shorten the rules or settings. Nothing was sent.")
      elsif error.is_a?(Publication::Invalid) && error.code == :server_match_capacity
        _("These settings would create more than 256 matches in one phase. Reduce the participant limit, choose groups or use rotating compositions. Nothing was sent.")
      elsif error.is_a?(TablesGateway::ContextChanged) || error.is_a?(ServerPlanArchive::ContextChanged)
        _("The account changed. Close tournaments and reopen them.")
      elsif error.is_a?(TablesGateway::UnconfirmedWrite) || error.is_a?(ServerPlanArchive::Unconfirmed)
        _("The change could not be confirmed. Refresh to check its status.")
      elsif error.is_a?(ServerParticipantLease::Busy)
        _("You already accepted another match. Cancel that invitation or finish the match first.")
      elsif error.respond_to?(:code)
        case error.code
        when :too_few_players
          if error.respond_to?(:details) && error.details[:minimum]
            _("Cannot start: %{count} participants registered; at least %{minimum} are required.") % error.details
          else
            _("There are not enough participants to start this tournament.")
          end
        when :incomplete_pairs
          if error.respond_to?(:details) && error.details[:count]
            _("Cannot start: unpaired participants: %{count}. An even number is required.") % {count: error.details[:count]}
          else
            _("Some participants still need partners. Complete the pairs before creating matches.")
          end
        when :partner_already_set then _("Dissolve your current partnership before choosing someone else.")
        when :partner_unavailable then _("This participant already has a partner.")
        when :own_partnership_only then _("You can only choose your own partner.")
        when :not_open then _("Registration has not opened yet.")
        when :closed,:tournament_started then _("Registration is closed.")
        when :participant_limit,:participant_limit_reached,:tournament_full,:capacity_exceeded then _("The tournament is full.")
        when :source_changed,:stale_publication,:phase_changed then _("The tournament changed. Refresh and choose the action again.")
        when :not_organizer then _("Only the organizer can do this.")
        when :already_at_another_table then _("Leave your current table before accepting a tournament match.")
        else _("Tournament access failed. Check pending changes before repeating a write.")
        end
      else
        _("Tournament access failed. Check pending changes before repeating a write.")
      end
      @alert.call(GameRoomContent.utf8(message))
      nil
    end

    def read_scope_identity
      [@identity,@owner]
    end

    def with_read_scope(&block)
      ServerReadScope.run(read_scope_identity,&block)
    end

    # These APIs are also used directly by managed background work. UI access
    # and nested calls share the operation's scope, never another worker's.
    module WorkerReads
      %i[directory_on_worker notification_context_on_worker start_notice_source_on_worker event_notice_source_on_worker coordination_source_on_worker complete_partnerships_on_worker
        coordination_view_on_worker readiness_on_worker proposal_on_worker proposal_view_on_worker entry_status_on_worker].each do |name|
        define_method(name) do |*args,**keywords,&block|
          with_read_scope { super(*args,**keywords,&block) }
        end
      end
    end
    prepend WorkerReads
  end
end
