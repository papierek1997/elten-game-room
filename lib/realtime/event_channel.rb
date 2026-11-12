require_relative 'channel'

module GameRoomRealtime
  # Optional ordered lane for actions which cannot be replaced by a newer
  # position. Reliable RPC is finite background work, never a wait in a frame.
  class EventChannel < Channel
    LIMIT = 128
    attr_writer :required_members

    def initialize(event_work: nil, event_work_factory: nil, **args)
      super(**args)
      @event_work = Operation.new(clock: @clock, work: event_work, factory: event_work_factory)
      @event_outbox, @event_inbox = [], []
      @deliveries = []
      @event_generation = 0
    end

    # Default remains owner-mediated for other consumers. A peer game must
    # select a different wire dialect and authenticate actors in its rules.
    def enable_events(mode = 'pong-local-1', routing: :owner)
      raise ArgumentError, 'unknown event routing' unless [:owner, :peers].include?(routing)
      @event_protocol, @event_routing = mode, routing
    end

    def required_members_present?
      connected? && missing_required(required_names, event_targets).empty?
    end

    def tick
      super
      dispatch_events
    rescue StandardError => error
      record_error(error, stage: :event_tick)
      reconnect(reason: 'EventTickFailed')
    end

    def send_event(data)
      raise @internal_error if @internal_error
      return false unless !@closed && !@reconnect_requested && @event_protocol && connected? && data.is_a?(String) && data.bytesize <= Protocol::MAX_BYTES
      required = required_names
      return true if event_targets.empty? && required.empty?
      if @event_outbox.length >= LIMIT
        reconnect(reason: 'ReliableOutboxFull')
        return false
      end
      @event_outbox << [@session, @event_generation, data.dup.freeze, required, @clock.call]
      # Starting a finite worker does not run its RPC on this UI thread. Do
      # not wait for another form tick; also collect a completed prior send
      # before reusing its worker, preserving deliveries and FIFO ordering.
      dispatch_events
      !@closed && !@reconnect_requested
    rescue StandardError => error
      record_error(error, stage: :event_send)
      reconnect(reason: 'EventSendFailed')
      false
    end

    def take_events
      result, @event_inbox = @event_inbox, []
      result.map do |sender, packet, received_at|
        @metrics.observe(:receive_wait, @clock.call - received_at)
        [sender, packet]
      end
    end

    def reconnect(reason: nil)
      return if @internal_error || @reconnect_requested || @closed
      invalidate_events
      @event_work.cancel
      super(reason: reason)
    end

    def close
      invalidate_events
      @event_work.close
      super
    end

    private

    def dispatch_events
      return if @closed || @reconnect_requested
      if (result = @event_work.take)
        value, error = result
        if value.is_a?(Array) && value[0] == @event_generation && value[1] == :recipients_missing && !@closed
          @event_outbox.length >= LIMIT ? reconnect(reason: 'ReliableOutboxFull') : @event_outbox.unshift(value[2])
        elsif value.is_a?(Array) && value[0] == @event_generation && value[1] && !@closed
          record_error(value[1], stage: :reliable)
          reconnect
        elsif error && !@closed
          record_error(error, stage: :reliable_worker)
          reconnect
        elsif value.is_a?(Array) && value[0] == @event_generation && !@closed
          @metrics.observe(:queue_wait, value[4])
          @metrics.observe(:send_rpc, value[5])
          if value[2].respond_to?(:results)
            @deliveries << [value[2], @clock.call, value[3]]
          elsif value[2] != :no_recipients
            reconnect(reason: 'MissingReliableDeliveryResult')
          end
        end
      end
      if @event_work.expired?
        @last_error = 'ReliableSendTimeout'
        trace('reliable_send_timeout')
        reconnect
      end
      @deliveries.delete_if do |delivery, started_at, required_ids|
        by_id = delivery.results.to_h do |recipient, status|
          id = recipient.respond_to?(:id) ? recipient.id.to_s : recipient.to_s
          [id, status]
        end
        # A missing status is pending, not success for an empty subset.
        statuses = required_ids.map { |id| by_id.fetch(id, :pending) }
        failed = statuses.any? { |status| ![:pending, :delivered].include?(status) }
        expired = statuses.include?(:pending) && @clock.call - started_at >= Operation::TIMEOUT
        if failed || expired
          @last_error = failed ? 'ReliableDeliveryFailed' : 'ReliableDeliveryTimeout'
          trace('delivery_failed', error: @last_error)
          reconnect
          break
        end
        !statuses.include?(:pending)
      end
      return if @closed || @reconnect_requested || !connected? || @event_work.busy? || @event_outbox.empty?
      if @deliveries.length >= LIMIT
        reconnect(reason: 'ReliableDeliveryQueueFull')
        return
      end
      entry = @event_outbox.first
      session, generation, data, required, queued_at = entry
      unless session.equal?(@session) && generation == @event_generation
        @event_outbox.shift
        return
      end
      unless missing_required(required, event_targets).empty?
        if @clock.call - queued_at >= Operation::TIMEOUT
          reconnect(reason: 'RequiredRecipientMissing')
        end
        return
      end
      allowed = allowed_members.map(&:downcase).freeze
      started = @event_work.start(:reliable) do
        begin
          # A scheduled worker may not run until after close/recovery. Do not
          # begin an obsolete write; an RPC already in flight is never killed.
          next nil if @closed || @reconnect_requested || generation != @event_generation || !session.equal?(@session)
          # Resolve IDs again in the finite worker: the native membership can
          # change between enqueuing the action and performing the actual RPC.
          targets = event_targets(session, allowed: allowed)
          if missing_required(required, targets).empty?
            required_ids = targets.select { |target| required.include?(target.user.to_s.downcase) }.map { |target| target.id.to_s }
            at = @clock.call
            delivery = targets.empty? ? :no_recipients : session.send_reliable(data, to: targets)
            [generation, nil, delivery, required_ids, at - queued_at, @clock.call - at]
          else
            [generation, :recipients_missing, entry]
          end
        rescue StandardError => error
          # Keep the generation even on failure: an old send must not tear
          # down a replacement channel which already works.
          [generation, error]
        end
      end
      @event_outbox.shift if started
    end

    def event_targets(session = @session, allowed: nil)
      return [] unless session
      allowed ||= allowed_members.map(&:downcase)
      session.participants.select do |p|
        p.id != session.self_id && allowed.include?(p.user.to_s.downcase) &&
          (@event_routing == :peers || host? || p.user.to_s.casecmp?(@owner))
      end
    end

    def required_names
      names = @required_members || event_targets.map(&:user)
      names.map { |name| name.to_s.downcase }.reject { |name| name.casecmp?(@viewer) }.uniq.freeze
    end

    def invitation_priority_names; required_names; end

    def missing_required(names, targets)
      names - targets.map { |target| target.user.to_s.downcase }
    end

    def reset_connection(now, **options)
      invalidate_events
      @event_work.cancel
      super
    end

    def invalidate_events
      @event_generation += 1
      @event_outbox.clear
      @event_inbox.clear
      @deliveries.clear
    end

    def metadata
      data = super
      data['events'] = @event_protocol if @event_protocol
      data
    end

    def receive_message(session, kind, message)
      return super unless kind == :reliable
      return if @closed || @reconnect_requested || !@session.equal?(session) || !@event_protocol
      sender = message.sender.user.to_s
      return unless authorized?(sender) && (@event_routing == :peers || host? || sender.casecmp?(@owner))
      packet = Protocol.decode(message.data, match: @match, epoch: @epoch)
      return unless packet && packet['k'] == 'event'
      key = sender.downcase
      return if packet['n'] <= @event_sequences.fetch(key, -1)
      if @event_sequences.key?(key) && packet['n'] != @event_sequences[key] + 1
        @last_error = 'ReliableSequenceGap'
        trace('reliable_sequence_gap')
        reconnect(reason: 'ReliableSequenceGap')
        return
      end
      if @event_inbox.length >= LIMIT
        reconnect(reason: 'ReliableInboxFull')
        return
      end
      return unless sequence_history_available?(@event_sequences, key)
      @event_sequences[key] = packet['n']
      @event_inbox << [key, packet, @clock.call]
      @last_packet_at = @clock.call
    end

    def attach(session)
      super
      invalidate_events
      @event_sequences = {}
      return unless @event_protocol
      session.on_reliable do |message|
        next if @closed || !@session.equal?(session)
        guarded_callback(:reliable_message) { receive_message(session, :reliable, message) }
      end
    end
  end
end
