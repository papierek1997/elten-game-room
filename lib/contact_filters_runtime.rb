require_relative "game_room_contacts"
require_relative "game_room_clock"
require_relative "notification_time"
require_relative "invitation_identity"

module GameRoomContactFiltersRuntime
  CACHE_LOCK = Mutex.new

  def contacts_cache
    CACHE_LOCK.synchronize do
      user = Session.name.to_s.strip.downcase
      if !@contacts_cache || @contacts_cache.user != user
        @contacts_cache&.close
        runtime = Programs.runtime_for(self) if defined?(Programs) && Programs.respond_to?(:runtime_for)
        runtime ||= Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
        @contacts_cache = GameRoomContacts::Cache.new(user: user, runtime: runtime, loader: lambda {
          raise "Contact account changed" unless Session.name.to_s.strip.downcase == user
          contacts = EltenLink::Contacts.list(EltenLink::Client.new)
          raise "Contact account changed" unless Session.name.to_s.strip.downcase == user
          contacts
        })
        @contact_pending = GameRoomContacts::Pending.new
        @contact_revision = 0
      end
      @contacts_cache
    end
  end

  def invitation_sender_allowed?(sender, tournament_match: false, settings: normalized_settings)
    tournament_match == true || !GameRoomPreferences.invitation_blocked?(settings, sender)
  end

  # nil means unknown, not a failed match. Do not fetch synchronously or turn
  # an unavailable contact list into permission to announce a stranger.
  def contact_notification_allowed?(notification, settings: normalized_settings)
    case notification.type.to_s
    when "game_room.invitation"
      sender = GameRoomInvitationIdentity.notification_sender(notification, notification.metadata.to_h)
      return false if sender.nil?
      tournament = notification.metadata.is_a?(Hash) && notification.metadata["tournament_match"] == true
      return true if tournament
      return false unless invitation_sender_allowed?(sender, tournament_match: tournament, settings: settings)
      case settings["invitation_notifications"]
      when "nobody" then false
      when "contacts" then contacts_cache.include?(sender)
      else true
      end
    when GameRoomTableWatch::TYPE
      settings["table_watch_contacts_only"] == true ? contacts_cache.include?(notification.sender) : true
    else true
    end
  end

  def contact_notification_received(notification, presentation, deferred: false)
    contacts_cache if @contacts_cache
    allowed = contact_notification_allowed?(notification)
    if allowed != false && ["game_room.invitation", GameRoomTableWatch::TYPE].include?(notification.type.to_s) &&
        GameRoomClock.server_available? && !GameRoomClock.synchronized?
      # Reuse the bounded receipt queue until the startup clock read finishes.
      # Creating this cache does not request contacts when filters are disabled.
      allowed = nil
    end
    if allowed == nil
      contacts_cache
      @contact_pending.add(notification, active: contact_notice_active_ids&.include?(notification.id.to_i))
    end
    if allowed != true || (!deferred && @contact_pending&.settled?(notification))
      presentation&.suppress_default!
      return false
    end
    true
  end

  def contacts_tick
    return unless @contacts_cache
    cache = contacts_cache # Also drops all old-account work and queued notices.
    revision = cache.revision
    if @contact_revision != revision
      @contact_revision = revision
      contact_notifications_changed
    end
    queue = @contact_pending
    entries = queue.entries
    return if entries.empty?
    active_ids = contact_notice_active_ids
    entries.each do |notification, _deadline, was_active|
      next if GameRoomClock.server_available? && !GameRoomClock.synchronized?
      expires = GameRoomNotificationTime.expires_at(notification)
      expired = expires > 0 && expires <= GameRoomClock.now.to_i
      expired ||= was_active && active_ids && !active_ids.include?(notification.id.to_i)
      expired ||= notification.type.to_s == GameRoomTableWatch::TYPE && !table_watch_receiver.visible?(notification)
      allowed = expired ? false : contact_notification_allowed?(notification)
      next if allowed == nil
      queue.finish(notification)
      present_deferred_contact_notification(notification) if allowed
    end
  end

  def present_deferred_contact_notification(notification)
    presentation = map_notification(notification)
    return unless presentation
    notification_received(notification, presentation, deferred: true)
    return if presentation.default_suppressed? || EltenAPI::UI.notifications_muted?
    event = {
      "func" => "notif", "alert" => presentation.alert, "sound" => presentation.sound,
      "id" => notification.id, "app_uuid" => notification.app_uuid, "type" => notification.type,
      "metadata" => notification.metadata, "presentation_metadata" => presentation.metadata
    }
    # Same delivery path/quiet-mode/callback as the host's app_notification
    # handler, on the extension/UI tick. No synthetic server notification.
    if $notifications_callback != nil
      $notifications_callback.call(event)
    else
      new.send(:process_notification, event)
    end
  rescue StandardError => error
    Log.warning("Game Room deferred notification failed: #{error.class}") if defined?(Log)
  end

  def contact_notice_active_ids
    return nil unless defined?(EltenAPI::NotificationService) && EltenAPI::NotificationService.respond_to?(:active_notifications)
    EltenAPI::NotificationService.active_notifications.select do |row|
      row.cat.to_s == "app" && row.app_uuid.to_s.casecmp?(server_app_uuid.to_s) && row.revoked != true
    end.map { |row| row.id.to_i }
  end

  def contact_notifications_changed
    $main_notifications_changed = true
    Session.notifications_update if Session.respond_to?(:notifications_update)
  end

  def contacts_settings_changed(settings)
    if settings["invitation_notifications"] == "contacts" || settings["table_watch_contacts_only"] == true ||
        (settings["widget_enabled"] && settings["widget_contacts_only"] == true)
      contacts_cache.snapshot
    end
    contact_notifications_changed
  end

  def contacts_stop
    CACHE_LOCK.synchronize do
      @contacts_cache&.close
      @contacts_cache = nil
      @contact_pending = nil
    end
  end
end
