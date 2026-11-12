require 'digest'
require_relative 'operation'
require_relative 'protocol'
require_relative 'metrics'
require_relative 'p2p_options'
require_relative 'errors'
require_relative 'endpoint_ownership'

module GameRoomRealtime
  # The only owner of Game Room's Communications endpoint. Sessions remain
  # private even for a public table. No per-frame network wait, retry loop,
  # background UI calls, application notifications, or original Pong service.
  class Channel
    RECEIVE_BATCH = 128
    SEQUENCE_HISTORY_LIMIT = 256
    attr_reader :epoch, :last_error, :last_exception, :internal_error

    def initialize(program:, match:, owner:, viewer:, clock:, members:, work: nil, work_factory: nil)
      @program, @match, @owner, @viewer = program, match, owner.to_s, viewer.to_s
      @clock, @members = clock, members
      @work = Operation.new(clock: clock, work: work, factory: work_factory)
      @generation = 0
      @closed = false
      @next_retry = 0.0
      @invite_after, @invite_attempts = {}, {}
      @invite_order, @invite_serial = {}, 0
      @incoming = {} # One newest packet per authenticated member, bounded by roster.
      @pending_invitation = nil
      @accepting_invitation = @accepted_invitation_key = nil
      @resource_lock = Mutex.new
      @endpoint_ownership = EndpointOwnership.for(program)
      @metrics = Metrics.new(clock: clock)
      @p2p_session_options = P2POptions.session_options({})
    end

    def host?; @owner.casecmp?(@viewer); end
    def connected?; @session != nil && @session.state == :open && @endpoint && !@endpoint.closed?; end

    def configure_p2p(options)
      return if @closed
      requested = P2POptions.session_options(options)
      return if requested == @p2p_session_options
      @p2p_session_options = requested
      # Normally configured before session creation. If options change while
      # setup is pending, use the existing generation-safe reconnect path.
      reconnect(reason: 'P2POptionsChanged') if @session || @work.kind == :session
    end

    # Native latency is the client-to-relay UDP RTT; p2p_status reports the
    # actual route and direct RTT separately for each current participant.
    # Both are cached, with freshness checked by the host. Never open an
    # endpoint, send probes or dispatch callbacks just to answer a shortcut.
    # nil means no active connection; nil relay_udp_ms means no valid UDP RTT
    # (e.g. TCP fallback), not zero latency or a measured TCP/peer round trip.
    def ping_sample
      endpoint, session = @endpoint, @session
      return if @closed || @reconnect_requested || !endpoint || !session ||
        session.state != :open || endpoint.closed?
      latency = endpoint.latency if endpoint.respond_to?(:latency) &&
        endpoint.respond_to?(:fast_path?) && endpoint.fast_path?
      milliseconds = (latency * 1000).round if latency.is_a?(Numeric) && latency.finite? && latency >= 0
      sample = { relay_udp_ms: milliseconds }
      if session.respond_to?(:p2p) && session.p2p != :off && session.respond_to?(:p2p_status)
        paths = session.p2p_status
        sample[:peers] = session.participants.filter_map do |participant|
          next if participant.id == session.self_id || !authorized?(participant.user)
          path = paths[participant.id] || {}
          direct = path[:transport] == :p2p
          rtt = path[:latency]
          peer_ms = (rtt * 1000).round if direct && rtt.is_a?(Numeric) && rtt.finite? && rtt >= 0
          { user: participant.user, transport: direct ? :p2p : :relay, p2p_ms: peer_ms }
        end
      end
      sample
    end

    def tick
      return if @closed
      raise @internal_error if @internal_error
      now = @clock.call
      @metrics.tick(endpoint: @endpoint, role: host? ? 'host' : 'guest', generation: @generation)
      complete_work(now)
      if @work.expired?
        @last_error = 'OperationTimeout'
        trace("#{@work.kind}_timeout")
        @work.kind == :depart ? @work.cancel : reconnect
      end
      # Closing the endpoint releases native waits. Do this before busy?, so
      # a setup/invitation with no answer cannot veto its own recovery.
      if @reconnect_requested
        @reconnect_requested = false
        reset_connection(now)
      elsif @endpoint && @endpoint.closed?
        reset_connection(now, delay: 0.0)
      end
      drain_invitations if @endpoint && !host? && !@endpoint.closed?
      drain_received_messages
      return if @work.busy?
      if @endpoint == nil || @endpoint.closed?
        return if now < @next_retry
        @next_retry = now + 1.0
        generation = @generation
        @work.start(:endpoint) do
          current = -> { @resource_lock.synchronize { !@closed && generation == @generation } }
          endpoint = @endpoint_ownership.open(current: current, owner: self) do |candidate|
            @resource_lock.synchronize do
              if @closed || generation != @generation
                false
              else
                @endpoint_ownership.claim(candidate, owner: self)
                @owned_endpoint = candidate
                true
              end
            end
          end
          [:endpoint, endpoint] if endpoint
        end
      elsif host? && !connected?
        return if now < @next_retry
        @next_retry = now + 1.0
        endpoint = @endpoint
        generation = @generation
        p2p_options = @p2p_session_options
        @work.start(:session) do
          session = endpoint.create_session(metadata: metadata, capacity: 32, public: false, encryption: 192, **p2p_options)
          if @closed || generation != @generation
            session.close
            nil
          else
            [:session, session]
          end
        end
      elsif !host? && @pending_invitation
        invitation = @pending_invitation
        unless invitation.status == :pending
          @pending_invitation = nil
          return
        end
        previous = @session
        generation = @generation
        @accepting_invitation = invitation
        started = @work.start(:accept) do
          # A queued worker may start after recovery/close or after native
          # cancellation. Do not begin an obsolete accept RPC.
          next nil if @closed || generation != @generation || invitation.status != :pending
          session = invitation.accept
          if @closed || generation != @generation
            session.leave
            nil
          else
            [:session, session, previous && !previous.equal?(session) ? previous : nil]
          end
        end
        if started
          @pending_invitation = nil if @pending_invitation.equal?(invitation)
        else
          @accepting_invitation = nil
        end
      elsif host? && connected?
        present = @session.participants.map { |p| p.user.downcase }
        members = allowed_members
        prune_invitation_history(members)
        candidates = members.select do |name|
          !present.include?(name.downcase) && !name.casecmp?(@viewer) && now >= @invite_after.fetch(name.downcase, 0.0)
        end
        priorities = invitation_priority_names
        missing = candidates.min_by do |name|
          [@invite_order.fetch(name.downcase, -1), priorities.include?(name.downcase) ? 0 : 1]
        end
        if missing
          key = missing.downcase
          attempt = @invite_attempts[key].to_i
          session = @session
          if @work.start(:invite) { session.invite(missing); [:invited, key] }
            @invite_attempts[key] = [attempt + 1, 3].min
            @inviting = [key, [0.5 * (2 ** attempt), 2.0].min]
            @invite_serial += 1
            @invite_order[key] = @invite_serial
            trace('invite_attempt')
          end
        end
      elsif @departing
        # Attach and register callbacks before the old session's departure RPC.
        # A slow or failed leave must not hold the new invitation hostage.
        previous = @departing
        started = @work.start(:depart) { previous.leave if previous.state == :open; nil }
        @departing = nil if started && @departing.equal?(previous)
      end
    rescue StandardError => error
      record_error(error, stage: :tick)
      reconnect(reason: 'TickFailed')
    end

    def send(data)
      raise @internal_error if @internal_error
      return false unless connected? && data.is_a?(String) && data.bytesize <= Protocol::MAX_BYTES
      targets = @session.participants.select do |p|
        p.id != @session.self_id && authorized?(p.user) && (host? || p.user.casecmp?(@owner))
      end
      return true if targets.empty?
      # Verified API queues TCP fallback without waiting; UDP is nonblocking.
      @session.send_unreliable(data, to: targets)
      true
    rescue StandardError => error
      record_error(error, stage: :send)
      false
    end

    def take_packets
      packets, @incoming = @incoming, {}
      packets
    end

    def reconnect(reason: nil)
      return if @internal_error
      @reconnect_reason ||= reason || @last_error || 'requested'
      @reconnect_requested = true
    end

    def close
      return if @closed
      endpoint = @resource_lock.synchronize do
        @closed = true
        owned = @owned_endpoint || @endpoint
        @owned_endpoint = nil
        owned
      end
      @incoming.clear
      @pending_invitation = nil
      @accepting_invitation = @accepted_invitation_key = nil
      @departing = nil
      # Closing a dedicated endpoint releases its sessions and callbacks. An
      # already-running finite setup operation checks @closed before returning.
      @work.close
      @session = @endpoint = nil
      dispose_endpoint(endpoint)
    end

    private

    def complete_work(now)
      if (result = @work.take)
        value, error, kind = result
        if kind == :invite && @inviting
          key, backoff = @inviting
          # Cooldown begins after the RPC, not while a slow request is pending.
          @invite_after[key] = now + (error ? backoff : 2.0)
          @inviting = nil
        end
        if kind == :accept
          @accepted_invitation_key = invitation_key(@accepting_invitation) if value.is_a?(Array) && value.first == :session
          @accepting_invitation = nil
        end
        if error
          record_error(error, stage: kind)
        end
        if value.is_a?(Array) && value.first == :endpoint
          @endpoint = value.last
          @next_retry = 0.0
          endpoint = @endpoint
          endpoint.on_invitation do |invitation|
            next if @closed || !@endpoint.equal?(endpoint)
            guarded_callback(:invitation) { consider_invitation(invitation) }
          end
          trace('endpoint_ready')
        elsif value.is_a?(Array) && value.first == :session
          attach(value[1])
          @departing = value[2]
        elsif value.is_a?(Array) && value.first == :invited
          trace('invite_sent')
        end
      end
    end

    def guarded_callback(stage)
      raise @internal_error if @internal_error
      yield
    rescue StandardError => error
      record_error(error, stage: stage)
      reconnect(reason: 'CallbackFailed')
    end

    # Preserve the exception across the worker boundary. Only native network
    # failures are recoverable; a broken operation stays stopped until close.
    def record_error(error, stage:)
      @last_exception = error
      @last_error = error.class.to_s
      if Errors.expected?(error)
        trace("#{stage}_failed", error: @last_error)
        return
      end
      unless @internal_error
        @internal_error = error
        if defined?(Log) && Log.respond_to?(:warning)
          Log.warning("Game Room Communications #{stage} generation=#{@generation}: #{error.class}: #{error.message}\n#{Array(error.backtrace).join("\n")}")
        end
      end
      raise @internal_error
    end

    def reset_connection(now, delay: 0.5)
      @resource_lock.synchronize { @generation += 1 }
      endpoint = release_ownership
      @session = @endpoint = @epoch = nil
      @incoming.clear
      @pending_invitation = nil
      @accepting_invitation = @accepted_invitation_key = nil
      @departing = nil
      @last_packet_at = nil
      @invite_after.clear
      @invite_attempts.clear
      @invite_order.clear
      @inviting = nil
      @next_retry = now + delay
      dispose_endpoint(endpoint)
      @work.cancel
      trace('reconnect', error: @reconnect_reason || @last_error || 'endpoint_closed')
      @reconnect_reason = nil
    end

    def trace(stage, error: nil)
      return unless defined?(Log) && Log.respond_to?(:debug)
      Log.debug("Game Room Communications #{stage} role=#{host? ? 'host' : 'guest'} generation=#{@generation} error=#{error || 'none'}")
    end

    def release_ownership
      @resource_lock.synchronize do
        endpoint = @owned_endpoint || @endpoint
        @owned_endpoint = nil
        endpoint
      end
    end

    def dispose_endpoint(endpoint)
      @endpoint_ownership.release(endpoint, owner: self)
    rescue StandardError => error
      record_error(error, stage: :dispose)
    end

    def metadata; { 'gr_realtime' => Protocol::VERSION, 'match' => @match }; end
    def allowed_members; @members.call.to_a.map(&:to_s).reject { |n| n.start_with?('bot:') }.uniq.first(32); end
    def invitation_priority_names; []; end
    def authorized?(name); allowed_members.any? { |candidate| candidate.casecmp?(name.to_s) }; end

    def prune_invitation_history(members)
      return if @invite_after.empty? && @invite_attempts.empty? && @invite_order.empty?
      current = members.map(&:downcase)
      [@invite_after, @invite_attempts, @invite_order].each do |history|
        history.delete_if { |name, _value| !current.include?(name) }
      end
    end

    # A departed user can return while an old authenticated packet is still
    # queued. Never evict its watermark within the same epoch. Bound historical
    # identities by using the existing recovery path before admitting another.
    def sequence_history_available?(sequences, key)
      return true if sequences.key?(key) || sequences.length < SEQUENCE_HISTORY_LIMIT
      reconnect(reason: 'SequenceHistoryFull')
      false
    end

    def drain_invitations
      # Invitations can precede registration of the UI callback while the
      # endpoint is being created. timeout: 0 is a verified non-pumping poll.
      8.times do
        invitation = @endpoint.next_invitation(timeout: 0)
        break unless invitation
        consider_invitation(invitation)
      end
    rescue StandardError => error
      record_error(error, stage: :invitations)
    end

    def consider_invitation(invitation)
      return if host? || @pending_invitation
      key = invitation_key(invitation)
      return if key == @accepted_invitation_key || (@accepting_invitation && key == invitation_key(@accepting_invitation))
      return if connected? && @last_packet_at && @clock.call - @last_packet_at < 2
      return unless invitation.sender.user.to_s.casecmp?(@owner)
      return unless invitation.session_metadata == metadata && invitation.status == :pending
      @pending_invitation = invitation
    end

    def invitation_key(invitation)
      return unless invitation
      id = invitation.id.to_s if invitation.respond_to?(:id)
      id && !id.empty? ? [:id, id] : [:object, invitation.object_id]
    end

    # Session.receive(timeout: 0) drains only already received local messages.
    # In ELTEN it neither waits nor pumps the UI or performs an RPC. A message
    # arriving after the native callback pass need not wait another UI cycle.
    # Keep callbacks as well: both paths share authentication and sequence
    # guards, so whichever arrives second cannot apply the same packet twice.
    def drain_received_messages
      session = @session
      return unless connected? && session.respond_to?(:receive)
      RECEIVE_BATCH.times do
        break if @closed || @reconnect_requested || !session.equal?(@session)
        item = session.receive(timeout: 0)
        break unless item
        kind, message = item
        receive_message(session, kind, message)
      end
    rescue StandardError => error
      return if @closed || !session.equal?(@session)
      record_error(error, stage: :receive)
      reconnect(reason: 'ReceiveFailed')
    end

    def receive_message(session, kind, message)
      return if @closed || @reconnect_requested || !@session.equal?(session) || kind != :unreliable
      sender = message.sender.user.to_s
      return unless authorized?(sender) && (host? || sender.casecmp?(@owner))
      packet = Protocol.decode(message.data, match: @match, epoch: @epoch)
      return unless packet && packet['k'] == (host? ? 'input' : 'state')
      key = sender.downcase
      return if packet['n'] <= @received_sequences.fetch(key, -1)
      return unless sequence_history_available?(@received_sequences, key)
      @received_sequences[key] = packet['n']
      @incoming[key] = packet
      @last_packet_at = @clock.call
      @last_error = nil
    end

    def attach(session)
      @session = session
      @last_error = nil
      @epoch = Digest::SHA256.hexdigest(session.id.to_s)[0, 16]
      @incoming.clear
      @invite_after.clear
      @invite_attempts.clear
      @invite_order.clear
      @inviting = nil
      @last_packet_at = nil
      @received_sequences = {}
      session.on_unreliable do |message|
        next if @closed || !@session.equal?(session)
        guarded_callback(:message) { receive_message(session, :unreliable, message) }
      end
      session.on_owner_changed { |_owner| reconnect(reason: 'OwnerChanged') unless @closed || !@session.equal?(session) }
      trace('session_ready')
    end
  end
end
