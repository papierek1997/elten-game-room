require "json"
require "digest"
require "securerandom"
require_relative "game_participants"
require_relative "live_session_store"
require_relative "game_session_clock"
require_relative "hidden_submissions"
require_relative "participant_replay"
require_relative "game_statistics_identity"
require_relative "tournament_marker"

# JSON archive format and validation shared by explicit storage adapters.
class GameRoomSavedGameArchive
  FORMAT = 1
  MAX_EVENTS = GameRoomLiveSessionStore::MAX_ARCHIVE_EVENTS
  EVENT_FIELDS = GameRoomEventProtocol::ARCHIVE_EVENT_FIELDS

  class ReplayRepository
    def players_for(session); session["__players"]; end
    def event_id(event); event["id"]; end
    def actor_of(event, _session = nil); event["actor"]; end
  end

  def initialize(program, owner:)
    @program, @owner = program, owner.to_s.dup.freeze
  end

  def put(game:, table:, snapshot:, repository:, now: GameRoomClock.now.to_i, intent: nil, boundary: nil, attempt: nil, tournament:nil)
    GameRoomTournamentMarker.ensure_savable!(table, snapshot.session, tournament: tournament)
    raise ArgumentError, "Unsupported saved game" unless game.supports_saved_games?
    raise ArgumentError, "Only the founder may save the game" unless GameRoomParticipants.same?(table["owner"], @owner)
    replay = game.replay(snapshot.session, snapshot.events, repository)
    error = game.save_game_error(replay)
    raise ArgumentError, error if error != nil
    row = {
      "format" => FORMAT, "game_schema" => game.saved_game_schema_version,
      "id" => SecureRandom.uuid, "owner" => @owner, "saved_at" => now.to_i,
      "game" => game.id, "table_name" => table["name"].to_s, "private" => table["private"] == true,
      "players" => repository.players_for(snapshot.session), "options" => snapshot.session["options"].to_s,
      "game_time" => GameRoomSessionClock.from_server(snapshot.session, now.to_i),
      "events" => replay.accepted_events.map do |event|
        { "id" => repository.event_id(event), "sequence" => event["sequence"].to_i,
          "actor" => repository.actor_of(event, snapshot.session), "action" => event["action"].to_s,
          "value" => event["value"].to_s, "created_at" => event["created_at"].to_i }.tap do |saved|
          # Native projections know the accepted offset at this event. Old
          # archives without it keep their historical interpretation; do not
          # manufacture a timestamp using the current restore offset.
          if event.key?('__game_time') || event.key?('__clock_offset')
            saved['game_time'] = GameRoomSessionClock.from_server(snapshot.session, saved['created_at'], event: event)
          end
        end
      end
    }
    if snapshot.session.key?('__statistics')
      row['statistics'] = GameRoomStatistics::Identity.copy(snapshot.session['__statistics'])
    end
    controllers = snapshot.session.fetch('__controllers', {})
    row['controllers'] = controllers.dup unless controllers.empty?
    unless snapshot.session.fetch('__seat_changes', []).empty?
      row['initial_players'] = snapshot.session.fetch('__initial_players').dup
      row['seat_changes'] = snapshot.session['__seat_changes'].map { |change| {'id' => change['id'], 'players' => change['players'].dup} }
    end
    private_data = if game.saved_game_requires_private_data?
      game.saved_private_data(replay, context: private_context(repository.session_id(snapshot.session)))
    end
    row["private_data"] = private_data unless private_data == nil
    row['tournament']=JSON.parse(JSON.generate(tournament)) if tournament
    row["checksum"] = checksum(row)
    validate(row, game: game)
    if intent
      persist_intent(row, intent: intent, table: table, session: snapshot.session, boundary: boundary, attempt: attempt)
    else
      persist(row)
    end
    row
  end

  def validate(row, game:)
    raise ArgumentError, "Unsupported saved game" if game == nil || !game.supports_saved_games?
    raise ArgumentError, "Incompatible saved game" unless row.is_a?(Hash) && row["format"] == FORMAT &&
      row["game"] == game.id && row["game_schema"] == game.saved_game_schema_version &&
      GameRoomParticipants.same?(row["owner"], @owner) && row["checksum"] == checksum(row)
    if row.key?('tournament')
      marker=row['tournament']
      raise ArgumentError,'Invalid tournament save reference' unless marker.is_a?(Hash) &&
        marker.keys.sort==%w[binding_digest leg match_id publication_ref schedule_id] && marker['publication_ref'].is_a?(Hash) &&
        marker['publication_ref'].keys.sort==%w[author publication_key] && marker['publication_ref'].values.all?{|value|value.is_a?(String) && value.bytesize.between?(1,256)} &&
        %w[binding_digest schedule_id match_id].all?{|key|marker[key].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(marker[key])} &&
        marker['leg'].is_a?(Integer) && marker['leg'].positive?
    end
    if row.key?('statistics') && !GameRoomStatistics::Identity.valid?(row['statistics'], require_started_at: true)
      raise ArgumentError, 'Invalid saved statistics identity'
    end
    players = row["players"]
    raise ArgumentError, "Invalid saved seats" unless players.is_a?(Array) && players.length.between?(game.minimum_players, game.maximum_players) &&
      players.all? { |player| player.is_a?(String) && player.length.between?(1, 64) } && GameRoomParticipants.unique(players).length == players.length
    raise ArgumentError, "Invalid saved game time" unless row["saved_at"].is_a?(Integer) && row["saved_at"] > 0 && row["game_time"].is_a?(Integer) && row["game_time"] > 0
    controllers = row.fetch('controllers', {})
    raise ArgumentError, 'Invalid saved controllers' unless controllers.is_a?(Hash) && controllers.all? do |seat, kind|
      players.include?(seat) && !GameRoomParticipants.bot?(seat) && %w[bot human].include?(kind)
    end
    options = JSON.parse(row.fetch("options"))
    raise ArgumentError, "Invalid saved rules" unless GameRoomOptionValues.normalizable_options?(options) && game.validation_error(options, player_count: players.length) == nil
    events = row["events"]
    raise ArgumentError, "Invalid saved events" unless events.is_a?(Array)
    replay_session = saved_replay_session(row)
    changes = row.fetch('seat_changes', [])
    raise ArgumentError, 'Invalid saved replacements' unless valid_saved_replacements?(row)
    raise ArgumentError, "The saved game is too large to restore safely" if events.length + changes.length > MAX_EVENTS
    last_id = 0
    events.each do |event|
      # Only the saved representation may enter a replay. Native proof and
      # projection fields are reconstructed by the live transport, never
      # supplied by a JSON file, even one with a matching checksum.
      raise ArgumentError, "Invalid saved event" unless event.is_a?(Hash) && (event.keys - EVENT_FIELDS).empty? &&
        event["id"].is_a?(Integer) && event["id"] > last_id &&
        event["sequence"].is_a?(Integer) && event["sequence"] >= 0 &&
        event['actor'].is_a?(String) && GameRoomParticipants.includes?(GameRoomParticipantReplay.roster_at(replay_session, event['id']), event["actor"]) &&
        event["action"].is_a?(String) && event["action"].length.between?(1, 32) && event["value"].is_a?(String) && event["value"].length <= 64 &&
        event["created_at"].is_a?(Integer) && event["created_at"] >= 0 &&
        (!event.key?('game_time') || (GameRoomSessionClock.valid_event_time?(event['game_time']) && event['game_time'] <= row['game_time']))
      last_id = event["id"]
    end
    raise ArgumentError, 'Overlapping saved replacement' unless (events.map { |event| event['id'] } & changes.map { |change| change['id'] }).empty?
    replay = game.replay(replay_session, events.map { |event| GameRoomSessionClock.archived_event(event) }, ReplayRepository.new)
    raise ArgumentError, "Incompatible saved game events" unless replay.accepted_events.length == events.length
    error = game.save_game_error(replay)
    raise ArgumentError, error if error != nil
    game.validate_saved_private_data(replay, row["private_data"])
    row
  rescue JSON::ParserError, KeyError, TypeError
    raise ArgumentError, "Invalid saved game data"
  end

  def restored_data(row, game:, table_id:, now: GameRoomClock.now.to_i)
    GameRoomTournamentMarker.ensure_savable!(row)
    validate(row, game: game)
    bot_number = 0
    all_players = GameRoomParticipants.unique(row['players'] + row.fetch('initial_players', []) + row.fetch('seat_changes', []).flat_map { |change| change['players'] })
    mapping = all_players.to_h do |player|
      replacement = if GameRoomParticipants.bot?(player)
        bot_number += 1
        GameRoomParticipants.bot_id(table_id, bot_number, name_token: GameRoomParticipants.bot_name_token(player))
      else
        player
      end
      [player.downcase, replacement]
    end
    restored = {
      players: row["players"].map { |player| mapping.fetch(player.downcase) },
      initial_players: row.fetch('initial_players', row['players']).map { |player| mapping.fetch(player.downcase) },
      seat_changes: row.fetch('seat_changes', []).map { |change| change.merge('players' => change['players'].map { |player| mapping.fetch(player.downcase) }) },
      controllers: row.fetch('controllers', {}).dup,
      events: row["events"].map { |event| event.merge("actor" => mapping.fetch(event["actor"].downcase), "value" => game.restored_event_value(event, mapping)) },
      clock_offset: now.to_i - row["game_time"].to_i, game_time: row["game_time"].to_i
    }
    restored[:statistics] = GameRoomStatistics::Identity.copy(row['statistics']) if row.key?('statistics')
    replay = game.replay({ '__players' => restored[:players], '__initial_players' => restored[:initial_players],
      '__seat_changes' => restored[:seat_changes], 'options' => row['options'] },
      restored[:events].map { |event| GameRoomSessionClock.archived_event(event) }, ReplayRepository.new)
    raise ArgumentError, "Incompatible saved game seats" unless replay.accepted_events.length == row["events"].length
    if row.key?("private_data")
      # This local callback is not serialized. The transport calls it before
      # publishing game_started; only the public event archive goes on the wire.
      restored[:before_publish] = ->(new_session_id) do
        game.restore_private_data(replay, row["private_data"], context: private_context(new_session_id))
      end
    end
    restored
  end

  private

  def saved_replay_session(row)
    {'__players' => row['players'], '__initial_players' => row.fetch('initial_players', row['players']),
     '__seat_changes' => row.fetch('seat_changes', []), 'options' => row['options']}
  end

  def valid_saved_replacements?(row)
    changes = row.fetch('seat_changes', [])
    initial = row.fetch('initial_players', row['players'])
    return false unless GameRoomTableControl.valid_players?(initial) && initial.length == row['players'].length && changes.is_a?(Array)
    previous = 0
    return false unless changes.all? do |change|
      valid = change.is_a?(Hash) && change.keys.sort == %w[id players] && change['id'].is_a?(Integer) && change['id'] > previous &&
        GameRoomTableControl.valid_players?(change['players']) && change['players'].length == initial.length
      previous = change['id'] if valid
      valid
    end
    (changes.empty? ? initial : changes.last['players']) == row['players']
  end

  def private_context(session_id)
    GameRoomGames::ActionContext.new(session_id: session_id,
      hidden_submissions: HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(@program)))
  end

  def checksum(row)
    Digest::SHA256.hexdigest(JSON.generate(row.reject { |key, _value| key == "checksum" }))
  end
end
