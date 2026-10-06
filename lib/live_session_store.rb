require "json"
require "securerandom"
require "thread"
require "digest"
require "zlib"
require "base64"
require_relative "game_participants"
require_relative "network_errors"
require_relative "game_session_clock"
require_relative "table_control"
require_relative "game_statistics_identity"
require_relative "game_room_presence_identity"
require_relative "game_room_background"
require_relative "game_event_protocol"
require_relative "game_session_contracts"

# The authoritative, ephemeral state of one Game Room table lives in one
# discoverable LiveSession.  Every mutation is appended to the session stack;
# repositories only project that ordered log into their familiar row-shaped
# values.  App tables are deliberately not involved in room or game state.
class GameRoomLiveSessionStore
  KIND = "elten_game_room_table".freeze
  PROTOCOL = 2
  FEATURE_DISCOVERY_PROTOCOL = 3
  LIFECYCLE_DISCOVERY_PROTOCOL = 4
  NAMED_SEATS_DISCOVERY_PROTOCOL = 5
  THINKING_TIME_DISCOVERY_PROTOCOL = 6
  CURRENT_DISCOVERY_PROTOCOL = 7
  DISCOVERY_BYTES = 1024
  MAX_OPTIONS_BYTES = 8192
  MAX_CAPACITY = 8
  DEFAULT_CAPACITY = 8
  STACK_ENTRIES = 4_096
  STACK_ENTRY_BYTES = 16_384
  ARCHIVE_EVENTS_PER_RECORD = 10
  MAX_ARCHIVE_EVENTS = (STACK_ENTRIES - 8) * ARCHIVE_EVENTS_PER_RECORD
  STACK_PAGE_SIZE = 128
  EVENT_ID_MULTIPLIER = 100
  DISCOVERY_LIMIT = 100
  INVITATION_TTL = 5 * 60

  Record = Struct.new(
    :table_id,
    :sequence,
    :message_id,
    :sender,
    :packet,
    :created_at,
    :estimated_time,
    keyword_init: true
  )

  def initialize(program, changed: nil, endpoint_provider: nil, presence_changed: nil)
    @program = program
    @changed = changed
    @presence_changed = presence_changed
    @endpoint_provider = endpoint_provider || -> { @program.live_sessions }
    @endpoint = nil
    @invitation_endpoint = nil
    @rooms = {}
    @sessions = {}
    @native_session_ids = {}
    @discovered = {}
    @pending_invitations = {}
    @resolved_invitations = {}
    @mutex = Mutex.new
    @callback_dispatch_mutex = Mutex.new
    @published_discovery = {}
    @discovery_retry_at = {}
    @inactive_rooms = {}
    @discovery_due, @activity_publish_at, @realtime_activity = {}, {}, {}
    @discovery_work_lock = Mutex.new
    runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
    @discovery_work = GameRoomBackground::Work.new(runtime: runtime)
    @program.class.manage(@discovery_work) if @program.class.respond_to?(:manage)
  end

  def start
    GameRoomClock.synchronize
    current = endpoint
    current.sessions.to_a.each { |session| attach_supported_session(session) } if current.respond_to?(:sessions)
    true
  end

  # Workers must observe queued moves even while the app scene is covered,
  # including before committing a plan. Visible UI delivery belongs to ELTEN.
  # Never reconnect, poll the server or tick other programs here.
  def dispatch_pending_events
    return 0 unless @callback_dispatch_mutex.try_lock

    begin
      current = @mutex.synchronize { @endpoint }
      return 0 unless current && current.respond_to?(:dispatch_events)
      return 0 if current.closed?

      # The host also bounds this call to 10 ms and guards native reentrancy.
      current.dispatch_events(32)
    ensure
      @callback_dispatch_mutex.unlock
      dispatch_discovery_publication
    end
  end

  def maintain_pending_work
    dispatch_discovery_publication
    nil
  end

  # Private live messages never enter the public stack or replay. Consumers
  # still validate the sender, game/round and commitment at the game layer.
  def send_private_game(table_id:, session_id:, recipient:, payload:, message_id:)
    session = active_session(table_id)
    raise IOError, "The private game connection is unavailable" unless session&.respond_to?(:send_private)
    raise ArgumentError, "Invalid private game payload" unless payload.is_a?(Hash) && JSON.generate(payload).bytesize <= 2048
    session.send_private(recipient, {"type" => "game_room_private", "version" => 1,
      "session_id" => session_id.to_i, "payload" => payload}, message_id: message_id, timeout: 5)
  end

  def private_game_messages_pending?(table_id, session_id)
    @mutex.synchronize { (@rooms[table_id]&.private_game_messages || []).any? { |item| item[:session_id] == session_id.to_i } }
  end

  def take_private_game_messages(table_id, session_id)
    @mutex.synchronize do
      messages = room_state(table_id).take_private_game_messages || []
      messages.select { |item| item[:session_id] == session_id.to_i }
    end
  end

  # Replaceable public presentation only, never a stack entry or an accepted
  # move. Callers send from a worker and validate game/turn/author on receipt.
  def send_game_preview(table_id:, session_id:, payload:, message_id:)
    session = active_session(table_id)
    raise IOError, "The preview connection is unavailable" unless session && !session.closed?
    raise ArgumentError, "Invalid preview payload" unless payload.is_a?(Hash) && JSON.generate(payload).bytesize <= 2048
    session.send({"type" => "game_room_preview", "version" => 1,
      "session_id" => session_id.to_i, "payload" => payload}, message_id: message_id, retries: 0)
  end

  def take_game_previews(table_id, session_id)
    @mutex.synchronize do
      messages = @rooms[table_id]&.take_public_game_previews || []
      messages.select { |item| item[:session_id] == session_id.to_i }
    end
  end

  def create_room(name:, game:, owner:, game_options:, capacity: DEFAULT_CAPACITY, private_table: false, resume_save_id: nil, bot_count: 0, bot_names: nil)
    start
    table_id = unused_identifier
    maximum = bounded_capacity(capacity)
    metadata = {
      "kind" => KIND,
      # Shared thinking-time rules require the same replay rules on all clients.
      # Earlier clients must not join and silently ignore a clock/timeout event.
      "protocol" => CURRENT_DISCOVERY_PROTOCOL,
      "table_id" => table_id,
      "statistics_room_id" => GameRoomPresence::Identity.create,
      "owner" => owner.to_s,
      "name" => name.to_s,
      "game" => game.to_s,
      "game_options" => game_options.to_s,
      "private" => private_table == true,
      "resume_save_id" => resume_save_id.to_s,
      "created_at" => GameRoomClock.now.to_i
    }
    discovery = metadata.dup
    discovery.merge!("status" => "waiting", "bot_count" => [[bot_count.to_i, 0].max, maximum - 1].min,
      "player_count" => 1 + [[bot_count.to_i, 0].max, maximum - 1].min, "max_players" => maximum)
    session = endpoint.create(
      metadata: metadata,
      participant_metadata: participant_metadata(table_id),
      capacity: maximum,
      visibility: private_table == true ? :private : :public,
      discovery_metadata: compact_discovery(discovery),
      stack_entry_bytes: STACK_ENTRY_BYTES,
      stack_entries: STACK_ENTRIES,
      pool_count: 1,
      private_messages: true
    )
    attach_session(table_id, session)
    append_record(table_id, "room_created", {
      "name" => name.to_s,
      "game" => game.to_s,
      "owner" => owner.to_s,
      "status" => "waiting",
      "max_players" => maximum,
      "bot_count" => [[bot_count.to_i, 0].max, maximum - 1].min,
      "bot_names" => Array.new([[bot_count.to_i, 0].max, maximum - 1].min) { |index| bot_names.to_a[index] },
      "game_options" => game_options.to_s,
      "created_at" => metadata["created_at"]
    }, actor: owner)
    table_for(table_id)
  rescue StandardError
    begin
      session&.close
    rescue StandardError
      nil
    end
    raise
  end

  def discover_rooms(game: nil, include_private: false)
    start
    found = {}
    discovered = {}
    discover_pages(sources: include_private ? [:created, :invited, :public] : [:public]).each do |item|
      metadata = item.discovery_metadata.to_h
      next if !supported_metadata?(metadata)

      table_id = positive_identifier(metadata["table_id"])
      next if table_id == nil

      begin
        row = table_from_discovered(item, metadata)
      rescue ArgumentError, Zlib::Error, JSON::ParserError
        next # One malformed public description must not hide all other rooms.
      end
      discovered[table_id] = item
      row = table_for(table_id, fallback: row) if active_session(table_id) != nil
      next if row == nil || (game != nil && row["game"].to_s != game.to_s)
      next if row["private"] == true && !include_private

      found[table_id] = row
    end
    replace_discovered_cache(discovered)
    active_table_ids.each do |table_id|
      row = table_for(table_id)
      next if row == nil || (game != nil && row["game"].to_s != game.to_s)
      next if row["private"] == true && !include_private

      found[table_id] = row
    end
    found.values.select { |row| %w[waiting playing].include?(row["status"].to_s) }
      .sort_by { |row| [row["status"].to_s == "waiting" ? 0 : 1, -row["updated_at"].to_i, -row["__id"].to_i] }
  end

  def current_room(user)
    start
    username = user.to_s
    active_table_ids.filter_map do |table_id|
      next if !connected_users(table_id).any? { |candidate| same_user?(candidate, username) }

      table_for(table_id)
    end.max_by { |row| [row["created_at"].to_i, row["__id"].to_i] }
  end

  def room_snapshot(table_or_id, force: false, read_only: false, **read_options)
    table_id = table_identifier(table_or_id)
    return nil if table_id == nil

    ensure_current(table_id, force: force, **read_options)
    session = active_session(table_id)
    return nil if session == nil

    reconcile_control_owner(table_id) unless read_only
    table = table_for(table_id)
    return nil if table == nil || !%w[waiting playing].include?(table["status"].to_s)

    members = connected_users(table_id)
    owner = table["owner"].to_s
    members.sort_by! { |member| same_user?(member, owner) ? 0 : 1 }
    publish_discovery(table_id) unless read_only
    GameRoomSessionContracts::RoomSnapshot.new(
      table: table,
      members: unique_users(members),
      bots: room_bots(table_id, table),
      observers: observer_users(table_id, members: members)
    ).to_h
  end

  def set_observer(table_or_id, observing, actor:, subject: nil)
    table_id = table_identifier(table_or_id)
    raise ArgumentError, "Invalid room" if table_id == nil
    raise ArgumentError, "Only your own table role may be changed" if !same_user?(endpoint.user, actor)

    ensure_current(table_id, force: true)
    members = connected_users(table_id)
    raise ArgumentError, "The user is not at this table" if !members.any? { |member| same_user?(member, actor) }
    target = subject || actor
    raise ArgumentError, "Invalid role subject" unless target.is_a?(String) && target.length.between?(1, 64) && GameRoomParticipants.human?(target)
    raise ArgumentError, "Only the table master may change another user's role" if subject && !same_user?(actor, owner_for(table_id))
    raise ArgumentError, "The user is not at this table" unless members.any? { |member| same_user?(member, target) }
    data = { "role" => observing ? "observer" : "player" }
    data["subject"] = subject if subject

    append_record(
      table_id,
      "room_role",
      data,
      actor: actor
    )
    observer_users(table_id, members: members)
  end

  def join_room(table, user)
    table_id = table_identifier(table)
    return :closed if table_id == nil
    return :already_here if active_session(table_id) != nil && connected_users(table_id).any? { |name| same_user?(name, user) }

    # DiscoveredSession#join creates membership on the endpoint that found it.
    # A widget/notification may pass a row discovered by another program
    # instance. Resolve through this store, whose callback queue the game owns.
    endpoint
    discovered = @mutex.synchronize { @discovered[table_id] }
    discovered ||= discover_item(table_id)
    return :closed if discovered == nil
    # Refresh only at the explicit join boundary, not while navigating a list.
    # A cached full table may have gained a free place since it was displayed.
    if discovered.respond_to?(:refresh) && discovered.respond_to?(:limits) && discovered.limits.to_h["discovery_refresh"] == true
      discovered.refresh(timeout: 10)
    end
    return :closed if discovered.respond_to?(:state) && discovered.state.to_s == "closed"
    return :full if discovered.respond_to?(:can_join?) && !discovered.can_join? && discovered.join_reason.to_s == "full"

    session = discovered.join(participant_metadata: participant_metadata(table_id))
    admit_joined_session(table_id, session)
  end

  def update_room(table_or_id, changes, actor:)
    table_id = table_identifier(table_or_id)
    raise ArgumentError, "Invalid room" if table_id == nil

    allowed = %w[status bot_count bot_names bot_players game_options updated_at]
    values = changes.to_h.each_with_object({}) do |(key, value), result|
      name = key.to_s
      result[name] = value if allowed.include?(name)
    end
    values["updated_at"] = GameRoomClock.now.to_i
    append_record(table_id, "room_state", values, actor: actor)
    publish_discovery(table_id)
    table_for(table_id)
  end

  # Called from the existing network/snapshot path, never from a native UI
  # callback. A room change updates its public description, not its identity.
  # Failed publication must not turn an already committed game action into a
  # failed action. Retain the old fingerprint so the next sync can retry.
  def publish_discovery(table_id, expected_session: nil)
    begin_room_io(table_id)
    session = active_session(table_id)
    return false unless session&.owner? && session.respond_to?(:update_discovery_metadata)
    return false if expected_session && !session.equal?(expected_session)
    lock = @mutex.synchronize { room_state(table_id).control_lock ||= Mutex.new }
    unless lock.try_lock
      queue_discovery_publication(table_id, delay: 1)
      return false
    end
    begin
      return false unless active_session(table_id).equal?(session) && session.owner?
      row = table_for(table_id)
      return false unless row
      metadata = session.metadata.to_h.merge(control_metadata(session)).merge(
        "owner" => row["owner"], "name" => row["name"], "game" => row["game"],
        "game_options" => row["game_options"], "status" => row["status"],
        "bot_count" => row["bot_count"], "player_count" => row["player_count"],
        "max_players" => row["max_players"])
      previous = session.discovery_metadata.to_h['last_activity_at'].to_i
      activity = row['last_activity_at'].to_i
      deadline = @mutex.synchronize { @activity_publish_at.fetch(table_id, 0) }
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if activity > previous && now < deadline
        queue_discovery_publication(table_id, delay: deadline - now)
        activity = previous
      end
      metadata['last_activity_at'] = activity if activity.positive?
      metadata['roster'] = discovery_roster(table_id, session, row)
      metadata.delete('roster') unless metadata['roster']
      return false if @published_discovery[table_id] == metadata
      if now < @discovery_retry_at.fetch(table_id, 0)
        queue_discovery_publication(table_id, delay: @discovery_retry_at[table_id] - now)
        return false
      end
      session.update_discovery_metadata(compact_discovery(metadata), timeout: 5)
      @mutex.synchronize { @activity_publish_at[table_id] = now + 60 } if activity > previous
      @published_discovery[table_id] = metadata
      @discovery_retry_at.delete(table_id)
      true
    rescue StandardError => error
      @discovery_retry_at[table_id] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      queue_discovery_publication(table_id, delay: 5)
      log_warning("discovery publication", table_id, error)
      false
    ensure
      lock.unlock
    end
  ensure
    end_room_io(table_id)
  end

  # Server ownership is the only source of current rights. The stack ledger
  # records their history; neither the creator nor an arbitrary stack writer
  # can confer these rights by declaring themselves the new master.
  def transfer_room_owner(table_or_id, user, control_guard: nil)
    id = table_identifier(table_or_id)
    native = active_session(id)
    raise ArgumentError, "Only the table master may transfer the table" unless native&.owner?
    target = native.participants.find { |participant| same_user?(participant.user, user) }
    raise ArgumentError, "The user is not at this table" unless target
    return true if same_user?(native.owner.user, user)
    control_guard&.call
    begin
      native.transfer_ownership(target)
    rescue StandardError => error
      # A native owner-changed event may have confirmed the mutation before
      # its HTTP reply failed. Never resend a transfer speculatively.
      dispatch_pending_events
      raise error unless same_user?(native.owner&.user, user)
    end
    raise GameRoomNetworkErrors::UncertainWrite, "Table master transfer is not confirmed" unless same_user?(native.owner&.user, user)
    emit_change(id, :table, nil)
    true
  end

  def reconcile_control_owner(table_or_id)
    id = table_identifier(table_or_id)
    native = active_session(id)
    return false unless native&.owner? && native.respond_to?(:update_discovery_metadata)
    ledger = control_ledger(id)
    return false unless ledger.complete
    return false if same_user?(ledger.current_owner, native.owner.user)
    latest = records_for(id).reverse.find { |r| r.packet["kind"] == "game_started" }
    game_id = latest&.packet&.dig("data", "session_id").to_i
    initial = latest&.packet&.dig('data', 'players').to_a
    publish_control(id, game_id, {}, players: initial.empty? ? nil : ledger.players(game_id, initial: initial))
    true
  end

  def set_seat_controller(table_or_id, session_id:, seat:, bot:, control_guard: nil)
    raise ArgumentError, 'Choose the replacement participant' unless bot
    replace_game_player(table_or_id, session_id: session_id, player: seat, control_guard: control_guard)
  end

  # A nil target creates a named bot; a spectator replaces the selected
  # occupant. Everything is one anchored
  # record, so a reader never observes two participants in the same place.
  def replace_game_player(table_or_id, session_id:, player:, replacement: nil, control_guard: nil)
    id = table_identifier(table_or_id)
    native = active_session(id)
    raise ArgumentError, "Only the table master may replace a player" unless native&.owner?
    ledger = control_ledger(id)
    raise GameRoomNetworkErrors::GamePaused, "Table master synchronization is pending" unless ledger.complete && same_user?(ledger.current_owner, native.owner.user)
    game = game_session(session_id, table: id)
    raise GameRoomNetworkErrors::GamePaused, "The player is not in this game" unless game && GameRoomParticipants.includes?(game['__players'], player)
    raise GameRoomNetworkErrors::GamePaused, 'The game is being saved' if game['__frozen']
    publish_control(id, session_id, {}, replacement: [player, replacement], control_guard: control_guard) != false
  end

  def publish_control(table_id, session_id, controllers, checkpoint_from: nil, players: nil, replacement: nil, control_guard: nil)
    begin_room_io(table_id)
    lock = @mutex.synchronize { room_state(table_id).control_lock ||= Mutex.new }
    lock.synchronize do
      native = active_session(table_id)
      raise ArgumentError, "Only the table master may update controllers" unless native&.owner?
      ledger = control_ledger(table_id)
      raise GameRoomNetworkErrors::GamePaused, "Incomplete control history" unless ledger.complete
      if replacement
        control_guard&.call
        latest = records_for(table_id).reverse.find { |row| row.packet['kind'] == 'game_started' }
        raise GameRoomNetworkErrors::GamePaused, 'The game has changed' unless latest && latest.packet.dig('data', 'session_id') == session_id.to_i
        current = game_session(session_id, table: table_id)
        raise GameRoomNetworkErrors::GamePaused, 'The game is being saved' if current['__frozen']
        players = current.fetch('__players').dup
        source, target = replacement
        index = players.index { |person| same_user?(person, source) }
        raise GameRoomNetworkErrors::GamePaused, 'The player is not in this game' unless index
        if target == nil
          raise GameRoomNetworkErrors::GamePaused, 'This place already has a computer' if GameRoomParticipants.bot?(source)
          occupied = (players + connected_users(table_id)).map { |person| GameRoomParticipants.display_name(person) }
          names = GameRoomBotNames.pick(occupied: occupied)
          all_players = current.fetch('__initial_players', []) + current.fetch('__seat_changes', []).flat_map { |change| change['players'] }
          number = (all_players + players).map { |person| GameRoomParticipants.bot_number(person).to_i }.max.to_i + 1
          target = GameRoomParticipants.bot_id(table_id, number, name_token: names)
        else
          # Revalidate after the selection dialog, under the control lock.
          # A stale choice must not exchange two occupied places.
          raise GameRoomNetworkErrors::GamePaused, 'The replacement is already playing' if GameRoomParticipants.includes?(players, target)
          target = connected_users(table_id).find { |person| same_user?(person, target) }
          raise GameRoomNetworkErrors::GamePaused, 'The user is not at this table' unless target && GameRoomParticipants.human?(target)
        end
        players[index] = target
      end
      # A control change must be anchored with its actual server position, not
      # a guessed next position (another participant can append concurrently).
      data = {"previous" => checkpoint_from ? nil : ledger.anchor, "owner" => native.owner.user,
        "session_id" => session_id.to_i, "controllers" => controllers, "from" => checkpoint_from || 0}
      data['players'] = players if players
      record = append_record(table_id, GameRoomTableControl::KIND, data, actor: Session.name)
      # The stack orders remote actions and this candidate. Recheck its exact
      # prior prefix before authenticating the new roster. Failure leaves an
      # inert, unanchored record, just like an unconfirmed metadata write.
      control_guard&.call(record.sequence) if replacement
      anchor = GameRoomTableControl.anchor(record)
      metadata = native.discovery_metadata.to_h.merge(GameRoomTableControl::ANCHOR_KEY => anchor)
      begin
        native.update_discovery_metadata(compact_discovery(metadata), timeout: 5)
      rescue StandardError => error
        dispatch_pending_events
        raise error unless control_metadata(native)[GameRoomTableControl::ANCHOR_KEY] == anchor
      end
      @published_discovery.delete(table_id)
      emit_change(table_id, :table, nil)
      anchor
    end
  ensure
    end_room_io(table_id)
  end

  def deactivate_room(table_or_id)
    table_id = table_identifier(table_or_id)
    return false if table_id == nil

    session = @mutex.synchronize { @sessions[table_id] }
    return false if session == nil

    session.owner? ? session.close : session.leave
    @mutex.synchronize do
      (room_state(table_id).pending_move = nil)
      room_state(table_id).take_recovered_moves
      @native_session_ids.delete_if { |_native_id, id| id == table_id }
      @sessions.delete(table_id)
      retain_inactive_room(table_id)
    end
    emit_presence_change
    true
  end

  def connected_users(table_or_id)
    table_id = table_identifier(table_or_id)
    session = table_id == nil ? nil : active_session(table_id)
    return [] if session == nil

    unique_users(session.participants.to_a.map { |participant| participant.user.to_s })
  end

  # Local membership state only: this must not discover, join or read the
  # server. A table window can be reopened after leaving the same native room.
  def active_membership?(table_or_id)
    table_id = table_identifier(table_or_id)
    table_id != nil && active_session(table_id) != nil
  end

  def append_activity(table:, kind:, actor:, message: "", subject: nil, invitation_id: nil)
    table_id = table_identifier(table)
    raise ArgumentError, "Invalid activity room" if table_id == nil

    data = {
      "activity_kind" => kind.to_s,
      "message" => message.to_s,
      "owner" => table["owner"].to_s,
      "game" => table["game"].to_s
    }
    message_id = nil
    if %w[invited invitation_rejected].include?(kind.to_s)
      data.merge!("subject" => subject.to_s, "invitation_id" => invitation_id.to_i)
      # A lost HTTP reply must not duplicate a confirmed invitation activity.
      hex = Digest::SHA256.hexdigest([table["__live_session_id"], actor.to_s.downcase, invitation_id, kind].join(":"))[0, 32]
      hex[12] = "5"
      hex[16] = "8"
      message_id = [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
    end
    record = append_record(table_id, "room_activity", data, actor: actor, message_id: message_id)
    activity_record(record)
  end

  # One confirmed stack record changes the options and supplies its history.
  # The caller also replays the last match: a room status alone is not proof
  # that it ended. Never replace the room, its participants or its visibility.
  def change_game_options(table:, options:, expected_options:, expected_session_id:)
    table_id = table_identifier(table)
    ensure_current(table_id, force: true)
    current = table_for(table_id)
    latest = game_sessions(table_id).max_by { |row| row["__stack_sequence"].to_i }
    return false unless current && same_user?(endpoint.user, current["owner"])
    return false unless latest.to_h["__id"].to_i == expected_session_id.to_i
    return true if current["game_options"].to_s == options.to_s
    return false unless current["game_options"].to_s == expected_options.to_s
    return false if latest && latest["__frozen"] && !latest["__aborted"]
    return false if latest == nil && !current["resume_save_id"].to_s.empty?
    record = append_record(table_id, "room_state", {
      "game_options" => options.to_s, "options_changed" => true,
      "expected_options" => expected_options.to_s, "expected_session_id" => expected_session_id.to_i,
      "updated_at" => GameRoomClock.now.to_i
    }, actor: endpoint.user)
    _projection, applied = project_room_records(table_id, {})
    record != nil && applied.include?(record.sequence)
  end

  def abort_game(session)
    table_id = table_identifier(session["table_id"])
    id = session["__id"].to_i
    ensure_current(table_id, force: true)
    return false unless same_user?(endpoint.user, owner_for(table_id))
    latest = game_sessions(table_id).max_by { |row| row["__stack_sequence"].to_i }
    return false unless latest.to_h["__id"].to_i == id
    return true if game_aborted?(table_id, id)
    return false if game_frozen?(table_id, id)

    hex = Digest::SHA256.hexdigest("abort:#{active_session(table_id).id}:#{id}")[0, 32]
    hex[12], hex[16] = "5", "8"
    uuid = [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
    append_record(table_id, "game_boundary", {
      "session_id" => id, "frozen" => true, "aborted" => true
    }, actor: endpoint.user, message_id: uuid)
    true
  end

  def start_game(table:, game:, players:, options:, actor:, restore: nil)
    table_id = table_identifier(table)
    raise ArgumentError, "Invalid room" if table_id == nil
    if restore && restore.key?(:statistics)
      unless GameRoomStatistics::Identity.valid?(restore[:statistics], require_started_at: true)
        raise ArgumentError, 'Invalid restored statistics identity'
      end
      statistics = GameRoomStatistics::Identity.copy(restore[:statistics])
    end
    archive = restore && (restore.fetch(:events) + restore.fetch(:seat_changes, [])).sort_by { |item| item['id'] }
    if archive && archive.length > MAX_ARCHIVE_EVENTS
      raise ArgumentError, "The saved game is too large to restore safely"
    end
    archive_id = restore ? SecureRandom.uuid : nil
    ensure_current(table_id, force: true)
    # Requested capacities are not a grant: use this session's server limits.
    # Preflight the entire import before writing its checkpoint or chunks.
    chunks = if archive
      limits = active_session(table_id).limits
      archive_chunks(archive, archive_id: archive_id, actor: actor,
        byte_limit: limits.fetch('max_stack_entry_bytes'), entry_limit: limits.fetch('max_stack_entries'))
    else
      []
    end
    state = table_for(table_id)
    members = connected_users(table_id)
    observers = observer_users(table_id, members: members)
    requested_players = unique_users(players.to_a)
    bots = room_bots(table_id, state)
    restored_controllers = restore ? restore.fetch(:controllers, {}) : {}
    invalid_player = requested_players.any? do |player|
      if GameRoomParticipants.bot?(player)
        !bots.any? { |bot| same_user?(bot, player) }
      else
        restored_controllers[player] != 'bot' && (observers.any? { |observer| same_user?(observer, player) } ||
          !members.any? { |member| same_user?(member, player) })
      end
    end
    if invalid_player
      raise ArgumentError, "The table roles changed before the game started"
    end

    game_session_id = unused_game_identifier(table_id)
    # Persist and verify any local secrets before uploading an archive or
    # making the restored game visible to other clients.
    restore[:before_publish]&.call(game_session_id) if restore != nil
    # Keep one complete room-state record before the new game. The immutable
    # room identity remains in native session metadata. No current-game replay
    # is truncated, and chat already received by this client stays local.
    checkpoint_state = state.slice("status", "bot_count", "bot_names", "bot_players", "game_options", "updated_at")
    checkpoint_state["observers"] = observer_users(table_id)
    checkpoint = append_record(table_id, "room_state", checkpoint_state, actor: actor)
    if restore != nil
      # A retried import may leave orphan archive chunks, but no published
      # game. Retain this complete room checkpoint before uploading again.
      trim_previous_games(table_id, checkpoint.sequence - 1) if game_sessions(table_id).empty?
      chunks.each_with_index do |events, index|
        append_record(table_id, "game_archive", { "archive_id" => archive_id, "index" => index, "events" => events }, actor: actor)
      end
    end
    payload = {
      "session_id" => game_session_id,
      "game" => game.to_s,
      "players" => players.to_a.map(&:to_s),
      "options" => options.to_s,
      "created_at" => GameRoomClock.now.to_i
    }
    payload['statistics'] = GameRoomStatistics::Identity.create(players: requested_players) unless restore
    if restore != nil
      payload['statistics'] = statistics if statistics
      payload['controllers'] = restored_controllers unless restored_controllers.empty?
      payload['initial_players'] = restore.fetch(:initial_players, requested_players)
      payload.merge!("archive_id" => archive_id, "archive_events" => archive.length,
        "event_id_base" => archive.map { |event| event["id"] }.max.to_i,
        "clock_offset" => restore[:game_time] == nil ? restore.fetch(:clock_offset).to_i : GameRoomClock.now.to_i - restore[:game_time].to_i)
    end
    record = append_record(table_id, "game_started", payload, actor: actor)
    trim_previous_games(table_id, checkpoint.sequence - 1) if record != nil && checkpoint != nil
    game_session_from(record)
  end

  def freeze_game(session, frozen: true, expected_boundary: nil)
    table_id = table_identifier(session["table_id"])
    return false if expected_boundary && active_session(table_id) == nil
    ensure_current(table_id, force: true)
    latest = game_sessions(table_id).max_by { |row| row["__stack_sequence"].to_i }
    current = latest.to_h["__id"].to_i == session["__id"].to_i && same_user?(endpoint.user, owner_for(table_id))
    if expected_boundary
      boundary = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_boundary" && record.packet.dig("data", "session_id") == session["__id"].to_i }
      # Only release this operation's pause, never a later save, aborted match
      # or a different master's game. The confirmed record is the receipt.
      return false unless !frozen && current && boundary && boundary.message_id == expected_boundary.message_id &&
        boundary.packet.dig("data", "frozen") == true && !game_aborted?(table_id, session["__id"])
    end
    raise GameRoomNetworkErrors::GamePaused, "The game controller changed" unless current
    raise GameRoomNetworkErrors::GamePaused, "The game was ended by the master" if game_aborted?(table_id, session["__id"])
    # Return the confirmed write before any subsequent snapshot/network read.
    append_record(table_id, "game_boundary", { "session_id" => session["__id"].to_i, "frozen" => frozen == true }, actor: endpoint.user)
  end

  def wait_for_room(table_id, timeout: 10.0)
    wanted = table_identifier(table_id)
    return false if wanted == nil

    deadline = monotonic + [timeout.to_f, 0.0].max
    loop do
      return true if active_session(wanted) != nil
      return false if monotonic >= deadline

      sleep 0.01
    end
  end

  private

  def trim_previous_games(table_id, through)
    return if through <= 0

    session = active_session(table_id)
    return if session == nil || !session.owner?

    ledger = control_ledger(table_id)
    if ledger.anchor
      latest = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_started" }
      # Establish a new owner-anchored root before discarding the old chain.
      # If publication is uncertain, the old log remains available in full.
      publish_control(table_id, latest.packet.dig("data", "session_id"), {}, checkpoint_from: through + 1)
    end
    session.stack_trim(through: through)
  rescue StandardError => error
    # The game is already committed. A failed/uncertain trim must not make the
    # caller retry starting it, or remove any additional records speculatively.
    log_warning("previous game cleanup", table_id, error)
  end

  # Discovery and invitation acceptance must apply the same human + bot limit.
  # The native capacity alone only counts connected humans.
  def admit_joined_session(table_id, session)
    attach_session(table_id, session)
    snapshot = room_snapshot(table_id)
    status = if snapshot == nil
      :closed
    elsif (snapshot[:members] - snapshot[:observers]).length + snapshot[:bots].length > snapshot[:table]["max_players"].to_i
      :full
    else
      :joined
    end
    deactivate_room(table_id) if status != :joined
    status
  rescue StandardError
    begin
      deactivate_room(table_id)
      session.leave if !session.closed?
    rescue StandardError => error
      log_warning("rejected membership cleanup", table_id, error)
    end
    raise
  end

  def endpoint
    current = @endpoint_provider.call
    changed = @mutex.synchronize do
      different = !@endpoint.equal?(current)
      @endpoint = current
      @discovered.clear if different
      different
    end
    if changed
      register_invitation_callback(current)
      if current.respond_to?(:on_error)
        current.on_error do |error|
          next if !@endpoint.equal?(current) || !GameRoomNetworkErrors.transient?(error)

          active_table_ids.each { |id| emit_change(id, :network_error, error) }
        end
      end
    end
    current
  end

  def discover_pages(sources: [:created, :invited, :public])
    return [] if !endpoint.respond_to?(:discover_sessions)

    result = []
    cursor = nil
    loop do
      page = endpoint.discover_sessions(
        sources: sources,
        limit: DISCOVERY_LIMIT,
        cursor: cursor
      )
      result.concat(page.to_a)
      cursor = page.respond_to?(:next_cursor) ? page.next_cursor : nil
      break if cursor.to_s.empty?
    end
    result
  end

  def discover_item(table_id)
    discover_pages.find do |item|
      metadata = item.discovery_metadata.to_h
      supported_metadata?(metadata) && metadata["table_id"].to_i == table_id.to_i
    end
  end

  def attach_supported_session(session)
    metadata = session.metadata.to_h
    return nil if !supported_metadata?(metadata)

    table_id = positive_identifier(metadata["table_id"])
    table_id == nil ? nil : attach_session(table_id, session)
  end

  def attach_session(table_id, session)
    existing = @mutex.synchronize { @sessions[table_id] }
    return existing if existing.equal?(session)

    attachment = Object.new

    attach_game_message_handler(table_id, session) if session.respond_to?(:on_message)

    if session.respond_to?(:on_stack_message)
      session.on_stack_message(with_metadata: true) do |sender, packet, info|
        next unless @mutex.synchronize { @sessions[table_id].equal?(session) }
        ingest_record(
          table_id,
          sequence: info.sequence,
          message_id: info.id,
          sender: sender.user,
          packet: packet,
          created_at: info.created_at,
          source_session: session
        )
      end
      session.on_stack_gap do |_gap|
        next unless @mutex.synchronize { @sessions[table_id].equal?(session) }
        # Wake the normal synchronizer; do not run a blocking read inside a
        # native callback. A read failure must retain the recovery wake-up.
        emit_change(table_id, :recovery, nil)
      end
    end
    session.on_participant_joined { |_participant| emit_change(table_id, :table, nil); emit_presence_change } if session.respond_to?(:on_participant_joined)
    session.on_participant_left { |_participant, _reason = nil| emit_change(table_id, :table, nil); emit_presence_change } if session.respond_to?(:on_participant_left)
    session.on_owner_changed { |_previous, _current| emit_change(table_id, :table, nil) } if session.respond_to?(:on_owner_changed)
    session.on_discovery_metadata_changed { |_metadata| emit_change(table_id, :table, nil) } if session.respond_to?(:on_discovery_metadata_changed)
    if session.respond_to?(:on_closed)
      session.on_closed do |_reason|
        current_closed = @mutex.synchronize do
          # A recovered membership may already have replaced this native
          # object. Its delayed close callback must not close the new view or
          # discard the new membership's pending move/private messages.
          current = @sessions[table_id]
          next false if current && !current.equal?(session)
          next false unless room_state(table_id).attachment.equal?(attachment)
          @sessions.delete(table_id)
          (room_state(table_id).pending_move = nil)
          room_state(table_id).take_recovered_moves
          room_state(table_id).take_private_game_messages
          room_state(table_id).take_public_game_previews
          @native_session_ids.delete(session.id.to_s) if session.respond_to?(:id)
          retain_inactive_room(table_id)
          true
        end
        if current_closed
          emit_change(table_id, :closed, nil)
          emit_presence_change
        end
      end
    end
    @mutex.synchronize do
      @sessions[table_id] = session
      room_state(table_id).attachment = attachment
      @inactive_rooms.delete(table_id)
      @native_session_ids[session.id.to_s] = table_id if session.respond_to?(:id)
    end
    ensure_current(table_id, force: true) if session.respond_to?(:stack_read)
    emit_presence_change
    session
  end

  def attach_game_message_handler(table_id, session)
    session.on_message(with_metadata: true) do |sender, packet, info|
      if info.respond_to?(:private?) && !info.private? && packet.is_a?(Hash) &&
          packet["type"] == "game_room_preview" && packet["version"] == 1 &&
          packet["session_id"].is_a?(Integer) && packet["session_id"].positive? &&
          packet["payload"].is_a?(Hash) && JSON.generate(packet["payload"]).bytesize <= 2048
        @mutex.synchronize do
          next unless @sessions[table_id].equal?(session)
          queue = room_state(table_id).public_game_previews
          queue << {sender: sender.user.to_s, session_id: packet["session_id"],
            payload: JSON.parse(JSON.generate(packet["payload"]))}
          queue.shift while queue.length > 64
        end
        next
      end
      next unless info.respond_to?(:private?) && info.private? &&
        info.recipient_user.to_s.casecmp(endpoint.user.to_s).zero? && packet.is_a?(Hash) &&
        packet["type"] == "game_room_private" && packet["version"] == 1 &&
        packet["session_id"].is_a?(Integer) && packet["session_id"].positive? &&
        packet["payload"].is_a?(Hash) && JSON.generate(packet["payload"]).bytesize <= 2048
      @mutex.synchronize do
        next unless @sessions[table_id].equal?(session)
        queue = room_state(table_id).private_game_messages
        queue << {sender: sender.user.to_s, session_id: packet["session_id"],
          payload: JSON.parse(JSON.generate(packet["payload"]))}
        queue.shift while queue.length > 64
      end
    end
  end

  def ensure_current(table_id, force: false, cancellation_token: nil, timeout: nil)
    begin_room_io(table_id)
    session = active_session(table_id)
    return false if session == nil || !session.respond_to?(:stack_read)

    last_sequence = session.respond_to?(:stack_state) ? session.stack_state["last_seq"].to_i : 0
    cursor = @mutex.synchronize { room_state(table_id).stack_cursor.to_i }
    return true if !force && last_sequence <= cursor

    read_options = {}
    read_options[:cancellation_token] = cancellation_token if cancellation_token
    read_options[:timeout] = timeout if timeout
    loop do
      cancellation_token&.raise_if_cancelled!
      page = session.stack_read(after: cursor, limit: STACK_PAGE_SIZE, **read_options)
      return false unless @mutex.synchronize { @sessions[table_id].equal?(session) }
      Array(page["entries"]).each do |entry|
        sender = if entry["sender"].is_a?(Hash)
          entry["sender"]["user"].to_s
        elsif session.respond_to?(:participant)
          session.participant(entry["sender_id"])&.user.to_s
        else
          ""
        end
        ingest_record(
          table_id,
          sequence: entry["seq"],
          message_id: entry["message_id"],
          sender: sender,
          packet: entry["packet"],
          created_at: entry["created_at"],
          source_session: session
        )
      end
      next_cursor = page["cursor"].to_i
      current = @mutex.synchronize do
        next false unless @sessions[table_id].equal?(session)

        room_state(table_id).stack_cursor = [room_state(table_id).stack_cursor.to_i, next_cursor].max
        room_state(table_id).received_sequences.delete_if { |seq, _| seq <= room_state(table_id).stack_cursor }
        true
      end
      return false unless current
      break if next_cursor <= cursor || page["has_more"] != true

      cursor = next_cursor
    end
    true
  rescue StandardError => error
    log_warning("stack read", table_id, error)
    # Do not present a partial local prefix as a successful server snapshot.
    # The UI's network boundary handles the error and its synchronizer retries.
    raise
  ensure
    end_room_io(table_id)
  end

  def records_for(table_id)
    source, raw, generation, cache = @mutex.synchronize do
      source = @rooms[table_id]&.records
      [source, source.to_a.dup, (@rooms[table_id]&.record_generation || 0), @rooms[table_id]&.validated_records]
    end
    native = active_session(table_id)
    anchor = control_metadata(native)[GameRoomTableControl::ANCHOR_KEY]
    key = [generation, native, anchor]
    return cache[:records].dup if cache && cache[:key] == key
    ledger = control_ledger(table_id, raw: raw, native: native)
    return [] unless ledger.complete
    # A new-game checkpoint may compact the server log. Preserve this client's
    # already verified older room/chat history, but never trust an unseen raw
    # prefix using the new owner's authority.
    root = ledger.records.first
    prefix_end = root && root.packet["data"]["previous"] == nil ? root.packet["data"]["from"].to_i : 0
    accepted = cache ? cache[:records].select { |record| record.sequence < prefix_end } : []
    retained = accepted.to_h { |record| [record.sequence, true] }
    validator = RecordValidator.new(accepted)
    raw.each do |record|
      next if retained[record.sequence]
      accepted << record if validator.accept(record, owner: ledger.owner_at(record.sequence), ledger: ledger)
    end
    @mutex.synchronize do
      # Counters restart after pruning. Check the actual collection and native
      # membership too, so a slower reader cannot publish into a rejoined room.
      if source && @rooms[table_id]&.records.equal?(source) &&
          @sessions[table_id].equal?(native) && room_state(table_id).record_generation == generation
        room_state(table_id).validated_records = {key: key, records: accepted.freeze}
      end
    end
    accepted.dup
  end

  def control_metadata(native)
    return {} unless native&.respond_to?(:discovery_metadata)
    native.discovery_metadata.to_h.select { |key, _| key == GameRoomTableControl::ANCHOR_KEY }
  end

  def control_ledger(table_id, raw: nil, native: active_session(table_id))
    raw ||= @mutex.synchronize { (@rooms[table_id]&.records || []).dup }
    GameRoomTableControl.new(founder: native&.metadata.to_h["owner"], records: raw,
      anchor: control_metadata(native)[GameRoomTableControl::ANCHOR_KEY])
  end

  def command_value(command, key)
    GameRoomEventProtocol.command_value(command, key)
  end

  def owner_for(table_id)
    session = active_session(table_id)
    session_owner = session&.respond_to?(:owner) ? session.owner&.user.to_s : ""
    return session_owner if !session_owner.empty?

    session&.metadata.to_h["owner"].to_s
  end

  def active_session(table_id)
    @mutex.synchronize do
      session = @sessions[table_id]
      if session != nil && session.respond_to?(:closed?) && session.closed?
        @sessions.delete(table_id)
        retain_inactive_room(table_id)
        session = nil
      end
      session
    end
  end

  def active_table_ids
    @mutex.synchronize { @sessions.keys.dup }
  end

  def supported_metadata?(metadata)
    metadata.is_a?(Hash) &&
      metadata["kind"].to_s == KIND &&
      [PROTOCOL, FEATURE_DISCOVERY_PROTOCOL, LIFECYCLE_DISCOVERY_PROTOCOL, NAMED_SEATS_DISCOVERY_PROTOCOL, THINKING_TIME_DISCOVERY_PROTOCOL, CURRENT_DISCOVERY_PROTOCOL].include?(metadata["protocol"].to_i) &&
      positive_identifier(metadata["table_id"]) != nil
  end

  # Discovery has a smaller budget than the private session metadata. Reserve
  # room for the owner-only control anchor even before the first handover.
  # Keep the complete options (including custom profiles), never substitute
  # defaults just to fit the public description.
  def compact_discovery(metadata)
    result = metadata.dup
    result.delete('statistics_room_id')
    # Optional roster information must never evict settings or control anchors.
    result.delete('roster') if JSON.generate(result).bytesize > DISCOVERY_BYTES && !result.key?('game_options')
    if result.key?('game_options')
      options = result['game_options'].to_s
      raise ArgumentError, 'Game options are too large' if options.bytesize > MAX_OPTIONS_BYTES
      result.delete('options_z')
      if JSON.generate(result).bytesize > DISCOVERY_BYTES - 120
        result.delete('game_options')
        result['options_z'] = Base64.strict_encode64(Zlib::Deflate.deflate(options))
      end
    end
    result.delete('roster') if JSON.generate(result).bytesize > DISCOVERY_BYTES
    raise ArgumentError, 'Table discovery metadata is too large' if JSON.generate(result).bytesize > DISCOVERY_BYTES
    result
  end

  def discovery_options(metadata)
    return metadata['game_options'].to_s unless metadata.key?('options_z')
    compressed = Base64.strict_decode64(metadata['options_z'].to_s)
    raise ArgumentError, 'Invalid table options' if compressed.bytesize > DISCOVERY_BYTES
    inflater = Zlib::Inflate.new
    output = String.new(encoding: Encoding::BINARY)
    inflater.inflate(compressed) do |chunk|
      raise ArgumentError, 'Table options are too large' if output.bytesize + chunk.bytesize > MAX_OPTIONS_BYTES
      output << chunk
    end
    raise ArgumentError, 'Incomplete table options' unless inflater.finished? && inflater.total_in == compressed.bytesize
    output.force_encoding(Encoding::UTF_8)
    raise ArgumentError, 'Invalid table options' unless output.valid_encoding? && JSON.parse(output).is_a?(Hash)
    output
  ensure
    inflater&.close
  end

  def participant_metadata(table_id)
    { "table_id" => table_id.to_i, "client" => "elten_game_room" }
  end

  def table_identifier(value)
    raw = if value.is_a?(Hash)
      value["__id"] || value["id"] || value["table_id"]
    else
      value
    end
    positive_identifier(raw)
  end

  def positive_identifier(value)
    number = Integer(value.to_s, 10)
    number if number.positive?
  rescue ArgumentError, TypeError
    nil
  end

  def unused_identifier
    loop do
      id = SecureRandom.random_number(2_000_000_000) + 1
      return id if !active_table_ids.include?(id)
    end
  end

  def unused_game_identifier(table_id)
    used = game_sessions(table_id).map { |row| row["__id"].to_i }
    loop do
      id = SecureRandom.random_number(2_000_000_000) + 1
      return id if !used.include?(id)
    end
  end

  def bounded_capacity(value)
    [[value.to_i, 2].max, MAX_CAPACITY].min
  end

  def normalize_time(value)
    return value.to_i if value.respond_to?(:to_i) && value.to_i.positive?

    GameRoomClock.now.to_i
  end

  def unique_users(users)
    users.to_a.each_with_object([]) do |user, result|
      value = user.to_s
      next if value.empty? || result.any? { |candidate| same_user?(candidate, value) }

      result << value
    end
  end

  def same_user?(first, second)
    !first.to_s.empty? && first.to_s.casecmp(second.to_s) == 0
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rescue Exception
    Time.now.to_f
  end

  def log_warning(stage, table_id, error)
    return if !defined?(Log)

    suffix = table_id == nil ? "" : " for table #{table_id}"
    Log.warning("ELTEN Game Room LiveSessions #{stage} failed#{suffix}: #{error.class}: #{error.message}")
  end
end

require_relative 'live_session_record_validator'
require_relative 'live_session_retention'
GameRoomLiveSessionStore.include(GameRoomLiveSessionStore::Retention)
require_relative 'live_session_discovery'
GameRoomLiveSessionStore.include(GameRoomLiveSessionStore::Discovery)

require_relative 'live_session_room_state'

require_relative "live_session_projections"

require_relative "live_session_writer"

require_relative "live_session_invitations"

require_relative "live_session_archive"
