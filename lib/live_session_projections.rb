class GameRoomLiveSessionStore
  module Projections
    public

    def room_bots(table_id, table)
      table['bot_players'] || GameRoomParticipants.bots_for(table_id, table['bot_count'].to_i, names: table['bot_names'])
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

    def game_sessions(table_or_id = nil, force: false)
      game_start_records(table_or_id, force: force).filter_map { |record| game_session_from(record) }
        .sort_by { |row| row["__id"].to_i }
    end

    # Select before materializing clocks, archives and seat history. Retained
    # old matches must not make every current-session read rebuild every row.
    # Only records accepted by records_for are eligible; IDs are not clocks.
    def find_game_session(table_or_id, force: false)
      starts = game_start_records(table_or_id, force: force)
        .sort_by { |record| [-record.sequence.to_i, record.packet.dig('data', 'session_id').to_i] }
      starts.each do |record|
        row = game_session_from(record)
        return row if row && (!block_given? || yield(row))
      end
      nil
    end

    def game_session(session_id, table: nil)
      wanted = positive_identifier(session_id)
      return nil if wanted == nil

      game_start_records(table).each do |record|
        next unless record.packet.dig('data', 'session_id') == wanted
        row = game_session_from(record)
        return row if row
      end
      nil
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

    def game_aborted?(table_id, session_id)
      records_for(table_id).any? do |record|
        record.packet["kind"] == "game_boundary" && record.packet.dig("data", "session_id") == session_id.to_i && record.packet.dig("data", "aborted") == true
      end
    end

    def game_frozen?(table_id, session_id)
      boundary = records_for(table_id).reverse.find { |record| record.packet["kind"] == "game_boundary" && record.packet.dig("data", "session_id") == session_id.to_i }
      boundary != nil && boundary.packet.dig("data", "frozen") == true
    end

    private

    def game_start_records(table_or_id, force: false)
      table_id = table_or_id == nil ? nil : table_identifier(table_or_id)
      ids = table_id == nil ? active_table_ids : [table_id]
      ids.compact.flat_map do |id|
        ensure_current(id, force: force)
        records_for(id).select { |record| record.packet['kind'] == 'game_started' }
      end
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
      published_activity = session&.discovery_metadata.to_h['last_activity_at'].to_i
      realtime = @mutex.synchronize { @realtime_activity[table_id] }
      realtime_time = realtime && realtime[0].equal?(session) && realtime[1] == latest_id ? realtime[2] : 0
      activity = [row['last_activity_at'].to_i, published_activity, realtime_time].max
      row['last_activity_at'] = activity if activity.positive?
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
        if activity_record?(record) && !record.estimated_time
          row['last_activity_at'] = [row['last_activity_at'].to_i, record.created_at.to_i].max
        end
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
        "max_players" => bounded_capacity(metadata["max_players"] || DEFAULT_CAPACITY),
        "bot_count" => [[metadata["bot_count"].to_i, 0].max, MAX_CAPACITY].min,
        "game_options" => discovery_options(metadata),
        "player_count" => metadata.key?("player_count") ? [[metadata["player_count"].to_i, 0].max, MAX_CAPACITY].min : 1,
        "created_at" => metadata["created_at"].to_i,
        "updated_at" => metadata["created_at"].to_i,
        "last_activity_at" => metadata['last_activity_at'].is_a?(Integer) && metadata['last_activity_at'].positive? ? metadata['last_activity_at'] : nil
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
        "__clock_revision" => @mutex.synchronize { (@rooms[record.table_id]&.clock_revisions&.fetch(id, 0) || 0) },
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
  end

  include Projections
end
