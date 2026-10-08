require_relative "game_participants"
require_relative "game_history_navigation"
require_relative "game_room_clock"
require_relative "game_content"
require_relative "game_snapshot"
require_relative "table_control"

require_relative "game_room_localization"

class TableActivityRepository
  using GameRoomLocalization::Translations
  Entry = Struct.new(
    :id,
    :table_id,
    :kind,
    :actor,
    :owner,
    :game,
    :message,
    :subject,
    :invitation_id,
    :created_at,
    :stack_sequence,
    :teams,
    :role,
    :replacement,
    keyword_init: true
  )

  TABLE_NAME = "table_activity".freeze
  KINDS = %w[created joined left bot_added bot_removed chat invited invitation_rejected game_aborted options_changed role_changed owner_changed seat_control_changed player_replaced].freeze
  GLOBAL_KINDS = %w[created joined left bot_added bot_removed].freeze
  BOT_KINDS = %w[bot_added bot_removed].freeze
  TABLE_LIMIT = 2_000
  GLOBAL_LIMIT = 200
  MESSAGE_MAX_LENGTH = 2_000
  PROJECTION_CACHE_LIMIT = 4_096

  def initialize(server_tables:, transport: nil)
    @server_tables = server_tables
    @transport = transport
  end

  def append(table:, kind:, message: nil, actor: Session.name, subject: nil, invitation_id: nil)
    normalized_kind = kind.to_s
    raise ArgumentError, "Invalid table activity kind" if !KINDS.include?(normalized_kind)

    table_id = row_id(table)
    owner = table_owner(table)
    game = table["game"].to_s
    author = actor.to_s.strip
    raise ArgumentError, "Invalid activity table" if table_id <= 0
    raise ArgumentError, "Activity author is required" if author.empty?
    raise ArgumentError, "Activity table owner is required" if owner.empty?
    raise ArgumentError, "Activity game is required" if game.empty?

    clean_message = normalized_kind == "chat" ? normalize_message(message) : ""
    raise ArgumentError, "A chat message cannot be empty" if normalized_kind == "chat" && clean_message.empty?
    if BOT_KINDS.include?(normalized_kind) && !subject.to_s.empty?
      # This existing field carries the stable bot ID, not a translated
      # sentence. It works in both the native log and the lobby table without
      # another request or a server-column migration.
      clean_message = bot_subject(subject, table_id)
      raise ArgumentError, "Invalid activity computer" if clean_message.empty?
    end
    invitation_activity = %w[invited invitation_rejected].include?(normalized_kind)
    if invitation_activity && (subject.to_s.strip.empty? || subject.to_s.length > 64 || invitation_id.to_i <= 0)
      raise ArgumentError, "Invalid invitation activity"
    end

    if native_live_sessions?
      arguments = {
        table: table,
        kind: normalized_kind,
        actor: author,
        message: clean_message
      }
      arguments.merge!(subject: subject.to_s, invitation_id: invitation_id.to_i) if invitation_activity
      inserted = @transport.append_activity(**arguments)
      persist_global_activity(table, normalized_kind, author, message: clean_message) if GLOBAL_KINDS.include?(normalized_kind) && table["private"] != true
      return entry_from(inserted, table)
    end

    inserted = activity_table.insert(
      "table_id" => table_id,
      "kind" => normalized_kind,
      "actor" => author,
      "table_owner" => owner,
      "game" => game,
      "message" => clean_message,
      "subject" => invitation_activity ? subject.to_s : "",
      "invitation_id" => invitation_activity ? invitation_id.to_i : 0,
      "created_at" => GameRoomClock.now.to_i
    )
    entry_from(inserted, table)
  end

  def append_safely(**arguments)
    append(**arguments)
  rescue StandardError => error
    Log.warning("ELTEN Game Room could not save table activity: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def entries_for(table, limit: TABLE_LIMIT, viewer: nil)
    table_id = row_id(table)
    return [] if table_id <= 0

    if native_live_sessions?
      # Always read the validated projection. Caching only the final ID/count
      # would miss corrected earlier records or a rejoined room generation.
      rows = @transport.activity_records(table)
      entries = native_entries(rows, table)
      entries = entries.last([[limit.to_i, 1].max, TABLE_LIMIT].min)
      return entries_for_current_visit(entries, table, viewer)
    end

    entries = activity_table
      .select(
        where: { "table_id" => table_id },
        order: [["__id", "asc"]],
        limit: [[limit.to_i, 1].max, TABLE_LIMIT].min
      )
      .to_a
      .filter_map { |row| entry_from(row, table) }
      .sort_by(&:id)
    entries_for_current_visit(entries, table, viewer)
  rescue StandardError => error
    Log.warning("ELTEN Game Room could not load table activity: #{error.class}: #{error.message}") if defined?(Log)
    []
  end

  def global_entries(tables: nil, limit: GLOBAL_LIMIT)
    # Named bot records use message for their identity. An empty-message
    # filter would hide them; the kind allowlist below still excludes chat.
    activity_table
      .select(
        order: [["__id", "desc"]],
        limit: GLOBAL_LIMIT
      )
      .to_a
      .filter_map do |row|
        next if !GLOBAL_KINDS.include?(row["kind"].to_s)

        table = {
          "__id" => row["table_id"].to_i,
          "owner" => row["table_owner"].to_s,
          "game" => row["game"].to_s
        }
        entry_from(row, table)
      end
      .sort_by(&:id)
      .last([[limit.to_i, 1].max, GLOBAL_LIMIT].min)
  rescue EltenLink::Error => error
    Log.warning("ELTEN Game Room could not load lobby activity: #{error.class}: #{error.message}") if defined?(Log)
    []
  end

  def latest_global_id
    rows = activity_table.select(
      order: [["__id", "desc"]],
      limit: 20
    ).to_a.select { |row| GLOBAL_KINDS.include?(row["kind"].to_s) }
    return 0 if rows.empty?

    rows.map { |row| row_id(row) }.max.to_i
  rescue EltenLink::Error => error
    Log.warning("ELTEN Game Room could not check lobby activity: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def text_for(entry, game_name:, global: false)
    player = GameRoomContent.utf8(GameRoomParticipants.display_name(entry.actor))
    owner = GameRoomContent.utf8(GameRoomParticipants.display_name(entry.owner))
    game = game_name.call(entry.game).to_s
    bot = GameRoomParticipants.display_name(entry.subject) if !entry.subject.to_s.empty?
    if global
      case entry.kind
      when "created"
        _("%{player} created a table for %{game}.") % { player: player, game: game }
      when "joined"
        _("%{player} joined %{owner}'s table for %{game}.") % { player: player, owner: owner, game: game }
      when "left"
        _("%{player} left %{owner}'s table for %{game}.") % { player: player, owner: owner, game: game }
      when "bot_added"
        return _("Added %{bot} at %{owner}'s table for %{game}.") % { bot: bot, owner: owner, game: game } if bot != nil
        _("%{player} added a computer at %{owner}'s table for %{game}.") % { player: player, owner: owner, game: game }
      when "bot_removed"
        return _("Removed %{bot} from %{owner}'s table for %{game}.") % { bot: bot, owner: owner, game: game } if bot != nil
        _("%{player} removed a computer from %{owner}'s table for %{game}.") % { player: player, owner: owner, game: game }
      end
    else
      case entry.kind
      when "created"
        _("%{player} created the table.") % { player: player }
      when "joined"
        _("%{player} joined the room.") % { player: player }
      when "left"
        _("%{player} left the room.") % { player: player }
      when "bot_added"
        return _("Added %{bot}.") % { bot: bot } if bot != nil
        _("%{player} added a computer.") % { player: player }
      when "bot_removed"
        return _("Removed %{bot}.") % { bot: bot } if bot != nil
        _("%{player} removed a computer.") % { player: player }
      when "chat"
        _("%{player}: %{message}") % { player: player, message: entry.message }
      when "invited"
        _("%{player} invited %{user}.") % { player: player, user: GameRoomParticipants.display_name(entry.subject) }
      when "invitation_rejected"
        _("%{user} declined %{player}'s invitation.") % { player: player, user: GameRoomParticipants.display_name(entry.subject) }
      when "game_aborted"
        _("%{player} ended the game. The table remains open.") % { player: player }
      when "options_changed"
        if entry.teams && !entry.teams.empty?
          return entry.teams.each_with_index.map do |members, index|
            _("Team %{team}: %{players}.") % { team: index + 1, players: members.map { |user| GameRoomContent.utf8(GameRoomParticipants.display_name(user)) }.join(", ") }
          end.join(" ")
        end
        _("%{player} changed the settings for the next game.") % { player: player }
      when "role_changed"
        if entry.role == "observer"
          _("%{player} chose %{user} as an observer for the next game.") % { player: player, user: GameRoomContent.utf8(GameRoomParticipants.display_name(entry.subject)) }
        else
          _("%{player} chose %{user} as a player for the next game.") % { player: player, user: GameRoomContent.utf8(GameRoomParticipants.display_name(entry.subject)) }
        end
      when "owner_changed"
        _("%{player} becomes the table master.") % { player: player }
      when 'player_replaced'
        _("%{replacement} replaces %{player}.") % {
          replacement: GameRoomContent.utf8(GameRoomParticipants.display_name(entry.replacement)),
          player: GameRoomContent.utf8(GameRoomParticipants.display_name(entry.subject)) }
      when "seat_control_changed"
        subject = GameRoomContent.utf8(GameRoomParticipants.display_name(entry.subject))
        entry.role == "bot" ? (_("A computer takes over %{player}'s place.") % { player: subject }) :
          (_("%{player} takes back control of their place.") % { player: subject })
      end
    end
  end

  def merge_history(game_entries:, game_events:, activity_entries:, game_name:)
    merged_history_entries(
      game_entries: game_entries,
      game_events: game_events,
      activity_entries: activity_entries,
      game_name: game_name
    ).map(&:text)
  end

  def merged_history_entries(game_entries:, game_events:, activity_entries:, game_name:)
    games = game_entries.to_a.map { |entry| [entry.event_id.to_i, entry.text.to_s] }
    events = game_events.to_a.map { |event| [row_id(event), event["__stack_sequence"], event["created_at"], event["move_id"]] }
    activities = activity_entries.to_a
    names = activities.map(&:game).uniq.to_h { |id| [id, game_name.call(id).to_s] }
    formatted = formatted_activities(activities, names)
    inputs = [games, events]
    cacheable = games.length + events.length + activities.length <= PROJECTION_CACHE_LIMIT
    cached_projection(:@merged_history_projection, inputs, context: formatted, cacheable: cacheable) do |owned|
      build_merged_history(*owned, formatted)
    end
  end

  private

  def native_entries(rows, table)
    context = GameRoomSnapshot.copy({ '__id' => row_id(table), 'owner' => table_owner(table), 'game' => table['game'] })
    cached = @entry_projection
    cached = nil unless cached && cached[:context] == context
    known = cached ? cached[:rows] : {}
    source = project_values(rows, known, key: method(:row_id)) do |owned|
      entry_from(owned, context)
    end
    packed = if cached && cached[:source] == source
      cached[:value]
    else
      Marshal.dump(source.filter_map { |item| item[:value] }.sort_by(&:id))
    end
    bounded = source.length <= PROJECTION_CACHE_LIMIT
    @entry_projection = { context: context, rows: retain_projection_items(source),
      source: bounded ? source : nil, value: bounded ? packed : nil }.freeze
    Marshal.load(packed)
  end

  def formatted_activities(activities, names)
    # Formatting room/chat entries is independent of new game moves. Retain
    # that work, and its owned input snapshot, across subsequent game turns.
    context = GameRoomLocalization.cache_token
    cached = @formatted_activity_projection
    cached = nil unless cached && cached[:context].equal?(context) && cached[:names] == names
    known = cached ? cached[:items] : {}
    own_names = GameRoomSnapshot.copy(names)
    source = project_values(activities, known, key: ->(entry) { entry.id.to_i }) do |entry|
      [entry.id.to_i, entry.stack_sequence.to_i, entry.created_at.to_i,
        entry.kind == 'chat' ? :chat : :room,
        text_for(entry, game_name: ->(id) { own_names.fetch(id) }, global: false).to_s.freeze].freeze
    end
    return cached if cached && cached[:source] == source

    value = { source: source, names: own_names, context: context, items: retain_projection_items(source),
      rows: source.map { |item| item[:value] }.freeze,
      native_order: source.any? { |item| item[:input].stack_sequence } }.freeze
    @formatted_activity_projection = activities.length <= PROJECTION_CACHE_LIMIT ? value : nil
    value
  end

  def project_values(values, known, key:)
    missing, positions = [], []
    source = values.each_with_index.map do |value, index|
      item = known[key.call(value)]
      next item if item && item[:input] == value
      missing << value
      positions << index
      nil
    end
    # One owned copy of the changed subset, not one serialization per row or
    # a fresh snapshot of thousands of unchanged messages on each game move.
    unless missing.empty?
      GameRoomSnapshot.copy(missing).each_with_index do |owned, index|
        source[positions[index]] = { id: key.call(owned), input: owned, value: yield(owned) }.freeze
      end
    end
    source
  end

  def retain_projection_items(source)
    source.last(PROJECTION_CACHE_LIMIT).to_h { |item| [item[:id], item] }.freeze
  end

  def build_merged_history(games, events, formatted)
    native_order = events.any? { |_id, sequence, _time, move| sequence || move.to_s.start_with?("archive:") } ||
      formatted[:native_order]
    event_times = events.each_with_object({}) do |(id, sequence, time, _move), result|
      result[id] = native_order ? sequence.to_i : time.to_i
    end
    records = games.each_with_index.map do |(id, text), index|
      item = GameRoomHistory::Entry.new(text: text, category: :game)
      [event_times.fetch(id, 0), id, 0, index, item]
    end
    formatted[:rows].each_with_index do |(id, sequence, time, category, text), index|
      next if text.empty?
      item = GameRoomHistory::Entry.new(text: text, category: category)
      records << [native_order ? sequence : time, id, 1, index, item]
    end
    records.sort_by { |record| record[0, 4] }.map(&:last)
  end

  # Each slot holds one bounded projection. Own both its input and output;
  # callers may mutate returned entries, source rows, texts or team arrays.
  # A single assignment publishes a complete cache entry across UI/worker
  # readers; a concurrent miss can only replace it with another valid entry.
  def cached_projection(slot, inputs, context: nil, cacheable: true)
    cached = instance_variable_get(slot)
    if cacheable && cached && cached[:context].equal?(context) && cached[:inputs] == inputs
      return Marshal.load(cached[:value])
    end

    owned_inputs = GameRoomSnapshot.copy(inputs)
    result = yield(owned_inputs)
    packed = Marshal.dump(result)
    if cacheable
      instance_variable_set(slot, { context: context, inputs: owned_inputs, value: packed }.freeze)
    else
      instance_variable_set(slot, nil)
    end
    Marshal.load(packed)
  end

  def native_live_sessions?
    @transport.respond_to?(:live_store?) && @transport.live_store?
  end

  def persist_global_activity(table, kind, actor, message: "")
    activity_table.insert(
      "table_id" => row_id(table),
      "kind" => kind.to_s,
      "actor" => actor.to_s,
      "table_owner" => table_owner(table),
      "game" => table["game"].to_s,
      "message" => message,
      "created_at" => GameRoomClock.now.to_i
    )
  rescue StandardError => error
    Log.warning("ELTEN Game Room could not save lobby activity: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def entries_for_current_visit(entries, table, viewer)
    username = viewer.to_s.strip
    return entries if username.empty?

    owner = table_owner(table)
    anchor_kind = GameRoomParticipants.same?(owner, username) ? "created" : "joined"
    anchor = entries.reverse.find do |entry|
      entry.kind == anchor_kind && GameRoomParticipants.same?(entry.actor, username)
    end
    return entries if anchor == nil

    entries.select { |entry| entry.id.to_i >= anchor.id.to_i }
  end

  def activity_table
    @activity_table ||= @server_tables.fetch(TABLE_NAME)
  end

  def entry_from(row, table)
    return nil if row_id(row) <= 0 || row["table_id"].to_i != row_id(table)
    return nil if !KINDS.include?(row["kind"].to_s)
    authority = native_live_sessions? && row["__authority_validated"] == true ? row["table_owner"].to_s : table_owner(table)
    return nil if row["table_owner"].to_s.casecmp(authority) != 0
    return nil if row["game"].to_s != table["game"].to_s

    insertion_user = row["__insertion_user"].to_s
    claimed_actor = row["actor"].to_s
    return nil if !insertion_user.empty? && insertion_user.casecmp(claimed_actor) != 0

    actor = insertion_user.empty? ? claimed_actor : insertion_user
    return nil if actor.empty?

    message = row["kind"].to_s == "chat" ? normalize_message(row["message"]) : ""
    return nil if row["kind"].to_s == "chat" && message.empty?
    subject = row["subject"].to_s
    if BOT_KINDS.include?(row["kind"].to_s)
      subject = bot_subject(row["message"], row_id(table))
      return nil if !row["message"].to_s.empty? && subject.empty?
    end
    if %w[invited invitation_rejected].include?(row["kind"].to_s)
      return nil if row["subject"].to_s.empty? || row["subject"].to_s.length > 64 || row["invitation_id"].to_i <= 0
    end
    if row["kind"] == "role_changed"
      return nil unless GameRoomParticipants.same?(actor, authority) &&
        %w[player observer].include?(row["role"]) && !subject.strip.empty? && subject.length <= 64 && GameRoomParticipants.human?(subject)
    end
    if %w[owner_changed seat_control_changed player_replaced].include?(row["kind"])
      return nil unless native_live_sessions? && row["__authority_validated"] == true && GameRoomParticipants.same?(actor, authority)
      return nil if row["kind"] == "seat_control_changed" && (!%w[human bot].include?(row["role"]) || subject.empty?)
      return nil if row['kind'] == 'player_replaced' && (subject.empty? || row['replacement'].to_s.empty?)
    end

    Entry.new(
      id: row_id(row),
      table_id: row["table_id"].to_i,
      kind: row["kind"].to_s,
      actor: actor,
      owner: authority,
      game: table["game"].to_s,
      message: message,
      subject: subject,
      invitation_id: row["invitation_id"].to_i,
      created_at: row["created_at"].to_i,
      stack_sequence: row["__stack_sequence"],
      teams: row["kind"] == "options_changed" && GameRoomParticipants.same?(actor, authority) ? teams_from(row) : nil,
      role: row["role"], replacement: row['replacement']
    )
  end

  def teams_from(row)
    players, seats = row["team_players"], row["team_seats"]
    return nil unless players.is_a?(Array) && seats.is_a?(Array) && players.length.between?(4, GameRoomTableControl::MAX_SEATS) && seats.length == players.length
    return nil unless players.all? { |name| name.is_a?(String) && !name.strip.empty? && name.length <= 64 } &&
      GameRoomParticipants.unique(players).length == players.length && seats.all? { |seat| seat.is_a?(Integer) && seat.between?(0, 3) }
    teams = Array.new(seats.max + 1) { [] }
    players.each_with_index { |player, index| teams[seats[index]] << player }
    teams if teams.length >= 2 && teams.first.length >= 2 && teams.map(&:length).uniq.length == 1
  end

  def normalize_message(value)
    value.to_s
      .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      .gsub(/[\r\n\t]+/, " ")
      .gsub(/[[:cntrl:]]/, "")
      .strip
      .gsub(/\s+/, " ")
      .slice(0, MESSAGE_MAX_LENGTH)
      .to_s
  end

  def bot_subject(value, table_id)
    candidate = value.to_s
    return "" unless candidate.length <= 64 && GameRoomParticipants.bot?(candidate)
    # This is an identity counter, not the number of occupied seats. Repeated
    # replacements can create bot 9 and later while the table still has 2 seats.
    return "" unless candidate.start_with?("bot:#{table_id}:") && GameRoomParticipants.bot_number(candidate).positive?

    candidate
  end

  def table_owner(row)
    insertion_user = row["__insertion_user"].to_s
    insertion_user.empty? ? row["owner"].to_s : insertion_user
  end

  def row_id(row)
    return 0 if row == nil

    (row["__id"] || row["id"]).to_i
  end
end
