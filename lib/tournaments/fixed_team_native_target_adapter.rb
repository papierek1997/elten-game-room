# encoding: UTF-8
require_relative '../game_room_transport'
require_relative '../game_repository'
require_relative 'coordination_contract'
require_relative 'fixed_team_seats'

module GameRoomTournaments
  # Jedyny dodatni provider jest jawnie wstrzykniętym lokalnym uczestnikiem commit.
  class FixedTeamNativeTargetAdapter
    Data = Publication::Data
    C = CoordinationContract

    def initialize(provider:, registry:)
      @provider, @registry = provider, registry
    end

    def supported?
      @provider && %i[local_transaction_version limits open committed].all? { |name| @provider.respond_to?(name) } &&
        @provider.local_transaction_version.eql?(1)
    end

    def preflight!(native:, request:, actor:, state: nil)
      raise C::Blocked, :coordination_unavailable unless supported?
      limits = Data.copy(@provider.limits)
      C.fields!(limits, %w[options_bytes discovery_bytes stack_entry_bytes core_bytes])
      raise C::Blocked, :native_limits unless limits.values.all? { |value| Data.integer?(value, 1) }
      options = JSON.generate(native.to_h['options'])
      raise C::Blocked, :native_limits if options.bytesize > [8192, limits['options_bytes']].min
      owner = request['players'].find { |person| person['account'] == actor }
      raise C::Blocked, :not_participant unless owner
      # Ta sama struktura co rzeczywiste create_room, nie discovery udające packet.
      projected = budget_readback(native: native, request: request, owner: owner['username'])
      raise C::Blocked, :native_limits if JSON.generate(projected['discovery']).bytesize > [1024, limits['discovery_bytes']].min
      if projected['stack'].any? { |entry| JSON.generate(entry['packet']).bytesize > [16_384, limits['stack_entry_bytes']].min }
        raise C::Blocked, :native_limits
      end
      begin
        Data.copy(projected, max_bytes: [262_144, limits['core_bytes']].min, max_nodes: 16_384, max_depth: 16)
        native_state = budget_native(projected).to_h { |key, rows| [key, (state ? state.fetch(key) : []) + rows] }
        Data.copy(native_state, max_bytes: [262_144, limits['core_bytes']].min, max_nodes: 16_384, max_depth: 16)
      rescue Publication::Invalid => error
        raise C::Blocked, :native_limits if error.code == :json_budget
        raise
      end
      limits
    end

    def create(state:, native:, request:, actor:)
      limits = preflight!(native: native, request: request, actor: actor, state: state)
      owner = request['players'].find { |person| person['account'] == actor }.fetch('username')
      with_transaction(state: state, owner: owner) do |transaction, transport|
        table = transport.create_room(name: 'FT2A', game: request['game_id'], owner: owner,
          game_options: JSON.generate(native.to_h['options']), private_table: true, capacity: match_capacity(request), bot_count: 0)
        readback = read_transaction(transaction, transport, table['__live_session_id'], table['__id'])
        raise C::Blocked, :native_limits if JSON.generate(readback).bytesize > limits['core_bytes']
        [Data.freeze_tree(C.copy(readback)), transaction.dump]
      end
    end

    def committed(receipt:)
      @provider.committed(receipt: Data.freeze_tree(C.copy(receipt)))
    end

    def lookup(state:, native_uuid:, table_id:, owner:)
      with_transaction(state: state, owner: owner) do |transaction, transport|
        transport.start
        Data.freeze_tree(C.copy(read_transaction(transaction, transport, native_uuid, table_id)))
      end
    end

    # Wyłącznie projekcja pojemności: nie jest obserwacją ani autorytetem celu.
    def budget_readback(native:, request:, owner:)
      uuid = 'ffffffff-ffff-4fff-bfff-ffffffffffff'
      metadata = {'created_at' => Publication::MAX_INTEGER, 'game' => request['game_id'],
        'game_options' => JSON.generate(native.to_h['options']), 'kind' => GameRoomLiveSessionStore::KIND,
        'name' => 'FT2A', 'owner' => owner, 'private' => true, 'protocol' => GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL,
        'resume_save_id' => '', 'statistics_room_id' => uuid, 'table_id' => Publication::MAX_INTEGER}
      room = metadata.slice('created_at', 'game', 'game_options', 'name', 'owner').merge(
        'bot_count' => 0, 'bot_names' => [], 'max_players' => match_capacity(request), 'status' => 'waiting')
      display_name = GameRoomParticipants.local_display_name
      discovery = metadata.reject { |key, _| key == 'statistics_room_id' }.merge(room.slice('bot_count', 'max_players', 'status'))
        .merge('player_count' => 1, 'owner_display_name' => display_name)
      table = room.merge('player_count' => 1, 'private' => true, 'resume_save_id' => '', 'id' => Publication::MAX_INTEGER,
        '__id' => Publication::MAX_INTEGER, '__insertion_user' => owner, '__live_session_id' => uuid,
        '__statistics_room_id' => uuid, '__discovery_protocol' => GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL,
        'last_activity_at' => nil, 'updated_at' => Publication::MAX_INTEGER)
      stack = [{'created_at' => Publication::MAX_INTEGER, 'message_id' => uuid,
        'packet' => {'version' => 2, 'kind' => 'room_created', 'actor' => owner, 'data' => room},
        'sender' => {'user' => owner}, 'sender_id' => uuid, 'seq' => 1}]
      unless display_name.empty?
        stack << {'created_at' => Publication::MAX_INTEGER, 'message_id' => 'ffffffff-ffff-4fff-bfff-fffffffffffe',
          'packet' => {'version' => 2, 'kind' => 'room_profile', 'actor' => owner, 'data' => {'display_name' => display_name}},
          'sender' => {'user' => owner}, 'sender_id' => uuid, 'seq' => 2}
      end
      {'metadata' => metadata, 'discovery' => discovery, 'table' => table, 'visibility' => 'private',
        'participants' => {owner.downcase => {'id' => uuid, 'user' => owner}}, 'stack' => stack, 'game_instance' => nil}
    end

    def budget_native(readback)
      table = readback['table']
      uuid = table['__live_session_id']
      args = {'metadata' => readback['metadata'], 'discovery_metadata' => readback['discovery'],
        'capacity' => table['max_players'], 'visibility' => 'private',
        'participant_metadata' => {'client' => 'elten_game_room', 'table_id' => table['__id'], 'display_name' => readback['discovery'].fetch('owner_display_name', '')},
        'stack_entries' => GameRoomLiveSessionStore::STACK_ENTRIES, 'stack_entry_bytes' => GameRoomLiveSessionStore::STACK_ENTRY_BYTES,
        'pool_count' => 1, 'private_messages' => true}
      core = args.slice('metadata', 'discovery_metadata', 'capacity', 'visibility', 'stack_entries', 'stack_entry_bytes').merge(
        'id' => uuid, 'owner' => table['owner'], 'participants' => readback['participants'], 'entries' => readback['stack'],
        'closed' => false, 'last_seq' => readback['stack'].last.fetch('seq'), 'trimmed_through' => 0, 'invitations' => {},
        'dedup' => readback['stack'].map { |entry| {'key' => [table['owner'], entry['message_id']], 'sequence' => entry['seq']} })
      {'creates' => [{'native_uuid' => uuid, 'pid' => Publication::MAX_INTEGER, 'arguments' => args}], 'cores' => [core]}
    end

    private

    def match_capacity(request)
      return 4 if request['role_policy_ref'] == FixedTeamSeats::POLICY
      count = request['players'].size
      game = @registry.build(request['game_id'])
      groups = request['players'].group_by { |person| person['team'] }
      unless request['role_policy_ref'] == FixedTeamSeats::LARGE_POLICY && count >= 6 && count.even? &&
          game.tournament_fixed_team_actions? && game.team_size(request['options'], player_count: count).eql?(count / 2) &&
          groups.size == 2 && !groups.key?(nil) && groups.values.all? { |people| people.size == count / 2 }
        raise C::Blocked, :native_target_mismatch
      end
      count
    end

    def with_transaction(state:, owner:)
      transaction = transport = primary = nil
      begin
        transaction = @provider.open(state: state, owner: owner)
        unless %i[program metadata dump].all? { |name| transaction.respond_to?(name) }
          raise C::Blocked, :coordination_unavailable
        end
        program = transaction.program
        raise C::Blocked, :coordination_unavailable unless program.respond_to?(:live_sessions)
        options = transaction.respond_to?(:transport_options) ? transaction.transport_options : {}
        transport = GameRoomTransport.new(program, **options.merge(local_view: true))
        yield transaction, transport
      rescue Exception => error
        primary = error
        raise error, cause: error.cause
      ensure
        begin
          transport&.close_local_view
        rescue Exception => error
          primary ||= error
        ensure
          begin
            transaction.close if transaction.respond_to?(:close)
          ensure
            # Także throw cleanup nie może połknąć pierwotnego wyjątku.
            raise primary, cause: primary.cause if primary
          end
        end
      end
    end

    def read_transaction(transaction, transport, native_uuid, table_id)
      snapshot = transport.room_snapshot(table_id, force: true, read_only: true)
      raise C::Blocked, :native_target_missing unless snapshot
      table = snapshot.fetch(:table)
      raise C::Blocked, :native_target_mismatch unless table['__live_session_id'] == native_uuid && table['__id'].eql?(table_id)
      repository = GameRepository.new(transaction.program, transport: transport)
      data = transaction.metadata(native_uuid: native_uuid)
      data.merge('table' => table, 'game_instance' => repository.session_for_table(table, force: true))
    end
  end
end
