# Local experiment only. Nothing in __app.rb loads this directory.
#
# Input -> existing Uno#action_for -> reliable request -> SERVER order/echo
# -> contiguous receipt prefix -> existing Uno#replay -> presentation data.
# No player, including the master, orders or relays another player's move.
#
# ORDERED_CONTRACT is a requirement of this experiment, NOT an existing Elten
# API capability. An adapter must supply authenticated, immutable receipts,
# including the sender's own messages, and recover the SAME numbered prefix.
# Native EventChannel provides per-sender order and does not satisfy it yet.
# The included relay is an in-memory simulation, not evidence about Elten's
# relay. There is deliberately no silent fallback to receive-order or a host.
#
# Not implemented here: a native transport/UI hook, durable checkpoints,
# membership/master changes inside a stream, or a second bot scheduler.
# A changed match/control epoch requires a new client and authoritative state.
require 'json'
require 'securerandom'
require_relative '../../games/uno'
require_relative '../../lib/game_repository'
require_relative '../../lib/game_snapshot'

module GameRoomUnoCommunicationsPrototype
  ORDERED_CONTRACT = 'uno-prototype/server-ordered-echo-and-recovery-v1'.freeze
  REACTION_OPTIONS = %w[interceptions super_interceptions straights buzzers].freeze
  MAX_PACKET_BYTES = 4_096
  MAX_RECEIPTS = 4_096
  MAX_GAP = 128

  class UnsupportedOrdering < StandardError; end
  class ProtocolError < StandardError; end
  class TransportUnavailable < StandardError; end
  class CapacityExceeded < StandardError; end

  # This metadata must come from the trusted transport, NEVER a peer's JSON.
  Receipt = Struct.new(:identity, :sequence, :sender, :request_id, :data, keyword_init: true)

  def self.mode_for(game:, options:)
    return :live_sessions unless game.is_a?(GameRoomGames::Uno)
    values = game.normalize_options(options)
    enabled = game.option_definitions.any? do |definition|
      REACTION_OPTIONS.include?(definition.key) && values[definition.key] == true &&
        game.option_visible?(definition, values)
    end
    enabled ? :communications : :live_sessions
  end

  def self.identity_for(session)
    identity = GameRoomSessionContracts::SessionIdentity.from_row(session)
    unless identity.table_id.positive? && identity.session_id.positive? && identity.control_epoch != nil
      raise ArgumentError, 'A confirmed match and control epoch are required'
    end
    JSON.generate([identity.table_id, identity.session_id, identity.control_epoch]).freeze
  end

  class Client
    attr_reader :cursor, :last_outcome, :identity, :fault

    # Returning nil means that the caller keeps the existing LiveSessions
    # runner. In particular, the factory is never called for ordinary UNO.
    def self.build(game:, session:, viewer:, endpoint_factory:, **options)
      values = JSON.parse(session.fetch('options'))
      return nil unless GameRoomUnoCommunicationsPrototype.mode_for(game: game, options: values) == :communications
      identity = GameRoomUnoCommunicationsPrototype.identity_for(session)
      endpoint = endpoint_factory.call(identity, viewer)
      new(game: game, session: session, viewer: viewer, endpoint: endpoint, **options)
    end

    def initialize(game:, session:, viewer:, endpoint:, repository: nil)
      @game, @session, @viewer = game, GameRoomSnapshot.copy(session), viewer.to_s
      @identity = GameRoomUnoCommunicationsPrototype.identity_for(@session)
      @repository = repository || GameRepository.new(nil, transport: Object.new)
      @players = @repository.players_for(@session)
      @owner = @session.fetch('__table_owner')
      @endpoint = checked_endpoint(endpoint)
      @events, @receipts, @requests, @buffer = [], {}, {}, {}
      @cursor, @pending, @closed, @needs_recovery = 0, nil, false, false
      @replay = @game.replay(@session, @events, @repository)
    end

    def replay; GameRoomSnapshot.copy(@replay); end
    def events; GameRoomSnapshot.copy(@events); end
    def pending?; @pending != nil; end
    def recovering?; @needs_recovery || !@buffer.empty?; end

    def submit(selection, context:, actor: @viewer, controller: false)
      return :closed if @closed
      return :failed if @fault
      return :waiting if pending? || recovering?
      return :forbidden unless authorized?(@viewer, actor, controller)
      status, plan = @game.action_for(selection, @replay, actor, context: context)
      return status unless status == :ok
      commands = plan.events.map { |event| GameRoomEventProtocol.normalized(event) }
      GameRoomEventProtocol.validate_commands!(commands)
      raise ProtocolError, 'This UNO prototype expects one event per action' unless commands.one?
      data = JSON.generate('version' => 1, 'round' => @replay.state.fetch(:round),
        'actor' => actor, 'controller' => controller, 'command' => commands.first)
      raise CapacityExceeded, 'The move packet is too large' if data.bytesize > MAX_PACKET_BYTES
      # Store before sending: a timeout does not prove that the relay rejected
      # the move. A retry keeps both its ID and its original RNG/deadline.
      @pending = [SecureRandom.uuid.freeze, data.freeze]
      retry_pending
    end

    def retry_pending
      return :closed if @closed
      return :failed if @fault
      return :idle unless @pending
      @endpoint.publish(*@pending)
      :pending
    rescue TransportUnavailable
      :uncertain
    end

    def tick
      return if @closed || @fault
      @endpoint.drain.each { |receipt| receive(receipt) }
      recover if recovering?
    rescue TransportUnavailable
      @needs_recovery = true
      :unavailable
    rescue ProtocolError, CapacityExceeded => error
      @fault = error
      raise
    end

    def recover
      return :closed if @closed
      return :failed if @fault
      @needs_recovery = true
      # Recovery must disclose its head even when the final message (and not
      # just a message in the middle) was lost. No periodic polling is added.
      head, receipts = @endpoint.recover_after(@cursor)
      raise ProtocolError, 'Invalid recovery head' unless head.is_a?(Integer) && head >= @cursor
      receipts.each { |receipt| receive(receipt) }
      @needs_recovery = @cursor != head || !@buffer.empty?
      @needs_recovery ? :incomplete : :ready
    rescue TransportUnavailable
      :unavailable
    rescue ProtocolError, CapacityExceeded => error
      @fault = error
      raise
    end

    def reconnect(endpoint)
      return :closed if @closed
      @endpoint = checked_endpoint(endpoint)
      recover
    end

    def close
      @closed = true
      @buffer.clear
      @pending = nil
    end

    private

    def checked_endpoint(endpoint)
      unless endpoint.respond_to?(:contract) && endpoint.contract == ORDERED_CONTRACT
        raise UnsupportedOrdering, 'Native Communications has no verified common server order/echo contract'
      end
      unless endpoint.identity == @identity && GameRoomParticipants.same?(endpoint.user, @viewer)
        raise ProtocolError, 'The endpoint belongs to another match or account'
      end
      endpoint
    end

    def authorized?(sender, actor, controller)
      return false unless @players.any? { |player| GameRoomParticipants.same?(player, actor) }
      if GameRoomParticipants.bot?(actor) || controller == true
        GameRoomParticipants.same?(sender, @owner)
      else
        GameRoomParticipants.same?(sender, actor)
      end
    end

    def receive(receipt)
      return unless receipt.is_a?(Receipt) && receipt.identity == @identity
      seq = receipt.sequence
      unless seq.is_a?(Integer) && seq.positive? && receipt.sender.is_a?(String) && receipt.sender.length.between?(1, 64) &&
          receipt.request_id.is_a?(String) && receipt.request_id.length.between?(1, 128) && receipt.data.is_a?(String)
        raise ProtocolError, 'Invalid ordered receipt'
      end
      # A trusted transport violating the packet bound cannot supply a usable
      # ordered prefix. Fail as for journal/gap overflow before copying bytes.
      raise CapacityExceeded, 'The ordered receipt packet is too large' if receipt.data.bytesize > MAX_PACKET_BYTES
      raise CapacityExceeded, 'Prototype journal limit reached' if seq > MAX_RECEIPTS
      prior = @receipts[seq] || @buffer[seq]
      raise ProtocolError, 'The relay changed an assigned receipt' if prior && prior != receipt
      return if seq <= @cursor
      raise CapacityExceeded, 'The gap is too large to buffer' if seq > @cursor + MAX_GAP
      @buffer[seq] = Receipt.new(identity: receipt.identity.dup.freeze, sequence: seq,
        sender: receipt.sender.dup.freeze, request_id: receipt.request_id.dup.freeze,
        data: receipt.data.dup.freeze).freeze
      while (next_receipt = @buffer.delete(@cursor + 1))
        apply_receipt(next_receipt)
        @receipts[next_receipt.sequence] = next_receipt
        @cursor = next_receipt.sequence
      end
    end

    def apply_receipt(receipt)
      own_echo = GameRoomParticipants.same?(receipt.sender, @viewer) && @pending && @pending.first == receipt.request_id
      raise ProtocolError, 'The own echo differs from the submitted move' if own_echo && @pending.last != receipt.data
      key = [receipt.sender.downcase, receipt.request_id]
      previous = @requests[key]
      raise ProtocolError, 'A request ID was reused for another move' if previous && previous != receipt.data
      status = previous ? :duplicate : apply_command(receipt)
      @requests[key] = receipt.data
      @last_outcome = { sequence: receipt.sequence, sender: receipt.sender,
        request_id: receipt.request_id, status: status }.freeze
      @pending = nil if own_echo
    end

    def apply_command(receipt)
      begin
        packet = JSON.parse(receipt.data, max_nesting: 8)
      rescue JSON::ParserError
        return :malformed
      end
      return :malformed unless valid_packet?(packet)
      return :forbidden unless authorized?(receipt.sender, packet['actor'], packet['controller'])
      return :stale_round unless packet['round'] == @replay.state[:round]
      command = packet.fetch('command')
      # Keep the ordinary repository's author/controller checks and the
      # ordinary replay's rule validation, including late-interception fees.
      event = { '__id' => receipt.sequence, 'sequence' => receipt.sequence,
        '__insertion_user' => receipt.sender, '__authority_user' => @owner,
        '__controller' => packet['controller'], 'actor' => packet['actor'],
        'action' => command['action'], 'value' => command['value'] }
      next_events = @events + [event]
      next_replay = @game.replay(@session, next_events, @repository)
      @events, @replay = next_events, next_replay
      @replay.accepted_events.any? { |entry| @repository.event_id(entry) == receipt.sequence } ? :applied : :rejected
    end

    def valid_packet?(packet)
      packet.is_a?(Hash) && packet.keys.sort == %w[actor command controller round version] &&
        packet['version'] == 1 && packet['round'].is_a?(Integer) && packet['round'] >= 0 &&
        packet['actor'].is_a?(String) && packet['actor'].length.between?(1, 64) &&
        [true, false].include?(packet['controller']) &&
        GameRoomEventProtocol.valid_wire_command?(packet['command'])
    end
  end
end
