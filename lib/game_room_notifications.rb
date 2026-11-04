require "digest"
require "json"
require_relative "invitation_identity"
require_relative "game_room_clock"

# Native 3.0.5 delivery/revocation. Keys identify one authenticated sender,
# recipient and event, not a list position or a tournament's current title.
module GameRoomNotifications
  CHECK_INTERVAL = 60
  INVITATION = "game_room.invitation".freeze
  module_function

  def key(type:, metadata:, sender:, recipient:)
    identity = if type == INVITATION || %w[game_room.invitation_resolved game_room.invitation_rejected].include?(type)
      [metadata.fetch("invitation_id"), metadata.fetch("table_id"), metadata.fetch("live_session_id")]
    elsif type == "game_room.table_created"
      [metadata.fetch("table_id"), metadata.fetch("live_session_id")]
    else
      # A tournament event has an explicit identity. Repeated coordination
      # wakes have no event ID and deliberately do not use this keyed sender.
      metadata.fetch("event_id")
    end
    Digest::SHA256.hexdigest(JSON.generate(["power-games-notice-v1", type,
      sender.to_s.downcase, recipient.to_s.downcase, identity]))
  end

  def invitation_key(reference)
    row = GameRoomInvitationIdentity.row(reference)
    key(type: INVITATION, sender: row.fetch("sender"), recipient: row.fetch("recipient"), metadata: {
      "invitation_id" => GameRoomInvitationIdentity.id(row), "table_id" => row.fetch("table_id"),
      "live_session_id" => row.fetch("live_session_id")
    })
  end

  def deliver(program, recipient, type:, metadata:, expires_in: 0, client: nil)
    value = key(type: type, metadata: metadata, sender: Session.name, recipient: recipient)
    options = {type: type, metadata: metadata, expires_in: expires_in, key: value}
    if client
      EltenLink::Apps.notify(client, appid: program.server_app_uuid, user: recipient, **options)
    else
      program.send_notification(recipient, **options)
    end
  end

  def revoke_invitation(program, reference)
    row = GameRoomInvitationIdentity.row(reference)
    return false unless row["sender"].to_s.casecmp?(Session.name.to_s)

    program.revoke_sent_notification(row.fetch("recipient"), key: invitation_key(row))
  end

  def revoke_closed_table(program, table)
    InvitationRepository.sent_for_table(table_id: table.fetch("__id"),
      live_session_id: table.fetch("__live_session_id"), sender: Session.name).each do |invitation|
      next unless revoke_invitation(program, invitation)

      InvitationRepository.resolve_sent(invitation)
    end
  end

  def lifecycle(program, notification)
    return unless notification.app_uuid.to_s.casecmp?(program.server_app_uuid.to_s)
    return unless supported_type?(notification.type.to_s)

    # The host owns the worker/timing. Checks only inspect existing local
    # evidence; they must never discover tables or poll tournament storage.
    notification.lifecycle(interval: CHECK_INTERVAL) do |current|
      current?(program, current)
    end
  end

  def current?(program, notification)
    now = GameRoomClock.now.to_i if GameRoomClock.synchronized?
    if notification.type.to_s == INVITATION || notification.type.to_s == "game_room.table_created"
      deadline = GameRoomNotificationTime.expires_at(notification)
      return false if now && deadline.positive? && deadline <= now
    end

    type = notification.type.to_s
    if type == "game_room.table_created"
      receiver = program.instance_variable_get(:@table_watch_receiver)
      return receiver.visible?(notification) if now && receiver && receiver.user.casecmp?(Session.name.to_s)
    elsif type.start_with?("game_room.tournament_")
      inbox = tournament_inbox(program, type)
      token = notification.metadata.to_h["token"] || notification.metadata.to_h["event_id"]
      return false if inbox && token && inbox.dismissed?(token)
      cached = inbox&.verified(notification.id)
      if cached && cached[1] == notification.sender.to_s.downcase && cached[0]["metadata"] == notification.metadata
        deadline = cached[0]["expires_at"]
        return false if now && deadline.is_a?(Integer) && deadline.positive? && deadline <= now
      end
    end
    true # Missing verification, an unloaded inbox or a cold clock is unknown.
  rescue GameRoomNetworkErrors::ClockUnavailable
    true
  end

  def supported_type?(type)
    [INVITATION, "game_room.table_created", "game_room.tournament_started",
      "game_room.tournament_registration", "game_room.tournament_partnership",
      "game_room.tournament_phase_finished", "game_room.tournament_finished"].include?(type)
  end

  def tournament_inbox(program, type)
    return program.instance_variable_get(:@tournament_start_inbox) if type == "game_room.tournament_started"
    kind = type.delete_prefix("game_room.tournament_")
    program.instance_variable_get(:@tournament_event_inboxes)&.[](kind)
  end

end
