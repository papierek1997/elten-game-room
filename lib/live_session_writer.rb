class GameRoomLiveSessionStore
  module Writer
    public

    def append_game_action(session:, sequence:, events:, actor:, controller: false, write_guard: nil)
      table_id = positive_identifier(session["table_id"])
      session_id = positive_identifier(session["__id"] || session["id"])
      raise ArgumentError, "Invalid game" if table_id == nil || session_id == nil
      ledger = control_ledger(table_id)
      raise GameRoomNetworkErrors::GamePaused, "Table master synchronization is pending" unless ledger.complete && same_user?(ledger.current_owner, owner_for(table_id))
      if session.key?("__control_epoch") && session["__control_epoch"] != ledger.epoch
        raise GameRoomNetworkErrors::GamePaused, "The game controller changed"
      end
      writer = local_actor || Session.name
      if controller || GameRoomParticipants.bot?(actor)
        raise ArgumentError, "Only the current table master may control this action" unless same_user?(writer, owner_for(table_id))
      elsif !same_user?(actor, writer)
        raise ArgumentError, "You no longer control this seat"
      end
      raise ArgumentError, 'The player is not in this game' unless GameRoomParticipants.includes?(
        game_session(session_id, table: table_id).to_h.fetch('__players', []), actor)
      raise GameRoomNetworkErrors::GamePaused, "The game was ended by the master" if game_aborted?(table_id, session_id)
      raise GameRoomNetworkErrors::GamePaused, "The game is being saved" if game_frozen?(table_id, session_id)

      random_request = GameRoomServerRandom.request_from(events.to_a)
      pool_request = GameRoomPrivateCards.request_from(events.to_a)
      commands = GameRoomEventProtocol.validate_commands!(events.to_a).map do |event|
        GameRoomEventProtocol.normalized(event).merge("move_id" => SecureRandom.uuid)
      end
      packet = GameRoomEventProtocol.game_action_packet(session_id: session_id, sequence: sequence,
        control_epoch: ledger.epoch, events: commands, actor: actor, controller: controller)
      current = game_session(session_id, table: table_id)
      if pool_request && %w[take reveal].include?(pool_request['operation']) && current['__tournament_match']
        # Retained with the PendingWrite/UUID across retries; this identifies
        # the boundary from which the ordinary client began its private RPC.
        packet['data']['presence_boundary'] = current['__game_boundary'].to_s
      end
      if GameRoomPrivateCards.enabled?(current)
        raise ArgumentError, 'This game requires a private card operation' unless (!!pool_request ^ !!random_request)
        operation = pool_request && pool_request['operation']
        proof = %w[take reveal].include?(operation) ? {'operation'=>operation} : nil
        unless GameRoomPrivateCards.valid_commands?(current['game'], commands,
            controlled: controller, host: same_user?(writer, owner_for(table_id)), pool: proof, random: random_request)
          raise ArgumentError, 'Invalid private card action for this game'
        end
        raise ArgumentError, 'A host cannot draw or reveal another player\'s cards' if controller && %w[take reveal check].include?(operation)
      elsif pool_request
        raise ArgumentError, 'This game does not use private hands'
      end
      if !random_request && current['__server_random'] == GameRoomServerRandom::VERSION &&
          GameRoomServerRandom.required?(current['game'], commands)
        raise ArgumentError, 'This action requires a server draw'
      end
      if random_request
        unless current['__server_random'] == GameRoomServerRandom::VERSION &&
            GameRoomServerRandom.actions(current['game']).include?(commands.first['action']) &&
            GameRoomServerRandom.accepts_request?(current['game'], random_request)
          raise ArgumentError, 'This game does not accept server random actions'
        end
        packet['data']['random_request'] = random_request
      end
      record = append_packet(table_id, packet, random_request: random_request, pool_request: pool_request, write_guard: write_guard)
      return nil unless record
      expand_game_action(record)
    end

    def consume_recovered_game_events(session)
      table_id = session["table_id"].to_i
      records = @mutex.synchronize do
        room_state(table_id).take_recovered_moves.to_a.map do |record|
          room_state(table_id).message_records[[record.sender.downcase, record.message_id]] || record
        end
      end
      return [] if game_aborted?(table_id, session["__id"])
      records.select { |record| record.packet.dig("data", "session_id").to_i == session["__id"].to_i }
        .flat_map { |record| expand_game_action(record) }
    end

    # Only invoked by error/gap recovery, never by an ordinary cached read.
    def pending_move_error(table_id)
      @mutex.synchronize do
        pending = @rooms[table_id.to_i]&.pending_move
        pending && (pending[:error] || GameRoomNetworkErrors::PendingMove.new("A game move is awaiting confirmation"))
      end
    end

    def reconcile(table_id)
      table_id = table_identifier(table_id)
      return false if table_id == nil
      return false if !ensure_current(table_id, force: true)

      pending = @mutex.synchronize { @rooms[table_id]&.pending_move }
      latest_game = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_started" }
      if pending != nil && latest_game != nil && pending[:packet].dig("data", "session_id") != latest_game.packet.dig("data", "session_id")
        @mutex.synchronize { (room_state(table_id).pending_move = nil) if room_state(table_id).pending_move.equal?(pending) }
        pending = nil
      end
      if pending != nil
        # An empty read is not evidence that a timed-out request cannot arrive
        # later. Keep its UUID, packet, actor, random values and event sequence.
        write_record(table_id, pending) unless reconcile_tournament_presence_write(table_id, pending)
      end
      true
    end

    private

    def append_record(table_id, kind, data, actor:, message_id: nil, write_guard: nil)
      packet = GameRoomEventProtocol.record_packet(kind: kind, actor: actor, data: data)
      append_packet(table_id, packet, message_id: message_id, write_guard: write_guard)
    end

    def append_packet(table_id, packet, message_id: nil, random_request: nil, pool_request: nil, write_guard: nil)
      session = active_session(table_id)
      return if write_guard && !write_guard.call(session)
      raise ArgumentError, "The room is no longer active" if session == nil

      message_id ||= SecureRandom.uuid
      pending = GameRoomSessionContracts::PendingWrite.new(message_id: message_id, packet: packet, sender: endpoint.user.to_s,
        writing: false, random_request: random_request, pool_request: pool_request, write_guard: write_guard)
      if packet['kind'] == 'room_activity' && packet.dig('data', 'activity_kind') == 'chat'
        # Re-entering an unchanged failed draft keeps its authenticated UUID.
        # A callback/recovery read may already have supplied the missing ACK.
        # Do not duplicate either the request or an unrelated packet's receipt.
        if (confirmed = confirmed_record(table_id, pending))
          raise ArgumentError, 'The chat operation identity was reused' unless confirmed.packet == packet
          return confirmed
        end
      end
      retained = @mutex.synchronize do
        previous = @rooms[table_id]&.pending_move
        if previous
          if packet['kind'] == 'game_boundary' && packet['data'].key?('tournament_presence') &&
              previous.message_id == message_id && previous.sender == pending.sender && previous.packet == packet
            next previous
          end
          raise GameRoomNetworkErrors::PendingMove, "An earlier game move is awaiting confirmation"
        end

        room_state(table_id).pending_move = pending if packet['kind'] == "game_action" ||
          packet['kind'] == 'game_boundary' && packet['data'].key?('tournament_presence')
        nil
      end
      return write_record(table_id, retained) if retained
      write_record(table_id, pending, write_guard: write_guard)
    end

    def write_record(table_id, pending, write_guard: nil)
      begin_room_io(table_id)
      acquired = false
      request_attempted = false
      # A server receipt wins over a later change of the precondition. It is
      # not a retry and must never be undone or rejected by a changed guard.
      confirmed = confirmed_record(table_id, pending)
      return confirmed if confirmed
      write_guard ||= pending.write_guard
      session = active_session(table_id)
      raise GameRoomNetworkErrors::PendingMove, "The game connection is not ready" if session == nil
      @mutex.synchronize do
        raise GameRoomNetworkErrors::PendingMove, "A game move is already being sent" if pending[:writing]

        pending[:writing] = true
        acquired = true
      end
      request = pending.random_request
      native_pool = pending.pool_request && %w[take reveal].include?(pending.pool_request['operation'])
      # Revalidate immediately before each actual push, including recovery.
      # Losing the HTTP reply is not evidence that the original request failed;
      # a denied retry therefore retains its uncertain UUID and packet.
      return nil unless write_precondition_valid?(table_id, session, pending, write_guard)
      # Acquiring the local slot is not a send. In particular, a failing read
      # in write_guard must not create a phantom uncertain game operation.
      # Private-pool verification also has read-only preflight work. Mark
      # uncertainty at its first mutation, including retirement/creation.
      result = if pending.pool_request
        write_private_pool(table_id, session, pending) { request_attempted = true }
      elsif request
        request_attempted = true
        session.stack_push_random(min: 1, max: request['sides'], count: request['count'],
          context: pending.packet, message_id: pending.message_id)
      else
        request_attempted = true
        session.stack_push(pending[:packet], message_id: pending[:message_id])
      end
      ingest_write_receipt(table_id, session, pending, result, native: request || native_pool)
    rescue StandardError => error
      # A native callback can confirm the write before its HTTP reply fails.
      confirmed = confirmed_record(table_id, pending)
      return confirmed if confirmed != nil

      @mutex.synchronize do
        if acquired && request_attempted && GameRoomNetworkErrors.transient?(error)
          pending[:uncertain] = true
          pending[:error] = error
        end
        (room_state(table_id).pending_move = nil) if room_state(table_id).pending_move.equal?(pending) && !pending[:uncertain] &&
          (!request_attempted || !GameRoomNetworkErrors.transient?(error))
      end
      raise
    ensure
      @mutex.synchronize { pending[:writing] = false } if acquired
      end_room_io(table_id)
    end

    def write_precondition_valid?(table_id, session, pending, write_guard)
      begin
        allowed = write_guard == nil || write_guard.call(session)
      rescue StandardError => error
        raise unless pending[:uncertain] && defined?(GameRoomSessionRunner::StaleView) && error.is_a?(GameRoomSessionRunner::StaleView)
        raise GameRoomNetworkErrors::UncertainWrite, 'The earlier operation cannot safely be retried after the game changed'
      end
      return true if allowed
      if pending[:uncertain]
        raise GameRoomNetworkErrors::UncertainWrite, 'The earlier operation cannot safely be retried after the game changed'
      end
      @mutex.synchronize do
        room = @rooms[table_id]
        room.pending_move = nil if room&.pending_move.equal?(pending) && !pending[:uncertain]
      end
      false
    end

    def ingest_write_receipt(table_id, session, pending, result, native:)
      sequence = extract_push_sequence(result)
      server_time = result.is_a?(Hash) ? (result.dig("entry", "created_at") || result["created_at"]) : nil
      server_time = nil unless server_time.respond_to?(:to_i) && server_time.to_i.positive?
      timestamp = server_time || (@record_clock ||= GameRoomSessionClock.new).server_now
      record = ingest_record(
        table_id,
        sequence: sequence,
        message_id: pending[:message_id],
        sender: pending[:sender],
        packet: native ? native_ack_packet(result) : pending[:packet],
        native_metadata: native ? result : nil,
        created_at: timestamp,
        estimated_time: server_time == nil,
        source_session: session
      )
      record || confirmed_record(table_id, pending) || raise(GameRoomNetworkErrors::UncertainWrite, 'The stored operation could not be verified')
    end

    def confirmed_record(table_id, pending)
      @mutex.synchronize { (@rooms[table_id]&.message_records || {})[[pending[:sender].downcase, pending[:message_id]]] }
    end

    def extract_push_sequence(result)
      candidates = [
        result.is_a?(Hash) ? result["seq"] : nil,
        result.is_a?(Hash) ? result.dig("entry", "seq") : nil
      ]
      sequence = candidates.map(&:to_i).find { |value| value.positive? }
      raise GameRoomNetworkErrors::UncertainWrite, "LiveSessions did not return the stored stack position" if sequence == nil

      sequence
    end

    def native_ack_packet(result)
      packet = result.is_a?(Hash) && (result['packet'] || result.dig('entry', 'packet'))
      raise GameRoomNetworkErrors::UncertainWrite, 'Missing native operation receipt' unless packet.is_a?(Hash)
      packet
    end

    def ingest_record(table_id, sequence:, message_id:, sender:, packet:, created_at:, estimated_time: false, source_session: nil, native_metadata: nil)
      seq = sequence.to_i
      identity = message_id.to_s
      return nil if seq <= 0 || identity.empty? || !packet.is_a?(Hash)
      pool_decoded = GameRoomPrivateCards.decode(packet, native_metadata, sender: sender, message_id: message_id)
      return nil unless pool_decoded
      packet, server_pool = pool_decoded
      decoded = GameRoomServerRandom.decode(packet, native_metadata)
      return nil unless decoded
      packet, server_random = decoded
      if packet["version"] != PROTOCOL || !packet["data"].is_a?(Hash) || !(packet["actor"].is_a?(String) && !packet["actor"].empty?) || sender.to_s.empty?
        # Do not print packet contents (they may contain private game data).
        Log.warning("ELTEN Game Room discarded invalid stack entry for table #{table_id}, sequence #{seq}") if defined?(Log)
        return nil
      end

      record = Record.new(
        table_id: table_id,
        sequence: seq,
        message_id: identity.dup.freeze,
        sender: sender.to_s.dup.freeze,
        packet: JSON.parse(JSON.generate(packet)),
        created_at: normalize_time(created_at),
        estimated_time: estimated_time,
        server_random: GameRoomSnapshot.copy(server_random),
        server_pool: GameRoomSnapshot.copy(server_pool)
      )
      # Packet/authority input never changes after ingestion. Estimated native
      # timestamps are corrected separately, with a new room generation.
      GameRoomSnapshot::Log.from_owned([record.packet, record.server_random, record.server_pool], bytes: 0)
      store_ingested_record(table_id, record, source_session)
    end

    def store_ingested_record(table_id, record, source_session)
      seq, identity, sender, estimated_time = record.sequence, record.message_id, record.sender, record.estimated_time
      corrected = nil
      inserted = @mutex.synchronize do
        # The callback/read may have passed its earlier membership check just
        # before leave and cache pruning. Never recreate that old collection.
        next false if source_session && !@sessions[table_id].equal?(source_session)
        next false if room_state(table_id).compacted_game_record?(record)

        key = [seq, identity]
        if room_state(table_id).record_keys.key?(key)
          previous = room_state(table_id).message_records[[sender.to_s.downcase, identity]]
          if previous && previous.sequence == seq && previous.estimated_time && !estimated_time
            if previous.created_at != record.created_at
              session_id = previous.packet.dig("data", "session_id").to_i
              room_state(table_id).clock_revisions[session_id] += 1 if session_id > 0
            end
            previous.created_at = record.created_at
            previous.estimated_time = false
            corrected = previous
            room_state(table_id).record_generation += 1
            room_state(table_id).history_corrections += 1
          end
          next false
        end

        room_state(table_id).record_keys[key] = true
        # A local push acknowledgement can overtake messages not delivered yet.
        # Only a contiguous prefix is safe as the cursor of subsequent reads.
        cursor = room_state(table_id).stack_cursor
        room_state(table_id).received_sequences[seq] = true if seq > cursor
        cursor += 1 while room_state(table_id).received_sequences.delete(cursor + 1)
        room_state(table_id).stack_cursor = cursor
        # Even if a late original and a retry occupy different stack positions,
        # all readers apply this authenticated operation just once.
        message_key = [sender.to_s.downcase, identity]
        previous = room_state(table_id).message_records[message_key]
        next false if previous != nil && previous.sequence <= seq
        room_state(table_id).records.delete(previous) if previous != nil

        room_state(table_id).message_records[message_key] = record
        rows = room_state(table_id).records
        ordered_append = rows.empty? || rows.last.sequence <= record.sequence
        rows << record
        rows.sort_by!(&:sequence) unless ordered_append
        room_state(table_id).record_generation += 1
        pending = room_state(table_id).pending_move
        if pending != nil && pending[:message_id] == identity && pending[:sender].casecmp(sender.to_s) == 0
          room_state(table_id).recovered_moves << record if pending[:uncertain]
          (room_state(table_id).pending_move = nil)
        end
        true
      end
      emit_record_change(table_id, record) if inserted
      if corrected
        if corrected.packet["kind"] == "game_started"
          emit_change(table_id, :game, corrected.packet.dig("data", "session_id").to_i)
        else
          emit_record_change(table_id, corrected)
        end
      end
      inserted ? record : nil
    rescue JSON::GeneratorError, JSON::ParserError
      nil
    end

    def emit_record_change(table_id, record)
      queue_discovery_publication(table_id, activity_only: true) if activity_record?(record)
      kind = record.packet["kind"].to_s
      data = record.packet["data"].to_h
      emit_presence_change if %w[room_created room_state game_started].include?(kind)
      case kind
      when "game_started"
        emit_change(table_id, :game_started, positive_identifier(data["session_id"]))
      when "game_action", "game_boundary"
        emit_change(table_id, :game, positive_identifier(data["session_id"]))
      else
        emit_change(table_id, :table, nil)
      end
    end

    def emit_change(table_id, kind, value)
      queue_discovery_publication(table_id) if kind == :table || kind == :game_started
      @changed&.call(table_id.to_i, kind.to_sym, value)
    rescue StandardError => error
      log_warning("change callback", table_id, error)
    end

    # Only schedule a coalesced census, never I/O for chat or gameplay packets.
    def emit_presence_change
      @presence_changed&.call
    rescue StandardError => error
      log_warning("presence callback", 0, error)
    end
  end

  include Writer
end
