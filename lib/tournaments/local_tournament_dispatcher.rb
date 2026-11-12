require_relative 'local_individual_execution'
require_relative 'local_match_proposals'
module GameRoomTournaments
  # One bounded event-driven pass on this client's own account. Other clients
  # prepare their disjoint matches; shared reservations enforce the table limit.
  class LocalTournamentDispatcher
    Data = Publication::Data
    C = CoordinationContract
    def initialize(**options)
      @options, @backend, @context, @clock = options, options.fetch(:plan_backend), options.fetch(:context), options.fetch(:clock)
      @expected = Data.freeze_tree(Data.copy(@context.call))
      @registry = options.fetch(:registry)
      @availability_lock = Mutex.new
      @storage = storage_class.new(plan_backend: @backend, plan_directory: options.fetch(:plan_directory),
        source_identity: options.fetch(:source_identity), registry: @registry, guard: method(:guard!))
    end
    def configure(intent_id:, max_tables:,consent_before_table:false)
      raise Publication::Invalid,:invalid_availability unless [true,false].include?(consent_before_table)
      raise Publication::Invalid, :invalid_table_limit unless Data.integer?(max_tables, 1) && max_tables <= 32
      record, intent_id = target!(intent_id)
      raise C::Blocked, :not_author unless record['preview']['actor'] == actor
      access(record) do |document|
        raise C::Blocked, :tables_in_use if LocalDispatchContract.active(document, intent_id).size > max_tables
        document['dispatch'] ||= {'policies' => {}, 'availability' => {}}
        document['dispatch']['policies'][intent_id] = {'plan_digest' => record['evidence']['plan_digest'], 'max_tables' => max_tables}
        document['dispatch']['policies'][intent_id]['consent_before_table']=true if consent_before_table
        @storage.write(document)
        max_tables
      end
    end
    def available(intent_id:, available:)
      raise Publication::Invalid, :invalid_availability unless [true, false].include?(available)
      requested_intent = intent_id
      record, intent_id = target!(intent_id)
      participant!(record)
      row = access(record) do |document|
        policy!(document, intent_id)
        people = document['dispatch']['availability'][intent_id] ||= {}
        prior = people[actor]
        now = now!
        revision = prior ? prior['revision'] : 1
        revision += 1 if prior && (prior['available'] != available || prior['expires_at'] <= now)
        people[actor] = {'available' => available, 'revision' => revision, 'observed_at' => now, 'expires_at' => now + LocalDispatchContract::TTL}
        LocalMatchProposals.withdraw(document,intent_id,actor) unless available
        @storage.write(document)
        Data.freeze_tree(Data.copy(people[actor]))
      end
      @availability_lock.synchronize { @own_availability = [requested_intent, row].freeze }
      row
    end
    # A lease heartbeat is an own-account write, not a presence query. Never
    # overwrite another client's withdrawal or a more recent lease snapshot.
    def availability_refresh_due?(intent_id:)
      own = @availability_lock.synchronize { @own_availability }
      own && own[0] == intent_id && own[1]['available'] && now! >= own[1]['expires_at'] - LocalDispatchContract::TTL / 2
    end
    def refresh_availability(intent_id:)
      own = @availability_lock.synchronize { @own_availability }
      raise C::Blocked, :availability_changed unless own && own[0] == intent_id && own[1]['available']
      record, intent_id = target!(intent_id)
      row = access(record) do |document|
        policy!(document, intent_id)
        people = document['dispatch']['availability'][intent_id]
        raise C::Blocked, :availability_changed unless people && people[actor].eql?(own[1])
        now = now!
        raise C::Blocked, :invalid_clock if now < own[1]['observed_at']
        revision = own[1]['revision'] + (own[1]['expires_at'] <= now ? 1 : 0)
        people[actor] = {'available' => true, 'revision' => revision, 'observed_at' => now, 'expires_at' => now + LocalDispatchContract::TTL}
        @storage.write(document)
        Data.freeze_tree(Data.copy(people[actor]))
      end
      @availability_lock.synchronize { @own_availability = [own[0], row].freeze }
      {state: :confirmed, effect: row}.freeze
    rescue C::Blocked, ReadinessContract::Blocked => error
      @availability_lock.synchronize { @own_availability = nil if @own_availability.equal?(own) }
      {state: :blocked, reason: error.code}.freeze
    end
    def snapshot(intent_id:)
      record, = target!(intent_id)
      access(record) { |document| projection(document, record) }
    end
    def advance(intent_id:)
      record, intent_id = target!(intent_id)
      participant!(record)
      view, idle_reason = access(record) do |document|
        projected = projection(document, record)
        own = (projected['active'] + projected['candidates']).any? { |row| row['players'].include?(actor) }
        [projected, own ? nil : waiting_reason(document, record, projected)]
      end
      own = view['active'].find { |row| row['players'].include?(actor) }
      candidate = own || view['candidates'].find { |row| row['players'].include?(actor) }
      return {state: :waiting, reason: idle_reason, status: view}.freeze unless candidate
      return {state: :blocked, reason: :execution_interrupted, status: view}.freeze if candidate['interrupted']
      unless candidate['reserved']
        consent=access(record) do |document|
          next true unless policy!(document,intent_id)['consent_before_table']
          existing=document.dig('dispatch','proposals',intent_id,LocalMatchProposals.key(candidate))
          proposal=LocalMatchProposals.prepare(document:document,intent:intent_id,candidate:candidate,now:now!)
          LocalMatchProposals.validate_current!(document,intent_id,proposal,now!)
          @storage.write(document) unless existing
          proposal['accepted'].sort==proposal['players'].sort
        end
        return {state: candidate['leg']==2 ? :awaiting_rematch : :awaiting_consent,status:view}.freeze unless consent
      end
      execution = execution(record, candidate)
      if candidate['started'] && candidate['coordinator'] == actor
        game = execution.local_game(action: :local_game_status)
        return game unless game[:state] == :confirmed
        if game[:status]['phase'] == 'finished'
          saved = execution.local_game(action: :finalize_local_game, revision: game[:status]['revision'])
          return saved.merge(status: snapshot(intent_id: intent_id)).freeze
        end
      end
      unless candidate['reserved']
        current = execution.current[:current]
        unless current && current['state'] == 'ready'
          declared = execution.declare(availability: 'ready', expected_revision: current ? current['ready_revision'] : 0)
          return declared unless declared[:state] == :confirmed
        end
      end
      return {state: :awaiting_invitation, status: view}.freeze if candidate['coordinator'] != actor
      result = candidate['bound'] ? execution.reconcile : execution.request_match
      return result.merge(status: snapshot(intent_id: intent_id)).freeze unless result[:state] == :bound
      access(record) do |document|
        pending=document.dig('dispatch','proposals',intent_id)
        if pending && pending.delete(LocalMatchProposals.key(candidate))
          @storage.write(document)
        end
      end
      invitations = execution.dispatch_invitations
      return invitations.merge(status: snapshot(intent_id: intent_id)).freeze unless invitations[:state] == :confirmed
      admission = execution.admission(action: :admission_status)[:status]
      started = nil
      if admission['entered_accounts'].to_a.size == candidate['players'].size
        started = execution.local_game(action: :start_local_game, binding_digest: C.digest(admission['binding']))
      end
      {state: started ? started[:state] : :invited, invitations: invitations[:effect], game: started,
        status: snapshot(intent_id: intent_id)}.freeze
    rescue LocalFixedTeamExecutionStorage::Unconfirmed => error
      {state: :uncertain, receipt: error.receipt}.freeze
    rescue C::Blocked, ReadinessContract::Blocked => error
      {state: :blocked, reason: error.code}.freeze
    end
    def accept(intent_id:,rematch_only:false,expected_proposal:nil,require_expected:false)
      record, intent_id = target!(intent_id)
      participant!(record)
      proposed=access(record) do |document|
        pending=document.dig('dispatch','proposals',intent_id) || {}
        next nil unless pending.values.any?{|row|row['players'].include?(actor)}
        if rematch_only
          key=pending.find{|_key,row|row['players'].include?(actor)}.first
          raise C::Blocked,:invitation_required unless JSON.parse(key).last==2
        end
        prior=pending.find{|_key,row|row['players'].include?(actor)}.last['accepted'].dup
        state=LocalMatchProposals.respond(document:document,intent:intent_id,actor:actor,accept:true,now:now!,expected:expected_proposal,require_expected:require_expected)
        state=:awaiting_rematch if rematch_only && state==:awaiting_consent
        @storage.write(document) unless pending.find{|_key,row|row['players'].include?(actor)}.last['accepted']==prior
        {state:state,status:projection(document,record)}.freeze
      end
      return proposed if proposed
      raise C::Blocked,:proposal_changed if expected_proposal
      view = access(record) { |document| projection(document, record) }
      own = view['active'].find { |row| row['players'].include?(actor) }
      raise C::Blocked, :invitation_required unless own && own['bound']
      access(record) do |document|
        raise C::Blocked, :participants_unavailable unless LocalDispatchContract.ready(document, intent_id, actor, now!)['state'] == 'ready'
        if own['coordinator'] != actor
          core = document['native']['cores'].find { |row| row['id'] == own['native_uuid'] }
          invitation = core && core['invitations'][actor]
          raise C::Blocked, :invitation_required unless invitation && invitation['expires_at'] > now!
        end
      end
      execution = execution(record, own)
      status = execution.admission(action: :admission_status)[:status]
      consent = execution.admission(action: :consent, binding_digest: C.digest(status['binding']))
      return consent unless consent[:state] == :confirmed
      execution.admission(action: :enter, consent_id: consent[:effect]['id'])
    end
    def decline(intent_id:,rematch_only:false,expected_proposal:nil,require_expected:false)
      record, intent_id = target!(intent_id)
      participant!(record)
      access(record) do |document|
        if rematch_only
          proposal=(document.dig('dispatch','proposals',intent_id) || {}).find{|_key,row|row['players'].include?(actor)}
          raise C::Blocked,:invitation_required unless proposal && JSON.parse(proposal.first).last==2
        end
        state=LocalMatchProposals.respond(document:document,intent:intent_id,actor:actor,accept:false,now:now!,expected:expected_proposal,require_expected:require_expected)
        @storage.write(document)
        {state:state,status:projection(document,record)}.freeze
      end
    end
    def renew_invitation(intent_id:, account:, invitation_id:)
      record, intent_id = target!(intent_id)
      participant!(record)
      own = snapshot(intent_id: intent_id)['active'].find { |row| row['players'].include?(actor) }
      raise C::Blocked, :invitation_required unless own && own['bound']
      raise C::Blocked, :not_coordinator unless own['coordinator'] == actor
      execution(record, own).dispatch_invitations(renew: {'account' => account, 'invitation_id' => invitation_id})
    rescue C::Blocked, ReadinessContract::Blocked => error
      {state: :blocked, reason: error.code}.freeze
    end
    def renew_expired(intent_id:)
      record, intent_id = target!(intent_id)
      participant!(record)
      own = snapshot(intent_id: intent_id)['active'].find { |row| row['players'].include?(actor) }
      raise C::Blocked, :not_coordinator unless own && own['bound'] && own['coordinator'] == actor
      pending = access(record) do |document|
        core = document['native']['cores'].find { |row| row['id'] == own['native_uuid'] }
        core['invitations'].find { |account, row| row['expires_at'] <= now! && !core['participants'].key?(account) }
      end
      return {state: :waiting, reason: :no_expired_invitation}.freeze unless pending
      renew_invitation(intent_id: intent_id, account: pending[0], invitation_id: pending[1]['id'])
    rescue C::Blocked, ReadinessContract::Blocked => error
      {state: :blocked, reason: error.code}.freeze
    end
    private
    def storage_class; LocalIndividualExecutionStorage; end
    def execution_class; LocalIndividualExecution; end
    def native_provider(match); IndividualNativeProvider.new(capacity: match['players'].size); end
    def actor; @expected.fetch('account'); end
    def guard!
      raise ReadinessContract::Blocked, :context_changed unless @context.call.eql?(@expected) && @expected['cancelled'].equal?(false)
    end
    def now!
      value = @clock.call
      raise Publication::Invalid, :invalid_clock unless Data.integer?(value)
      value
    end
    # Accepted previews may alias an existing immutable plan. Only its original
    # intent owns dispatch policies, leases, proposals and execution records.
    # Keep this resolution at the operation boundary, not in the UI tick that
    # checks whether the already captured own lease needs renewal.
    def target!(id)
      guard!
      record = @backend.current(intent_id: id)
      raise Publication::Invalid, :missing_plan unless record
      [record, record.fetch('preview').fetch('intent_id')]
    end
    def participant!(record)
      raise C::Blocked, :not_participant unless record['evidence']['source']['roster'].any? { |person| person['account'] == actor }
    end
    def policy!(document, intent)
      LocalDispatchContract.policy(document, intent) || raise(C::Blocked, :dispatch_not_configured)
    end
    def access(record)
      @storage.access(validate: ->(document) { LocalFixedTeamReadinessPort.validate_document!(document, identity: @storage.identity) }) do |document|
        document ||= @storage.empty
        @storage.remember_record(document, record)
        guard!
        @storage.write(document) if LocalMatchProposals.prune(document,record['preview']['intent_id'],now!)
        yield document
      end
    end
    def projection(document, record)
      intent, now = record['preview']['intent_id'], now!
      policy = policy!(document, intent)
      active = LocalDispatchContract.active(document, intent).map do |row|
        {'match_id' => row['request']['match_id'], 'leg' => row['request']['leg'], 'window_id' => row['request']['window']['id'],
          'players' => row['request']['players'].map { |person| person['account'] }, 'coordinator' => row['coordinator'],
          'bound' => !!row['target'], 'reserved' => row['operations'].key?('reserve'), 'started' => !!row['start'],
          'interrupted' => interrupted?(document, row, now),
          'native_uuid' => row.dig('target', 'binding', 'native_uuid')}
      end
      occupied = (document['busy'].keys + active.flat_map { |row| row['players'] }).uniq
      remaining = policy['max_tables'] - active.size
      candidates = []
      matches=record['evidence']['plan']['matches']
      if policy['consent_before_table']
        matches=matches.sort_by{|match|match['leg']==2 && previous_leg_complete?(document,record,match) ? 0 : 1}
      end
      matches.each do |match|
        break if candidates.size >= remaining
        existing = document['executions'].values.find { |row| row['record_intent'] == intent && row['request']['match_id'] == match['match_id'] && row['request']['leg'] == match['leg'] }
        next if existing && (existing['result'] || existing['operations'].key?('reserve'))
        window = match['windows'].find { |value| value['opens'] <= now && now < value['closes'] - 1 }
        next unless window
        people = match['players'].map { |person| person['account'] }
        next if people.any? { |person| occupied.include?(person) || LocalDispatchContract.ready(document, intent, person, now)['state'] != 'ready' }
        if match['leg'] > 1
          next unless previous_leg_complete?(document, record, match)
        end
        candidates << {'match_id' => match['match_id'], 'leg' => match['leg'], 'window_id' => window['id'], 'players' => people,
          'coordinator' => existing ? existing['coordinator'] : coordinator_for(record, match), 'bound' => false, 'reserved' => false, 'started' => false}
        occupied.concat(people)
      end
      proposal=(document.dig('dispatch','proposals',intent) || {}).find{|_id,row|row['players'].include?(actor)}
      proposal=proposal && {'token'=>LocalMatchProposals.token(intent,*proposal),'players'=>proposal.last['players'],
        'leg'=>JSON.parse(proposal.first).last,'accepted'=>proposal.last['accepted']}
      Data.freeze_tree(Data.copy({'intent_id'=>intent,'max_tables' => policy['max_tables'], 'active' => active, 'candidates' => candidates,
        'own_ready'=>LocalDispatchContract.ready(document,intent,actor,now)['state']=='ready','proposal'=>proposal}, max_bytes: 262_144, max_nodes: 16_384, max_depth: 12))
    end
    def coordinator_for(record, match)
      people = match['players'].sort_by { |person| person['seat'] }
      seat = @registry.build(match['game_id']).tournament_table_creator_seat(
        options: record['evidence']['source']['options'], player_count: people.size)
      return people.map { |person| person['account'] }.min if seat.nil?
      raise Publication::Invalid, :invalid_composition unless seat.is_a?(Integer) && seat.between?(0, people.size - 1)
      people.fetch(seat)['account']
    end

    # A finished replay may still be exported after the match window closes.
    # An unfinished match retains its reservation without further dispatch.
    def interrupted?(document, row, now)
      if row['start']
        return true if row['epoch'] != row['start']['epoch']
        return false if now < row['request']['window']['closes']
        core = document['native']['cores'].find { |value| value['id'] == row['start']['native_uuid'] }
        LocalFixedTeamMoves.with_core(core, row, owner: core['owner']) do |_tx, _transport, _table, repository, session|
          snapshot = repository.snapshot_for(session, force_events: true)
          return !@registry.build(row['request']['game_id']).replay(snapshot.session, snapshot.events, repository).finished?
        end
      elsif row['target']
        grant = row['grant']
        !grant || grant['fencing'] != row['epoch'] || now >= grant['expires_at']
      else
        false
      end
    end

    # Explain this snapshot only; waiting never changes readiness or awards a result.
    def waiting_reason(document, record, view)
      intent, now = record['preview']['intent_id'], now!
      pending = record['evidence']['plan']['matches'].select do |match|
        match['players'].any? { |person| person['account'] == actor } &&
          !document['executions'].values.any? { |row| row['record_intent'] == intent &&
            row['request']['match_id'] == match['match_id'] && row['request']['leg'] == match['leg'] && row['result'] }
      end
      return :matches_completed if pending.empty?
      open = pending.select { |match| match['windows'].any? { |window| window['opens'] <= now && now < window['closes'] - 1 } }
      if open.empty?
        return pending.any? { |match| match['windows'].any? { |window| window['opens'] > now } } ? :match_window_not_open : :match_window_closed
      end
      ready = open.select { |match| match['players'].all? { |person| LocalDispatchContract.ready(document, intent, person['account'], now)['state'] == 'ready' } }
      return :participants_unavailable if ready.empty?
      return :table_limit if view['active'].size >= view['max_tables']
      occupied = document['busy'].keys + (view['active'] + view['candidates']).flat_map { |row| row['players'] }
      free = ready.reject { |match| match['players'].any? { |person| occupied.include?(person['account']) } }
      return :participants_busy if free.empty?
      return :previous_match_pending unless free.any? { |match| match['leg'] == 1 || previous_leg_complete?(document, record, match) }
      nil
    end
    def previous_leg_complete?(document, record, match)
      people = match['players'].map { |person| person['account'] }.sort
      previous = record['evidence']['plan']['matches'].find do |value|
        value['leg'] == match['leg'] - 1 && value['players'].map { |person| person['account'] }.sort == people
      end
      previous && document['executions'].values.any? { |row| row['record_intent'] == record['preview']['intent_id'] &&
        row['request']['match_id'] == previous['match_id'] && row['request']['leg'] == previous['leg'] && row['result'] }
    end
    def execution(record, row)
      match = record['evidence']['plan']['matches'].find { |value| value['match_id'] == row['match_id'] && value['leg'] == row['leg'] }
      window = match['windows'].find { |value| value['id'] == row['window_id'] }
      execution = execution_class.new(**@options.merge(expires_at: window['closes'] - 1))
      execution.native_provider = native_provider(match)
      execution.select(intent_id: record['preview']['intent_id'], match_id: row['match_id'], leg: row['leg'], window_id: row['window_id'])
      execution
    end
  end
end
