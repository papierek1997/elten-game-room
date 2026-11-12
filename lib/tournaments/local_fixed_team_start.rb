# encoding: UTF-8
require_relative 'local_fixed_team_admission'
require_relative 'local_fixed_team_native_provider'
require_relative '../game_repository'

module GameRoomTournaments
  # One local Start and its native LiveSessions proof share the admission commit.
  # No global Session impersonation and no second game execution loop.
  class LocalFixedTeamStart < LocalFixedTeamAdmission
    C = CoordinationContract
    Data = Publication::Data
    FIELDS = %w[version kind id account binding_digest epoch native_uuid table_id created_at session_id records].freeze

    def self.validate!(execution, core)
      receipt = execution['start']
      return unless execution.key?('start')
      C.fields!(receipt, FIELDS)
      target = execution['target']
      raise Publication::Invalid, :sandbox_corrupt unless target && core
      binding = target['binding']
      expected = {'version' => 1, 'kind' => 'start', 'account' => execution['coordinator'],
        'binding_digest' => C.digest(binding), 'native_uuid' => binding['native_uuid'], 'table_id' => binding['table_id'],
        'epoch' => execution['operations']['create_bind']['operation']['preconditions']['grant']['fencing']}
      unless expected.all? { |key, value| receipt[key].eql?(value) } &&
          receipt['epoch'] <= execution['epoch'] && Data.integer?(receipt['created_at']) &&
          receipt['created_at'] >= execution['request']['window']['opens'] && receipt['created_at'] < execution['expires_at'] &&
          Data.integer?(receipt['session_id'], 1)
        raise Publication::Invalid, :sandbox_corrupt
      end
      Data.text!(receipt['id'], bytes: 256)
      entries = execution.dig('admission', 'entries')
      people = execution['request']['players'].sort_by { |p| p['seat'] }
      unless entries && entries.keys.sort == people.map { |p| p['account'] }.sort &&
          entries.values.all? { |r| r['epoch'] == receipt['epoch'] && r['created_at'] <= receipt['created_at'] }
        raise Publication::Invalid, :sandbox_corrupt
      end
      records = receipt['records']
      moves = execution.key?('moves') ? execution['moves'] : []
      unless moves.is_a?(Array) && moves.all? { |move| move.is_a?(Hash) && move['record'].is_a?(Hash) } &&
          records.is_a?(Array) && records.size == 2 && core['entries'].take(2).eql?(records) &&
          core['last_seq'].eql?(3 + moves.size) && core['trimmed_through'].eql?(1)
        raise Publication::Invalid, :sandbox_corrupt
      end
      records.each_with_index do |record, index|
        C.fields!(record, %w[seq message_id sender sender_id packet created_at])
        C.fields!(record['packet'], %w[version kind actor data])
        unless record['seq'].eql?(index + 2) && record['sender'].eql?({'user' => core['owner']}) &&
            record['sender_id'] == core['participants'].fetch(receipt['account'])['id'] &&
            record['packet']['version'].eql?(GameRoomLiveSessionStore::PROTOCOL) && record['packet']['actor'] == core['owner'] &&
            record['packet']['kind'] == %w[room_state game_started][index] && Data.integer?(record['created_at'], 1)
          raise Publication::Invalid, :sandbox_corrupt
        end
        Data.text!(record['message_id'], bytes: 256)
        raise Publication::Invalid, :sandbox_corrupt if JSON.generate(record['packet']).bytesize > core['stack_entry_bytes']
      end
      original = target['readback']['stack'].first
      history = [original, *records, *moves.map { |move| move['record'] }]
      dedup = history.map { |row| {'key' => [row.dig('sender', 'user'), row['message_id']], 'sequence' => row['seq']} }
      raise Publication::Invalid, :sandbox_corrupt unless core['dedup'].eql?(dedup) && dedup.map { |r| r['key'] }.uniq.size == history.size &&
        core['entries'].eql?(records + moves.map { |move| move['record'] })
      checkpoint = records.first['packet']['data']
      # The normal store checkpoints these fields from the immutable room.
      table = target['readback']['table']
      expected_checkpoint = table.slice('status', 'bot_count', 'bot_names', 'bot_players', 'game_options', 'updated_at').merge('observers' => [])
      raise Publication::Invalid, :sandbox_corrupt unless checkpoint.eql?(expected_checkpoint)
      data = records.last['packet']['data']
      C.fields!(data, %w[session_id game players options created_at statistics])
      unless data['session_id'].eql?(receipt['session_id']) && data['game'] == binding['game_id'] &&
          data['players'].eql?(people.map { |p| p['username'] }) &&
          data['options'] == JSON.generate(target['native']['options']) && Data.integer?(data['created_at'], 1) &&
          GameRoomStatistics::Identity.valid?(data['statistics'], require_started_at: false) && data['statistics']['mode'] == 'humans'
        raise Publication::Invalid, :sandbox_corrupt
      end
    end

    def initialize(native:, registry:, **options)
      super(**options)
      @native, @registry = native.to_h, registry
    end

    def start(binding_digest:)
      Data.text!(binding_digest, bytes: 256)
      @record_reader.call(true)
      @port.transaction do |document|
        @record_reader.call(true)
        execution = execution!(document)
        binding = execution['target']['binding']
        raise C::Blocked, :target_changed unless binding_digest == C.digest(binding)
        raise C::Blocked, :not_coordinator unless actor == execution['coordinator']
        next detached(execution['start']) if execution['start']
        raise C::Blocked, :stale_grant unless active?(execution)
        core = core!(document, execution)
        people = @request['players'].sort_by { |p| p['seat'] }
        entries = execution.dig('admission', 'entries') || {}
        unless entries.keys.sort == people.map { |p| p['account'] }.sort && entries.values.all? { |r| r['epoch'] == execution['epoch'] }
          raise C::Blocked, :entries_required
        end
        receipt = with_native(document, execution) do |transaction, transport, table, repository|
          raise C::Blocked, :game_already_started if repository.session_for_table(table, force: true)
          session = transport.start_game(table: table, game: @request['game_id'], players: @native['players'],
            options: JSON.generate(@native['options']), actor: core['owner'])
          raise C::Blocked, :start_unconfirmed unless session && session['__authority_validated']
          document['native'] = @storage.copy(transaction.dump)
          updated = core!(document, execution)
          value = {'version' => 1, 'kind' => 'start', 'id' => SecureRandom.uuid, 'account' => actor,
            'binding_digest' => binding_digest, 'epoch' => execution['epoch'], 'native_uuid' => binding['native_uuid'],
            'table_id' => binding['table_id'], 'created_at' => @clock.call, 'session_id' => session['__id'],
            'records' => @storage.copy(updated['entries'])}
          execution['start'] = value
          @record_reader.call(true)
          raise C::Blocked, :stale_grant unless active?(execution)
          @storage.write(document, receipt: value)
          value
        end
        detached(receipt)
      end
    end

    private

    def with_native(document, execution)
      uuid = execution['target']['binding']['native_uuid']
      owner = core!(document, execution)['owner']
      provider = LocalFixedTeamNativeProvider.new
      transaction = provider.open_for_start(state: document['native'], owner: owner, native_uuid: uuid)
      transport = primary = nil
      begin
        transport = GameRoomTransport.new(transaction.program, **transaction.transport_options)
        transport.start
        table = transport.room_snapshot(execution['target']['binding']['table_id'], force: true)&.fetch(:table)
        raise C::Blocked, :native_target_mismatch unless table && table['__live_session_id'] == uuid
        yield transaction, transport, table, GameRepository.new(transaction.program, transport: transport)
      rescue Exception => error
        primary = error
        raise error, cause: error.cause
      ensure
        begin
          transport&.close_local_view
        ensure
          begin
            transaction.close
          ensure
            raise primary, cause: primary.cause if primary
          end
        end
      end
    end
  end
end
