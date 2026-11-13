require_relative "game_room_localization"
require_relative "game_participants"

module GameRoomPreferences
  using GameRoomLocalization::Translations

  INVITATION_POLICIES = %w[contacts nobody everyone].freeze
  ROOM_SOUND_NAMES = %w[connect disconnect conference_created].freeze
  SOUND_GROUPS = %w[all game room chat notifications].freeze
  LEGACY_SOUND_KEYS = {
    "game" => "game_sounds", "room" => "room_membership_sounds",
    "chat" => "chat_sounds", "notifications" => "invitation_sounds"
  }.freeze
  # Old widget settings stored only the checked games. Treat the pre-2.0
  # catalogue as known so old opt-outs survive; the six 2.0 additions (and
  # later games) start checked. The user approved this one-time migration.
  LEGACY_WIDGET_GAME_IDS = %w[
    four_in_a_row tic_tac_toe chess checkers reversi ludo spades farkle
    ninety_nine tysiac categories monopoly yahtzee uno poker makao quiz
  ].freeze
  # Lobby per-game settings began with the same catalogue. Older files do
  # not distinguish missing later games from later manual opt-outs; enable
  # those additions once, then remember lobby choices independently.
  LEGACY_LOBBY_GAME_IDS = LEGACY_WIDGET_GAME_IDS

  module_function

  def defaults(game_ids)
    games = normalized_game_ids(game_ids)
    {
      "display_name" => "",
      "background_table_speech" => true,
      "background_turn_sound" => true,
      "background_game_sounds" => "never",
      "scrabble_draft_speech" => false,
      "announce_lobby_changes" => true,
      "announce_table_created" => true,
      "announce_player_joined" => true,
      "announce_player_left" => true,
      "announce_computer_changes" => true,
      "lobby_games" => games.dup,
      "lobby_known_games" => games.dup,
      "invitation_notifications" => "everyone",
      "invitation_blacklist" => [],
      "table_watch_contacts_only" => false,
      "game_sounds" => true,
      "optional_game_sounds" => true,
      "room_membership_sounds" => true,
      "chat_sounds" => true,
      "invitation_sounds" => true,
      "widget_enabled" => true,
      "widget_contacts_only" => false,
      "widget_games" => games.dup,
      "widget_known_games" => games.dup,
      "widget_show_unavailable" => false,
      "hrtf_enabled" => true,
      "hrtf_games" => games.dup,
      "hrtf_known_games" => games.dup
    }
  end

  def normalize(values, game_ids)
    source = values.is_a?(Hash) ? values : {}
    result = defaults(game_ids)
    source.each { |key, value| result[key.to_s] = duplicate(value) }

    legacy = source["announce_lobby_changes"] != false
    %w[
      announce_table_created
      announce_player_joined
      announce_player_left
      announce_computer_changes
    ].each do |key|
      result[key] = legacy if !source.key?(key)
      result[key] = result[key] != false
    end
    result["announce_lobby_changes"] = %w[
      announce_table_created
      announce_player_joined
      announce_player_left
      announce_computer_changes
    ].any? { |key| result[key] }

    allowed_games = normalized_game_ids(game_ids)
    result["lobby_games"], result["lobby_known_games"] = game_selection(
      source, allowed_games, "lobby_games", "lobby_known_games", LEGACY_LOBBY_GAME_IDS
    )
    result["widget_games"], result["widget_known_games"] = game_selection(
      source, allowed_games, "widget_games", "widget_known_games", LEGACY_WIDGET_GAME_IDS
    )
    result["hrtf_games"], result["hrtf_known_games"] = game_selection(
      source, allowed_games, "hrtf_games", "hrtf_known_games", allowed_games
    )
    result["hrtf_enabled"] = source["hrtf_enabled"] != false
    result["display_name"] = GameRoomParticipants.normalize_display_name(source["display_name"]) || ""
    result["invitation_notifications"] = normalized_invitation_policy(result["invitation_notifications"])
    result["invitation_blacklist"] = invitation_blacklist(result["invitation_blacklist"])
    result["background_game_sounds"] = %w[all audio never].include?(source["background_game_sounds"]) ? source["background_game_sounds"] : "never"
    result["scrabble_draft_speech"] = source["scrabble_draft_speech"] == true
    %w[widget_contacts_only table_watch_contacts_only].each { |key| result[key] = source[key] == true }
    %w[
      background_table_speech
      background_turn_sound
      game_sounds
      optional_game_sounds
      room_membership_sounds
      chat_sounds
      invitation_sounds
      widget_enabled
      widget_show_unavailable
    ].each { |key| result[key] = result[key] != false }
    result["sound_volumes"] = sound_volumes(source)
    result["background_music"] = background_music(source)
    LEGACY_SOUND_KEYS.each do |group, key|
      result[key] = result["sound_volumes"][group] > 0
    end
    result.merge(GameRoomLocalization.normalize_settings(result))
  end

  def background_music(values)
    source = values['background_music'].is_a?(Hash) ? values['background_music'] : {}
    %w[general game].to_h do |kind|
      track = source[kind].is_a?(Hash) ? source[kind] : {}
      volume = track['volume'].is_a?(Numeric) ? track['volume'].to_i.clamp(0, 100) : 30
      path = track['file'].is_a?(String) && !track['file'].include?("\0") ? track['file'].dup : ''
      [kind, {'enabled' => track['enabled'] == true, 'file' => path, 'volume' => volume}]
    end
  end

  def lobby_announcement_enabled?(values, kind, game_id, game_ids)
    settings = normalize(values, game_ids)
    key = case kind.to_s
    when "created" then "announce_table_created"
    when "joined" then "announce_player_joined"
    when "left" then "announce_player_left"
    when "bot_added", "bot_removed" then "announce_computer_changes"
    end
    return false if key == nil || !settings[key]

    settings["lobby_games"].include?(game_id.to_s)
  end

  def sound_enabled?(values, name, game_ids = [])
    sound_volume(values, name) > 0
  end

  def sound_group(name)
    return "chat" if name.to_s == "chatmsg"
    return "room" if ROOM_SOUND_NAMES.include?(name.to_s)
    return "notifications" if %w[notice table_notice invitation_rejected].include?(name.to_s)

    "game"
  end

  def sound_volumes(values)
    source = values.is_a?(Hash) ? values : {}
    stored = source["sound_volumes"].is_a?(Hash) ? source["sound_volumes"] : {}
    SOUND_GROUPS.to_h do |group|
      fallback = source[LEGACY_SOUND_KEYS[group]] == false ? 0 : 100
      level = stored.key?(group) ? stored[group] : fallback
      begin
        level = [[Integer(level), 0].max, 100].min
      rescue ArgumentError, TypeError
        level = fallback
      end
      [group, level]
    end
  end

  def sound_volume(values, name)
    levels = sound_volumes(values)
    levels["all"] * levels[sound_group(name)] / 10_000.0
  end

  def hrtf_game?(values, game_id)
    values.is_a?(Hash) && values["hrtf_enabled"] == true && values["hrtf_games"].to_a.map(&:to_s).include?(game_id.to_s)
  end

  def widget_enabled?(values, game_ids)
    normalize(values, game_ids)["widget_enabled"]
  end

  def widget_game_enabled?(values, game_id, game_ids)
    normalize(values, game_ids)["widget_games"].include?(game_id.to_s)
  end

  def normalized_invitation_policy(value)
    policy = value.to_s
    INVITATION_POLICIES.include?(policy) ? policy : "everyone"
  end

  def invitation_blacklist(values)
    names = values.is_a?(Array) ? values.grep(String).map(&:strip) : []
    GameRoomParticipants.unique(names)
  end

  def invitation_blocked?(values, sender)
    names = values.is_a?(Hash) ? invitation_blacklist(values["invitation_blacklist"]) : []
    GameRoomParticipants.includes?(names, sender.to_s.strip)
  end

  def normalized_game_ids(game_ids)
    game_ids.to_a.map(&:to_s).reject(&:empty?).uniq
  end

  def selected_games(source, key, allowed)
    return allowed.dup if !source.key?(key)

    # A present non-list selects no known games, as nil/objects did before.
    # Do not reset it to all games; new-game migration remains independent.
    requested = source[key].is_a?(Array) ? source[key].map(&:to_s) : []
    allowed.select { |game_id| requested.include?(game_id) }
  end
  private_class_method :selected_games

  def game_selection(source, allowed, selected_key, known_key, legacy_games)
    known = if source[known_key].is_a?(Array)
      normalized_game_ids(source[known_key])
    elsif source.key?(selected_key)
      legacy_games
    else
      allowed
    end
    selected = selected_games(source, selected_key, allowed)
    # Keep this a pure read: lobby/widget refreshes and notification mapping must
    # not write settings. Settings Save persists both the choices and known
    # catalogue, so unchecking a new game is not undone on the next load.
    [allowed.select { |id| selected.include?(id) || !known.include?(id) }, (known + allowed).uniq]
  end
  private_class_method :game_selection

  def duplicate(value)
    value.is_a?(Array) || value.is_a?(Hash) ? value.dup : value
  end
  private_class_method :duplicate
end
