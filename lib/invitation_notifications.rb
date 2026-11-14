require_relative "game_room_clock"
require_relative "notification_time"
require_relative "invitation_identity"
class InvitationNotifications
  NOTIFICATION_TYPE = "game_room.invitation".freeze

  def initialize(client:, app_uuid:, gateway: nil, current_user: -> { defined?(Session) ? Session.name.to_s : "" })
    @client = client
    @app_uuid = app_uuid.to_s
    @gateway = gateway || EltenLink::Notifications
    @current_user = current_user
  end

  # ELTEN marks a notification as read after scheduling NotificationActionScene,
  # before that scene creates our fresh program. Reading is not an invitation
  # response. Retain only the notification explicitly opened by the host, and
  # only while selecting/checking that invitation (never the whole program UI).
  def with_opened(notification)
    previous = @opened_notification
    previous_user = @opened_user
    @opened_notification = notification
    @opened_user = @current_user.call.to_s
    yield
  ensure
    @opened_notification = previous
    @opened_user = previous_user
  end

  def revoke(reference, notification_id: nil)
    user = @current_user.call.to_s
    recipient = GameRoomInvitationIdentity.row(reference)["recipient"].to_s
    return 0 unless user.empty? || recipient.empty? || user.casecmp?(recipient)

    direct_id = notification_id.to_i
    if direct_id > 0
      @gateway.revoke(@client, direct_id)
      return 1
    end

    return 0 unless GameRoomInvitationIdentity.id(reference).positive?

    notifications = @gateway
      .list(@client, all: false, app_uuids: [@app_uuid])
      .to_a
    return 0 unless @current_user.call.to_s.casecmp?(user)
    matches = notifications.filter_map do |notification|
      row = identity_row(notification, recipient: user)
      [notification, row] if row && GameRoomInvitationIdentity.matches?(row, reference)
    end
    # A legacy ID alone cannot disambiguate different rooms or senders.
    return 0 unless matches.map { |_notice, row| GameRoomInvitationIdentity.key(row) }.uniq.size == 1
    ids = matches.filter_map { |notice, _row| notification_id(notice) }.uniq
    return 0 if ids.empty?

    @gateway.revoke_many(@client, ids)
    ids.length
  end

  def revoke_for_table(table_id, live_session_id: nil)
    wanted = table_id.to_i
    return 0 if wanted <= 0

    user = @current_user.call.to_s
    ids = @gateway
      .list(@client, all: false, app_uuids: [@app_uuid])
      .to_a
      .filter_map { |notification| matching_table_notification_id(notification, wanted, live_session_id) }
      .uniq
    return 0 unless @current_user.call.to_s.casecmp?(user)
    return 0 if ids.empty?

    @gateway.revoke_many(@client, ids)
    ids.length
  end

  def pending(recipient:, now: GameRoomClock.now.to_i)
    user = @current_user.call.to_s
    return [] unless user.empty? || user.casecmp?(recipient.to_s)
    rows = @gateway.list(@client, all: false, app_uuids: [@app_uuid]).to_a.filter_map do |notification|
      pending_row(notification, recipient: recipient, now: now)
    end
    return [] unless @current_user.call.to_s.casecmp?(user)
    opened = pending_row(@opened_notification, recipient: recipient, now: now, allow_read: true) if @opened_user == user
    ([opened] + rows).compact.uniq { |row| GameRoomInvitationIdentity.key(row) }
  end

  private

  def pending_row(notification, recipient:, now:, allow_read: false)
    return nil if notification == nil || (allow_read && notification_id(notification) == nil)

    metadata = invitation_metadata(notification, allow_read: allow_read)
    return nil if metadata == nil
    expiration = GameRoomNotificationTime.expires_at(notification, metadata)
    return nil if expiration <= now.to_i
    return nil if hash_value(metadata, "invitation_id").to_i <= 0 || hash_value(metadata, "table_id").to_i <= 0
    return nil if hash_value(metadata, "live_session_id").to_s.empty?

    {
      "__id" => hash_value(metadata, "invitation_id").to_i,
      "table_id" => hash_value(metadata, "table_id").to_i,
      "live_session_id" => hash_value(metadata, "live_session_id").to_s,
      "sender" => GameRoomInvitationIdentity.notification_sender(notification, metadata),
      "recipient" => recipient.to_s,
      "created_at" => GameRoomNotificationTime.created_at(notification) || hash_value(metadata, "created_at").to_i,
      "expires_at" => expiration,
      "notification_id" => notification_id(notification),
      "status" => "pending"
    }
  end

  def identity_row(notification, recipient:)
    metadata = invitation_metadata(notification)
    return nil if metadata == nil

    { "__id" => hash_value(metadata, "invitation_id"), "table_id" => hash_value(metadata, "table_id"),
      "live_session_id" => hash_value(metadata, "live_session_id"),
      "sender" => GameRoomInvitationIdentity.notification_sender(notification, metadata), "recipient" => recipient }
  end

  def matching_table_notification_id(notification, table_id, live_session_id)
    metadata = invitation_metadata(notification)
    if metadata == nil && same_app?(notification) && defined?(GameRoomTableWatch)
      payload = notification.respond_to?(:payload) ? notification.payload : nil
      if payload.is_a?(Hash) && hash_value(payload, "type") == GameRoomTableWatch::TYPE
        value = hash_value(payload, "metadata")
        metadata = value if value.is_a?(Hash) && !live_session_id.to_s.empty? && hash_value(value, "live_session_id").to_s == live_session_id.to_s
      end
    end
    return nil if metadata == nil
    return nil unless GameRoomNotificationTime.integer_value?(hash_value(metadata, "table_id"))
    return nil if hash_value(metadata, "table_id").to_i != table_id
    native_id = hash_value(metadata, "live_session_id").to_s
    return nil if !live_session_id.to_s.empty? && !native_id.empty? && native_id != live_session_id.to_s

    notification_id(notification)
  end

  def invitation_metadata(notification, allow_read: false)
    return nil if !allow_read && notification.respond_to?(:revoked) && notification.revoked == true
    return nil if !same_app?(notification)

    type = notification.respond_to?(:type) ? notification.type.to_s : ""
    metadata = notification.respond_to?(:metadata) ? notification.metadata : nil
    if type.empty? || !metadata.is_a?(Hash)
      payload = notification.respond_to?(:payload) ? notification.payload : nil
      return nil if !payload.is_a?(Hash)
      type = hash_value(payload, "type").to_s
      metadata = hash_value(payload, "metadata")
    end
    return nil if type != NOTIFICATION_TYPE || !metadata.is_a?(Hash)
    return nil unless GameRoomInvitationIdentity.valid_notification_metadata?(metadata)
    return nil if GameRoomInvitationIdentity.notification_sender(notification, metadata).nil?

    metadata
  end

  def notification_id(notification)
    id = notification.respond_to?(:id) ? notification.id.to_i : 0
    id > 0 ? id : nil
  end

  def same_app?(notification)
    uuid = notification.respond_to?(:app_uuid) ? notification.app_uuid.to_s : ""
    !uuid.empty? && uuid.casecmp(@app_uuid) == 0
  end

  def hash_value(hash, key)
    hash[key] || hash[key.to_sym]
  end
end
