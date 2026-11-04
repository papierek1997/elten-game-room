require_relative "game_room_clock"
require "securerandom"
require_relative "invitation_response_outbox"
require_relative "invitation_identity"

class InvitationRepository
  SENT_LOCK = Mutex.new
  SENT = {}

  def self.sent_for_table(table_id:, live_session_id:, sender:)
    return [] if table_id.to_i <= 0 || live_session_id.to_s.empty? || sender.to_s.empty?

    SENT_LOCK.synchronize do
      SENT.values.select { |row| row["table_id"].to_i == table_id.to_i &&
        row["live_session_id"].to_s == live_session_id.to_s && row["sender"].to_s.casecmp?(sender.to_s) }.map(&:dup)
    end
  end

  def self.resolve_sent(reference, table_id: nil, recipient: nil)
    expected = GameRoomInvitationIdentity.row(reference).dup
    expected["table_id"] = table_id unless table_id.nil?
    expected["recipient"] = recipient unless recipient.nil?
    SENT_LOCK.synchronize do
      selected = GameRoomInvitationIdentity.unique(SENT.values, expected)
      SENT.delete_if { |_key, row| row.equal?(selected) } if selected
    end
  end

  def self.sent_for_receipt(id, table_id:, recipient:, sender:, live_session_id: nil)
    return nil if id.to_i <= 0 || table_id.to_i <= 0 || recipient.to_s.empty? || sender.to_s.empty?

    SENT_LOCK.synchronize do
      GameRoomInvitationIdentity.unique(SENT.values, { "__id" => id, "table_id" => table_id,
        "recipient" => recipient, "sender" => sender, "live_session_id" => live_session_id })
    end
  end
  InvitationResult = Struct.new(:invitation, :created, keyword_init: true) do
    def created?
      created == true
    end
  end

  PendingInvitation = Struct.new(:invitation, :table, keyword_init: true) do
    def id
      (invitation["__id"] || invitation["id"]).to_i
    end

    def table_id
      invitation["table_id"].to_i
    end

    def sender
      invitation["sender"].to_s
    end

    def recipient
      invitation["recipient"].to_s
    end

    def created_at
      invitation["created_at"].to_i
    end

    def expires_at
      invitation["expires_at"].to_i
    end
  end

  DEFAULT_TTL = 5 * 60
  RESPONSES = ["accepted", "rejected", "expired"].freeze

  def initialize(server_tables: nil, transport: nil, notification_source: nil, response_sender: nil, response_outbox: nil,
    current_user: -> { defined?(Session) ? Session.name.to_s : "" }, sender_allowed: nil)
    @transport = transport
    @notification_source = notification_source
    @response_sender = response_sender
    @response_outbox = response_outbox
    @current_user = current_user
    @sender_allowed = sender_allowed
    @sent_invitations = SENT
    @responses = {}
    @response_expirations = {}
  end

  # Reserve a duplicate key only for an invitation that was actually sent.
  # Notification delivery is separate and must not turn a failed native
  # invitation into a success message or a long local lockout.
  def deliver(table:, sender:, recipient:)
    result = create(table: table, sender: sender, recipient: recipient)
    return result if !result.created?

    delivered = false
    begin
      delivered = yield(result.invitation)
      delivered ? result : nil
    ensure
      if !delivered
        SENT_LOCK.synchronize { @sent_invitations.delete_if { |_key, row| row.equal?(result.invitation) } }
      end
    end
  end

  def create(table:, sender:, recipient:, now: GameRoomClock.now.to_i, ttl: DEFAULT_TTL)
    table_id = row_id(table)
    clean_sender = sender.to_s.strip
    clean_recipient = recipient.to_s.strip
    raise ArgumentError, "Invalid invitation table" if table_id <= 0
    raise ArgumentError, "Invitation sender is required" if clean_sender.empty?
    raise ArgumentError, "Invitation recipient is required" if clean_recipient.empty?
    raise ArgumentError, "You cannot invite yourself" if same_user?(clean_sender, clean_recipient)

    return SENT_LOCK.synchronize do
      @sent_invitations.delete_if { |_key, row| row["expires_at"].to_i <= now.to_i }
      key = [table_id, table["__live_session_id"].to_s, clean_sender.downcase, clean_recipient.downcase]
      existing = @sent_invitations[key]
      if existing != nil && existing["expires_at"].to_i > now.to_i
        next InvitationResult.new(invitation: existing, created: false)
      end

      id = SecureRandom.random_number(2_000_000_000) + 1
      row = {
        "__id" => id,
        "id" => id,
        "table_id" => table_id,
        "live_session_id" => table["__live_session_id"].to_s,
        "sender" => clean_sender,
        "recipient" => clean_recipient,
        "status" => "pending",
        "created_at" => now.to_i,
        "expires_at" => now.to_i + [ttl.to_i, 1].max,
        "updated_at" => now.to_i,
        "__insertion_user" => clean_sender
      }
      @sent_invitations[key] = row
      InvitationResult.new(invitation: row, created: true)
    end
  end

  def pending_for(recipient, tables:, now: GameRoomClock.now.to_i)
    user = @current_user.call.to_s
    return [] unless user.empty? || same_user?(user, recipient)
    prune_responses(now)
    table_by_id = tables.to_a.each_with_object({}) do |table, result|
      id = row_id(table)
      result[id] = table if id > 0 && %w[waiting playing].include?(table["status"].to_s)
    end

    rows = (@notification_source == nil ? [] : @notification_source.call(recipient, now)) + @transport.pending_invitations
    return [] unless @current_user.call.to_s.casecmp?(user)
    return rows.filter_map do |row|
      next unless row_id(row).positive? && !row["sender"].to_s.empty?
      next if !same_user?(row["recipient"], recipient)
      next if row["expires_at"].to_i.positive? && row["expires_at"].to_i <= now.to_i
      next if @responses.key?(GameRoomInvitationIdentity.key(row))

      table = table_by_id[row["table_id"].to_i]
      next if table != nil && !row["live_session_id"].to_s.empty? && row["live_session_id"].to_s != table["__live_session_id"].to_s
      next if table && @sender_allowed && !@sender_allowed.call(row["sender"], table)
      table == nil ? nil : PendingInvitation.new(invitation: row, table: table)
    end.uniq { |pending| GameRoomInvitationIdentity.key(pending) }
  end

  def pending_by_id(reference, recipient, tables:, now: GameRoomClock.now.to_i)
    GameRoomInvitationIdentity.unique(pending_for(recipient, tables: tables, now: now), reference)
  end

  def respond(invitation, recipient:, response:, now: GameRoomClock.now.to_i)
    row = invitation.respond_to?(:invitation) ? invitation.invitation : invitation
    invitation_id = row_id(row)
    clean_recipient = recipient.to_s.strip
    clean_response = response.to_s
    raise ArgumentError, "Invalid invitation" if invitation_id <= 0
    raise ArgumentError, "Invitation belongs to another user" if !same_user?(row["recipient"], clean_recipient)
    user = @current_user.call.to_s
    raise ArgumentError, "Invitation belongs to another user" unless user.empty? || same_user?(user, clean_recipient)
    raise ArgumentError, "Invalid invitation response" if !RESPONSES.include?(clean_response)

    prune_responses(now)
    key = GameRoomInvitationIdentity.key(row)
    return @responses[key] if @responses.key?(key)

    decision = {
      "__id" => invitation_id,
      "invitation_id" => invitation_id,
      "table_id" => row["table_id"].to_i,
      "recipient" => clean_recipient,
      "response" => clean_response,
      "created_at" => now.to_i
    }
    if @response_sender
      outbox = @response_outbox ||= InvitationResponseOutbox.default
      decision["response"] = outbox.submit(row, clean_response, &@response_sender)
    end
    if row["expires_at"].to_i.positive?
      @response_expirations[key] = [row["expires_at"].to_i, now.to_i + InvitationResponseOutbox::TTL].max
    end
    return @responses[key] = decision
  end

  private

  # Keep the immutable choice while the invitation can still appear, and at
  # least through the independent outbox's delivery horizon. Legacy invitations
  # without a finite expiry cannot safely be retired by a guessed item limit.
  def prune_responses(now)
    @response_expirations.delete_if do |key, expires|
      expired = expires <= now.to_i
      @responses.delete(key) if expired
      expired
    end
  end

  def row_id(row)
    return 0 if row == nil

    (row["__id"] || row["id"]).to_i
  end

  def same_user?(first, second)
    !first.to_s.empty? && first.to_s.casecmp(second.to_s) == 0
  end
end
