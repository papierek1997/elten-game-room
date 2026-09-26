require 'json'
require_relative 'table_control'
require_relative 'game_statistics_identity'

# Pure stack validation. Only earlier accepted starts enter the index; neither
# future starts nor rejected authors can grant permission to a game action.
class GameRoomLiveSessionStore
  class RecordValidator
    def initialize(accepted = [])
      @starts = {}
      accepted.each { |record| remember(record) }
    end

    def accept(record, owner:, ledger:)
      valid = if record.packet['kind'] == GameRoomTableControl::KIND
        ledger.authoritative_record?(record)
      else
        valid_record?(record.sender, record.packet, owner: owner, ledger: ledger, sequence: record.sequence)
      end
      remember(record) if valid
      valid
    end

    private

    def remember(record)
      @starts[record.packet.dig('data', 'session_id')] = record if record.packet['kind'] == 'game_started'
    end

    def same_user?(first, second)
      GameRoomParticipants.same?(first, second)
    end

    def unique_users(users)
      GameRoomParticipants.unique(users)
    end

    def valid_record?(sender, packet, owner:, ledger: nil, sequence: nil)
      kind = packet["kind"]
      actor = packet["actor"]
      data = packet["data"]
      return false if sender.to_s.empty? || !kind.is_a?(String) || !nonempty_text?(actor) || !data.is_a?(Hash)

      case kind
      when "room_created"
        return false if !same_user?(sender, owner) || !same_user?(actor, owner)

        same_user?(data["owner"], owner) && nonempty_text?(data["owner"]) &&
          nonempty_text?(data["name"]) && nonempty_text?(data["game"]) &&
          room_fields_valid?(data) && integer_between?(data["max_players"], 2, MAX_CAPACITY)
      when "room_state"
        return false if !same_user?(sender, owner) || !same_user?(actor, owner)

        (data.keys - %w[status bot_count bot_names bot_players game_options updated_at observers options_changed expected_options expected_session_id]).empty? &&
          (!data.key?("options_changed") || (data["options_changed"] == true && data.key?("game_options") &&
            json_object_text?(data["expected_options"]) && data["expected_session_id"].is_a?(Integer) && data["expected_session_id"] >= 0)) && room_fields_valid?(data)
      when "room_role"
        same_user?(sender, actor) && (data.keys - %w[role subject]).empty? && %w[player observer].include?(data["role"]) &&
          (!data.key?("subject") || (same_user?(actor, owner) && nonempty_text?(data["subject"]) &&
            data["subject"].length <= 64 && GameRoomParticipants.human?(data["subject"])))
      when "room_activity"
        if %w[invited invitation_rejected].include?(data["activity_kind"])
          return false unless nonempty_text?(data["subject"]) && data["subject"].length <= 64 && positive_integer?(data["invitation_id"])
        end
        same_user?(sender, actor) &&
          %w[created joined left bot_added bot_removed chat invited invitation_rejected].include?(data["activity_kind"]) &&
          %w[message owner game].all? { |key| data[key].is_a?(String) }
      when "game_started"
        return false if !same_user?(sender, owner) || !same_user?(actor, owner)
        return false if data.key?('statistics') && !GameRoomStatistics::Identity.valid?(data['statistics'])

        if data.key?("archive_id")
          return false unless nonempty_text?(data["archive_id"]) && data["archive_id"].length <= 64 &&
            integer_between?(data["archive_events"], 0, MAX_ARCHIVE_EVENTS) &&
            data["event_id_base"].is_a?(Integer) && data["event_id_base"] >= 0 && data["clock_offset"].is_a?(Integer)
        elsif %w[archive_events event_id_base clock_offset].any? { |key| data.key?(key) }
          return false
        end
        players = data["players"]
        if data.key?('initial_players')
          return false unless data.key?('archive_id') && GameRoomTableControl.valid_players?(data['initial_players']) &&
            players.is_a?(Array) && data['initial_players'].length == players.length
        end
        if data.key?('controllers')
          return false unless data.key?('archive_id') && data['controllers'].is_a?(Hash) && data['controllers'].all? do |seat, kind|
            players.is_a?(Array) && players.include?(seat) && !GameRoomParticipants.bot?(seat) && %w[human bot].include?(kind)
          end
        end
        players.is_a?(Array) && players.all? { |player| nonempty_text?(player) && player.length <= 64 } &&
          players.length.between?(1, MAX_CAPACITY) &&
          unique_users(players).length == players.length && positive_integer?(data["session_id"]) &&
          nonempty_text?(data["game"]) && json_object_text?(data["options"]) &&
          positive_integer?(data["created_at"])
      when "game_archive"
        return false unless same_user?(sender, owner) && same_user?(actor, owner)

        events = data["events"]
        nonempty_text?(data["archive_id"]) && data["archive_id"].length <= 64 && integer_between?(data["index"], 0, STACK_ENTRIES - 8) &&
          events.is_a?(Array) && events.length.between?(1, ARCHIVE_EVENTS_PER_RECORD) && events.all? do |event|
            next event.keys.sort == %w[id players] && positive_integer?(event['id']) && GameRoomTableControl.valid_players?(event['players']) if event.is_a?(Hash) && event.key?('players')
            event.is_a?(Hash) && positive_integer?(event["id"]) && event["sequence"].is_a?(Integer) && event["sequence"] >= 0 &&
              nonempty_text?(event["actor"]) && event["actor"].length <= 64 && nonempty_text?(event["action"]) && event["action"].length <= 32 &&
              event["value"].is_a?(String) && event["value"].length <= 64 && event["created_at"].is_a?(Integer) && event["created_at"] >= 0
          end
      when "game_boundary"
        same_user?(sender, owner) && same_user?(actor, owner) && positive_integer?(data["session_id"]) &&
          [true, false].include?(data["frozen"]) &&
          (!data.key?("aborted") || (data["aborted"] == true && data["frozen"] == true))
      when "game_action"
        valid_game_action_record?(sender, actor, data, owner, ledger: ledger, sequence: sequence)
      else
        false
      end
    end

    def valid_game_action_record?(sender, actor, data, owner, ledger: nil, sequence: nil)
      controlled = data["controller"] == true
      if ledger && sequence
        expected_epoch = ledger.epoch_at(sequence)
        return false unless data.fetch("control_epoch", "initial") == expected_epoch
      end
      return false if data.key?("controller") && data["controller"] != true && data["controller"] != false
      if GameRoomParticipants.bot?(actor) || controlled
        return false if !same_user?(sender, owner)
      else
        return false if !same_user?(sender, actor)
      end

      session_id = data["session_id"]
      commands = data["events"]
      return false if !positive_integer?(session_id) || !data["sequence"].is_a?(Integer) || data["sequence"] < 0
      return false if !commands.is_a?(Array) || commands.empty? || commands.length > 50
      return false if commands.any? do |command|
        !command.is_a?(Hash) || !nonempty_text?(command["action"]) || command["action"].length > 32 ||
          !command["value"].is_a?(String) || command["value"].length > 64 || !nonempty_text?(command["move_id"])
      end

      game = @starts[session_id]
      return false if game == nil

      players = game.packet.dig("data", "players").to_a.map(&:to_s)
      players = ledger.players(session_id, initial: players, before: sequence) if ledger
      if GameRoomParticipants.bot?(actor) || controlled
        same_user?(sender, owner) && players.any? { |player| same_user?(player, actor) }
      else
        same_user?(sender, actor) && players.any? { |player| same_user?(player, actor) }
      end
    end

    def nonempty_text?(value)
      value.is_a?(String) && !value.empty?
    end

    def positive_integer?(value)
      value.is_a?(Integer) && value.positive?
    end

    def integer_between?(value, minimum, maximum)
      value.is_a?(Integer) && value.between?(minimum, maximum)
    end

    def json_object_text?(value)
      value.is_a?(String) && JSON.parse(value).is_a?(Hash)
    rescue JSON::ParserError
      false
    end

    def room_fields_valid?(data)
      if data.key?('bot_players')
        bots = data['bot_players']
        return false unless bots.is_a?(Array) && bots.length == data['bot_count'] &&
          GameRoomParticipants.unique(bots).length == bots.length && bots.all? { |person| GameRoomParticipants.bot?(person) }
      end
      return false if data.key?("status") && !%w[waiting playing closed].include?(data["status"])
      return false if data.key?("bot_count") && !integer_between?(data["bot_count"], 0, MAX_CAPACITY)
      if data.key?("bot_names")
        names = data["bot_names"]
        return false unless names.is_a?(Array) && names.length <= MAX_CAPACITY && names.length == data["bot_count"]
        return false unless names.all? { |token| token == nil || (token.is_a?(String) && GameRoomBotNames.name_for(token) != nil) }
        return false unless names.compact.uniq.length == names.compact.length
      end
      return false if data.key?("game_options") && !json_object_text?(data["game_options"])
      if data.key?("observers")
        observers = data["observers"]
        return false if !observers.is_a?(Array) || observers.length > MAX_CAPACITY
        return false if observers.any? { |observer| !nonempty_text?(observer) }
        return false if unique_users(observers).length != observers.length
      end

      %w[created_at updated_at].all? { |key| !data.key?(key) || positive_integer?(data[key]) }
    end

  end
end
