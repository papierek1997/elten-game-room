require_relative 'server_workspace'
require_relative 'proposal_notice'
require_relative 'tournament_start_notice'
require_relative 'phase_description'
require_relative '../game_room_background'

module GameRoomTournaments
  # Finite directory/result work. Ordinary table invitations need no readiness
  # records, participant reservations or renewal timer.
  class ServerCoordination
    TYPE='game_room.tournament_changed'.freeze
    Data=Publication::Data
    LIMIT=64
    attr_reader :last_error

    def self.reference(value)
      value=Data.copy(value,max_bytes:512,max_nodes:8,max_depth:2)
      raise Publication::Invalid,:invalid_coordination_reference unless value.is_a?(Hash) && value.keys.sort==%w[author publication_key]
      value['author']=Data.account(value['author']).downcase
      Data.key!(value['publication_key'])
      Data.freeze_tree(value)
    end

    def initialize(workspace:,user:,clock:,worker:,wake:,started:->(_reference){},finished:->(_reference){},phase_finished:->(_reference,_phase_id){},partners_changed:->(_reference,_change){})
      @workspace,@user,@clock,@worker,@wake,@started=workspace,user,clock,worker,wake,started
      @finished=finished
      @phase_finished=phase_finished
      @partners_changed=partners_changed
      @announced_partners={}
      @owner=Data.account(user.call).downcase
      @lock=Mutex.new
      @pending,@deadlines={}, {}
      @view_revisions,@view_values={},{}
      @observed_references={}
      @view_sequence=0
      @active_job=@retry_job=nil
      @started_references={}
      @finished_references={}
      @announced_phases={}
      @failures=0
      @retry_at=0
      @closed=false
    end

    def changed(reference,broadcast:false,sender:nil)
      reference=self.class.reference(reference)
      sender=Data.account(sender).downcase if sender
      @lock.synchronize do
        return false if @closed || @pending.size>=LIMIT && !@pending.key?(reference)
        prior=@pending[reference]
        @pending[reference]={broadcast:broadcast || prior&.fetch(:broadcast,false),sender:sender || prior&.fetch(:sender,nil),timed:false}
      end
      true
    end

    def bootstrap
      @lock.synchronize{@bootstrap=true unless @closed}
    end

    def view_revision(reference)
      @lock.synchronize{reference ? @view_revisions[reference] : @view_sequence}
    end

    # Presentation only, consumed on this revision's UI refresh. Mutations and
    # explicit Refresh always read the server again through ServerWorkspace.
    def view_snapshot(reference)
      presentation_snapshot(reference)&.fetch('overview',nil)
    end

    def take_observed_references
      check!
      @lock.synchronize do
        values=@observed_references.keys
        @observed_references.clear
        values
      end
    end

    private def presentation_snapshot(reference)
      check!
      @lock.synchronize do
        return nil if @last_error || @pending.key?(reference) || @active_job&.first==reference || @retry_job&.first==reference
        @view_values[reference]
      end
    end

    def tick
      return if @closed
      if (done=@worker.take)
        value,error=done
        if !error && value && @active_job && @active_job.first!=:directory
          visible=value.slice('completed','directory','results','blocked','blocked_details','overview')
          reference=@active_job.first
          @lock.synchronize do
            if !visible.empty? && @view_values[reference]!=visible
              @view_values[reference]=Data.freeze_tree(Data.copy(visible,max_bytes:2_097_152,max_nodes:131_072,max_depth:18))
              @view_revisions[reference]=(@view_sequence+=1)
              while @view_values.size>LIMIT
                oldest=@view_values.shift.first
                @view_revisions.delete(oldest)
              end
            end
          end
        end
        missing=error.is_a?(Publication::Invalid) && error.code==:missing_publication
        if @active_job && @active_job.first!=:directory && ((!error && value) || missing)
          @lock.synchronize do
            @observed_references[@active_job.first]=true
            @observed_references.shift while @observed_references.size>LIMIT
          end
        end
        @last_error=error if error
        cause=error
        cause=cause.cause while cause && cause.cause && !GameRoomNetworkErrors.expected?(cause)
        if cause && (GameRoomNetworkErrors.expected?(cause) || cause.is_a?(IOError) || cause.is_a?(SystemCallError))
          @failures+=1
          delay=GameRoomNetworkErrors.retry_delay(cause,normal:[30 * 2**[@failures-1,4].min,300].min,rate_limit:60)
          @retry_at=@clock.call+delay
          # Startup and one-shot wakes may have no later availability timer.
          # Retain the failed job, not just the delay before unrelated work.
          @lock.synchronize{@retry_job=@active_job unless @closed}
        else
          # A closed window, incomplete roster or invalid fixture belongs to
          # one tournament. Keep the error visible, but do not delay unrelated
          # fixtures as though their connection had failed as well.
          @failures=0
          @retry_at=0
          @last_error=nil unless error
        end
        @active_job=nil
        @lock.synchronize{@bootstrap=true} if error.is_a?(GameRoomNetworkErrors::ClockUnavailable)
        if value && value['deadlines']
          @lock.synchronize{value['deadlines'].each{|ref,time|@deadlines[ref]=time}}
        end
      end
      return if @worker.busy?
      return if @clock.call<@retry_at
      job=@lock.synchronize do
        now=@clock.call
        @deadlines.delete_if do |reference,time|
          due=time<=now
          @pending[reference] ||= {broadcast:false,sender:nil,timed:true} if due
          due
        end
        if @retry_job
          retry_job=@retry_job
          @retry_job=nil
          retry_job
        elsif @bootstrap
          @bootstrap=false
          [:directory,nil]
        elsif !@pending.empty?
          @pending.shift
        end
      end
      return unless job
      started=GameRoomBackground.admit(@worker) do
        check!
        job.first==:directory ? directory : coordinate(job.first,**job.last)
      end
      if started
        @active_job=job
      else
        @lock.synchronize{@retry_job ||= job unless @closed}
      end
    end

    def close
      @lock.synchronize{@closed=true;@pending.clear;@deadlines.clear;@view_revisions.clear;@view_values.clear;@observed_references.clear;@active_job=@retry_job=nil;@bootstrap=false}
      @worker.close
    end

    # Public for deterministic integration tests; runtime calls it only on the
    # managed worker. A remote wake carries no state or execution permission.
    def coordinate(reference,broadcast:false,sender:nil,timed:false)
      @workspace.read_operation { coordinate_current(reference,broadcast:broadcast,sender:sender,timed:timed) }
    end

    private def coordinate_current(reference,broadcast:,sender:,timed:)
      context=notification_context!(reference,broadcast:broadcast,sender:sender)
      visible={'directory'=>context.slice('publication','members','pairs','pair_requests','invitations')}
      row=context['publication']
      if !row || !TournamentTiming.started?(row,@clock.call)
        deadline=row && TournamentLifecycle.next_change(row,now:@clock.call)
        schedule(reference,deadline-@clock.call) if deadline
        return visible
      end

      begin
        if context['needs_pair_completion']
          result = @workspace.complete_partnerships_on_worker(publication_ref: reference)
          context = notification_context!(reference, broadcast: !!result, sender: nil)
          visible['directory'] = context.slice('publication','members','pairs','pair_requests','invitations')
        end
        source=@workspace.coordination_view_on_worker(publication_ref:reference)
      rescue Publication::Invalid, PublicService::Error=>error
        raise unless %i[registration_open no_players too_few_players incomplete_pairs unresolved_source_diagnostics].include?(error.code)
        result = visible.merge('blocked'=>error.code.to_s)
        result['blocked_details'] = error.details.transform_keys(&:to_s) if error.respond_to?(:details)
        return result
      end
      visible['results']=source.fetch('results')
      visible['overview']=source.slice('candidate','results','phase_history')
      if source.fetch('results')['completed']
        @lock.synchronize{@deadlines.delete(reference)}
        if reference['author']==@owner && !@finished_references.key?(reference)
          @finished.call(reference)
          @finished_references.shift if @finished_references.size>=LIMIT
          @finished_references[reference]=true
        end
        return visible.merge('completed'=>true)
      end
      if reference['author']==@owner
        PhaseDescription.transitions(source).each do |transition|
          key=[reference,transition['phase_id']]
          next if @announced_phases.key?(key)
          @phase_finished.call(reference,transition['phase_id'])
          @announced_phases.shift if @announced_phases.size>=LIMIT
          @announced_phases[key]=true
        end
      end
      if reference['author']==@owner && !@started_references.key?(reference)
        @started.call(reference)
        @started_references.shift if @started_references.size>=LIMIT
        @started_references[reference]=true
      end
      visible
    end

    private
    def notification_context!(reference,broadcast:,sender:)
      check!
      source=@workspace.notification_context_on_worker(publication_ref:reference)
      people=source.fetch('people')
      eligible=source.fetch('senders')
      raise ProposalNotice::Stale,'Unrelated tournament wake' if sender && !eligible.include?(sender)
      raise ProposalNotice::Stale,'Not a tournament participant' unless eligible.include?(@owner)
      check!
      source.fetch('partner_changes',[]).each do |change|
        next unless change['author']==@owner
        key=[reference,change['key'],change['index']]
        next if @announced_partners.key?(key)
        @partners_changed.call(reference,change)
        @announced_partners.shift if @announced_partners.size>=512
        @announced_partners[key]=true
      end
      if broadcast
        names=source['usernames'] || RegistrationProjection.usernames(source.fetch('members'))
        # Pending invitees are not players, but must learn about closed/full
        # registration too. Reuse this event, not a recipient polling loop.
        invited=source.fetch('invitations',[]).select { |entry| entry['status']=='pending' && !entry['resolved'] }
        names=names.merge(invited.to_h { |entry| [entry.fetch('account'),entry.fetch('username')] })
        recipients=(people+invited.map { |entry| entry.fetch('account') }).uniq
        recipients.reject{|person|person==@owner}.each{|person|@wake.call(RegistrationProjection.delivery_name(names,person),reference)}
      end
      source
    end

    def directory
      data=@workspace.directory_on_worker
      now=@clock.call
      refs=data.fetch('announcements').filter_map do |row|
        member=data.fetch('members').any?{|person|person['tournament_id']==row['__id'] && person['account']==@owner}
        next unless member || row['__insertion_user'].downcase==@owner
        start=TournamentTiming.starts_at(row)
        next unless start
        next if !TournamentTiming.optional?(row) && TournamentLifecycle.ending_at(row)<=now
        [self.class.reference({'author'=>row['__insertion_user'],'publication_key'=>row['publication_key']}),[start,now].max]
      end
      {'deadlines'=>refs.first(LIMIT)}
    end

    def schedule(reference,seconds)
      @lock.synchronize{@deadlines[reference]=@clock.call+seconds unless @closed}
    end

    def check!
      raise ServerPlanArchive::ContextChanged,'Account changed' if @closed || Data.account(@user.call).downcase!=@owner
      true
    end
  end
end
