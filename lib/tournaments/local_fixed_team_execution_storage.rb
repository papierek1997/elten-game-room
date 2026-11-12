# encoding: UTF-8
require_relative 'local_fixed_team_plan_backend'
require_relative 'readiness_contract'
require_relative 'fixed_team_bound_target'
require_relative 'local_fixed_team_admission'
require_relative 'local_fixed_team_start'
require_relative 'local_fixed_team_moves'
require_relative 'local_fixed_team_result'
require_relative 'local_organizer_result'
require_relative 'local_dispatch_contract'
require_relative 'local_dispatch_invitations'
require_relative 'local_dispatch_events'
require_relative 'local_game_events'
require_relative 'local_private_move_input'

module GameRoomTournaments
  # Własna przestrzeń wynika z rodzica FT1, nigdy z osobnego katalogu wykonania.
  class LocalFixedTeamExecutionStorage
    include LocalPrivateMoveInput
    Data = Publication::Data
    Invalid = Publication::Invalid
    C = CoordinationContract
    MAX_BYTES = 33_554_432
    MAX_NODES = 524_288
    MAX_RECORDS = 64
    MAX_READINESS = 2048
    MAX_EXECUTIONS = 512
    MAX_OPERATIONS = 1024
    MAX_ROOMS = 512
    NATIVE_CORE_FIELDS = %w[id owner capacity metadata discovery_metadata visibility participants entries last_seq trimmed_through
      closed invitations dedup stack_entries stack_entry_bytes].freeze
    attr_reader :identity, :directory, :path

    class Unconfirmed < IOError
      attr_reader :attempt_id, :receipt
      def initialize(attempt_id:, receipt:)
        @attempt_id, @receipt = attempt_id, receipt
        super('Niepewne zastąpienie FT2A; odczytaj tę samą operację')
      end
    end

    def initialize(plan_directory:, source_identity:, plan_backend:, guard:, registry:)
      @registry = registry
      Data.text!(plan_directory, bytes: 4096)
      value = plan_directory.tr('\\', '/')
      raise Invalid, :invalid_directory if value.start_with?('//') || value.match?(/\A[A-Za-z]:(?!\/)/)
      unless plan_backend.instance_of?(plan_backend_class) && plan_backend.local_test? &&
          plan_backend.identity == plan_backend_class.identity(directory: value, source_identity: source_identity)
        raise Invalid, :invalid_composition
      end
      @identity = plan_backend.identity.dup.freeze
      @plan_backend = plan_backend
      @directory = File.join(File.expand_path(value), *execution_namespace).freeze
      @path = File.join(@directory, 'state.json').freeze
      @guard, @mutex = guard, Mutex.new
    end

    def accepted_record(intent_id)
      @plan_backend.readback(intent_id: intent_id)
    end

    def plan_backend_class; LocalFixedTeamPlanBackend; end
    def execution_namespace; ['fixed-teams-v1', 'execution-ft2-v1']; end
    def bound_target_class; FixedTeamBoundTarget; end
    def native_payload_class; FixedTeamNativePayload; end
    def native_adapter_class; FixedTeamNativeTargetAdapter; end
    def moves_class; LocalFixedTeamMoves; end
    def result_class; LocalFixedTeamResult; end

    def empty
      {'version' => 1, 'identity' => identity, 'records' => {}, 'readiness' => [], 'executions' => {}, 'busy' => {},
        'native' => {'creates' => [], 'cores' => []}}
    end

    def remember_record(document, record)
      key = record['preview']['intent_id']
      prior = document['records'][key]
      raise Invalid, :sandbox_corrupt if prior && !prior.eql?(record)
      document['records'][key] = copy(record)
    end

    def copy(value)
      Data.copy(value, max_bytes: MAX_BYTES, max_nodes: MAX_NODES, max_depth: 24)
    end

    def access(validate:)
      @mutex.synchronize do
        lock = nil
        primary = nil
        begin
          @guard.call
          StrictJson.verify!
          check_paths
          FileUtils.mkdir_p(directory, mode: 0o700)
          check_paths
          lock = File.open(path + '.lock', File::RDWR | File::CREAT, 0o600)
          check_open(lock, path + '.lock')
          raise IOError, 'Nie uzyskano blokady FT2A' unless lock.flock(File::LOCK_EX)
          @guard.call
          check_paths
          document = read_document
          validate_busy!(document) if document
          validate.call(document) if document
          @inside = Thread.current
          @validator = validate
          yield document
        rescue Exception => error
          primary = error
          raise error, cause: error.cause
        ensure
          begin
            lock.close if lock && !lock.closed?
          ensure
            @inside = @validator = nil
            raise primary, cause: primary.cause if primary
          end
        end
      end
    end

    def budget(document)
      validate_counts!(document)
      copy(document)
    end

    def preflight(document)
      raise Invalid, :outside_access unless @inside.equal?(Thread.current)
      value = budget(document)
      validate_busy!(value)
      @validator.call(value)
      value
    end

    def write(document, receipt: nil)
      value = preflight(document)
      detached_receipt = receipt && Data.freeze_tree(copy(receipt))
      attempt_id = SecureRandom.uuid.freeze
      replace_attempted = false
      bytes = JSON.generate(value)
      temporary = path + '.tmp-' + SecureRandom.hex(12)
      file = nil
      primary = nil
      begin
        @guard.call
        file = File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600)
        check_open(file, temporary)
        file.binmode
        raise IOError, 'Niepełny zapis FT2A' unless file.write(bytes) == bytes.bytesize
        file.flush
        file.fsync
        file.close
        check_paths
        @guard.call
        replace_attempted = true
        File.rename(temporary, path)
      rescue Exception => error
        primary = error
        if replace_attempted && detached_receipt && (error.is_a?(IOError) || error.is_a?(SystemCallError))
          primary = Unconfirmed.new(attempt_id: attempt_id, receipt: detached_receipt)
          raise primary, cause: error
        end
        raise error, cause: error.cause
      ensure
        begin
          file.close if file && !file.closed?
          File.delete(temporary) if file && File.exist?(temporary)
        ensure
          raise primary, cause: primary.cause if primary
        end
      end
      LocalGameEvents.publish(identity)
      LocalDispatchEvents.publish(identity) if document.key?('dispatch') && !(receipt.is_a?(Hash) && receipt['kind'] == 'move')
      nil
    end

    private

    def validate_counts!(document)
      C.fields!(document, LocalDispatchContract.root_fields(document))
      unless document['records'].is_a?(Hash) && document['readiness'].is_a?(Array) && document['executions'].is_a?(Hash) && document['native'].is_a?(Hash)
        raise Invalid, :sandbox_corrupt
      end
      native = document['native']
      C.fields!(native, %w[creates cores])
      raise Invalid, :sandbox_corrupt unless native.values.all? { |v| v.is_a?(Array) }
      if document['records'].size > MAX_RECORDS || document['readiness'].size > MAX_READINESS ||
          document['executions'].size > MAX_EXECUTIONS || native.values.any? { |v| v.size > MAX_ROOMS }
        raise Invalid, :sandbox_limit
      end
      operations = document['executions'].values.sum do |e|
        raise Invalid, :sandbox_corrupt unless e.is_a?(Hash) && e['operations'].is_a?(Hash)
        e['operations'].size
      end
      raise Invalid, :sandbox_limit if operations > MAX_OPERATIONS
    end

    def validate_busy!(document)
      validate_counts!(document)
      validate_native_shapes!(document['native'])
      validate_records!(document)
      unless document.is_a?(Hash) && document['executions'].is_a?(Hash) && document['busy'].is_a?(Hash)
        raise Invalid, :sandbox_corrupt
      end
      expected = {}
      document['executions'].each do |key, execution|
        validate_execution!(document, key, execution)
        unless execution.is_a?(Hash) && execution['operations'].is_a?(Hash) && execution['request'].is_a?(Hash)
          raise Invalid, :sandbox_corrupt
        end
        next unless execution['operations'].key?('reserve')
        if execution['result']
          raise Invalid, :sandbox_corrupt if document['busy'].values.include?(key)
          next
        end
        players = execution['request']['players']
        raise Invalid, :sandbox_corrupt unless players.is_a?(Array) && players.size.between?(1, 256)
        players.each do |person|
          account = person.is_a?(Hash) && person['account']
          raise Invalid, :sandbox_corrupt unless account.is_a?(String) && !expected.key?(account)
          expected[account] = key
        end
      end
      raise Invalid, :sandbox_corrupt unless expected.eql?(document['busy'])
      validate_native!(document)
      validate_receipt_links!(document)
      LocalDispatchContract.validate!(document)
    end

    def validate_receipt_links!(document)
      operations = document['executions'].values.flat_map { |e| e['operations'].values }
      ids = operations.map { |r| r['operation_id'] } + document['readiness'].map { |r| r['operation']['operation_id'] }
      proofs = operations.map { |r| r['receipt'] }
      raise Invalid, :sandbox_corrupt unless ids.uniq.eql?(ids) && proofs.uniq.eql?(proofs)
      grants = document['executions'].values.select { |e| e['operations'].key?('reserve') }
      grant_ids = grants.map { |e| e['operations']['reserve']['result']['id'] }
      raise Invalid, :sandbox_corrupt unless grant_ids.uniq.eql?(grant_ids)
      document['readiness'].each do |receipt|
        next unless receipt['status'] == 'confirmed'
        operation = receipt['operation']
        receipt['result']['invalidated_grants'].each do |id|
          execution = grants.find { |e| e['operations']['reserve']['result']['id'] == id }
          grant = execution && execution['operations']['reserve']['result']
          unless execution && execution['grant'].nil? && readiness_for_execution?(operation, execution) &&
              grant['ready_versions'].key?(operation['account']) &&
              receipt['result']['ready_revision'].to_s != grant['ready_versions'][operation['account']]
            raise Invalid, :sandbox_corrupt
          end
        end
      end
      grants.each do |execution|
        next unless execution['grant']
        execution['grant']['ready_versions'].each do |account, revision|
          latest = document['readiness'].reverse.find do |r|
            r['status'] == 'confirmed' && r['operation']['account'] == account && readiness_for_execution?(r['operation'], execution)
          end
          unless latest && latest['result']['state'] == 'ready' && latest['result']['ready_revision'].to_s == revision
            raise Invalid, :sandbox_corrupt
          end
        end
      end
    end

    def readiness_for_execution?(operation, execution)
      request = operation['request']
      target = execution['request']
      request['scope'].eql?(target['scope'].slice('app_uuid', 'backend_identity', 'tournament_id')) &&
        request['match_ref'].values_at('plan_id', 'match_id', 'leg').eql?(target.values_at('plan_id', 'match_id', 'leg'))
    end

    def validate_execution!(document, key, execution)
      fields = %w[request record_intent epoch coordinator policy_ref expires_at grant operations target]
      fields += ['admission'] if execution.key?('admission')
      fields += ['start'] if execution.key?('start')
      fields += ['moves'] if execution.key?('moves')
      fields += ['result'] if execution.key?('result')
      C.fields!(execution, fields)
      raise Invalid, :sandbox_corrupt if execution.key?('result') && !execution['result'].is_a?(Hash)
      request = CoordinationRequest.build(execution['request'], registry: @registry)
      raw = request.to_h
      record = document['records'][execution['record_intent']]
      raise Invalid, :sandbox_corrupt unless record && Data.integer?(execution['epoch'], 1)
      selectors = {evidence: record['evidence'], expected_source: record['expected_source'], registry: @registry,
        match_id: raw['match_id'], leg: raw['leg'], window_id: raw['window']['id']}
      expected = CoordinationRequest.from_execution_plan(**selectors)
      unless raw.eql?(expected.to_h) && record['request_digests'].dig(raw['match_id'], raw['window']['id']) == request.digest &&
          C.digest(raw.values_at('scope', 'match_id', 'leg', 'execution_generation')) == key &&
          raw['players'].any? { |person| person['account'] == execution['coordinator'] }
        raise Invalid, :sandbox_corrupt
      end
      Data.text!(execution['policy_ref'], bytes: 256)
      unless Data.integer?(execution['expires_at']) && execution['expires_at'] > raw['window']['opens'] && execution['expires_at'] <= raw['window']['closes']
        raise Invalid, :sandbox_corrupt
      end
      operations = execution['operations']
      raise Invalid, :sandbox_corrupt unless operations.is_a?(Hash) && (operations.keys - %w[reserve create_bind]).empty?
      operations.each do |kind, receipt|
        raise Invalid, :sandbox_corrupt unless receipt.is_a?(Hash)
        op = C.operation!(receipt['operation'], registry: @registry)
        unless op['kind'] == kind && op['request'].eql?(raw) && op['actor'] == execution['coordinator'] && receipt['status'] == 'confirmed'
          raise Invalid, :sandbox_corrupt
        end
        C.response!(receipt, op)
        validate_ready_versions!(document, record, execution, op)
      end
      reserve = operations['reserve']
      create = operations['create_bind']
      if reserve
        grant = reserve['result']
        C.grant!(grant, raw, reserve['operation']['preconditions']['ready_versions'])
        unless grant['holder_account'] == execution['coordinator'] && grant['coordinator_epoch'] == grant['fencing'].to_s &&
            grant['expires_at'] == execution['expires_at'] && grant['fencing'] <= execution['epoch'] &&
            (execution['grant'].nil? ? execution['epoch'] > grant['fencing'] : execution['grant'].eql?(grant) && execution['epoch'] == grant['fencing'])
          raise Invalid, :sandbox_corrupt
        end
      elsif !execution['grant'].nil? || create
        raise Invalid, :sandbox_corrupt
      end
      if create
        unless create['operation']['preconditions']['grant'].eql?(reserve['result']) && execution['target'].is_a?(Hash)
          raise Invalid, :sandbox_corrupt
        end
        target = bound_target_class.build(record: record, response: create, readback: execution['target']['readback'], registry: @registry)
        raise Invalid, :sandbox_corrupt unless target.to_h.eql?(execution['target'])
      elsif !execution['target'].nil?
        raise Invalid, :sandbox_corrupt
      end
      core = execution['target'] && document['native']['cores'].find { |row| row['id'] == execution['target']['binding']['native_uuid'] }
      validate_native_identity!(core, target.to_h['readback']) if core
      LocalFixedTeamAdmission.validate!(execution, core)
      LocalFixedTeamStart.validate!(execution, core)
      if record['evidence']['version'].eql?(2) && GameResult::RESULT_POLICIES.include?(record['evidence']['source']['result_policy'])
        require_relative 'local_game_result'
        move_validator, result_validator = LocalGameMoves, LocalGameResult
      else
        move_validator, result_validator = moves_class, result_class
      end
      move_validator.validate!(execution, core, registry: @registry, private_reader: method(:private_move_input))
      if execution.dig('result', 'kind') == 'forfeit'
        LocalOrganizerResult.validate!(execution, core, record)
      else
        result_validator.validate!(execution, core, registry: @registry, result_policy: record['evidence']['source']['result_policy'])
      end
    rescue C::Blocked => error
      raise Invalid.new(:sandbox_corrupt), cause: error
    end

    def validate_ready_versions!(document, record, execution, operation)
      request = execution['request']
      operation['preconditions']['ready_versions'].each do |account, revision|
        receipt = document['readiness'].find do |row|
          op = row['operation']; ref = op['request']['match_ref']
          row['status'] == 'confirmed' && op['account'] == account && row['result']['ready_revision'].to_s == revision &&
            op['request']['scope'].eql?(request['scope'].slice('app_uuid', 'backend_identity', 'tournament_id')) &&
            ref.values_at('plan_id', 'match_id', 'leg').eql?(request.values_at('plan_id', 'match_id', 'leg'))
        end
        unless receipt && receipt['result']['state'] == 'ready' && receipt['operation']['request']['policy_ref'] == execution['policy_ref'] &&
            receipt['operation']['accepted_match']['plan_digest'] == record['evidence']['plan_digest']
          raise Invalid, :sandbox_corrupt
        end
      end
    end

    # Admission, Start and move replay inspect native data before the complete
    # relationship checks below. Reject malformed containers before their use.
    def validate_native_shapes!(native)
      native['cores'].each do |core|
        C.fields!(core, NATIVE_CORE_FIELDS)
        unless core['participants'].is_a?(Hash) && core['entries'].is_a?(Array) &&
            core['metadata'].is_a?(Hash) && core['discovery_metadata'].is_a?(Hash) &&
            Data.integer?(core['stack_entry_bytes'], 1)
          raise Invalid, :sandbox_corrupt
        end
      end
    end

    # Native replay assumes SDK metadata and visibility. Authenticate the
    # stored identity against the verified target before handing it to replay.
    def validate_native_identity!(core, readback)
      expected_discovery = readback['discovery'].merge('player_count' => core['participants'].size)
      unless core['metadata'].eql?(readback['metadata']) && core['discovery_metadata'].eql?(expected_discovery) &&
          core['visibility'].eql?(readback['visibility'])
        raise Invalid, :sandbox_corrupt
      end
    end

    def validate_native!(document)
      native = document['native']
      C.fields!(native, %w[creates cores])
      raise Invalid, :sandbox_corrupt unless native.values.all? { |value| value.is_a?(Array) }
      targets = document['executions'].values.filter_map { |execution| execution['target'] }
      ids = targets.map { |target| target['binding']['native_uuid'] }
      unless ids.uniq == ids && native['cores'].size == ids.size && native['creates'].size == ids.size
        raise Invalid, :sandbox_corrupt
      end
      seen = []
      native['cores'].each do |core|
        C.fields!(core, NATIVE_CORE_FIELDS)
        target = targets.find { |row| row['binding']['native_uuid'] == core['id'] }
        raise Invalid, :sandbox_corrupt unless target && !seen.include?(core['id'])
        seen << core['id']
        readback = target['readback']
        execution = document['executions'].values.find { |row| row['target'].equal?(target) }
        started = execution && execution['start']
        validate_native_identity!(core, readback)
        unless (started || core['entries'].eql?(readback['stack'])) &&
            core['owner'] == readback['table']['owner'] && core['capacity'].eql?(execution['request']['players'].size) &&
            core['closed'].equal?(!!execution['result']) &&
            (started || (core['last_seq'].eql?(1) && core['trimmed_through'].eql?(0) &&
              core['entries'].size == 1 && core['entries'].first.dig('packet', 'kind') == 'room_created'))
          raise Invalid, :sandbox_corrupt
        end
        LocalDispatchInvitations.validate!(execution, core)
        entry = core['entries'].first
        expected_dedup = [{'key' => [core['owner'], entry['message_id']], 'sequence' => entry['seq']}]
        raise Invalid, :sandbox_corrupt unless started || core['dedup'].eql?(expected_dedup)
        calls = native['creates'].select { |row| row.is_a?(Hash) && row['native_uuid'] == core['id'] }
        raise Invalid, :sandbox_corrupt unless calls.size == 1
        call = calls.first
        C.fields!(call, %w[native_uuid pid arguments])
        args = call['arguments']
        expected_args = {'metadata' => readback['metadata'], 'discovery_metadata' => readback['discovery'],
          'visibility' => 'private', 'capacity' => execution['request']['players'].size, 'participant_metadata' => {'client' => 'elten_game_room', 'table_id' => readback['table']['__id']},
          'pool_count' => 1, 'private_messages' => true, 'stack_entries' => GameRoomLiveSessionStore::STACK_ENTRIES,
          'stack_entry_bytes' => GameRoomLiveSessionStore::STACK_ENTRY_BYTES}
        unless Data.integer?(call['pid'], 1) && args.eql?(expected_args) &&
            core['stack_entries'].eql?(GameRoomLiveSessionStore::STACK_ENTRIES) &&
            core['stack_entry_bytes'].eql?(GameRoomLiveSessionStore::STACK_ENTRY_BYTES)
          raise Invalid, :sandbox_corrupt
        end
      end
    end

    def validate_records!(document)
      unless document.is_a?(Hash) && document['records'].is_a?(Hash) && document['records'].size <= MAX_RECORDS && document['readiness'].is_a?(Array)
        raise Invalid, :sandbox_corrupt
      end
      document['records'].each do |key, record|
        Data.text!(key, bytes: 256)
        trusted = accepted_record(key)
        unless trusted && trusted.eql?(record) && trusted['preview']['intent_id'] == key
          raise Invalid, :sandbox_corrupt
        end
      end
      times = {}
      document['readiness'].each do |receipt|
        ReadinessContract.fields!(receipt, %w[status operation request_digest reason result])
        operation = ReadinessContract.operation!(receipt['operation'])
        ReadinessContract.response!(receipt, operation)
        request = operation['request']
        if receipt['status'] == 'confirmed'
          key = [request['scope'], request['match_ref'], operation['account']]
          time = receipt['result']['server_time']
          raise Invalid, :sandbox_corrupt if times.key?(key) && time < times[key]
          times[key] = time
        end
        reference = request['match_ref']
        record = document['records'].values.find do |row|
          row['evidence']['plan']['id'] == reference['plan_id'] &&
            row['evidence']['scope'].slice('app_uuid', 'backend_identity', 'tournament_id').eql?(request['scope'])
        end
        raise Invalid, :sandbox_corrupt unless record && record['expected_source']['roster_generation'] == reference['roster_generation']
        match = record['evidence']['plan']['matches'].find { |row| row['match_id'] == reference['match_id'] && row['leg'].eql?(reference['leg']) }
        raise Invalid, :sandbox_corrupt unless match
        accepted = {'status' => 'confirmed', 'plan_digest' => record['evidence']['plan_digest'], 'full_roster' => true,
          'roles_status' => 'confirmed', 'members' => match['players'].map { |person| {'account' => person['account'], 'kind' => 'human', 'role' => 'player'} }}
        raise Invalid, :sandbox_corrupt unless operation['accepted_match'].eql?(accepted)
      end
    end

    def stat(value)
      File.lstat(value)
    rescue Errno::ENOENT
      nil
    end

    def check_paths
      value = directory
      loop do
        info = stat(value)
        raise Invalid, :unsafe_sandbox if info && (info.symlink? || !info.directory?)
        parent = File.dirname(value)
        break if parent == value
        value = parent
      end
      [path, path + '.lock'].each do |name|
        info = stat(name)
        raise Invalid, :unsafe_sandbox if info && (info.symlink? || !info.file? || info.nlink != 1)
      end
    end

    def check_open(file, name)
      info = file.stat
      raise Invalid, :unsafe_sandbox unless info.file? && info.nlink == 1 && File.identical?(file, name)
    end

    def read_document
      return nil unless stat(path)
      File.open(path, 'rb') do |file|
        check_open(file, path)
        bytes = file.read(MAX_BYTES + 1)
        raise Invalid, :json_budget if bytes.bytesize > MAX_BYTES
        restore_record_references(copy(StrictJson.parse(bytes, max_nesting: 24)))
      end
    end

    # Historyczny, niewydany format FT2A nie zawierał records.
    # Rekonstrukcja wyłącznie w RAM; każdy wpis pochodzi z readback rodzica FT1.
    def restore_record_references(document)
      return document if document.is_a?(Hash) && document.key?('records')
      C.fields!(document, %w[version identity readiness executions busy native])
      unless document['version'].eql?(1) && document['identity'] == identity && document['executions'].is_a?(Hash) && document['readiness'].is_a?(Array)
        raise Invalid, :sandbox_corrupt
      end
      records = {}
      document['executions'].each_value do |execution|
        raise Invalid, :sandbox_corrupt unless execution.is_a?(Hash)
        id = Data.text!(execution['record_intent'], bytes: 256)
        records[id] ||= accepted_record(id)
        raise Invalid, :legacy_record_reference_missing unless records[id] && records[id]['preview']['intent_id'] == id
      end
      document['readiness'].each do |receipt|
        ReadinessContract.fields!(receipt, %w[status operation request_digest reason result])
        operation = ReadinessContract.operation!(receipt['operation'])
        request = operation['request']
        unless records.values.any? { |r| r['evidence']['plan']['id'] == request['match_ref']['plan_id'] &&
            r['evidence']['scope'].slice('app_uuid', 'backend_identity', 'tournament_id').eql?(request['scope']) }
          raise Invalid, :legacy_record_reference_missing
        end
      end
      document.merge('records' => records)
    end
  end
end
