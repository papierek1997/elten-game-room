require_relative "game_room_transport"
require_relative "game_participants"

class LobbyRepository
  CreateResult = Struct.new(:table, :created, keyword_init: true) do
    def created?
      created == true
    end
  end

  JoinResult = Struct.new(:table, :status, :members, keyword_init: true) do
    def entered?
      status == :joined || status == :already_here
    end
  end

  TableSnapshot = Struct.new(:table, :members, :bots, :observers, keyword_init: true) do
    def participants
      GameRoomParticipants.unique(members.to_a + bots.to_a)
    end

    def observer?(user)
      GameRoomParticipants.includes?(observers.to_a, user)
    end

    def game_participants
      humans = members.to_a.reject { |member| observer?(member) }
      GameRoomParticipants.unique(humans + bots.to_a)
    end

    def participant_count
      # An active place survives departure with a new participant. Room roles
      # also describe the next game, not only the current active roster.
      return table['player_count'].to_i if table.to_h['status'] == 'playing' && table.key?('player_count')
      return table["player_count"].to_i if table.to_h.key?("__discovered_session") && observers == nil

      game_participants.length
    end
  end

  BotUpdateResult = Struct.new(:status, :snapshot, :activity, keyword_init: true) do
    def updated?
      status == :updated
    end
  end

  TABLE_NAME_MIN_LENGTH = 3
  TABLE_NAME_MAX_LENGTH = 60
  DEFAULT_ROOM_CAPACITY = 8
  MAX_ROOM_CAPACITY = GameRoomLiveSessionStore::MAX_CAPACITY
  AVAILABLE_STATUSES = %w[waiting playing].freeze

  def initialize(program, transport: nil, server_tables: nil, activity_repository: nil)
    @program = program
    @transport = transport || GameRoomTransport.new(program)
    @activity_repository = activity_repository
  end

  def valid_table_name?(name)
    length = normalized_name(name).length
    length >= TABLE_NAME_MIN_LENGTH && length <= TABLE_NAME_MAX_LENGTH
  end

  def open_tables(game: nil)
    @transport.discover_rooms(game: game)
  end

  def open_table_snapshots(game: nil, hide_inactive: false)
    return open_tables(game: game).reject { |row| hide_inactive && inactive_playing_table?(row) }.map do |row|
      snapshot = @transport.room_snapshot(row)
      snapshot == nil ? TableSnapshot.new(table: row, members: [owner_of(row)], bots: bots_for(row)) : native_snapshot(snapshot)
    end
  end

  def inactive_playing_table?(row)
    stamp = row['last_activity_at']
    row['status'] == 'playing' && stamp.is_a?(Integer) && stamp.positive? &&
      GameRoomClock.synchronized? && GameRoomClock.now - stamp >= 45 * 60
  end

  def discovered_roster(snapshot)
    @transport.discovered_roster(snapshot.table)
  end

  def discovered_options(snapshot)
    @transport.discovered_options(snapshot.table)
  end

  def snapshot_for(row, force: false)
    snapshot = force ? @transport.room_snapshot(row, force: true) : @transport.room_snapshot(row)
    return snapshot == nil ? nil : native_snapshot(snapshot)
  end

  def create_table(name:, game:, owner:, game_options: "{}", private_table: false, resume_save_id: nil, bot_count: 0, bot_names: nil)
    clean_name = normalized_name(name)
    raise ArgumentError, "Invalid table name" if !valid_table_name?(clean_name)

    existing = current_table_for(owner)
    return CreateResult.new(table: existing, created: false) if existing != nil

    table = @transport.create_room(
      name: clean_name,
      game: game,
      owner: owner,
      game_options: game_options,
      capacity: DEFAULT_ROOM_CAPACITY,
      private_table: private_table, resume_save_id: resume_save_id, bot_count: bot_count, bot_names: bot_names
    )
    append_activity(table, "created", actor: owner, table_users: [owner])
    return CreateResult.new(table: table, created: true)
  end

  def join_table(row, user, announce: true)
    current = current_table_for(user)
    if current != nil && table_id(current) != table_id(row)
      snapshot = snapshot_for(current)
      return JoinResult.new(table: current, status: :already_at_another_table, members: snapshot&.members.to_a)
    end

    newly_joined = @transport.respond_to?(:consume_new_join) && @transport.consume_new_join(table_id(row), user)
    status = if newly_joined
      :joined
    elsif current != nil && table_id(current) == table_id(row)
      :already_here
    else
      @transport.join_room(row, user)
    end
    return JoinResult.new(table: row, status: status, members: []) unless [:joined, :already_here].include?(status)
    snapshot = snapshot_for(row)
    return JoinResult.new(table: row, status: :closed, members: []) if snapshot == nil

    append_activity(snapshot.table, "joined", actor: user, table_users: snapshot.members) if status == :joined
    return JoinResult.new(table: snapshot.table, status: status, members: snapshot.members)
  end

  def leave_table(row, user, control_guard: nil)
    snapshot = snapshot_for(row)
    return :closed if snapshot == nil

    if owner_of(snapshot.table).casecmp(user.to_s) == 0
      successor = successor_for(snapshot, user)
      unless successor
        @transport.deactivate_table(table_id: table_id(snapshot.table))
        return :closed
      end
      @transport.transfer_room_owner(snapshot.table, successor, **(control_guard ? {control_guard: control_guard} : {}))
      snapshot = snapshot_for(snapshot.table)
      raise IOError, "The table master transfer was not confirmed" unless snapshot &&
        GameRoomParticipants.same?(owner_of(snapshot.table), successor)
    end
    append_activity(snapshot.table, "left", actor: user, table_users: snapshot.members)
    @transport.deactivate_table(table_id: table_id(snapshot.table))
    return :left
  end

  def successor_for(snapshot, departing)
    session = @transport.game_sessions(snapshot.table).max_by { |row| row["__stack_sequence"].to_i }
    seats = session && session["__players"]
    preferred = Array(seats) + snapshot.game_participants + snapshot.members
    preferred.find { |name| GameRoomParticipants.human?(name) &&
      !GameRoomParticipants.same?(name, departing) && GameRoomParticipants.includes?(snapshot.members, name) }
  end

  def current_table_for(user)
    @transport.current_room(user)
  end

  def single_open_table_for(owner)
    open_tables.find { |row| owner_of(row).casecmp(owner.to_s) == 0 }
  end

  def close_table(row)
    current = snapshot_for(row)&.table
    return false if current == nil
    raise ArgumentError, "Only the table owner may close it" if owner_of(current).casecmp(Session.name.to_s) != 0

    return @transport.deactivate_table(table_id: table_id(current))
  end

  def owner_of(row)
    row["__insertion_user"].to_s.empty? ? row["owner"].to_s : row["__insertion_user"].to_s
  end

  def table_id(row)
    return 0 if row == nil

    (row["__id"] || row["id"]).to_i
  end

  def capacity_of(row)
    requested = [row["max_players"].to_i, DEFAULT_ROOM_CAPACITY].max
    [requested, MAX_ROOM_CAPACITY].min
  end

  def bot_count(row)
    count = [row["bot_count"].to_i, 0].max
    [count, capacity_of(row)].min
  end

  def bots_for(row)
    return row['bot_players'].dup if row['bot_players'].is_a?(Array)
    GameRoomParticipants.bots_for(table_id(row), bot_count(row), names: row["bot_names"])
  end

  def add_bot(row, snapshot: nil)
    update_bot_count(row, 1, snapshot: snapshot)
  end

  def remove_bot(row, snapshot: nil, participant: nil)
    update_bot_count(row, -1, snapshot: snapshot, participant: participant)
  end

  def set_observer(row, user, observing)
    snapshot = snapshot_for(row, force: true)
    return nil if snapshot == nil
    own_role = GameRoomParticipants.same?(user, Session.name)
    raise ArgumentError, "Only the table master may change another user's role" unless own_role || GameRoomParticipants.same?(owner_of(snapshot.table), Session.name)
    raise ArgumentError, "A computer cannot observe a game" if GameRoomParticipants.bot?(user)
    raise ArgumentError, "The user is not at this table" if !GameRoomParticipants.includes?(snapshot.members, user)

    if own_role
      @transport.set_observer(snapshot.table, observing, actor: Session.name)
    else
      @transport.set_observer(snapshot.table, observing, actor: Session.name, subject: user)
    end
    snapshot_for(snapshot.table, force: true)
  end

  def available?(row)
    AVAILABLE_STATUSES.include?(row["status"].to_s)
  end

  def waiting?(row)
    row["status"].to_s == "waiting"
  end

  def playing?(row)
    row["status"].to_s == "playing"
  end

  def set_game_active(row, active, snapshot: nil)
    id = table_id(row)
    raise ArgumentError, "Invalid table row" if id <= 0

    current_snapshot = snapshot.is_a?(TableSnapshot) ? snapshot : snapshot_for(row)
    return nil if current_snapshot == nil
    current = current_snapshot.table
    raise ArgumentError, "Only the table owner may update it" if owner_of(current).casecmp(Session.name.to_s) != 0

    status = active ? "playing" : "waiting"
    return current if current["status"].to_s == status

    updated = @transport.update_room(current, { "status" => status }, actor: Session.name)
    row.replace(updated) if row.is_a?(Hash)
    current_snapshot.table.replace(updated)
    return updated
  end

  private

  def native_snapshot(value)
    TableSnapshot.new(
      table: value.fetch(:table),
      members: value.fetch(:members).to_a,
      bots: value.fetch(:bots).to_a,
      observers: value.fetch(:observers, []).to_a
    )
  end

  def update_bot_count(row, difference, snapshot: nil, participant: nil)
    id = table_id(row)
    raise ArgumentError, "Invalid table row" if id <= 0
    raise ArgumentError, "Only the table owner may manage computers" if owner_of(row).casecmp(Session.name.to_s) != 0

    current_snapshot = snapshot.is_a?(TableSnapshot) ? snapshot : snapshot_for(row)
    return bot_update_result(:closed, snapshot) if current_snapshot == nil
    current = current_snapshot.table
    current_count = bot_count(current)
    requested = current_count + difference.to_i
    return bot_update_result(:none, current_snapshot) if requested < 0
    return bot_update_result(:full, current_snapshot) if current_snapshot.members.length + requested > capacity_of(current)

    if difference > 0 && current["__discovery_protocol"].to_i < GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL
      return bot_update_result(:old_room, current_snapshot)
    end
    bot_names = Array.new(current_count) { |index| current["bot_names"].to_a[index] }
    activity_subject = nil
    if difference > 0
      occupied = current_snapshot.participants.map { |person| GameRoomParticipants.display_name(person) }
      bot_names << GameRoomBotNames.pick(occupied: occupied)
      activity_subject = GameRoomParticipants.bot_id(id, requested, name_token: bot_names.last)
    else
      index = participant == nil ? current_count - 1 : bots_for(current).index(participant)
      return bot_update_result(:stale, current_snapshot) if index == nil
      activity_subject = bots_for(current)[index]
      bot_names.delete_at(index)
    end
    changes = { "bot_count" => requested }
    if current['bot_players'].is_a?(Array)
      bots = current['bot_players'].dup
      if difference > 0
        number = bots.map { |person| GameRoomParticipants.bot_number(person).to_i }.max.to_i + 1
        activity_subject = GameRoomParticipants.bot_id(id, number, name_token: bot_names.last)
        bots << activity_subject
      else
        bots.delete_at(index)
      end
      changes['bot_players'] = bots
    end
    changes["bot_names"] = bot_names if current["__discovery_protocol"].to_i >= GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL
    updated = @transport.update_room(current, changes, actor: Session.name)
    row.replace(updated) if row.is_a?(Hash)
    current_snapshot.table.replace(updated)
    current_snapshot.bots = bots_for(updated)
    activity = append_activity(
      updated,
      difference.to_i > 0 ? "bot_added" : "bot_removed",
      actor: Session.name,
      subject: activity_subject,
      table_users: current_snapshot.members
    )
    return bot_update_result(:updated, current_snapshot, activity: activity)
  end

  def bot_update_result(status, snapshot, activity: nil)
    return status if snapshot == nil

    BotUpdateResult.new(status: status, snapshot: snapshot, activity: activity)
  end

  def append_activity(row, kind, actor:, table_users: [], subject: nil)
    arguments = { table: row, kind: kind, actor: actor }
    arguments[:subject] = subject if subject != nil
    @activity_repository&.append_safely(**arguments)
  end

  def normalized_name(name)
    name.to_s.strip.gsub(/\s+/, " ")
  end
end
