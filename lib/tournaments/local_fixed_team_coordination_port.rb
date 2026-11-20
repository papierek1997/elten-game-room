# encoding: UTF-8
require_relative 'coordination_service'
require_relative 'local_fixed_team_execution_context'
require_relative 'fixed_team_native_target_adapter'
require_relative 'fixed_team_bound_target'

module GameRoomTournaments
  # Port tej samej lokalnej kompozycji, nigdy domyślny adapter SDK.
  class LocalFixedTeamCoordinationPort
    C = CoordinationContract
    attr_reader :identity, :events, :epoch

    Data = Publication::Data
    def initialize(readiness:, authority:, request:, clock:, native_provider:, storage:, record_reader:, registry:, policy_ref:, expires_at:)
      @readiness, @authority, @request, @clock = readiness, authority, request.to_h, clock
      @identity, @storage, @record_reader, @registry = readiness.identity, storage, record_reader, registry
      @policy_ref, @expires_at = policy_ref, expires_at
      @adapter = @storage.native_adapter_class.new(provider: native_provider, registry: registry)
      @key = C.digest(@request.values_at('scope', 'match_id', 'leg', 'execution_generation'))
      @events = LocalReadinessSession::Events.new
      @record = record_reader.call(false)
      @epoch = nil
    end

    def preflight!
      @readiness.transaction do |document|
        existing = document['executions'][@key]
        state = existing && existing['operations'].key?('create_bind') ? nil : document['native']
        @adapter.preflight!(native: native_payload, request: @request, actor: actor, state: state)
      end
      self
    end

    # Ograniczony lokalny producent ma stałe długości UUID i stałe opisy.
    # Projekcja służy wyłącznie pomiarowi, nigdy lookup ani zapisowi receipt.
    def preflight_operation(operation:, max_bytes:)
      op = Data.freeze_tree(C.copy(operation))
      C.operation!(op, registry: @registry)
      raise C::Blocked, :operation_conflict unless op['request'].eql?(@request)
      @readiness.transaction do |document|
        execution = execution!(document)
        receipt = execution['operations'][op['kind']]
        if receipt
          raise C::Blocked, :operation_conflict unless receipt['operation'].eql?(op)
        else
          receipt = budget_response(op, execution)
          budget_transition(document, op, receipt)
        end
        Data.copy(receipt, max_bytes: [max_bytes, 262_144].min, max_nodes: 16_384, max_depth: 16)
        C.binding!(receipt, registry: @registry) if op['kind'] == 'create_bind'
      end
      true
    rescue Publication::Invalid => error
      raise C::Blocked, :payload_too_large if error.code == :json_budget
      raise
    end

    def open(create: true)
      @readiness.transaction do |document|
        execution = document['executions'][@key]
        LocalDispatchContract.reserve!(document, @record['preview']['intent_id'], @request, @clock.call) if create && !(execution && execution['grant'])
        unless execution
          raise C::Blocked, :missing_execution unless create
          @record_reader.call(true)
          raise C::Blocked, :operation_limit if document['executions'].size >= 512
          next_epoch = document['executions'].values.map { |row| row.fetch('epoch') }.max.to_i + 1
          execution = {'request' => @request, 'record_intent' => @record['preview']['intent_id'], 'epoch' => next_epoch,
            'coordinator' => actor, 'policy_ref' => @policy_ref, 'expires_at' => @expires_at,
            'grant' => nil, 'operations' => {}, 'target' => nil}
          document['executions'][@key] = execution
          @storage.remember_record(document, @record)
          @storage.write(document)
        end
        raise C::Blocked, :operation_conflict unless execution['request'].eql?(@request)
        @epoch = execution['epoch']
      end
      @events.emit(@epoch.to_s)
      self
    end

    def revoke(expected_epoch:)
      raise C::Invalid, :invalid_epoch unless Data.integer?(expected_epoch, 1)
      next_epoch = @readiness.transaction do |document|
        execution = execution!(document)
        unless execution['epoch'] == expected_epoch && execution['coordinator'] == actor
          raise C::Blocked, :stale_coordinator
        end
        raise C::Blocked, :epoch_limit unless Data.integer?(expected_epoch + 1, 1)
        execution['epoch'] += 1
        execution['grant'] = nil
        @storage.write(document)
        execution['epoch']
      end
      @events.emit(next_epoch.to_s)
      next_epoch
    end

    def negotiate(scope:, required:)
      supported = @adapter.supported?
      {'status' => supported ? 'confirmed' : 'unsupported', 'identity' => identity, 'scope' => scope,
        'capabilities' => supported ? C::REQUIRED : {}, 'authorization' => 'authenticated_participant_or_delegate',
        'retention' => 'match_lineage', 'max_bytes' => 262_144}
    end

    def snapshot(request:)
      raise C::Blocked, :target_mismatch unless request.eql?(@request)
      @readiness.transaction { |document| view(document) }
    end

    def reserve(operation:)
      mutate(operation, 'reserve') do |document, execution, op, snapshot|
        LocalDispatchContract.reserve!(document, execution['record_intent'], @request, @clock.call)
        accounts = @request['players'].map { |person| person['account'] }
        raise C::Blocked, :participants_busy if accounts.any? { |account| document['busy'].key?(account) }
        raise C::Blocked, :grant_already_present unless execution['grant'].nil?
        grant = {'id' => SecureRandom.uuid, 'revision' => '1', 'fencing' => @epoch,
          'ready_versions' => op['preconditions']['ready_versions'], 'window' => @request['window'],
          'holder_account' => actor, 'coordinator_epoch' => @epoch.to_s, 'expires_at' => execution['expires_at']}
        C.grant!(grant, @request, op['preconditions']['ready_versions'])
        receipt = response(op, grant, snapshot)
        execution['grant'] = grant
        accounts.each { |account| document['busy'][account] = @key }
        execution['operations']['reserve'] = receipt
        @storage.write(document, receipt: receipt)
        receipt
      end
    end

    def create_bind(operation:)
      mutate(operation, 'create_bind') do |document, execution, op, snapshot|
        grant = execution['grant']
        unless grant && grant.eql?(op['preconditions']['grant']) && grant['holder_account'] == actor &&
            grant['fencing'] == @epoch && @clock.call < grant['expires_at'] &&
            @request['players'].all? { |person| document['busy'][person['account']] == @key }
          raise C::Blocked, :stale_grant
        end
        native = native_payload
        @adapter.preflight!(native: native, request: @request, actor: actor)
        readback, core = @adapter.create(state: document['native'], native: native, request: @request, actor: actor)
        table = readback.fetch('table')
        result = {'native_uuid' => table['__live_session_id'], 'table_id' => table['__id'], 'binding_id' => SecureRandom.uuid,
          'binding_revision' => '1', 'creator_account' => actor, 'game_instance' => nil}
        receipt = response(op, result, snapshot)
        target = @storage.bound_target_class.build(record: @record, response: receipt, readback: readback, registry: @registry)
        execution['operations']['create_bind'] = receipt
        execution['target'] = target.to_h
        document['native'] = core
        @storage.write(document, receipt: receipt)
        @confirmed_effect = op
        @adapter.committed(receipt: receipt)
        receipt
      end
    end

    def effect_confirmed?(operation)
      @confirmed_effect && @confirmed_effect.eql?(operation)
    end

    def lookup(scope:, kind:, operation_id:)
      raise C::Blocked, :target_mismatch unless scope.eql?(@request['scope'])
      @readiness.transaction do |document|
        execution = execution!(document)
        own!
        receipt = execution['operations'][kind]
        raise C::PortUnavailable, 'Brak autorytatywnego rozstrzygnięcia tej operacji' unless receipt && receipt['operation_id'] == operation_id
        C.response!(receipt, receipt['operation'])
      end
    end

    def lookup_target(operation_id:, proof_ref:)
      @readiness.transaction do |document|
        execution = execution!(document)
        own!
        active_binding!(execution)
        receipt = execution['operations']['create_bind']
        unless receipt && receipt['operation_id'] == operation_id && receipt['receipt'] == proof_ref
          raise C::Blocked, :target_mismatch
        end
        owner = @request['players'].find { |person| person['account'] == receipt['operation']['actor'] }.fetch('username')
        result = receipt['result']
        # Creation receipt remains immutable after participant admission. The
        # storage validates current membership separately against own receipts.
        state = @storage.copy(document['native'])
        core = state['cores'].find { |row| row['id'] == result['native_uuid'] }
        original = execution['target']['readback']
        core['participants'] = @storage.copy(original['participants'])
        core['discovery_metadata'] = @storage.copy(original['discovery'])
        core['entries'] = @storage.copy(original['stack'])
        core['last_seq'], core['trimmed_through'] = core['entries'].last.fetch('seq'), 0
        core['closed'] = false
        core['dedup'] = core['entries'].map { |row| {'key' => [core['owner'], row['message_id']], 'sequence' => row['seq']} }
        readback = @adapter.lookup(state: state, native_uuid: result['native_uuid'], table_id: result['table_id'], owner: owner)
        target = @storage.bound_target_class.build(record: @record, response: receipt, readback: readback, registry: @registry)
        raise C::Blocked, :native_target_mismatch unless target.to_h.eql?(execution['target'])
        target
      end
    end

    # Ostatnia granica publikacji wyniku; lokalne events nie widzą procesu B.
    # Osobna transakcja po lookup_target, nigdy I/O wewnątrz lokalnego guardu.
    def validate_epoch!
      @readiness.transaction do |document|
        active_binding!(execution!(document))
        own!
      end
      nil
    end

    private

    def active_binding!(execution)
      grant = execution['grant']
      created_epoch = execution.dig('operations', 'create_bind', 'operation', 'preconditions', 'grant', 'fencing')
      unless grant && grant['fencing'] == execution['epoch'] && created_epoch == execution['epoch'] && !execution['result']
        raise C::Blocked, :stale_grant
      end
    end

    def actor
      @authority.call.fetch('account')
    end

    def own!
      raise C::Blocked, :not_participant unless @request['players'].any? { |person| person['account'] == actor }
    end

    def execution!(document)
      execution = document['executions'][@key]
      raise C::Blocked, :missing_execution unless execution && execution['request'].eql?(@request)
      raise C::Blocked, :stale_coordinator unless execution['epoch'] == @epoch
      execution
    end

    def native_payload
      @storage.native_payload_class.from_execution_plan(evidence: @record['evidence'], expected_source: @record['expected_source'],
        match_id: @request['match_id'], leg: @request['leg'], window_id: @request['window']['id'], registry: @registry)
    end

    def view(document)
      execution = execution!(document)
      own!
      ready = @readiness.coordination_view(document)
      revision = C.digest([ready, execution['epoch'], execution['grant']])
      {'status' => 'confirmed', 'read_id' => revision, 'scope' => @request['scope'], 'request' => @request,
        'seal_status' => 'confirmed', 'resource_revision' => revision,
        'server_time' => {'seconds' => @clock.call, 'source' => 'local_test:ft2a'}, 'ready' => ready,
        'authorized_account' => actor, 'delegation' => nil, 'competing_operation' => nil, 'grant' => execution['grant'],
        'shared' => execution['operations'].transform_values { |receipt| receipt['operation'] }}
    end

    def mutate(operation, kind)
      op = Data.freeze_tree(C.copy(operation))
      C.operation!(op, registry: @registry)
      unless op['kind'] == kind && op['request'].eql?(@request) && op['actor'] == actor
        raise C::Blocked, :operation_conflict
      end
      @record_reader.call(true)
      @readiness.transaction do |document|
        execution = execution!(document)
        prior = execution['operations'][kind]
        if prior
          raise C::Blocked, :operation_conflict unless prior['operation'].eql?(op)
          next prior
        end
        unless execution['epoch'] == @epoch && execution['coordinator'] == actor
          raise C::Blocked, :stale_coordinator
        end
        snapshot = view(document)
        C.window!(snapshot, @request)
        unless @clock.call < execution['expires_at'] && execution['expires_at'] <= @request['window']['closes'] &&
            snapshot['ready'].values.all? { |value| value['state'] == 'ready' }
          raise C::Blocked, :not_all_ready
        end
        unless snapshot['resource_revision'] == op['preconditions']['expected_revision'] &&
            snapshot['ready'].transform_values { |value| value['revision'] }.eql?(op['preconditions']['ready_versions'])
          raise C::Blocked, :stale_preconditions
        end
        budget_transition(document, op, budget_response(op, execution))
        yield document, execution, op, snapshot
      end
    end

    def budget_transition(document, operation, receipt)
      projected = @storage.copy(document)
      execution = projected['executions'].fetch(@key)
      execution['operations'][operation['kind']] = receipt
      if operation['kind'] == 'reserve'
        execution['grant'] = receipt['result']
        @request['players'].each { |p| projected['busy'][p['account']] = @key }
      else
        native = native_payload
        @adapter.preflight!(native: native, request: @request, actor: operation['actor'], state: document['native'])
        owner = @request['players'].find { |p| p['account'] == operation['actor'] }.fetch('username')
        readback = @adapter.budget_readback(native: native, request: @request, owner: owner)
        execution['target'] = @storage.bound_target_class.build(record: @record, response: receipt, readback: readback, registry: @registry).to_h
        @adapter.budget_native(readback).each { |key, rows| projected['native'][key].concat(rows) }
      end
      # Semantyka rzeczywistego stanu i operacji została sprawdzona osobno.
      # Hipotetyczny UUID nie jest autorytetem: badamy tylko cały serializowany agregat.
      @storage.budget(projected)
      nil
    end

    def budget_response(operation, execution)
      uuid = 'ffffffff-ffff-4fff-bfff-ffffffffffff'
      value = if operation['kind'] == 'reserve'
        {'id' => uuid, 'revision' => '1', 'fencing' => execution['epoch'],
          'ready_versions' => operation['preconditions']['ready_versions'], 'window' => @request['window'],
          'holder_account' => operation['actor'], 'coordinator_epoch' => execution['epoch'].to_s, 'expires_at' => execution['expires_at']}
      else
        {'native_uuid' => uuid, 'table_id' => Publication::MAX_INTEGER, 'binding_id' => uuid,
          'binding_revision' => '1', 'creator_account' => operation['actor'], 'game_instance' => nil}
      end
      {'status' => 'confirmed', 'scope' => @request['scope'], 'kind' => operation['kind'],
        'operation_id' => operation['operation_id'], 'request_digest' => operation['request_digest'], 'operation' => operation,
        'resource_revision' => 'f' * 64, 'server_time' => {'seconds' => Publication::MAX_INTEGER, 'source' => 'local_test:ft2a'},
        'reason' => 'confirmed', 'receipt' => uuid, 'result' => value}
    end

    def response(operation, result, snapshot)
      C.response!({'status' => 'confirmed', 'scope' => @request['scope'], 'kind' => operation['kind'],
        'operation_id' => operation['operation_id'], 'request_digest' => operation['request_digest'], 'operation' => operation,
        'resource_revision' => snapshot['resource_revision'], 'server_time' => snapshot['server_time'],
        'reason' => 'confirmed', 'receipt' => SecureRandom.uuid, 'result' => result}, operation)
    end
  end
end
