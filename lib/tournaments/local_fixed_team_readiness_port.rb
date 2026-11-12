# encoding: UTF-8
require_relative 'readiness_service'
require_relative 'local_fixed_team_execution_storage'

module GameRoomTournaments
  # Gotowość dotyczy dokładnego zaakceptowanego FT1; konto pochodzi z Context.
  class LocalFixedTeamReadinessPort
    C = ReadinessContract
    attr_reader :identity, :scope, :match_ref

    def initialize(storage:, context:, record_reader:, request:, policy_ref:, clock:)
      @storage, @context, @record_reader, @request = storage, context, record_reader, request
      @identity = storage.identity
      @policy_ref, @clock = policy_ref, clock
      record = @record = record_reader.call(false)
      data = request.to_h
      @scope = C.frozen_copy(data['scope'].slice('app_uuid', 'backend_identity', 'tournament_id'))
      @match_ref = C.frozen_copy(data.slice('plan_id', 'match_id', 'leg').merge(
        'roster_generation' => record['expected_source']['roster_generation']))
      @accepted = C.frozen_copy({'status' => 'confirmed', 'plan_digest' => record['evidence']['plan_digest'],
        'full_roster' => true, 'roles_status' => 'confirmed', 'members' => data['players'].map do |person|
          {'account' => person['account'], 'kind' => 'human', 'role' => 'player'}
        end})
    end

    def negotiate(scope:, required:)
      target!(scope, @match_ref)
      if required.eql?(C::WRITE)
        @record_reader.call(true)
        access do |document|
          C.accepted_match!(@accepted, actor)
          raise C::Blocked, :already_started if started?(document)
          raise C::Blocked, :sandbox_limit if document['readiness'].size >= 2048
          preflight_declaration(document)
        end
      end
      C.frozen_copy({'status' => 'confirmed', 'identity' => identity, 'scope' => scope, 'capabilities' => C::WRITE,
        'authorization' => 'own_account', 'retention' => 'match_lineage', 'max_bytes' => 65_536})
    end

    def snapshot(scope:, match_ref:)
      target!(scope, match_ref)
      access do |document|
        own = actor
        C.accepted_match!(@accepted, own)
        {'status' => 'confirmed', 'identity' => identity, 'scope' => scope, 'match_ref' => match_ref, 'account' => own,
          'accepted_match' => @accepted, 'policy' => {'status' => 'confirmed', 'ref' => @policy_ref, 'allows' => %w[ready withdrawn]},
          'current' => current_for(document, own), 'phase' => started?(document) ? 'started' : 'not_started'}
      end
    end

    def store(operation:)
      operation = C.operation!(operation)
      authorize!(operation)
      @record_reader.call(true)
      access do |document|
        prior = document['readiness'].find { |row| row['operation']['operation_id'] == operation['operation_id'] }
        if prior
          raise C::Blocked, :operation_conflict unless prior['operation'].eql?(operation)
          next C.response!(prior, operation)
        end
        raise C::Blocked, :sandbox_limit if document['readiness'].size >= 2048
        current = current_for(document, actor)
        already_started = started?(document)
        status = !already_started && current['ready_revision'].eql?(operation['request']['expected_ready_revision']) ? 'confirmed' : 'conflict'
        result = nil
        if status == 'confirmed'
          now = @clock.call
          raise C::Invalid, :invalid_clock unless C::Data.integer?(now)
          raise C::Blocked, :sandbox_limit unless C::Data.integer?(current['ready_revision'] + 1)
          affected = document['executions'].values.select do |row|
            row['grant'] && row['request']['plan_id'] == match_ref['plan_id'] &&
              row['request']['match_id'] == match_ref['match_id'] && row['request']['leg'] == match_ref['leg']
          end
          invalidated = affected.map { |row| row['grant']['id'] }
          affected.each do |row|
            raise C::Blocked, :epoch_limit unless C::Data.integer?(row['epoch'] + 1, 1)
            row['epoch'] += 1
            row['grant'] = nil
          end
          result = {'account' => actor, 'ready_revision' => current['ready_revision'] + 1,
            'state' => operation['request']['availability'], 'server_time' => [now, current['server_time']].max, 'invalidated_grants' => invalidated}
        end
        receipt = C.response!({'status' => status, 'operation' => operation, 'request_digest' => operation['request_digest'],
          'reason' => already_started ? 'already_started' : status, 'result' => result}, operation)
        document['readiness'] << receipt
        @storage.remember_record(document, @record)
        @storage.write(document, receipt: receipt)
        receipt
      end
    end

    def lookup(operation:)
      operation = C.operation!(operation)
      authorize!(operation)
      access do |document|
        prior = document['readiness'].find { |row| row['operation']['operation_id'] == operation['operation_id'] }
        raise C::Blocked, :operation_conflict if prior && !prior['operation'].eql?(operation)
        C.response!(prior || {'status' => 'unknown', 'operation' => operation, 'request_digest' => operation['request_digest'],
          'reason' => 'not_observed', 'result' => nil}, operation)
      end
    end

    def coordination_view(document = nil)
      return access { |value| coordination_view(value) } unless document
      intent = @record['preview']['intent_id']
      if LocalDispatchContract.policy(document, intent)
        now = @clock.call
        return @accepted['members'].to_h do |person|
          current = current_for(document, person['account'])
          available = LocalDispatchContract.ready(document, intent, person['account'], now)['state'] == 'ready'
          [person['account'], {'state' => available && current['state'] == 'ready' ? 'ready' : 'withdrawn', 'revision' => current['ready_revision'].to_s}]
        end
      end
      @accepted['members'].to_h do |person|
        current = current_for(document, person['account'])
        [person['account'], {'state' => current['state'] == 'unknown' ? 'withdrawn' : current['state'],
          'revision' => current['ready_revision'].to_s}]
      end
    end

    def transaction(&block)
      access(&block)
    end

    private

    def started?(document)
      self.class.started_match?(document, scope: scope, match_ref: match_ref, plan_digest: @accepted['plan_digest'])
    end

    # Maksymalny lokalny wynik nowej deklaracji; nie jest utrwalanym receiptem.
    def preflight_declaration(document)
      projected = @storage.copy(document)
      own = actor
      current = current_for(projected, own)
      request = {'version' => 1, 'scope' => scope, 'match_ref' => match_ref, 'availability' => 'withdrawn',
        'expected_ready_revision' => current['ready_revision'], 'policy_ref' => @policy_ref}
      operation = C.operation(request, own, @accepted, SecureRandom.uuid)
      affected = projected['executions'].values.select do |row|
        row['grant'] && row['request']['plan_id'] == match_ref['plan_id'] &&
          row['request']['match_id'] == match_ref['match_id'] && row['request']['leg'] == match_ref['leg']
      end
      invalidated = affected.map { |row| row['grant']['id'] }
      affected.each do |row|
        raise C::Blocked, :epoch_limit unless C::Data.integer?(row['epoch'] + 1, 1)
        row['epoch'] += 1
        row['grant'] = nil
      end
      result = {'account' => own, 'ready_revision' => current['ready_revision'] + 1, 'state' => 'withdrawn',
        'server_time' => Publication::MAX_INTEGER, 'invalidated_grants' => invalidated}
      receipt = C.response!({'status' => 'confirmed', 'operation' => operation, 'request_digest' => operation['request_digest'],
        'reason' => 'confirmed', 'result' => result}, operation)
      projected['readiness'] << receipt
      @storage.remember_record(projected, @record)
      @storage.preflight(projected)
      nil
    end

    def actor
      @context.call.fetch('account')
    end

    def target!(scope, match_ref)
      raise C::Blocked, :target_mismatch unless scope.eql?(@scope) && match_ref.eql?(@match_ref)
    end

    def authorize!(operation)
      target!(operation['request']['scope'], operation['request']['match_ref'])
      C.accepted_match!(@accepted, actor)
      unless operation['account'] == actor && operation['accepted_match'].eql?(@accepted) && operation['request']['policy_ref'] == @policy_ref
        raise C::Blocked, :authority_mismatch
      end
    end

    def current_for(document, account)
      receipt = document['readiness'].reverse.find do |row|
        row['status'] == 'confirmed' && row['operation']['account'] == account &&
          row['operation']['request']['scope'].eql?(scope) && row['operation']['request']['match_ref'].eql?(match_ref)
      end
      receipt ? receipt['result'].slice('state', 'ready_revision', 'server_time') : {'state' => 'unknown', 'ready_revision' => 0, 'server_time' => 0}
    end

    def access
      @storage.access(validate: method(:validate!)) do |document|
        yield(document || @storage.empty)
      end
    end

    def validate!(document)
      self.class.validate_document!(document, identity: identity)
    end
    def self.validate_document!(document, identity:)
      C.fields!(document, LocalDispatchContract.root_fields(document))
      unless document['version'].eql?(1) && document['identity'] == identity && document['readiness'].is_a?(Array) && document['readiness'].size <= 2048
        raise C::Blocked, :sandbox_corrupt
      end
      ids = []
      revisions = Hash.new(0)
      document['readiness'].each do |receipt|
        operation = C.operation!(receipt['operation'])
        C.response!(receipt, operation)
        raise C::Blocked, :sandbox_corrupt if ids.include?(operation['operation_id']) || !%w[confirmed conflict].include?(receipt['status'])
        ids << operation['operation_id']
        request = operation['request']
        raise C::Blocked, :sandbox_corrupt unless request['scope']['backend_identity'] == identity
        key = [request['scope'], request['match_ref'], operation['account']]
        if receipt['status'] == 'confirmed'
          unless request['expected_ready_revision'] == revisions[key] && receipt['result']['ready_revision'] == revisions[key] + 1
            raise C::Blocked, :sandbox_corrupt
          end
          revisions[key] += 1
        elsif receipt['reason'] == 'already_started'
          unless started_match?(document, scope: request['scope'], match_ref: request['match_ref'],
              plan_digest: operation['accepted_match']['plan_digest'])
            raise C::Blocked, :sandbox_corrupt
          end
        elsif request['expected_ready_revision'] == revisions[key]
          raise C::Blocked, :sandbox_corrupt
        end
      end
    end

    # Storage has already authenticated complete Start/native lineage. Match
    # its exact scope/plan/fixture and parent proof, never another started table.
    def self.started_match?(document, scope:, match_ref:, plan_digest:)
      records, executions = document.values_at('records', 'executions')
      return false unless records.is_a?(Hash) && executions.is_a?(Hash)
      executions.values.any? do |execution|
        next false unless execution.is_a?(Hash) && execution['start'].is_a?(Hash)
        request = execution['request']
        record = records[execution['record_intent']]
        next false unless request.is_a?(Hash) && request['scope'].is_a?(Hash) && record.is_a?(Hash) &&
          record['evidence'].is_a?(Hash) && record['expected_source'].is_a?(Hash)
        request['scope'].slice('app_uuid', 'backend_identity', 'tournament_id').eql?(scope) &&
          request.values_at('plan_id', 'match_id', 'leg').eql?(match_ref.values_at('plan_id', 'match_id', 'leg')) &&
          record['evidence']['plan_digest'].eql?(plan_digest) &&
          record['expected_source']['roster_generation'].eql?(match_ref['roster_generation'])
      end
    end
  end
end
