require_relative 'host_bridge'
require_relative 'game_room_notifications'
require "thread"

# A durable reply is still needed when the invited person has no room connection.
# It is an application receipt, not a user notification. Only our two receipt
# types and internal tournament wakes are filtered; ordinary invitations and
# all other applications are intact.
module GameRoomInvitationReceipts
  TYPES = %w[game_room.invitation_resolved game_room.invitation_rejected].freeze
  LOCK = Mutex.new
  INFLIGHT = {}
  MAX_INFLIGHT = 16

  # The host owns this resource only while the application is registered.
  # Closing an old runtime must not remove a replacement with the same UUID.
  class Registration
    def initialize(program, uuid)
      @program, @uuid = program, uuid
    end

    def close
      program, @program = @program, nil
      return unless program
      host = ::NotificationGroups
      GameRoomHostBridge.registry(host, key: :@game_room_receipt_programs,
        lock: :@game_room_receipt_registry_lock, initial: {}) do |registry|
        registry.delete(@uuid) if registry[@uuid].equal?(program)
      end
      if program.instance_variable_get(:@game_room_receipt_registration).equal?(self)
        program.remove_instance_variable(:@game_room_receipt_registration)
      end
      program.release(self) if program.respond_to?(:release)
    end
  end

  module_function

  def install(program)
    return unless defined?(NotificationGroups) && program.respond_to?(:server_app_uuid)

    uuid = program.server_app_uuid.to_s.downcase
    return if uuid.empty?

    host = ::NotificationGroups
    GameRoomHostBridge.registry(host, key: :@game_room_receipt_programs,
      lock: :@game_room_receipt_registry_lock, initial: {}) { |registry| registry[uuid] = program }
    unless program.instance_variable_get(:@game_room_receipt_registration)
      registration = Registration.new(program, uuid)
      program.instance_variable_set(:@game_room_receipt_registration, registration)
      if program.respond_to?(:manage) && (!program.respond_to?(:app_runtime) || program.app_runtime)
        program.manage(registration)
      end
    end
    return if host.instance_variable_get(:@game_room_receipt_bridge_version) == 4

    GameRoomHostBridge.prepare(host, marker: :@game_room_receipt_bridge,
      method_name: :build_notification_groups, source: '/lib/invitation_receipts.rb')
    # Replace legacy lexical bodies as well: merely reusing their module
    # would still retain the first application namespace.
    TOPLEVEL_BINDING.eval(<<~'RUBY', __FILE__, __LINE__ + 1)
      ::NotificationGroups.instance_variable_get(:@game_room_receipt_bridge).module_eval do
        def build_notification_groups(notifications, **options)
          host = ::NotificationGroups
          registry = host.instance_variable_get(:@game_room_receipt_registry_lock).synchronize do
            host.instance_variable_get(:@game_room_receipt_programs).dup
          end
          visible = notifications.reject do |row|
            program = row.cat.to_s == "app" ? registry[row.app_uuid.to_s.downcase] : nil
            payload = row.payload.is_a?(Hash) ? row.payload : {}
            type = (payload["type"] || payload[:type]).to_s
            hidden = program != nil && %w[game_room.invitation_resolved game_room.invitation_rejected].include?(type)
            if hidden && row.revoked != true
              program.receive_invitation_receipt(::Programs.app_notification_from(row))
            end
            # suppress_default! silences delivery, not the host's list. A wake
            # has no user action/text, including in read history. Its ordinary
            # receipt callback still updates tournaments; a list redraw must
            # not replay that callback or start another server read.
            hidden ||= program != nil && type == "game_room.tournament_changed"
            if program != nil && type.start_with?("game_room.tournament_") && program.respond_to?(:game_room_notification_current?)
              hidden ||= program.game_room_notification_current?(::Programs.app_notification_from(row)) == false
            end
            if program != nil && type == "game_room.table_created" && program.respond_to?(:table_notice_visible?)
              hidden ||= !program.table_notice_visible?(::Programs.app_notification_from(row))
            end
            if program != nil && type == "game_room.invitation" && program.respond_to?(:contact_notification_allowed?)
              hidden ||= program.contact_notification_allowed?(::Programs.app_notification_from(row)) != true
            end
            hidden
          end
          super(visible, **options)
        end
      end
    RUBY
    host.instance_variable_set(:@game_room_receipt_bridge_version, 4)
  end

  def enqueue(program, notification)
    return false unless TYPES.include?(notification.type.to_s) && notification.id.to_i.positive?

    user = Session.name.to_s
    enqueue_work(program, [user.downcase, :receipt, notification.id.to_i]) do
      process(program, notification, user: user)
    end
  end

  def retry_history(program, writer)
    user = Session.name.to_s
    enqueue_work(program, [user.downcase, :history, writer.object_id]) do
      writer.record("invited") if Session.name.to_s.casecmp(user) == 0
    end
  end

  def enqueue_work(program, key, &operation)
    claimed = LOCK.synchronize do
      next false if INFLIGHT.key?(key) || INFLIGHT.size >= MAX_INFLIGHT

      INFLIGHT[key] = true
    end
    return false unless claimed

    runtime = Programs.runtime_for(program) if defined?(Programs) && Programs.respond_to?(:runtime_for)
    runtime ||= Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
    Thread.new do
      Thread.current.report_on_exception = false
      work = lambda do
        # Event-driven, bounded retries; no notification polling or UI callbacks.
        attempts = 0
        begin
          operation.call
        rescue StandardError => error
          attempts += 1
          if attempts < 3 && GameRoomNetworkErrors.transient?(error)
            sleep(attempts * 0.5)
            retry
          end
          Log.warning("ELTEN Game Room invitation receipt failed: #{error.class}") if defined?(Log)
        end
      end
      if runtime != nil && Programs.respond_to?(:with_runtime)
        Programs.with_runtime(runtime) { work.call }
      else
        work.call
      end
    ensure
      LOCK.synchronize { INFLIGHT.delete(key) }
    end
    true
  rescue StandardError
    LOCK.synchronize { INFLIGHT.delete(key) } if defined?(key)
    raise
  end

  def process(program, notification, user: Session.name.to_s, gateway: EltenLink::Notifications, client: nil)
    return false if Session.name.to_s.casecmp(user.to_s) != 0
    return false unless notification.app_uuid.to_s.casecmp(program.server_app_uuid.to_s) == 0 &&
      TYPES.include?(notification.type.to_s) && notification.id.to_i.positive?

    metadata = notification.metadata.to_h
    recipient = metadata["user"].to_s
    if !recipient.empty? && recipient.casecmp(notification.sender.to_s) == 0
      row = InvitationRepository.sent_for_receipt(metadata["invitation_id"], table_id: metadata["table_id"],
        recipient: recipient, sender: user, live_session_id: metadata["live_session_id"])
      response = metadata["response"].to_s
      if row != nil && InvitationRepository::RESPONSES.include?(response)
        history = row["__history_writer"]
        history&.record("invited")
        history&.record("invitation_rejected") if response == "rejected"
        return false if Session.name.to_s.casecmp(user.to_s) != 0
        GameRoomNotifications.revoke_invitation(program, row)
        return false if Session.name.to_s.casecmp(user.to_s) != 0
        InvitationRepository.resolve_sent(row)
      end
    end
    # Also consume old duplicate rejection notices; never fabricate a room event
    # from them, since they did not carry the exact invitation identity.
    return false if Session.name.to_s.casecmp(user.to_s) != 0
    gateway.revoke(client || EltenLink::Client.new, notification.id.to_i)
    if defined?(EltenAPI::NotificationService) && EltenAPI::NotificationService.respond_to?(:revoke_active_notifications)
      EltenAPI::NotificationService.revoke_active_notifications([notification.id.to_i])
    end
    true
  end

  class HistoryWriter
    def initialize(repository:, table:, invitation:)
      @repository, @table, @invitation = repository, table.dup, invitation
      @lock = Mutex.new
      @written = {}
    end

    def record(kind)
      @lock.synchronize do
        return true if @written[kind]
        return false if @closed
        return false if Session.name.to_s.casecmp(@invitation["sender"].to_s) != 0

        @repository.append(table: @table, kind: kind, actor: @invitation["sender"],
          subject: @invitation["recipient"], invitation_id: @invitation["__id"])
        @written[kind] = true
      end
    rescue ArgumentError => error
      raise unless error.message == "The room is no longer active"

      @closed = true
      false
    rescue EltenAPI::LiveSessions::SessionClosed
      @closed = true
      false
    end
  end
end
