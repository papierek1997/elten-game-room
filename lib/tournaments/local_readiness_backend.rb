# encoding: UTF-8
require_relative 'local_readiness_storage'
require_relative 'readiness_request'
require_relative 'schedule_candidate'

module GameRoomTournaments
  # Odrębny autorytet lokalnej próby, nigdy seal/ACL serwera ani fallback.
  class LocalReadinessBackend
    C = ReadinessContract
    POLICY = 'local-test-own-readiness-v1'.freeze
    APP = 'local-test-tournament-readiness-k03'.freeze
    MAX_PLANS = 16
    MAX_OPERATIONS = 2048
    attr_reader :identity

    def initialize(directory:, actor:, clock: -> { Time.now.to_i }, source: nil, guard: -> {})
      @actor = Publication::Data.account(actor).downcase.freeze
      @clock, @source, @guard = clock, source, guard
      @storage = LocalReadinessStorage.new(directory: directory, guard: guard)
      @identity = ('local-test-k03:' + @storage.path).freeze
    end

    def local_test?
      true
    end

    def plans
      access { |document| detached(document['plans']) }
    end

    # Wywołanie jest WYŁĄCZNIE świadomym zatwierdzeniem pokazanej pełnej próby.
    def accept(candidate:)
      data = candidate_data(candidate)
      require_source(data)
      digest = candidate_digest(data)
      access do |document|
        prior = document['plans'].find { |plan| plan['source_digest'] == digest }
        next detached(prior) if prior
        raise C::Blocked, :sandbox_limit if document['plans'].size >= MAX_PLANS
        anchor = {'plan_id' => 'local-test:' + SecureRandom.uuid, 'source_digest' => digest, 'candidate' => data}
        document['plans'] << anchor
        persist(document)
        detached(anchor)
      end
    end

    def verify_source(candidate:, plan_id:)
      data = candidate_data(candidate)
      access do |document|
        anchor = plan!(document, plan_id)
        raise C::Blocked, :source_changed unless candidate_digest(data) == anchor['source_digest']
        true
      end
    end

    def target(plan_id:, match_id:)
      access { |document| target_for(plan!(document, plan_id), match_id) }
    end

    def negotiate(scope:, required:)
      access do |document|
        raise C::Blocked, :unknown_scope unless document['plans'].any? { |plan| scope_for(plan).eql?(scope) }
        C.frozen_copy({'status' => 'confirmed', 'identity' => identity, 'scope' => scope,
          'capabilities' => C::WRITE, 'authorization' => 'own_account', 'retention' => 'match_lineage', 'max_bytes' => 65_536})
      end
    end

    # Trwała generacja gate wynika z przyjętych rewizji wszystkich uczestników
    # tego meczu. D2B1 nigdy nie otwiera gate i nie emituje grantów.
    def gate_state(scope:, match_ref:)
      access do |document|
        anchor, match = match!(document, scope, match_ref)
        own!(match)
        revision = document['receipts'].count do |item|
          item['status'] == 'confirmed' && item['operation']['request']['match_ref'].eql?(match_ref)
        end
        C.frozen_copy({'open' => false, 'revision' => revision, 'grants' => []})
      end
    end

    def snapshot(scope:, match_ref:)
      access do |document|
        anchor, match = match!(document, scope, match_ref)
        own!(match)
        C.snapshot!(snapshot_for(document, anchor, match), scope, match_ref, @actor, identity)
      end
    end

    def store(operation:)
      operation = C.operation!(operation)
      @guard.call
      # Źródło odczytujemy świeżo, a kotwicę porównujemy ponownie pod flock.
      anchor = plans.find { |plan| plan['plan_id'] == operation['request']['match_ref']['plan_id'] }
      raise C::Blocked, :unknown_plan unless anchor
      require_source(anchor['candidate'])
      access do |document|
        plan, match = authorize!(document, operation)
        previous = document['receipts'].find { |item| item['operation']['operation_id'] == operation['operation_id'] }
        if previous
          raise C::Blocked, :operation_conflict unless previous['operation'].eql?(operation)
          next C.response!(previous, operation)
        end
        raise C::Blocked, :sandbox_limit if document['receipts'].size >= MAX_OPERATIONS
        current = current_for(document, plan, match)
        request = operation['request']
        status = request['expected_ready_revision'].eql?(current['ready_revision']) ? 'confirmed' : 'conflict'
        result = nil
        if status == 'confirmed'
          raise C::Blocked, :sandbox_limit if current['ready_revision'] >= Publication::MAX_INTEGER
          time = @clock.call
          raise C::Invalid, :invalid_clock unless C::Data.integer?(time)
          # Nie istnieje producent grantów ani startu. Gate pozostaje zamknięty.
          result = {'account' => @actor, 'ready_revision' => current['ready_revision'] + 1,
            'state' => request['availability'], 'server_time' => [time, current['server_time']].max,
            'invalidated_grants' => []}
        end
        receipt = {'status' => status, 'operation' => operation, 'request_digest' => operation['request_digest'],
          'reason' => status, 'result' => result}
        receipt = C.response!(receipt, operation)
        # Cały receipt musi zmieścić się przed jakąkolwiek zmianą trwałą.
        document['receipts'] << receipt
        persist(document)
        receipt
      end
    end

    def lookup(operation:)
      operation = C.operation!(operation)
      access do |document|
        authorize!(document, operation)
        value = document['receipts'].find { |item| item['operation']['operation_id'] == operation['operation_id'] }
        raise C::Blocked, :operation_conflict if value && !value['operation'].eql?(operation)
        value ||= {'status' => 'unknown', 'operation' => operation, 'request_digest' => operation['request_digest'],
          'reason' => 'not_observed', 'result' => nil}
        C.response!(value, operation)
      end
    end

    private

    def access
      @guard.call
      @storage.access(validate: method(:validate!)) do |document|
        document ||= {'version' => 1, 'identity' => identity, 'plans' => [], 'receipts' => []}
        yield document
      end
    end

    def persist(document)
      validate!(document)
      @storage.write(document)
    end

    def detached(value)
      C::Data.freeze_tree(C::Data.copy(value, max_bytes: LocalReadinessStorage::MAX_BYTES,
        max_nodes: ScheduleCandidate::MAX_RESULT_NODES * MAX_PLANS, max_depth: 24))
    end

    def candidate_data(candidate)
      unless candidate.instance_of?(ScheduleCandidate) && candidate.frozen?
        raise C::Blocked, :unconfirmed_candidate
      end
      data = detached(candidate.to_h)
      validate_candidate!(data)
      data
    end

    def validate_candidate!(data)
      raise C::Invalid, :invalid_fields unless data.is_a?(Hash)
      fields = %w[schedule_id roster_generation backend_identity publication_ref publication_digest format pairing rematch
        players_per_match roles_teams timezone registration_opens_at registration_closes_at state finality dispatch_allowed
        finalize_allowed start_allowed observed_at roster matches game_id game_options windows]
      fields += ['groups'] if data['format'] == 'groups_knockout'
      fields += ['group_advancement'] if data.key?('group_advancement')
      fields += Publication::ROUND_SETTINGS if data.key?('knockout_rematch')
      fields += Publication::WIN_SETTINGS.select { |key| data.key?(key) }
      fields += %w[starts_at daily_hours].select { |key| data.key?(key) }
      fields += ['knockout'] if data['format'] == 'knockout'
      C.fields!(data, fields)
      C::Data.copy(data, max_bytes: ScheduleCandidate::MAX_RESULT_BYTES,
        max_nodes: ScheduleCandidate::MAX_RESULT_NODES, max_depth: 8)
      %w[schedule_id roster_generation publication_digest].each do |key|
        raise C::Blocked, :sandbox_corrupt unless data[key].is_a?(String) && data[key].match?(/\A[0-9a-f]{64}\z/)
      end
      C.fields!(data['publication_ref'], %w[author publication_key])
      C.text!(data['publication_ref']['author'])
      C.text!(data['publication_ref']['publication_key'])
      C.text!(data['game_id'])
      C.text!(data['timezone'])
      unless %w[round_robin groups_knockout knockout].include?(data['format']) && %w[all_combinations balanced_cycle].include?(data['pairing']) &&
          [true, false].include?(data['rematch']) && C::Data.integer?(data['players_per_match'],2) && data['players_per_match'] <= 8 &&
          data['game_options'].is_a?(Hash) && data['windows'].is_a?(Array) &&
          %w[registration_opens_at registration_closes_at observed_at].all? { |key| C::Data.integer?(data[key]) } &&
          data['observed_at'] >= data['registration_closes_at'] && data['registration_closes_at'] > data['registration_opens_at']
        raise C::Blocked, :sandbox_corrupt
      end
      unless data.is_a?(Hash) && data['backend_identity'].is_a?(String) && data['backend_identity'].start_with?('local_test:') &&
          data['state'] == 'observed_candidate' && data['finality'] == 'unknown' && data['roles_teams'] == 'unassigned' &&
          data['dispatch_allowed'].equal?(false) && data['finalize_allowed'].equal?(false) && data['start_allowed'].equal?(false) &&
          data['roster'].is_a?(Array) && data['roster'].size.between?(2,256) && data['roster'].uniq == data['roster'] &&
          data['matches'].is_a?(Array) && data['matches'].size.between?(1,5000)
        raise C::Blocked, :sandbox_corrupt
      end
      DraftDetails.validate!({'windows' => data['windows']})
      validate_candidate_timing!(data)
      data['roster'].each { |actor| C.text!(actor); raise C::Blocked, :sandbox_corrupt unless actor == actor.downcase }
      ids = []
      data['matches'].each do |match|
        C.fields!(match, %w[number players leg match_id])
        unless C::Data.integer?(match['number'],1) && C::Data.integer?(match['leg'],1) &&
            match['leg'] <= (data['rematch'] ? 2 : 1) &&
            match['players'].is_a?(Array) && match['players'].size == data['players_per_match'] &&
            match['players'].uniq == match['players'] && (match['players'] - data['roster']).empty? &&
            match['match_id'].is_a?(String) && match['match_id'].match?(/\A[0-9a-f]{64}\z/) && !ids.include?(match['match_id'])
          raise C::Blocked, :sandbox_corrupt
        end
        ids << match['match_id']
      end
      if data['format'] == 'groups_knockout'
        GroupSchedule.validate!(data, units: data['roster'], unit_key: 'players', players_per_match: data['players_per_match'])
      elsif data['format'] == 'knockout'
        metadata = data['knockout']
        unless metadata.is_a?(Hash) && metadata['origin'] == 'direct_final' &&
            ['automatic_cross_groups_v1', 'automatic_compact_groups_v2'].include?(data['group_advancement']) &&
            metadata['publication_digest'] == data['publication_digest'] && data['rematch'] == (metadata['rematch'] == true)
          raise C::Blocked, :sandbox_corrupt
        end
        schedule, fixtures = KnockoutSchedule.matches(metadata: metadata, generation: data['roster_generation'])
        raise C::Blocked, :sandbox_corrupt unless schedule == data['schedule_id'] && fixtures.eql?(data['matches']) && metadata['seeds'].sort == data['roster'].sort
      end
    end

    def validate_candidate_timing!(data)
      # Keep the complete current candidate, including optional schedule and
      # series settings. These are source identity, not permission to start:
      # this diagnostic port still leaves its gate closed and roles unassigned.
      if data.key?('starts_at')
        start = data['starts_at']
        unless C::Data.integer?(start) && (start.zero? || start >= data['registration_closes_at'])
          raise C::Blocked, :sandbox_corrupt
        end
      end
      if data.key?('daily_hours')
        raise C::Blocked, :sandbox_corrupt unless data.key?('starts_at') && data['windows'].empty?
        TournamentTiming.validate_daily_hours!(data['daily_hours'])
      end
      Publication::WIN_SETTINGS.each do |key|
        next unless data.key?(key)
        unless %w[groups_knockout knockout].include?(data['format']) &&
            C::Data.integer?(data[key], 1) && data[key] <= 99 && data[key.sub('wins_to', 'rematch')] == false
          raise C::Blocked, :sandbox_corrupt
        end
      end
    end

    def candidate_digest(data)
      Digest::SHA256.hexdigest(JSON.generate(data.reject { |key, _value| key == 'observed_at' }))
    end

    def require_source(data)
      raise C::Blocked, :source_unavailable unless @source
      @guard.call
      candidate = @source.call(data.fetch('publication_ref'))
      @guard.call
      unless candidate_digest(candidate_data(candidate)) == candidate_digest(data)
        raise C::Blocked, :source_changed
      end
    end

    def plan!(document, id)
      document['plans'].find { |item| item['plan_id'].eql?(id) } || raise(C::Blocked, :unknown_plan)
    end

    def scope_for(anchor)
      {'app_uuid' => APP, 'backend_identity' => identity,
        'tournament_id' => C.digest(anchor['candidate']['publication_ref'])}
    end

    def target_for(anchor, id)
      match = anchor['candidate']['matches'].find { |item| item['match_id'].eql?(id) }
      raise C::Blocked, :unknown_match unless match
      {scope: C.frozen_copy(scope_for(anchor)), match_ref: C.frozen_copy({'plan_id' => anchor['plan_id'],
        'match_id' => id, 'leg' => match['leg'], 'roster_generation' => anchor['candidate']['roster_generation']})}.freeze
    end

    def match!(document, scope, reference)
      C.target!(scope, reference)
      anchor = plan!(document, reference['plan_id'])
      expected = target_for(anchor, reference['match_id'])
      unless expected[:scope].eql?(scope) && expected[:match_ref].eql?(reference)
        raise C::Blocked, :target_mismatch
      end
      [anchor, anchor['candidate']['matches'].find { |item| item['match_id'] == reference['match_id'] }]
    end

    def own!(match)
      raise C::Blocked, :not_participant unless match['players'].include?(@actor)
    end

    def accepted(anchor, match)
      {'status' => 'confirmed', 'plan_digest' => anchor['source_digest'], 'full_roster' => true,
        'members' => match['players'].map { |actor| {'account' => actor, 'kind' => 'human', 'role' => 'player'} },
        'roles_status' => 'confirmed'}
    end

    def authorize!(document, operation)
      request = operation['request']
      anchor, match = match!(document, request['scope'], request['match_ref'])
      own!(match)
      unless operation['account'].eql?(@actor) && operation['accepted_match'].eql?(accepted(anchor, match)) && request['policy_ref'] == POLICY
        raise C::Blocked, :authority_mismatch
      end
      [anchor, match]
    end

    def current_for(document, anchor, match, actor = @actor)
      receipts = document['receipts'].select do |item|
        op = item['operation']
        item['status'] == 'confirmed' && op['account'] == actor &&
          op['request']['match_ref']['plan_id'] == anchor['plan_id'] && op['request']['match_ref']['match_id'] == match['match_id']
      end
      last = receipts.last
      last ? last['result'].slice('state', 'ready_revision', 'server_time') : {'state' => 'unknown', 'ready_revision' => 0, 'server_time' => 0}
    end

    def snapshot_for(document, anchor, match)
      target = target_for(anchor, match['match_id'])
      {'status' => 'confirmed', 'identity' => identity, 'scope' => target[:scope], 'match_ref' => target[:match_ref], 'account' => @actor,
        'accepted_match' => accepted(anchor, match), 'policy' => {'status' => 'confirmed', 'ref' => POLICY, 'allows' => %w[ready withdrawn]},
        'current' => current_for(document, anchor, match), 'phase' => 'not_started'}
    end

    def validate!(document)
      C.fields!(document, %w[version identity plans receipts])
      unless document['version'].eql?(1) && document['identity'].eql?(identity) &&
          document['plans'].is_a?(Array) && document['plans'].size <= MAX_PLANS &&
          document['receipts'].is_a?(Array) && document['receipts'].size <= MAX_OPERATIONS
        raise C::Blocked, :sandbox_corrupt
      end
      ids = []
      document['plans'].each do |anchor|
        C.fields!(anchor, %w[plan_id source_digest candidate])
        unless anchor['plan_id'].is_a?(String) && anchor['plan_id'].match?(/\Alocal-test:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/) && !ids.include?(anchor['plan_id'])
          raise C::Blocked, :sandbox_corrupt
        end
        ids << anchor['plan_id']
        validate_candidate!(anchor['candidate'])
        raise C::Blocked, :sandbox_corrupt unless candidate_digest(anchor['candidate']).eql?(anchor['source_digest'])
      end
      seen = []
      revisions = Hash.new(0)
      document['receipts'].each do |receipt|
        C.fields!(receipt, %w[status operation request_digest reason result])
        operation = C.operation!(receipt['operation'])
        C.response!(receipt, operation)
        raise C::Blocked, :sandbox_corrupt unless %w[confirmed conflict].include?(receipt['status']) && !seen.include?(operation['operation_id'])
        seen << operation['operation_id']
        anchor, match = match!(document, operation['request']['scope'], operation['request']['match_ref'])
        unless operation['accepted_match'].eql?(accepted(anchor, match)) && operation['request']['policy_ref'] == POLICY && match['players'].include?(operation['account'])
          raise C::Blocked, :sandbox_corrupt
        end
        key = [anchor['plan_id'], match['match_id'], operation['account']]
        if receipt['status'] == 'confirmed'
          unless operation['request']['expected_ready_revision'] == revisions[key] && receipt['result']['ready_revision'] == revisions[key]+1 && receipt['result']['invalidated_grants'] == []
            raise C::Blocked, :sandbox_corrupt
          end
          revisions[key] += 1
        elsif operation['request']['expected_ready_revision'] == revisions[key]
          raise C::Blocked, :sandbox_corrupt
        end
      end
    rescue C::Invalid, DraftDetails::Invalid
      raise C::Blocked, :sandbox_corrupt
    end
  end
end
