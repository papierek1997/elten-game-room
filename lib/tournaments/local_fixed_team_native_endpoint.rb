# encoding: UTF-8
require 'securerandom'
require_relative 'coordination_contract'
require_relative '../game_session_contracts'

module GameRoomTournaments
  # Wąski odłączony native core. Tworzenie zachowuje pojedyncze room_created.
  # Membership rozszerza tylko atomowa admission, nie discovery lub planned roster.
  # Start ma osobne uprawnienie dla jednego celu. Zaproszenia są lokalnymi
  # potwierdzeniami standardowej ścieżki transportu; endpoint nie używa sieci.
  class LocalFixedTeamNativeEndpoint
    include GameRoomSessionContracts::LocalActor
    Data = Publication::Data
    C = CoordinationContract
    Participant = Struct.new(:id, :user, keyword_init: true)
    # Uchwyt może przeżyć endpoint, ale po close nie przechowuje starego closure.
    Callback = Struct.new(:callback) do
      def call(*arguments)
        callback&.call(*arguments)
      end
      def close
        self.callback = nil
      end
    end
    attr_reader :user

    def initialize(state:, owner:, clock:, start_target: nil, move_target: nil, expected_capacity: 4)
      raise C::Blocked, :native_target_mismatch unless expected_capacity.is_a?(Integer) && expected_capacity.between?(1, 256)
      @expected_capacity = expected_capacity
      @state = copy(state)
      @user = Data.account(owner).freeze
      @clock, @mutex, @closed = clock, Mutex.new, false
      @start_target = start_target
      @move_target = move_target
      @callbacks = []
      @views = @state.fetch('cores').select { |core| core['participants'].key?(@user.downcase) && !core['closed'] }.map { |core| View.new(self, core['id']) }
    end

    def access
      @mutex.synchronize do
        raise C::Blocked, :local_view_closed if @closed
        yield @state
      end
    end

    def sessions
      access { @views.dup.freeze }
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    # This explicit local tournament simulator never calls a server. A local
    # transport view alone does not imply this: diagnostics may use real APIs.
    def offline?; true; end

    def on_invitation(&callback)
      access do
        handle = Callback.new(callback)
        @callbacks << handle
        handle
      end
    end
    def on_error(&callback)
      on_invitation(&callback)
    end

    def close_view
      @mutex.synchronize do
        @closed = true
        @callbacks.each(&:close)
        @callbacks.clear
        @views.clear
        @state = nil
      end
      nil
    end

    def create(metadata:, participant_metadata:, capacity:, visibility:, discovery_metadata:, stack_entry_bytes:, stack_entries:, pool_count:, private_messages:)
      arguments = copy({'metadata' => metadata, 'participant_metadata' => participant_metadata, 'capacity' => capacity,
        'visibility' => visibility.to_s, 'discovery_metadata' => discovery_metadata, 'stack_entry_bytes' => stack_entry_bytes,
        'stack_entries' => stack_entries, 'pool_count' => pool_count, 'private_messages' => private_messages})
      unless capacity.eql?(@expected_capacity) && visibility == :private && pool_count.eql?(1) && private_messages.equal?(true) && metadata['owner'] == user
        raise C::Blocked, :native_target_mismatch
      end
      raise C::Blocked, :native_limits if JSON.generate(metadata).bytesize > 16_384 || JSON.generate(discovery_metadata).bytesize > 1024
      access do |state|
        id = SecureRandom.uuid
        participant = {'id' => SecureRandom.uuid, 'user' => user}
        core = arguments.slice('metadata', 'discovery_metadata', 'capacity', 'visibility', 'stack_entries', 'stack_entry_bytes').merge(
          'id' => id, 'owner' => user, 'participants' => {user.downcase => participant}, 'entries' => [],
          'last_seq' => 0, 'trimmed_through' => 0, 'closed' => false, 'invitations' => {}, 'dedup' => [])
        state.fetch('creates') << {'native_uuid' => id, 'pid' => Process.pid, 'arguments' => arguments}
        state.fetch('cores') << core
        view = View.new(self, id)
        @views << view
        view
      end
    end

    def core(id)
      access do |state|
        value = state.fetch('cores').find { |row| row['id'] == id && row['participants'].key?(user.downcase) }
        raise C::Blocked, :native_target_missing unless value
        yield value
      end
    end

    def metadata(native_uuid:)
      core(native_uuid) do |value|
        detached({'metadata' => value['metadata'], 'discovery' => value['discovery_metadata'], 'stack' => value['entries'],
          'visibility' => value['visibility'], 'participants' => value['participants']})
      end
    end

    def dump
      access { |state| detached(state) }
    end

    def copy(value)
      Data.copy(value, max_bytes: 262_144, max_nodes: 16_384, max_depth: 16)
    end

    def detached(value)
      Data.freeze_tree(copy(value))
    end

    class View
      attr_reader :id
      def initialize(endpoint, id)
        @endpoint, @id = endpoint, id.dup.freeze
      end
      def metadata; read('metadata'); end
      def discovery_metadata; read('discovery_metadata'); end
      def visibility; read('visibility').to_sym; end
      def capacity; read('capacity'); end
      def closed?; @endpoint.closed? || read('closed'); end
      def owner?; owner.user == @endpoint.user; end
      def participants
        read('participants').values.map { |p| Participant.new(id: p['id'], user: p['user']).freeze }.freeze
      end
      def participant(id)
        participants.find { |p| p.id == id }
      end
      def owner
        participants.find { |p| p.user == read('owner') }
      end
      def invite(user, metadata:)
        recipient = Data.account(user)
        @endpoint.core(id) do |core|
          raise C::Blocked, :not_coordinator unless core['owner'] == @endpoint.user && !core['closed']
          raise C::Blocked, :invalid_invitation if recipient.casecmp(@endpoint.user).zero? || metadata['purpose'] != 'game_invitation'
          key = recipient.downcase
          prior = core['invitations'][key]
          if prior
            raise C::Blocked, :operation_conflict unless prior['binding_digest'] == metadata['binding_digest'] && prior['epoch'] == metadata['epoch']
            if metadata.key?('replaces_id')
              next @endpoint.detached(prior) if prior['replaces_id'] == metadata['replaces_id']
              unless prior['id'] == metadata['replaces_id'] && prior['expires_at'] <= metadata['created_at'] && !core['participants'].key?(key)
                raise C::Blocked, :invitation_changed
              end
            else
              next @endpoint.detached(prior)
            end
          elsif metadata.key?('replaces_id')
            raise C::Blocked, :invitation_changed
          end
          row = metadata.slice('binding_digest', 'epoch', 'table_id', 'created_at', 'expires_at', 'replaces_id').merge(
            'id' => SecureRandom.random_number(2_000_000_000) + 1, 'native_uuid' => id, 'sender' => @endpoint.user, 'recipient' => recipient)
          row['id'] = row['id'] % 2_000_000_000 + 1 if prior && row['id'] == prior['id']
          core['invitations'][key] = @endpoint.copy(row)
          @endpoint.detached(row)
        end
      end
      def stack_state
        @endpoint.core(id) { |core| @endpoint.detached(core.slice('last_seq', 'trimmed_through')) }
      end
      def stack_read(after:, limit:, **_options)
        @endpoint.core(id) do |core|
          gap = {'from' => after + 1, 'to' => core['trimmed_through']} if after < core['trimmed_through']
          start = [after, core['trimmed_through']].max
          entries = core['entries'].select { |row| row['seq'] > start }.take(limit)
          cursor = entries.last ? entries.last['seq'] : start
          @endpoint.detached({'session_id' => id, 'entries' => entries, 'cursor' => cursor,
            'through' => core['last_seq'], 'has_more' => cursor < core['last_seq'], 'gap' => gap})
        end
      end
      def stack_push(packet, message_id:)
        value = @endpoint.copy(packet)
        key = [@endpoint.user, Data.text!(message_id, bytes: 256).dup]
        @endpoint.core(id) do |core|
          prior = core['dedup'].find { |row| row['key'] == key }
          if prior
            entry = core['entries'].find { |row| row['seq'] == prior['sequence'] }
            raise C::Blocked, :operation_conflict unless entry && entry['packet'].eql?(value)
            next @endpoint.detached({'entry' => entry, 'seq' => entry['seq']})
          end
          creation = core['entries'].empty? && value['kind'] == 'room_created'
          prefix = core['entries'].take_while { |row| %w[room_created room_profile].include?(row.dig('packet', 'kind')) }
          profile = !prefix.empty? && prefix.size == core['entries'].size &&
            core['owner'] == @endpoint.user && value.keys.sort == %w[actor data kind version] &&
            value['version'] == 2 && value['kind'] == 'room_profile' && value['data'].is_a?(Hash) &&
            value['data'].keys == ['display_name'] && value['data']['display_name'].is_a?(String) &&
            GameRoomParticipants.normalize_display_name(value['data']['display_name']) == value['data']['display_name']
          start = @endpoint.instance_variable_get(:@start_target) == id && core['owner'] == @endpoint.user &&
            [[prefix.size, 'room_state'], [prefix.size + 1, 'game_started']].include?([core['last_seq'], value['kind']])
          target = @endpoint.instance_variable_get(:@move_target)
          move = target && target[:native_uuid] == id && target[:after] == core['last_seq'] &&
            value['kind'] == 'game_action' && value.dig('data', 'session_id') == target[:session_id] &&
            value.dig('data', 'controller').equal?(false)
          unless (creation || profile || start || move) && value['actor'] == @endpoint.user
            raise C::Blocked, :local_create_only
          end
          raise C::Blocked, :native_limits if JSON.generate(value).bytesize > core['stack_entry_bytes']
          participant = core['participants'].fetch(@endpoint.user.downcase)
          now = @endpoint.instance_variable_get(:@clock).now.to_i
          raise C::Blocked, :invalid_clock unless now.positive?
          sequence = core['last_seq'] + 1
          entry = {'seq' => sequence, 'message_id' => key.last, 'sender' => {'user' => @endpoint.user},
            'sender_id' => participant['id'], 'packet' => value, 'created_at' => now}
          core['entries'] << entry
          core['last_seq'] = sequence
          core['dedup'] << {'key' => key, 'sequence' => sequence}
          @endpoint.detached({'seq' => sequence, 'entry' => entry})
        end
      end
      def stack_trim(through:)
        @endpoint.core(id) do |core|
          checkpoint = core['entries'].find { |row| row.dig('packet', 'kind') == 'room_state' }
          unless @endpoint.instance_variable_get(:@start_target) == id && core['owner'] == @endpoint.user &&
              checkpoint && core['last_seq'] == checkpoint['seq'] + 1 && through.eql?(checkpoint['seq'] - 1) &&
              core['entries'].last.dig('packet', 'kind') == 'game_started'
            raise C::Blocked, :local_create_only
          end
          core['entries'].reject! { |row| row['seq'] <= through }
          core['trimmed_through'] = through
          true
        end
      end
      def close
        # Zwalniamy widok roboczy, nigdy trwały pokój po commit.
        @endpoint.close_view
      end
      private
      def read(key)
        @endpoint.core(id) { |core| @endpoint.detached(core.fetch(key)) }
      end
    end
  end
end
