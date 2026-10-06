require "json"
require_relative "game_room_transport"
require_relative "game_participants"
require_relative "participant_replay"
require_relative "bot_turn_gate"
require_relative "game_event_protocol"
require_relative "game_session_contracts"
require_relative "table_control"

class GameRepository
  GameSnapshot = GameRoomSessionContracts::GameSnapshot

  MAX_EVENTS_PER_ACTION = GameRoomEventProtocol::MAX_EVENTS
  MAX_ACTION_LENGTH = GameRoomEventProtocol::MAX_ACTION_LENGTH
  MAX_VALUE_LENGTH = GameRoomEventProtocol::MAX_VALUE_LENGTH
  MAX_PLAYERS = GameRoomTableControl::MAX_SEATS
  MAX_PLAYER_LENGTH = 64
  PLAYERS_FORMAT_VERSION = 1
  MAX_PLAYERS_JSON_LENGTH = 1_024

  def initialize(program, transport: nil, server_tables: nil)
    @program = program
    @transport = transport || GameRoomTransport.new(program)
    @bot_turn_mutex = Mutex.new
    @bot_turn_controllers = {}
  end

  def bot_turn_controller(table_id)
    lookup = lambda do |retained|
      @bot_turn_mutex.synchronize do
        @bot_turn_controllers.delete_if do |id, controller|
          id != table_id.to_i && !retained[id] && controller.retire_if_idle
        end
        @bot_turn_controllers[table_id.to_i] ||= GameRoomBots::TurnController.new
      end
    end
    # Foreign injected adapters may not expose local lifecycle information;
    # absence of that information must not mean that all their rooms closed.
    return @transport.with_retained_rooms(&lookup) if @transport.respond_to?(:with_retained_rooms)
    @bot_turn_mutex.synchronize do
      @bot_turn_controllers[table_id.to_i] ||= GameRoomBots::TurnController.new
    end
  end

  def restore_session(table:, game:, players:, options:, restore:)
    raise ArgumentError, "Only the founder may restore the game" unless GameRoomParticipants.same?(table["owner"], Session.name)
    @start_session_mutex ||= Mutex.new
    @start_session_mutex.synchronize do
      existing = session_for_table(table, force: true)
      next existing if existing != nil
      @transport.start_game(table: table, game: game, players: players, options: options, actor: Session.name, restore: restore)
    end
  end

  def session_for_table(table, force: false)
    table_id = row_id(table)
    return nil if table_id <= 0

    @transport.find_game_session(table, force: force) do |row|
      valid_session_for_table?(row, table, players: players_for(row))
    end
  end

  def latest_session_id_for_table(table)
    table_id = row_id(table)
    return 0 if table_id <= 0

    latest = @transport.find_game_session(table)
    return session_id(latest)
  end

  def session_by_id(id, table: nil)
    target_id = id.to_i
    return nil if target_id <= 0

    row = @transport.game_session(target_id, table: table)
    return nil if row == nil
    return row if table == nil

    return valid_session_for_table?(row, table, players: players_for(row)) ? row : nil
  end

  def start_session(table:, game:, players:, options: "{}", recipients: players, expected_previous_session_id: nil)
    @start_session_mutex ||= Mutex.new
    @start_session_mutex.synchronize do
      start_session_once(
        table: table,
        game: game,
        players: players,
        options: options,
        recipients: recipients,
        expected_previous_session_id: expected_previous_session_id
      )
    end
  end

  def snapshot_for(session, force_events: false)
    return nil if session_id(session) <= 0 || session["table_id"].to_i <= 0

    players = players_for(session)
    return nil if players.empty?

    current = with_players(session, players)
    refreshed = @transport.game_session(session_id(current), table: current["table_id"])
    current = with_players(refreshed, players_for(refreshed)) if refreshed != nil
    events = events_for(current, force: force_events)
    # A terminal boundary can have arrived in the event read just completed.
    refreshed = @transport.game_session(session_id(current), table: current["table_id"])
    current = with_players(refreshed, players_for(refreshed)) if refreshed != nil
    GameSnapshot.new(session: current, events: events)
  end

  # The transport invokes this at its mutation boundary, not while a picker
  # is open. For replacements it checks again against the ordered prefix
  # preceding the as-yet unauthenticated control record. A racing old-seat
  # commitment must not be silently inherited by a different participant.
  def control_change_guard(table:, game:, session:, player: nil, replacement: nil)
    expected_id = session_id(session)
    expected_epoch = session && session['__control_epoch']
    lambda do |before_sequence = nil|
      current = session_for_table(table, force: true)
      unless session_id(current) == expected_id && (!current ||
          (current['__control_epoch'] == expected_epoch && current['__control_ready'] != false))
        raise GameRoomNetworkErrors::GamePaused, 'The game controller changed'
      end
      next true unless current
      # An aborted match no longer owns playable private input. Its waiting
      # room may still change master, but its old seats must not be replaced.
      next true if current['__aborted'] && player == nil
      if current['__frozen'] || current['__aborted']
        raise GameRoomNetworkErrors::GamePaused, 'The game is paused'
      end
      snapshot = snapshot_for(current)
      unless snapshot && session_id(snapshot.session) == expected_id && snapshot.session['__control_epoch'] == expected_epoch &&
          snapshot.session['__control_ready'] != false
        raise GameRoomNetworkErrors::GamePaused, 'The game controller changed'
      end
      next true if snapshot.session['__aborted'] && player == nil
      if snapshot.session['__frozen'] || snapshot.session['__aborted']
        raise GameRoomNetworkErrors::GamePaused, 'The game is paused'
      end
      events = snapshot.events
      events = events.reject { |event| event['__stack_sequence'].to_i >= before_sequence } if before_sequence
      replay = game.replay(snapshot.session, events, self)
      error = if player
        game.participant_replacement_error(replay, player: player, replacement: replacement)
      else
        game.controller_change_error(replay)
      end
      raise GameRoomNetworkErrors::GamePaused, error if error
      true
    end
  end

  def event_revision(session, known_revision: nil, force: false)
    events_revision(events_for(session, force: force))
  end

  def events_revision(events)
    ids = events.to_a.map { |event| event_id(event) }
    [ids.length, ids.max.to_i]
  end

  def confirmed_event_ids(session)
    # Native entries are already persisted; an uncertain write is reconciled
    # by the store before this prefix can confirm a bot's move.
    events_for(session).map { |event| event_id(event) }.select(&:positive?)
  end

  def next_sequence(session, accepted_events)
    accepted_events.to_a.map { |event| event["sequence"].to_i + 1 }.max.to_i
  end

  def consume_recovered_events(session)
    @transport.consume_recovered_game_events(session)
  end

  def append_events(session:, sequence:, events:, recipients: nil, actor: Session.name, controller: false)
    raise ArgumentError, "The game no longer exists" if session_id(session) <= 0 || session["table_id"].to_i <= 0

    players = players_for(session)
    raise ArgumentError, "The game participant list is incomplete" if players.empty?
    event_actor = actor.to_s
    raise ArgumentError, "A game event requires an actor" if event_actor.empty?
    if GameRoomParticipants.bot?(event_actor)
      owner = session["__table_owner"] || insertion_user(session, "player_one")
      raise ArgumentError, "Only the table owner may move a computer" if owner.casecmp(Session.name.to_s) != 0
      raise ArgumentError, "The computer is not a player in this game" if !includes_user?(players, event_actor)
    elsif controller
      owner = session["__table_owner"] || insertion_user(session, "player_one")
      raise ArgumentError, "Only the table owner may submit an automatic player action" if owner.casecmp(Session.name.to_s) != 0
      raise ArgumentError, "The automatic action actor is not a player in this game" if !includes_user?(players, event_actor)
    else
      raise ArgumentError, "A user may only submit their own move" if event_actor.casecmp(Session.name.to_s) != 0
      raise ArgumentError, "You are not a player in this game" if !includes_user?(players, Session.name)
    end
    current = with_players(session, players)
    commands = events.to_a
    GameRoomEventProtocol.validate_commands!(commands)
    return @transport.append_game_action(
      session: current,
      sequence: sequence,
      events: commands,
      actor: event_actor,
      controller: controller == true
    )
  end

  def players_for(session)
    embedded = session["__players"]
    return unique_users(embedded) if embedded.is_a?(Array)

    persisted_players_for(session)
  end

  def actor_of(event, session = nil)
    author = insertion_user(event, "actor")
    claimed = event["actor"].to_s
    if event["__controller"] == true
      return "" if session == nil
      owner = event["__authority_user"] || insertion_user(session, "player_one")
      return "" if !GameRoomParticipants.same?(author, owner)
      return "" if !includes_user?(event_players(session, event), claimed)
      return claimed
    end
    return author if !GameRoomParticipants.bot?(claimed)
    return "" if session == nil

    players = event_players(session, event)
    owner = event["__authority_user"] || insertion_user(session, "player_one")
    return "" if !includes_user?(players, claimed)
    return "" if author.casecmp(owner) != 0

    claimed
  end

  def session_id(row)
    row_id(row)
  end

  def event_id(row)
    row_id(row)
  end

  private

  def event_players(session, event)
    return players_for(session) if session.fetch('__seat_changes', []).empty?
    GameRoomParticipantReplay.roster_at(session, event_id(event))
  end

  def start_session_once(table:, game:, players:, options:, recipients:, expected_previous_session_id:)
    current = session_for_table(table)
    if expected_previous_session_id != nil && session_id(current) != expected_previous_session_id.to_i
      return current
    end

    owner = insertion_user(table, "owner")
    raise ArgumentError, "Only the table owner may start a game" if owner.casecmp(Session.name.to_s) != 0

    participants = unique_users(players)
    raise ArgumentError, "A game requires at least one player" if participants.empty?
    raise ArgumentError, "A game supports at most #{MAX_PLAYERS} players" if participants.length > MAX_PLAYERS
    raise ArgumentError, "A game participant name is too long" if participants.any? { |participant| participant.length > MAX_PLAYER_LENGTH }
    inserted = @transport.start_game(
      table: table,
      game: game,
      players: participants,
      options: options,
      actor: Session.name
    )
    return inserted
  end

  def command_value(command, key)
    GameRoomEventProtocol.command_value(command, key)
  end

  def events_for(session, force: false)
    @transport.game_events(session, force: force)
  end

  def persisted_players_for(session)
    encoded = session["players_json"].to_s
    return [] if encoded.empty? || encoded.length > MAX_PLAYERS_JSON_LENGTH

    payload = JSON.parse(encoded)
    return [] if !payload.is_a?(Hash) || payload["version"].to_i != PLAYERS_FORMAT_VERSION

    seats = payload["seats"]
    return [] if !seats.is_a?(Array) || seats.empty? || seats.length > MAX_PLAYERS
    return [] if seats.map { |seat| seat.is_a?(Hash) ? seat["id"] : nil } != (1..seats.length).to_a

    players = seats.map { |seat| seat["controller"].to_s }
    return [] if players.any? { |player| player.empty? || player.length > MAX_PLAYER_LENGTH }

    unique = unique_users(players)
    unique.length == players.length ? unique : []
  rescue JSON::ParserError, TypeError
    []
  end

  def with_players(session, players)
    session.merge("__players" => unique_users(players))
  end

  def row_id(row)
    return 0 if row == nil

    (row["__id"] || row["id"]).to_i
  end

  def insertion_user(row, fallback_key)
    user = row["__insertion_user"].to_s
    user.empty? ? row[fallback_key].to_s : user
  end

  def valid_session_for_table?(session, table, players: persisted_players_for(session))
    owner = insertion_user(table, "owner")
    creator = insertion_user(session, "player_one")
    # LiveSessions authenticates the author independently of the playing seats.
    # The table master may be an observer (including a Taboo moderator).
    valid_first_seat = session["player_one"].to_s.casecmp(players.first.to_s) == 0
    session["table_id"].to_i == row_id(table) &&
      session["game"].to_s == table["game"].to_s &&
      (creator.casecmp(owner) == 0 || session["__authority_validated"] == true) &&
      !players.empty? &&
      valid_first_seat
  end

  def unique_users(users)
    result = []
    users.to_a.each do |user|
      value = user.to_s
      next if value.empty? || includes_user?(result, value)

      result << value
    end
    result
  end

  def includes_user?(users, user)
    users.any? { |candidate| candidate.to_s.casecmp(user.to_s) == 0 }
  end
end
