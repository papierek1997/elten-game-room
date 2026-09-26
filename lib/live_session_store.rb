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

  def initialize(program, changed: nil, endpoint_provider: nil)
    @program = program
    @changed = changed
    @endpoint_provider = endpoint_provider || -> { @program.live_sessions }
    @endpoint = nil
    @invitation_endpoint = nil
    @sessions = {}
    @native_session_ids = {}
    @records = Hash.new { |hash, key| hash[key] = [] }
    @record_keys = Hash.new { |hash, key| hash[key] = {} }
    @clock_revisions = Hash.new(0)
    @message_records = Hash.new { |hash, key| hash[key] = {} }
    @pending_moves = {}
    @recovered_moves = Hash.new { |hash, key| hash[key] = [] }
    @stack_cursors = Hash.new(0)
    @received_sequences = Hash.new { |hash, key| hash[key] = {} }
    @discovered = {}
    @pending_invitations = {}
    @resolved_invitations = {}
    @private_game_messages = Hash.new { |hash, key| hash[key] = [] }
    @mutex = Mutex.new
    @callback_dispatch_mutex = Mutex.new
    @published_discovery = {}
    @discovery_retry_at = {}
    @record_generations = Hash.new(0)
    @validated_records = {}
    @control_locks = {}
    @attachments = {}
    @inactive_rooms = {}
    @room_io = {}
    @retained_subscriptions = {}
  end

  def start
    GameRoomClock.synchronize
    current = endpoint
    current.sessions.to_a.each { |session| attach_supported_session(session) } if current.respond_to?(:sessions)
    true
  end

  # ELTEN keeps protocol I/O running while its main scene is suspended, but
  # does not dispatch callbacks to a parallel scene. Drain only this already
  # opened endpoint; never reconnect, poll the server or tick other programs.
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
    end
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
    @mutex.synchronize { @private_game_messages.fetch(table_id, []).any? { |item| item[:session_id] == session_id.to_i } }
  end

  def take_private_game_messages(table_id, session_id)
    @mutex.synchronize do
      messages = @private_game_messages.delete(table_id) || []
      messages.select { |item| item[:session_id] == session_id.to_i }
    end
  end

  def create_room(name:, game:, owner:, game_options:, capacity: MAX_CAPACITY, private_table: false, resume_save_id: nil, bot_count: 0, bot_names: nil)
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

  def room_bots(table_id, table)
    table['bot_players'] || GameRoomParticipants.bots_for(table_id, table['bot_count'].to_i, names: table['bot_names'])
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
    {
      table: table,
      members: unique_users(members),
      bots: room_bots(table_id, table),
      observers: observer_users(table_id, members: members)
    }
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

    discovered = table.is_a?(Hash) ? table["__discovered_session"] : nil
    discovered ||= @mutex.synchronize { @discovered[table_id] }
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
  def publish_discovery(table_id)
    begin_room_io(table_id)
    session = active_session(table_id)
    return false unless session&.owner? && session.respond_to?(:update_discovery_metadata)
    lock = @mutex.synchronize { @control_locks[table_id] ||= Mutex.new }
    return false unless lock.try_lock
    begin
      row = table_for(table_id)
      return false unless row
      metadata = session.metadata.to_h.merge(control_metadata(session)).merge(
        "owner" => row["owner"], "name" => row["name"], "game" => row["game"],
        "game_options" => row["game_options"], "status" => row["status"],
        "bot_count" => row["bot_count"], "player_count" => row["player_count"],
        "max_players" => row["max_players"])
      return false if @published_discovery[table_id] == metadata
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) < @discovery_retry_at.fetch(table_id, 0)
      session.update_discovery_metadata(compact_discovery(metadata), timeout: 5)
      @published_discovery[table_id] = metadata
      @discovery_retry_at.delete(table_id)
      true
    rescue StandardError => error
      @discovery_retry_at[table_id] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
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
    lock = @mutex.synchronize { @control_locks[table_id] ||= Mutex.new }
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
      @pending_moves.delete(table_id)
      @recovered_moves.delete(table_id)
      @native_session_ids.delete_if { |_native_id, id| id == table_id }
      @sessions.delete(table_id)
      retain_inactive_room(table_id)
    end
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

  def activity_records(table_or_id)
    table_id = table_identifier(table_or_id)
    return [] if table_id == nil

    ensure_current(table_id)
    ended = {}
    records = records_for(table_id)
    base = table_from_metadata(active_session(table_id)&.metadata.to_h, table_id) || {}
    projection, option_changes = project_room_records(table_id, base, records: records)
    ledger = control_ledger(table_id)
    lifecycle = ->(record, kind) { lifecycle_activity(record, kind, ledger: ledger, game: projection['game']) }
    starts = records.select { |record| record.packet['kind'] == 'game_started' }
      .group_by { |record| record.packet.dig('data', 'session_id') }
    records.flat_map do |record|
      if record.packet["kind"] == "game_boundary" && record.packet.dig("data", "aborted") == true
        id = record.packet.dig("data", "session_id")
        next if ended[id]
        ended[id] = true
        lifecycle.call(record, "game_aborted")
      elsif record.packet["kind"] == "room_state" && record.packet.dig("data", "options_changed") == true
        lifecycle.call(record, "options_changed") if option_changes.include?(record.sequence)
      elsif record.packet["kind"] == "room_activity"
        activity_record(record, ledger: ledger)
      elsif record.packet["kind"] == "room_role" && record.packet.dig("data", "subject")
        lifecycle.call(record, "role_changed")
      elsif record.packet["kind"] == GameRoomTableControl::KIND
        data = record.packet["data"]
        next [] unless data["from"].zero?
        changes = []
        if !same_user?(ledger.owner_at(record.sequence - 1), record.sender)
          changes << lifecycle.call(record, "owner_changed")
        end
        game = starts[data['session_id']]&.first
        initial = game&.packet&.dig('data', 'players').to_a
        prior = ledger.players(data['session_id'], initial: initial, before: record.sequence)
        data.fetch('players', prior).each_with_index do |person, index|
          next if prior[index] == person
          changes << lifecycle.call(record, 'player_replaced').merge(
            'subject' => prior[index], 'replacement' => person,
            '__id' => record.sequence * EVENT_ID_MULTIPLIER + changes.length)
        end
        changes
      end
    end.compact
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

  def game_aborted?(table_id, session_id)
    records_for(table_id).any? do |record|
      record.packet["kind"] == "game_boundary" && record.packet.dig("data", "session_id") == session_id.to_i && record.packet.dig("data", "aborted") == true
    end
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
    chunks = archive ? archive_chunks(archive, archive_id: archive_id, actor: actor) : []

    ensure_current(table_id, force: true)
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

  def game_sessions(table_or_id = nil, force: false)
    table_id = table_or_id == nil ? nil : table_identifier(table_or_id)
    ids = table_id == nil ? active_table_ids : [table_id]
    ids.compact.flat_map do |id|
      ensure_current(id, force: force)
      records_for(id).filter_map do |record|
        game_session_from(record) if record.packet["kind"].to_s == "game_started"
      end
    end.sort_by { |row| row["__id"].to_i }
  end

  def game_session(session_id, table: nil)
    wanted = positive_identifier(session_id)
    return nil if wanted == nil

    game_sessions(table).find { |row| row["__id"].to_i == wanted }
  end

  def append_game_action(session:, sequence:, events:, actor:, controller: false)
    table_id = positive_identifier(session["table_id"])
    session_id = positive_identifier(session["__id"] || session["id"])
    raise ArgumentError, "Invalid game" if table_id == nil || session_id == nil
    ledger = control_ledger(table_id)
    raise GameRoomNetworkErrors::GamePaused, "Table master synchronization is pending" unless ledger.complete && same_user?(ledger.current_owner, owner_for(table_id))
    if session.key?("__control_epoch") && session["__control_epoch"] != ledger.epoch
      raise GameRoomNetworkErrors::GamePaused, "The game controller changed"
    end
    if controller || GameRoomParticipants.bot?(actor)
      raise ArgumentError, "Only the current table master may control this action" unless same_user?(Session.name, owner_for(table_id))
    elsif !same_user?(actor, Session.name)
      raise ArgumentError, "You no longer control this seat"
    end
    raise ArgumentError, 'The player is not in this game' unless GameRoomParticipants.includes?(
      game_session(session_id, table: table_id).to_h.fetch('__players', []), actor)
    raise GameRoomNetworkErrors::GamePaused, "The game was ended by the master" if game_aborted?(table_id, session_id)
    raise GameRoomNetworkErrors::GamePaused, "The game is being saved" if game_frozen?(table_id, session_id)

    commands = events.to_a.map do |event|
      {
        "action" => command_value(event, "action").to_s,
        "value" => command_value(event, "value").to_s,
        "move_id" => SecureRandom.uuid
      }
    end
    record = append_record(table_id, "game_action", {
      "session_id" => session_id,
      "sequence" => sequence.to_i,
      "controller" => controller == true,
      "control_epoch" => ledger.epoch,
      "events" => commands
    }, actor: actor)
    expand_game_action(record)
  end

  def game_events(session, force: false)
    table_id = positive_identifier(session["table_id"])
    session_id = positive_identifier(session["__id"] || session["id"])
    return [] if table_id == nil || session_id == nil

    ensure_current(table_id, force: force)
    records = records_for(table_id)
    ledger = control_ledger(table_id)
    starts = records.select { |record| record.packet['kind'] == 'game_started' && record.packet.dig('data', 'session_id') == session_id }
    # Historical archive lookup used the first start; live action expansion
    # used the latest start's ID base. Reuse both without changing that format.
    game_record = starts.first
    action_game_record = starts.last
    frozen = false
    aborted = false
    imported = if !session["__archive_id"].to_s.empty?
      (game_record == nil ? [] : archive_events_for(game_record).to_a).reject { |item| item.key?('players') }.map do |event|
            event.merge("__id" => event["id"], "session_id" => session_id, "table_id" => table_id,
              "__insertion_user" => game_record.sender, "__controller" => true, "move_id" => "archive:#{game_record.message_id}:#{event['id']}")
      end
    else
      []
    end
    current = records.flat_map do |record|
      if record.packet["kind"] == "game_boundary" && record.packet.dig("data", "session_id") == session_id
        frozen = record.packet.dig("data", "frozen") == true
        aborted ||= record.packet.dig("data", "aborted") == true
      end
      next [] if record.packet["kind"].to_s != "game_action"
      next [] if record.packet.dig("data", "session_id").to_i != session_id
      next [] if frozen || aborted

      expand_game_action(record, game_record: action_game_record, ledger: ledger)
    end
    (imported + current).sort_by { |row| row["__id"].to_i }
  end

  def freeze_game(session, frozen: true)
    table_id = table_identifier(session["table_id"])
    ensure_current(table_id, force: true)
    raise GameRoomNetworkErrors::GamePaused, "The game was ended by the master" if game_aborted?(table_id, session["__id"])
    boundary = append_record(table_id, "game_boundary", { "session_id" => session["__id"].to_i, "frozen" => frozen == true }, actor: endpoint.user)
    game_events(session, force: true)
    boundary
  end

  def game_frozen?(table_id, session_id)
    boundary = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_boundary" && record.packet.dig("data", "session_id") == session_id.to_i }
    boundary != nil && boundary.packet.dig("data", "frozen") == true
  end

  def consume_recovered_game_events(session)
    table_id = session["table_id"].to_i
    records = @mutex.synchronize do
      @recovered_moves.delete(table_id).to_a.map do |record|
        @message_records[table_id][[record.sender.downcase, record.message_id]] || record
      end
    end
    return [] if game_aborted?(table_id, session["__id"])
    records.select { |record| record.packet.dig("data", "session_id").to_i == session["__id"].to_i }
      .flat_map { |record| expand_game_action(record) }
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
    prune_invitations
    recipient = endpoint.user.to_s
    @mutex.synchronize do
      @pending_invitations.values.map do |stored|
        invitation = stored[:invitation]
        metadata = invitation.invitation_metadata.to_h
        inviter = invitation.respond_to?(:inviter) ? invitation.inviter.user.to_s : metadata["sender"].to_s
        {
          "__id" => stored[:id],
          "table_id" => stored[:table_id],
          "sender" => inviter,
          "recipient" => recipient,
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

    session = stored[:invitation].accept(participant_metadata: participant_metadata(table_id).merge(participant_metadata.to_h))
    status = admit_joined_session(stored[:table_id], session)
    resolve_invitation(stored[:id])
    status == :joined
  rescue StandardError
    restore_invitation(stored) if stored && stored[:invitation].pending?
    raise
  end

  def reject_invitation(table_id:, invitation_id:)
    stored = take_invitation(table_id, invitation_id)
    return false if stored == nil

    stored[:invitation].reject
    resolve_invitation(stored[:id])
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

  # Only invoked by error/gap recovery, never by an ordinary cached read.
  def pending_move_error(table_id)
    @mutex.synchronize do
      pending = @pending_moves[table_id.to_i]
      pending && (pending[:error] || GameRoomNetworkErrors::PendingMove.new("A game move is awaiting confirmation"))
    end
  end

  def reconcile(table_id)
    table_id = table_identifier(table_id)
    return false if table_id == nil
    return false if !ensure_current(table_id, force: true)

    pending = @mutex.synchronize { @pending_moves[table_id] }
    latest_game = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_started" }
    if pending != nil && latest_game != nil && pending[:packet].dig("data", "session_id") != latest_game.packet.dig("data", "session_id")
      @mutex.synchronize { @pending_moves.delete(table_id) if @pending_moves[table_id].equal?(pending) }
      pending = nil
    end
    if pending != nil
      # An empty read is not evidence that a timed-out request cannot arrive
      # later. Keep its UUID, packet, actor, random values and event sequence.
      write_record(table_id, pending)
    end
    true
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

  def register_invitation_callback(current)
    register = @mutex.synchronize do
      next false if @invitation_endpoint.equal?(current)

      @invitation_endpoint = current
      true
    end
    return if !register

    current.on_invitation { |invitation| receive_invitation(invitation) }
    return if !current.respond_to?(:next_invitation)

    loop do
      invitation = current.next_invitation(timeout: 0)
      break if invitation == nil

      receive_invitation(invitation)
    end
  end

  def receive_invitation(invitation)
    return if invitation.respond_to?(:pending?) && !invitation.pending?

    metadata = invitation.metadata.to_h
    return if !supported_metadata?(metadata)

    invitation_metadata = invitation.invitation_metadata.to_h
    return if invitation_metadata["purpose"].to_s != "game_invitation"

    table_id = positive_identifier(metadata["table_id"])
    invitation_id = positive_identifier(invitation_metadata["invitation_id"])
    return if table_id == nil || invitation_id == nil

    @mutex.synchronize do
      return if @resolved_invitations.key?(invitation_id)

      @pending_invitations[invitation_id] = {
        id: invitation_id,
        table_id: table_id,
        invitation: invitation,
        created_at: GameRoomClock.now.to_i
      }
    end
    emit_change(table_id, :invitation, invitation_id)
  rescue StandardError => error
    log_warning("incoming invitation", nil, error)
  end

  def take_invitation(table_id, invitation_id)
    prune_invitations
    id = positive_identifier(invitation_id)
    room_id = table_identifier(table_id)
    return nil if id == nil || room_id == nil

    @mutex.synchronize do
      stored = @pending_invitations[id]
      next nil if stored == nil || stored[:table_id] != room_id

      @pending_invitations.delete(id)
    end
  end

  def restore_invitation(stored)
    @mutex.synchronize { @pending_invitations[stored[:id]] = stored }
  end

  def resolve_invitation(id)
    @mutex.synchronize do
      @pending_invitations.delete(id.to_i)
      @resolved_invitations[id.to_i] = GameRoomClock.now.to_i + INVITATION_TTL
    end
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

    if session.respond_to?(:on_message)
      session.on_message(with_metadata: true) do |sender, packet, info|
        next unless info.respond_to?(:private?) && info.private? &&
          info.recipient_user.to_s.casecmp(endpoint.user.to_s).zero? && packet.is_a?(Hash) &&
          packet["type"] == "game_room_private" && packet["version"] == 1 &&
          packet["session_id"].is_a?(Integer) && packet["session_id"].positive? &&
          packet["payload"].is_a?(Hash) && JSON.generate(packet["payload"]).bytesize <= 2048
        @mutex.synchronize do
          next unless @sessions[table_id].equal?(session)
          queue = @private_game_messages[table_id]
          queue << {sender: sender.user.to_s, session_id: packet["session_id"],
            payload: JSON.parse(JSON.generate(packet["payload"]))}
          queue.shift while queue.length > 64
        end
      end
    end

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
    session.on_participant_joined { |_participant| emit_change(table_id, :table, nil) } if session.respond_to?(:on_participant_joined)
    session.on_participant_left { |_participant, _reason = nil| emit_change(table_id, :table, nil) } if session.respond_to?(:on_participant_left)
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
          next false unless @attachments[table_id].equal?(attachment)
          @sessions.delete(table_id)
          @pending_moves.delete(table_id)
          @recovered_moves.delete(table_id)
          @private_game_messages.delete(table_id)
          @native_session_ids.delete(session.id.to_s) if session.respond_to?(:id)
          retain_inactive_room(table_id)
          true
        end
        emit_change(table_id, :closed, nil) if current_closed
      end
    end
    @mutex.synchronize do
      @sessions[table_id] = session
      @attachments[table_id] = attachment
      @inactive_rooms.delete(table_id)
      @native_session_ids[session.id.to_s] = table_id if session.respond_to?(:id)
    end
    ensure_current(table_id, force: true) if session.respond_to?(:stack_read)
    session
  end

  def ensure_current(table_id, force: false, cancellation_token: nil, timeout: nil)
    begin_room_io(table_id)
    session = active_session(table_id)
    return false if session == nil || !session.respond_to?(:stack_read)

    last_sequence = session.respond_to?(:stack_state) ? session.stack_state["last_seq"].to_i : 0
    cursor = @mutex.synchronize { @stack_cursors[table_id].to_i }
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

        @stack_cursors[table_id] = [@stack_cursors[table_id].to_i, next_cursor].max
        @received_sequences[table_id].delete_if { |seq, _| seq <= @stack_cursors[table_id] }
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

  def append_record(table_id, kind, data, actor:, message_id: nil)
    session = active_session(table_id)
    raise ArgumentError, "The room is no longer active" if session == nil

    message_id ||= SecureRandom.uuid
    packet = {
      "version" => PROTOCOL,
      "kind" => kind.to_s,
      "actor" => actor.to_s,
      "data" => JSON.parse(JSON.generate(data))
    }
    pending = { message_id: message_id, packet: packet, sender: endpoint.user.to_s, writing: false }
    @mutex.synchronize do
      raise GameRoomNetworkErrors::PendingMove, "An earlier game move is awaiting confirmation" if @pending_moves.key?(table_id)

      @pending_moves[table_id] = pending if kind.to_s == "game_action"
    end
    write_record(table_id, pending)
  end

  def write_record(table_id, pending)
    begin_room_io(table_id)
    acquired = false
    session = active_session(table_id)
    raise GameRoomNetworkErrors::PendingMove, "The game connection is not ready" if session == nil
    @mutex.synchronize do
      raise GameRoomNetworkErrors::PendingMove, "A game move is already being sent" if pending[:writing]

      pending[:writing] = true
      acquired = true
    end
    result = session.stack_push(pending[:packet], message_id: pending[:message_id])
    sequence = extract_push_sequence(result)
    server_time = result.is_a?(Hash) ? (result.dig("entry", "created_at") || result["created_at"]) : nil
    server_time = nil unless server_time.respond_to?(:to_i) && server_time.to_i.positive?
    timestamp = server_time || (@record_clock ||= GameRoomSessionClock.new).server_now
    record = ingest_record(
      table_id,
      sequence: sequence,
      message_id: pending[:message_id],
      sender: pending[:sender],
      packet: pending[:packet],
      created_at: timestamp,
      estimated_time: server_time == nil,
      source_session: session
    )
    record || confirmed_record(table_id, pending)
  rescue StandardError => error
    # A native callback can confirm the write before its HTTP reply fails.
    confirmed = confirmed_record(table_id, pending)
    return confirmed if confirmed != nil

    @mutex.synchronize do
      if acquired && GameRoomNetworkErrors.transient?(error)
        pending[:uncertain] = true
        pending[:error] = error
      end
      @pending_moves.delete(table_id) if @pending_moves[table_id].equal?(pending) && !GameRoomNetworkErrors.transient?(error)
    end
    raise
  ensure
    @mutex.synchronize { pending[:writing] = false } if acquired
    end_room_io(table_id)
  end

  def confirmed_record(table_id, pending)
    @mutex.synchronize { @message_records.fetch(table_id, {})[[pending[:sender].downcase, pending[:message_id]]] }
  end

  def extract_push_sequence(result)
    candidates = [
      result.is_a?(Hash) ? result["seq"] : nil,
      result.is_a?(Hash) ? result.dig("entry", "seq") : nil
    ]
    sequence = candidates.map(&:to_i).find { |value| value.positive? }
    raise GameRoomNetworkErrors::UncertainWrite, "LiveSessions did not return the stored stack position" if sequence == nil

    sequence
  end

  def ingest_record(table_id, sequence:, message_id:, sender:, packet:, created_at:, estimated_time: false, source_session: nil)
    seq = sequence.to_i
    identity = message_id.to_s
    return nil if seq <= 0 || identity.empty? || !packet.is_a?(Hash)
    if packet["version"] != PROTOCOL || !packet["data"].is_a?(Hash) || !(packet["actor"].is_a?(String) && !packet["actor"].empty?) || sender.to_s.empty?
      # Do not print packet contents (they may contain private game data).
      Log.warning("ELTEN Game Room discarded invalid stack entry for table #{table_id}, sequence #{seq}") if defined?(Log)
      return nil
    end

    record = Record.new(
      table_id: table_id,
      sequence: seq,
      message_id: identity,
      sender: sender.to_s,
      packet: JSON.parse(JSON.generate(packet)),
      created_at: normalize_time(created_at),
      estimated_time: estimated_time
    )
    corrected = nil
    inserted = @mutex.synchronize do
      # The callback/read may have passed its earlier membership check just
      # before leave and cache pruning. Never recreate that old collection.
      next false if source_session && !@sessions[table_id].equal?(source_session)

      key = [seq, identity]
      if @record_keys[table_id].key?(key)
        previous = @message_records[table_id][[sender.to_s.downcase, identity]]
        if previous && previous.sequence == seq && previous.estimated_time && !estimated_time
          if previous.created_at != record.created_at
            session_id = previous.packet.dig("data", "session_id").to_i
            @clock_revisions[[table_id, session_id]] += 1 if session_id > 0
          end
          previous.created_at = record.created_at
          previous.estimated_time = false
          corrected = previous
          @record_generations[table_id] += 1
        end
        next false
      end

      @record_keys[table_id][key] = true
      # A local push acknowledgement can overtake messages not delivered yet.
      # Only a contiguous prefix is safe as the cursor of subsequent reads.
      cursor = @stack_cursors[table_id]
      @received_sequences[table_id][seq] = true if seq > cursor
      cursor += 1 while @received_sequences[table_id].delete(cursor + 1)
      @stack_cursors[table_id] = cursor
      # Even if a late original and a retry occupy different stack positions,
      # all readers apply this authenticated operation just once.
      message_key = [sender.to_s.downcase, identity]
      previous = @message_records[table_id][message_key]
      next false if previous != nil && previous.sequence <= seq
      @records[table_id].delete(previous) if previous != nil

      @message_records[table_id][message_key] = record
      rows = @records[table_id]
      ordered_append = rows.empty? || rows.last.sequence <= record.sequence
      rows << record
      rows.sort_by!(&:sequence) unless ordered_append
      @record_generations[table_id] += 1
      pending = @pending_moves[table_id]
      if pending != nil && pending[:message_id] == identity && pending[:sender].casecmp(sender.to_s) == 0
        @recovered_moves[table_id] << record if pending[:uncertain]
        @pending_moves.delete(table_id)
      end
      true
    end
    emit_record_change(table_id, record) if inserted
    if corrected
      if corrected.packet["kind"] == "game_started"
        emit_change(table_id, :game, corrected.packet.dig("data", "session_id").to_i)
      else
        emit_record_change(table_id, corrected)
      end
    end
    inserted ? record : nil
  rescue JSON::GeneratorError, JSON::ParserError
    nil
  end

  def emit_record_change(table_id, record)
    kind = record.packet["kind"].to_s
    data = record.packet["data"].to_h
    case kind
    when "game_started"
      emit_change(table_id, :game_started, positive_identifier(data["session_id"]))
    when "game_action", "game_boundary"
      emit_change(table_id, :game, positive_identifier(data["session_id"]))
    else
      emit_change(table_id, :table, nil)
    end
  end

  def emit_change(table_id, kind, value)
    @changed&.call(table_id.to_i, kind.to_sym, value)
  rescue StandardError => error
    log_warning("change callback", table_id, error)
  end

  def records_for(table_id)
    source, raw, generation, cache = @mutex.synchronize do
      source = @records.fetch(table_id, nil)
      [source, source.to_a.dup, @record_generations[table_id], @validated_records[table_id]]
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
      if source && @records.fetch(table_id, nil).equal?(source) &&
          @sessions[table_id].equal?(native) && @record_generations[table_id] == generation
        @validated_records[table_id] = {key: key, records: accepted.freeze}
      end
    end
    accepted.dup
  end

  def control_metadata(native)
    return {} unless native&.respond_to?(:discovery_metadata)
    native.discovery_metadata.to_h.select { |key, _| key == GameRoomTableControl::ANCHOR_KEY }
  end

  def control_ledger(table_id, raw: nil, native: active_session(table_id))
    raw ||= @mutex.synchronize { @records.fetch(table_id, []).dup }
    GameRoomTableControl.new(founder: native&.metadata.to_h["owner"], records: raw,
      anchor: control_metadata(native)[GameRoomTableControl::ANCHOR_KEY])
  end

  def observer_users(table_id, members: nil)
    roles = {}
    starts = {}
    ledger = control_ledger(table_id)
    records_for(table_id).each do |record|
      case record.packet["kind"].to_s
      when "game_started"
        starts[record.packet.dig('data', 'session_id')] ||= record
      when "room_state"
        data = record.packet["data"].to_h
        next if !data.key?("observers")

        roles = unique_users(data["observers"].to_a).each_with_object({}) do |user, result|
          result[user.downcase] = "observer"
        end
      when "room_role"
        target = record.packet.dig("data", "subject") || record.packet["actor"]
        roles[target.to_s.downcase] = record.packet.dig("data", "role").to_s
      when GameRoomTableControl::KIND
        data = record.packet['data']
        next unless data['players']
        game = starts[data['session_id']]
        next unless game
        prior = ledger.players(data['session_id'], initial: game.packet['data']['players'], before: record.sequence)
        prior.each { |person| roles[person.downcase] = 'observer' unless GameRoomParticipants.includes?(data['players'], person) }
        data['players'].each { |person| roles[person.downcase] = 'player' unless GameRoomParticipants.includes?(prior, person) }
      end
    end
    current_members = unique_users(members || connected_users(table_id))
    current_members.select { |member| roles[member.downcase] == "observer" }
  end

  def table_for(table_id, fallback: nil)
    session = active_session(table_id)
    metadata = session&.metadata.to_h
    base = fallback || table_from_metadata(metadata || {}, table_id)
    return nil if base == nil

    row, _changes = project_room_records(table_id, base.dup)
    row["__id"] = table_id
    row["id"] = table_id
    row["owner"] = owner_for(table_id)
    row["__insertion_user"] = row["owner"].to_s
    row["private"] = session.respond_to?(:visibility) ? session.visibility.to_sym == :private : base["private"] == true
    row["max_players"] = bounded_capacity(row["max_players"] || session&.capacity)
    row["bot_count"] = [[row["bot_count"].to_i, 0].max, row["max_players"]].min
    row["bot_names"] = Array.new(row["bot_count"]) { |index| row["bot_names"].to_a[index] } if row.key?("bot_names")
    members = connected_users(table_id)
    row["player_count"] = (members - observer_users(table_id, members: members)).length + row["bot_count"].to_i
    row["status"] = "waiting" if row["status"].to_s.empty?
    latest = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_started" }
    latest_id = latest&.packet&.dig("data", "session_id")
    row["status"] = "waiting" if latest_id && game_aborted?(table_id, latest_id)
    row["player_count"] = latest.packet.dig("data", "players").to_a.length if latest && row["status"] == "playing"
    row["created_at"] = metadata["created_at"].to_i if row["created_at"].to_i <= 0 && metadata
    row["updated_at"] = row["created_at"].to_i if row["updated_at"].to_i <= 0
    row["__live_session_id"] = session.id.to_s if session&.respond_to?(:id)
    row.delete('__statistics_room_id')
    identity = metadata['statistics_room_id']
    row['__statistics_room_id'] = identity.dup.freeze if GameRoomPresence::Identity.valid?(identity)
    row
  end

  # Compare-and-apply in the ordered log, not merely at the sender. Two
  # overlapping option dialogs cannot overwrite each other or a newer game.
  def project_room_records(table_id, row, records: records_for(table_id))
    current_game_id, changes = 0, []
    records.each do |record|
      case record.packet["kind"].to_s
      when "room_created"
        data = record.packet["data"].to_h
        row.merge!(data)
        row["created_at"] = record.created_at.to_i
      when "room_state"
        data = record.packet["data"].to_h
        if data["options_changed"] == true
          next unless data["expected_session_id"].to_i == current_game_id && data["expected_options"].to_s == row["game_options"].to_s
          changes << record.sequence
        end
        row.merge!(data.reject { |key, _| %w[options_changed expected_options expected_session_id].include?(key) })
      when "game_started"
        current_game_id = record.packet.dig("data", "session_id").to_i
      when GameRoomTableControl::KIND
        data = record.packet['data']
        if data['session_id'] == current_game_id && data['players']
          row['bot_players'] = data['players'].select { |person| GameRoomParticipants.bot?(person) }
          row['bot_count'] = row['bot_players'].length
          row['bot_names'] = row['bot_players'].map { |person| GameRoomParticipants.bot_name_token(person) }
          begin
            options = JSON.parse(row['game_options'])
            options[GameRoomTeams::PLAYERS_KEY] = data['players'].dup if options.key?(GameRoomTeams::PLAYERS_KEY)
            row['game_options'] = JSON.generate(options)
          rescue JSON::ParserError, TypeError
            # Validation of the original room options remains authoritative.
          end
        end
      end
      # Order is provided by the stack, including old clients whose payload
      # contains a skewed wall-clock timestamp.
      row["updated_at"] = record.created_at.to_i
    end
    [row, changes]
  end

  def table_from_metadata(metadata, table_id)
    return nil if !supported_metadata?(metadata)

    {
      "__id" => table_id,
      "id" => table_id,
      "__insertion_user" => metadata["owner"].to_s,
      "__discovery_protocol" => metadata["protocol"].to_i,
      "name" => metadata["name"].to_s,
      "game" => metadata["game"].to_s,
      "owner" => metadata["owner"].to_s,
      "private" => metadata["private"] == true,
      "resume_save_id" => metadata["resume_save_id"].to_s,
      "status" => %w[waiting playing].include?(metadata["status"]) ? metadata["status"] : "waiting",
      "max_players" => bounded_capacity(metadata["max_players"] || MAX_CAPACITY),
      "bot_count" => [[metadata["bot_count"].to_i, 0].max, MAX_CAPACITY].min,
      "game_options" => discovery_options(metadata),
      "player_count" => metadata.key?("player_count") ? [[metadata["player_count"].to_i, 0].max, MAX_CAPACITY].min : 1,
      "created_at" => metadata["created_at"].to_i,
      "updated_at" => metadata["created_at"].to_i
    }
  end

  def table_from_discovered(item, metadata)
    table_id = positive_identifier(metadata["table_id"])
    return nil if table_id == nil

    row = table_from_metadata(metadata, table_id)
    if item.respond_to?(:created_at) && item.created_at.to_i > 0
      row["created_at"] = row["updated_at"] = item.created_at.to_i
    end
    row["max_players"] = bounded_capacity(item.capacity)
    row["player_count"] = item.participant_count.to_i if !metadata.key?("player_count")
    row["__native_participant_count"] = item.participant_count.to_i
    row["__live_session_id"] = item.id.to_s
    row["private"] = item.visibility.to_sym == :private if item.respond_to?(:visibility)
    row["__discovered_session"] = item
    row
  end

  def game_session_from(record)
    return nil if record == nil || record.packet["kind"].to_s != "game_started"

    data = record.packet["data"].to_h
    players = data["players"].to_a.map(&:to_s)
    id = positive_identifier(data["session_id"])
    return nil if id == nil || players.empty?
    return nil if data.key?("archive_id") && archive_events_for(record) == nil
    clock = game_clock_state(record.table_id, id, data["clock_offset"].to_i)
    ledger = control_ledger(record.table_id)
    initial = data.fetch('initial_players', players).dup
    restored_changes = data['archive_id'] ? archive_events_for(record).select { |item| item.key?('players') } : []
    replacements = ledger.replacements(id, initial: players).map do |change|
      {'id' => data['event_id_base'].to_i + change.sequence * EVENT_ID_MULTIPLIER,
       'players' => change.packet['data']['players'].dup}
    end
    players = ledger.players(id, initial: players)

    session = {
      "__id" => id,
      "id" => id,
      "__insertion_user" => record.sender.to_s,
      "__authority_validated" => true,
      "__table_owner" => owner_for(record.table_id),
      "__control_epoch" => ledger.epoch,
      "__controllers" => {},
      "__initial_players" => initial,
      "__seat_changes" => restored_changes + replacements,
      "__control_ready" => same_user?(ledger.current_owner, owner_for(record.table_id)),
      "table_id" => table_id_for_record(record),
      "game" => data["game"].to_s,
      "player_one" => players[0].to_s,
      "player_two" => players[1].to_s,
      "players_json" => JSON.generate(
        "version" => 1,
        "seats" => players.each_with_index.map { |player, index| { "id" => index + 1, "controller" => player } }
      ),
      "__players" => players,
      "status" => "active",
      "options" => data["options"].to_s,
      "created_at" => data["created_at"].to_i,
      "updated_at" => data["created_at"].to_i,
      "__stack_sequence" => record.sequence.to_i,
      "__server_started_at" => record.created_at.to_i,
      "__clock_revision" => @mutex.synchronize { @clock_revisions[[record.table_id, id]] },
      "__archive_id" => data["archive_id"], "__event_id_base" => data["event_id_base"].to_i,
      "__clock_offset" => clock[:offset], "__frozen_at" => clock[:frozen_at],
      "__frozen" => clock[:frozen_at] != nil,
      "__aborted" => game_aborted?(record.table_id, id)
    }
    if data.key?('statistics')
      session['__statistics'] = GameRoomStatistics::Identity.copy(data['statistics'], started_at: record.created_at.to_i)
    end
    session
  end

  def game_clock_state(table_id, session_id, offset)
    frozen_at = nil
    records_for(table_id).each do |item|
      next unless item.packet["kind"] == "game_boundary" && item.packet.dig("data", "session_id") == session_id
      if item.packet.dig("data", "frozen") == true
        frozen_at ||= item.created_at.to_i
      elsif frozen_at != nil
        offset += [item.created_at.to_i - frozen_at, 0].max
        frozen_at = nil
      end
    end
    { offset: offset, frozen_at: frozen_at }
  end

  # A roster row can be larger than a move (eight Unicode participant names).
  # Respect both native byte and item limits before publishing anything.
  def archive_chunks(archive, archive_id:, actor:)
    chunks, current = [], []
    fits = lambda do |events, index|
      events.length <= ARCHIVE_EVENTS_PER_RECORD && JSON.generate({
        'version' => PROTOCOL, 'kind' => 'game_archive', 'actor' => actor.to_s,
        'data' => {'archive_id' => archive_id, 'index' => index, 'events' => events}
      }).bytesize <= STACK_ENTRY_BYTES
    end
    archive.each do |event|
      unless fits.call(current + [event], chunks.length)
        chunks << current unless current.empty?
        current = []
      end
      raise ArgumentError, 'The saved game is too large to restore safely' unless fits.call(current + [event], chunks.length)
      current << event
    end
    chunks << current unless current.empty?
    raise ArgumentError, 'The saved game is too large to restore safely' if chunks.length > STACK_ENTRIES - 8
    chunks
  end

  def archive_events_for(game_record)
    data = game_record.packet["data"]
    chunks = records_for(game_record.table_id).select do |item|
      item.sequence < game_record.sequence && item.packet["kind"] == "game_archive" && item.packet.dig("data", "archive_id") == data["archive_id"]
    end.sort_by { |item| item.packet.dig("data", "index") }
    return nil unless chunks.each_with_index.all? { |item, index| item.packet.dig("data", "index") == index }
    events = chunks.flat_map { |item| item.packet.dig("data", "events") }
    return nil unless events.length == data["archive_events"] && events.map { |event| event["id"] }.max.to_i == data["event_id_base"]
    previous = 0
    players = data.fetch('initial_players', data['players'])
    return nil unless events.all? do |event|
      valid = event['id'] > previous
      if event.key?('players')
        valid &&= event['players'].length == players.length
        players = event['players']
      else
        valid &&= GameRoomParticipants.includes?(players, event['actor'])
      end
      previous = event["id"]
      valid
    end
    return nil unless players == data['players']
    events
  end

  def activity_record(record, ledger: nil)
    return nil if record == nil || record.packet["kind"].to_s != "room_activity"

    data = record.packet["data"].to_h
    ledger ||= control_ledger(record.table_id)
    {
      "__id" => record.sequence.to_i * EVENT_ID_MULTIPLIER,
      "id" => record.sequence.to_i * EVENT_ID_MULTIPLIER,
      "table_id" => record.table_id.to_i,
      "kind" => data["activity_kind"].to_s,
      "actor" => record.packet["actor"].to_s,
      "table_owner" => ledger.owner_at(record.sequence),
      "__authority_validated" => true,
      "game" => data["game"].to_s,
      "message" => data["message"].to_s,
      "subject" => data["subject"].to_s,
      "invitation_id" => data["invitation_id"].to_i,
      "created_at" => record.created_at.to_i,
      "__stack_sequence" => record.sequence.to_i,
      "__insertion_user" => record.sender.to_s
    }
  end

  def lifecycle_activity(record, kind, ledger:, game:)
    result = { "__id" => record.sequence * EVENT_ID_MULTIPLIER, "table_id" => record.table_id,
      "kind" => kind, "actor" => record.sender, "__insertion_user" => record.sender,
      "table_owner" => ledger.owner_at(record.sequence), "game" => game,
      "__authority_validated" => true,
      "message" => "", "created_at" => record.created_at, "__stack_sequence" => record.sequence.to_i }
    data = record.packet["data"]
    if kind == "options_changed"
      before = JSON.parse(data["expected_options"])
      after = JSON.parse(data["game_options"])
      keys = %w[team_players team_seats]
      if keys.any? { |key| before[key] != after[key] }
        result["team_players"] = after["team_players"]
        result["team_seats"] = after["team_seats"]
      end
    elsif kind == "role_changed"
      result["subject"] = data["subject"]
      result["role"] = data["role"]
    end
    result
  end

  def table_id_for_record(record)
    record.table_id.to_i
  end

  def expand_game_action(record, game_record: nil, ledger: nil)
    data = record.packet["data"].to_h
    table_id = table_id_for_record(record)
    actor = record.packet["actor"].to_s
    game_record ||= records_for(table_id).reverse.find { |item| item.packet["kind"] == "game_started" && item.packet.dig("data", "session_id") == data["session_id"] }
    ledger ||= control_ledger(table_id)
    id_base = game_record&.packet&.dig("data", "event_id_base").to_i
    Array(data["events"]).each_with_index.map do |command, offset|
      {
        "__id" => id_base + record.sequence.to_i * EVENT_ID_MULTIPLIER + offset,
        "id" => id_base + record.sequence.to_i * EVENT_ID_MULTIPLIER + offset,
        "__insertion_user" => record.sender.to_s,
        "__authority_user" => ledger.owner_at(record.sequence),
        "session_id" => data["session_id"].to_i,
        "table_id" => table_id,
        "sequence" => data["sequence"].to_i + offset,
        "__stack_sequence" => record.sequence.to_i,
        "__stack_offset" => offset,
        "move_id" => command["move_id"].to_s,
        "actor" => actor,
        "__controller" => data["controller"] == true,
        "action" => command["action"].to_s,
        "value" => command["value"].to_s,
        "created_at" => record.created_at.to_i
      }
    end
  end

  def command_value(command, key)
    return command.public_send(key) if command.respond_to?(key)
    return nil if !command.respond_to?(:key?)
    return command[key] if command.key?(key)
    return command[key.to_sym] if command.key?(key.to_sym)

    nil
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
    if result.key?('game_options')
      options = result['game_options'].to_s
      raise ArgumentError, 'Game options are too large' if options.bytesize > MAX_OPTIONS_BYTES
      result.delete('options_z')
      if JSON.generate(result).bytesize > DISCOVERY_BYTES - 120
        result.delete('game_options')
        result['options_z'] = Base64.strict_encode64(Zlib::Deflate.deflate(options))
      end
    end
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
