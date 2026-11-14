# encoding: UTF-8
require_relative 'fixed_team_native_payload'
require_relative 'coordination_contract'

module GameRoomTournaments
  # Powiązane dane nie stanowią zgody na wejście albo Start.
  class FixedTeamBoundTarget
    C = CoordinationContract
    Data = Publication::Data

    def self.build(record:, response:, readback:, registry:)
      op = response.fetch('operation')
      C.operation!(op, registry: registry)
      response = C.response!(response, op)
      raise C::Blocked, :unconfirmed_target unless response['status'] == 'confirmed' && op['kind'] == 'create_bind'
      request = op['request']
      selectors = {evidence: record['evidence'], expected_source: record['expected_source'], match_id: request['match_id'],
        leg: request['leg'], window_id: request['window']['id'], registry: registry}
      expected = CoordinationRequest.from_execution_plan(**selectors)
      native = native_payload_class.from_execution_plan(**selectors)
      unless expected.to_h.eql?(request) && record['request_digests'].dig(request['match_id'], request['window']['id']) == expected.digest &&
          native_record_matches?(record, request, native)
        raise C::Blocked, :record_mismatch
      end
      binding = C.binding!(response, registry: registry)
      readback = C.copy(readback)
      complete_readback = C.copy(readback)
      normalize_presentation_metadata!(readback, request, op)
      C.fields!(readback, %w[metadata discovery stack visibility participants table game_instance])
      table = readback['table']
      C.fields!(table, %w[created_at game game_options name owner bot_count bot_names max_players status player_count private resume_save_id id __id __insertion_user __live_session_id __statistics_room_id __discovery_protocol last_activity_at updated_at])
      C.fields!(readback['metadata'], %w[created_at game game_options kind name owner private protocol resume_save_id statistics_room_id table_id])
      C.fields!(readback['discovery'], %w[created_at game game_options kind name owner private protocol resume_save_id table_id bot_count max_players status player_count])
      unless table['__discovery_protocol'].eql?(GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL) &&
          table['name'].eql?('FT2A') && table['last_activity_at'].nil? &&
          table['__statistics_room_id'].is_a?(String) && table['game_options'].is_a?(String)
        raise C::Blocked, :native_target_mismatch
      end
      Data.text!(table['__statistics_room_id'], bytes: 256)
      owner = request['players'].find { |person| person['account'] == op['actor'] }
      unless owner && readback['visibility'] == 'private' && table['private'].equal?(true) &&
          table['__live_session_id'] == binding.to_h['native_uuid'] && table['__id'].eql?(binding.to_h['table_id']) &&
          table['owner'] == owner['username'] && table['game'] == request['game_id'] && table['bot_count'].eql?(0) &&
          table['status'] == 'waiting' && readback['game_instance'].nil?
        raise C::Blocked, :native_target_mismatch
      end
      options = StrictJson.parse(table.fetch('game_options'), max_nesting: 8)
      raise C::Blocked, :native_target_mismatch unless options.eql?(native.to_h['options'])
      validate_readback!(readback, owner, capacity: native.to_h['players'].size)
      game = registry.build(request['game_id'])
      consumed = game.game_start_options(options, players: native.to_h['players'], fixed: true)
      unless consumed.eql?(native.to_h['options']) && valid_assignment?(game, consumed, native.to_h['players'])
        raise C::Blocked, :native_target_mismatch
      end
      new(Data.freeze_tree(C.copy({'binding' => binding.to_h, 'native' => native.to_h,
        'receipt' => {'operation_id' => op['operation_id'], 'proof_ref' => response['receipt'], 'request_digest' => expected.digest,
          'operation_digest' => op['request_digest'], 'native_digest' => native.digest}, 'readback' => complete_readback})))
    end

    def self.native_payload_class; FixedTeamNativePayload; end
    def self.native_record_matches?(record, request, native)
      record['native_payload_digests'].dig(request['match_id'], request['window']['id']) == native.digest
    end
    def self.valid_assignment?(game, options, players)
      game.prepared_team_assignment(options, players: players)
    end

    # Cosmetic, authenticated profiles do not change a match's sealed native
    # identity. Validate their exact shape before excluding them from it.
    def self.normalize_presentation_metadata!(readback, request, operation)
      discovery = readback['discovery']
      if discovery.is_a?(Hash)
        if discovery.key?('owner_display_name')
          value = discovery.delete('owner_display_name')
          raise C::Invalid, :invalid_fields unless value.is_a?(String) &&
            GameRoomParticipants.normalize_display_name(value) == value
        end
      end
      owner = request['players'].find { |person| person['account'] == operation['actor'] }
      return unless owner && readback['stack'].is_a?(Array)
      stack = readback['stack']
      unless stack.each_with_index.all? { |entry, index| entry.is_a?(Hash) && entry['seq'] == index + 1 } &&
          stack.map { |entry| entry['message_id'] }.uniq.size == stack.size
        raise C::Blocked, :native_target_mismatch
      end
      readback['stack'] = stack.reject do |entry|
        next false unless entry.is_a?(Hash) && entry.dig('packet', 'kind') == 'room_profile'
        C.fields!(entry, %w[created_at message_id packet sender sender_id seq])
        C.fields!(entry['packet'], %w[version kind actor data])
        data = entry['packet']['data']
        C.fields!(data, ['display_name'])
        person = readback.dig('participants', owner['account'])
        unless person && entry['packet']['version'] == 2 &&
            entry['packet']['actor'] == owner['username'] && entry['sender'] == {'user' => owner['username']} &&
            entry['sender_id'] == person['id'] && Data.integer?(entry['seq'], 2) &&
            Data.integer?(entry['created_at']) && data['display_name'].is_a?(String) &&
            GameRoomParticipants.normalize_display_name(data['display_name']) == data['display_name']
          raise C::Blocked, :native_target_mismatch
        end
        Data.text!(entry['message_id'], bytes: 256)
        true
      end
    end
    private_class_method :normalize_presentation_metadata!

    def self.validate_readback!(readback, owner, capacity:)
      table = readback['table']
      metadata = table.slice('game', 'game_options', 'name', 'owner', 'private', 'resume_save_id').merge(
        'created_at' => readback['metadata']['created_at'],
        'kind' => 'elten_game_room_table', 'protocol' => table['__discovery_protocol'],
        'statistics_room_id' => table['__statistics_room_id'], 'table_id' => table['__id'])
      discovery = metadata.reject { |key, _| key == 'statistics_room_id' }.merge(
        table.slice('bot_count', 'max_players', 'player_count', 'status'))
      unless readback['metadata'].eql?(metadata) && readback['discovery'].eql?(discovery) &&
          table['max_players'].eql?(capacity) && table['player_count'].eql?(1) && table['bot_names'].eql?([]) &&
          table['resume_save_id'].eql?('') && Data.integer?(table['created_at']) && Data.integer?(metadata['created_at']) &&
          table['__insertion_user'] == owner['username'] && table['id'].eql?(table['__id'])
        raise C::Blocked, :native_target_mismatch
      end
      people = readback['participants']
      C.fields!(people, [owner['account']])
      person = people[owner['account']]
      C.fields!(person, %w[id user])
      Data.text!(person['id'], bytes: 256)
      raise C::Blocked, :native_target_mismatch unless person['user'] == owner['username']
      stack = readback['stack']
      raise C::Blocked, :native_target_mismatch unless stack.is_a?(Array) && stack.size == 1
      entry = stack.first
      C.fields!(entry, %w[created_at message_id packet sender sender_id seq])
      Data.text!(entry['message_id'], bytes: 256)
      packet = {'version' => 2, 'kind' => 'room_created', 'actor' => owner['username'],
        'data' => table.slice('bot_count', 'bot_names', 'game', 'game_options', 'max_players', 'name', 'owner', 'status').merge('created_at' => metadata['created_at'])}
      unless entry['packet'].eql?(packet) && entry['seq'].eql?(1) && entry['sender'].eql?({'user' => owner['username']}) &&
          entry['sender_id'] == person['id'] && Data.integer?(entry['created_at']) &&
          table['created_at'].eql?(entry['created_at']) && table['updated_at'].eql?(entry['created_at'])
        raise C::Blocked, :native_target_mismatch
      end
    end
    private_class_method :validate_readback!

    def initialize(value)
      @value = value
      freeze
    end
    private_class_method :new

    def to_h
      @value
    end
  end
end
