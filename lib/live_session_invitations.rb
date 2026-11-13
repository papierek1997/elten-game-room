require_relative "invitation_identity"

class GameRoomLiveSessionStore
  module Invitations
    public

    # Read the current authenticated provider without dispatching callbacks,
    # discovery or any server request. The endpoint object is an identity token.
    def invitation_account_identity
      current = @endpoint_provider.call
      [current, current.user.to_s.dup.freeze].freeze
    end

    def invite_user(table_id:, user:, metadata:)
      session = active_session(table_identifier(table_id))
      return false if session == nil

      # The current API accepts a participant identity for invitations, not just
      # the room owner's identity. Let it validate the actual membership.
      result = session.invite(user.to_s, metadata: metadata.to_h.merge("purpose" => "game_invitation"))
      result
    end

    def pending_invitations
      current = endpoint
      prune_invitations
      @mutex.synchronize do
        @pending_invitations.values.filter_map do |stored|
          next unless stored[:endpoint].equal?(current) && @invitation_endpoint.equal?(current)
          invitation = stored[:invitation]
          {
            "__id" => stored[:id],
            "table_id" => stored[:table_id],
            "live_session_id" => stored[:native_id],
            "sender" => stored[:sender],
            "sender_display_name" => invitation.invitation_metadata.to_h['sender_display_name'],
            "recipient" => stored[:recipient],
            "status" => "pending",
            "created_at" => stored[:created_at],
            "expires_at" => invitation_expiration(stored),
            "__native_invitation" => invitation
          }
        end
      end
    end

    def accept_invitation(table_id:, invitation_id:, participant_metadata: {})
      stored = take_invitation(table_id, invitation_id)
      return false if stored == nil

      verify_room_resource!(stored[:table_id], stored[:native_id])
      session = stored[:invitation].accept(participant_metadata: participant_metadata(table_id).merge(participant_metadata.to_h))
      account = [stored[:endpoint], stored[:recipient]]
      return false unless invitation_account_current?(account)

      status = admit_joined_session(stored[:table_id], session, account: account)
      return false unless invitation_account_current?(account)

      resolve_invitation(stored)
      status == :joined
    rescue StandardError
      restore_invitation(stored) if stored && stored[:invitation].pending?
      raise
    end

    def reject_invitation(table_id:, invitation_id:)
      stored = take_invitation(table_id, invitation_id)
      return false if stored == nil

      stored[:invitation].reject
      return false unless invitation_account_current?([stored[:endpoint], stored[:recipient]])

      resolve_invitation(stored)
      true
    rescue StandardError
      restore_invitation(stored) if stored
      raise
    end

    # A notification may be opened by a brand-new endpoint. The native server
    # invitation in fresh discovery, not another endpoint's queue, grants access.
    def reject_discovered_invitation(table)
      item = table["__discovered_session"]
      data = item.respond_to?(:invitation) ? item.invitation : nil
      raise GameRoomNetworkErrors::UnsupportedInvitation, "The server did not provide the private invitation identity" unless data.is_a?(Hash)
      native_id = data["invitation_id"] || data["id"]
      raise GameRoomNetworkErrors::UnsupportedInvitation, "The server did not provide the private invitation identity" if native_id.to_s.empty?

      identity = Struct.new(:id, :invitation_id, :generation).new(item.id, native_id, data["generation"].to_i)
      endpoint.reject_invitation(identity)
      true
    end

    private

    def invitation_account_current?(account)
      current, user = invitation_account_identity
      current.equal?(account.first) && user.casecmp?(account.last)
    end

    def register_invitation_callback(current)
      register = @mutex.synchronize do
        next false if @invitation_endpoint.equal?(current)

        @invitation_endpoint = current
        # A callback belongs to its authenticated endpoint, not whichever
        # account happens to open the next lobby. Fresh endpoints discover
        # their own native invitations / durable notices normally.
        @pending_invitations.clear
        @resolved_invitations.clear
        true
      end
      return if !register

      current.on_invitation { |invitation| receive_invitation(invitation, source: current) }
      return if !current.respond_to?(:next_invitation)

      loop do
        invitation = current.next_invitation(timeout: 0)
        break if invitation == nil

        receive_invitation(invitation, source: current)
      end
    end

    def receive_invitation(invitation, source:)
      return if invitation.respond_to?(:pending?) && !invitation.pending?

      metadata = invitation.metadata.to_h
      return if !supported_metadata?(metadata)

      invitation_metadata = invitation.invitation_metadata.to_h
      return if invitation_metadata["purpose"].to_s != "game_invitation"

      table_id = positive_identifier(metadata["table_id"])
      invitation_id = positive_identifier(invitation_metadata["invitation_id"])
      return if table_id == nil || invitation_id == nil
      native_id = invitation.id.to_s
      sender = invitation.inviter.user.to_s
      recipient = source.user.to_s
      return if native_id.empty? || sender.empty? || recipient.empty?
      claimed_sender = invitation_metadata["sender"].to_s
      return if !claimed_sender.empty? && !sender.casecmp?(claimed_sender)
      key = GameRoomInvitationIdentity.key("__id" => invitation_id, "table_id" => table_id,
        "live_session_id" => native_id, "sender" => sender, "recipient" => recipient)

      @mutex.synchronize do
        return if @local_view_closed || !@invitation_endpoint.equal?(source) || !@endpoint.equal?(source)
        return if @resolved_invitations.key?(invitation_resolution_key(key, invitation))

        @pending_invitations[key] = {
          key: key,
          id: invitation_id,
          table_id: table_id,
          native_id: native_id,
          sender: sender,
          recipient: recipient,
          endpoint: source,
          invitation: invitation,
          created_at: GameRoomClock.now.to_i
        }
      end
      emit_change(table_id, :invitation, invitation_id)
    rescue StandardError => error
      log_warning("incoming invitation", nil, error)
    end

    def take_invitation(table_id, invitation_id)
      current = endpoint
      prune_invitations
      id = positive_identifier(invitation_id)
      room_id = table_identifier(table_id)
      return nil if id == nil || room_id == nil

      @mutex.synchronize do
        next nil unless @invitation_endpoint.equal?(current)
        matches = @pending_invitations.values.select do |stored|
          stored[:id] == id && stored[:table_id] == room_id && stored[:endpoint].equal?(current)
        end
        next nil unless matches.size == 1

        @pending_invitations.delete(matches.first[:key])
      end
    end

    def restore_invitation(stored)
      @mutex.synchronize do
        next unless @invitation_endpoint.equal?(stored[:endpoint]) && !@local_view_closed
        next if @resolved_invitations.key?(invitation_resolution_key(stored[:key], stored[:invitation]))

        @pending_invitations[stored[:key]] ||= stored
      end
    end

    def resolve_invitation(stored)
      @mutex.synchronize do
        next unless @invitation_endpoint.equal?(stored[:endpoint])

        key = invitation_resolution_key(stored[:key], stored[:invitation])
        current = @pending_invitations[stored[:key]]
        if current && invitation_resolution_key(current[:key], current[:invitation]) == key
          @pending_invitations.delete(stored[:key])
        end
        @resolved_invitations[key] = GameRoomClock.now.to_i + INVITATION_TTL
      end
    end

    # Discovery consumes the server invitation too, but the SDK leaves an
    # already delivered Invitation wrapper in its original pending state.
    # Retire only the confirmed native identity, without another server write.
    def resolve_discovered_invitation(table_id, session, account:)
      return unless invitation_account_current?(account) && session.respond_to?(:join_context)
      context = session.join_context
      return unless context.is_a?(Hash) && context['method'] == 'invitation'
      key = native_invitation_resolution_key(session.id, context['invitation_id'], context['invitation_generation'])
      return unless key

      @mutex.synchronize do
        next if @local_view_closed || !@endpoint.equal?(account.first) || !@invitation_endpoint.equal?(account.first)
        @pending_invitations.delete_if do |scope, stored|
          stored[:table_id] == table_id && stored[:endpoint].equal?(account.first) &&
            stored[:recipient].casecmp?(account.last) && invitation_resolution_key(scope, stored[:invitation]) == key
        end
        @resolved_invitations[key] = GameRoomClock.now.to_i + INVITATION_TTL
      end
    end

    def invitation_resolution_key(scope, invitation)
      return scope unless invitation.respond_to?(:invitation_id) && invitation.respond_to?(:generation)
      native_invitation_resolution_key(invitation.id, invitation.invitation_id, invitation.generation) || scope
    end

    def native_invitation_resolution_key(native_id, invitation_id, generation)
      return unless native_id.is_a?(String) && !native_id.empty? && invitation_id.is_a?(String) && !invitation_id.empty?
      return unless generation.is_a?(Integer) && generation >= 0
      [:native, native_id.dup.freeze, invitation_id.dup.freeze, generation].freeze
    end

    def prune_invitations
      now = GameRoomClock.now.to_i
      expired = []
      @mutex.synchronize do
        @pending_invitations.delete_if do |_id, stored|
          invitation = stored[:invitation]
          no_longer_pending = invitation.respond_to?(:pending?) && !invitation.pending?
          timed_out = invitation_expiration(stored) <= now
          expired << invitation if timed_out && !no_longer_pending
          no_longer_pending || timed_out
        end
        @resolved_invitations.delete_if { |_id, expires_at| expires_at <= now }
      end
      expired.each do |invitation|
        invitation.reject if !invitation.respond_to?(:pending?) || invitation.pending?
      rescue StandardError => error
        log_warning("expired invitation cleanup", nil, error)
      end
    end

    def invitation_expiration(stored)
      local_expiration = stored[:created_at].to_i + INVITATION_TTL
      invitation = stored[:invitation]
      native_expiration = invitation.respond_to?(:expires_at) ? invitation.expires_at.to_i : 0
      native_expiration.positive? ? [local_expiration, native_expiration].min : local_expiration
    end
  end

  include Invitations
end
