# encoding: UTF-8

=begin Elten3AppInfo
{
  "id": "c24d98cc-9ccd-4d50-b801-459da324ff60",
  "name": "ELTEN Game Room",
  "description": "Accessible multiplayer games for ELTEN users.",
  "version": "2.0.1",
  "build_id": "229",
  "EltenAPIVersion": "3.0.3",
  "main_language": "en",
  "supported_languages": ["en", "pl"],
  "localized_descriptions": {
    "pl": "Dostępne gry wieloosobowe dla użytkowników ELTEN-a."
  },
  "author": "papierek",
  "main": "__app.rb",
  "main_class": "EltenGameRoom",
  "platforms": ["all"],
  "menu": {
    "main": "ELTEN Game Room"
  },
  "required_assets": {
    "sounds": [
      "connect", "disconnect", "chatmsg", "notice", "buzzer2", "ding", "shuffle", "draw", "draw2",
      "farkle", "hit1", "interception", "lose1", "lose3", "play", "play2", "replay",
      "reverse", "reverse3", "roll", "skip", "win1", "win2",
      "farkle_bank", "ninety3366", "1000_mariage", "win_party", "lose_party",
      "domino_refill", "domino_move_tile", "domino_take_chip",
      "krowa-race", "krowa-word-tower", "krowa-single", "krowa-opponent-guessed",
      "krowa-duplicate", "krowa-unknown", "krowa-length", "krowa-success"
    ]
  }
}
=end Elten3AppInfo

require "json"
require_relative "lib/game_audio"
require_relative "lib/game_room_transport"
require_relative "lib/game_sync"
require_relative "lib/game_room_server_tables"
require_relative "lib/game_room_user_registry"
require_relative "lib/table_activity_repository"
require_relative "lib/game_rules"
require_relative "lib/game_room_changelog"
require_relative "lib/game_room_screens"
require_relative "lib/invitation_repository"
require_relative "lib/invitation_notifications"
require_relative "lib/table_watch_runtime"
require_relative "lib/invitation_receipts"
require_relative "lib/game_participants"
require_relative "lib/game_sounds"
require_relative "lib/game_room_preferences"
require_relative "lib/game_room_widget"
require_relative "lib/game_teams"
require_relative "lib/game_bots"
require_relative "lib/lobby_repository"
require_relative "lib/game_repository"
require_relative "lib/saved_games"
require_relative "lib/game_lifecycle"
require_relative "lib/room_presentation"
require_relative "lib/game_rounds"
require_relative "lib/game_random"
require_relative "lib/game_scoring"
require_relative "lib/hidden_submissions"
require_relative "lib/game_shortcuts"
require_relative "lib/game_surfaces"
require_relative "lib/game_layout"
require_relative "lib/game_simulation"
require_relative "lib/game_training"
require_relative "lib/game_screen"
require_relative "lib/game_content"
require_relative "content/languages"
require_relative "content/monopoly_boards"
require_relative "content/quiz_general_en"
require_relative "content/quiz_pl_wikidata"
require_relative "content/quiz_witcher_pl"
require_relative "games/base"
require_relative "games/board_game"
require_relative "games/card_game"
require_relative "games/four_in_a_row"
require_relative "games/tic_tac_toe"
require_relative "games/chess"
require_relative "games/checkers"
require_relative "games/reversi"
require_relative "games/ludo"
require_relative "games/spades"
require_relative "games/farkle"
require_relative "games/ninety_nine"
require_relative "games/tysiac"
require_relative "games/categories"
require_relative "games/monopoly"
require_relative "games/yahtzee"
require_relative "games/uno"
require_relative "games/poker"
require_relative "games/makao"
require_relative "games/quiz_party"
require_relative "games/rummy"
require_relative "games/domino"
require_relative "games/mexican_train"
require_relative "games/scrabble"
require_relative "games/taboo"
require_relative "games/biblios"
require_relative "games/krowa"
require_relative "games/registry"

class EltenGameRoom < Program
  extend GameRoomTableWatchRuntime
  GAME_ROOM_VERSION = "2.0.1".freeze
  GAME_ROOM_BUILD_ID = 229
  GAME_ROOM_CAPABILITIES = ["invitations", "live_sessions", "live_session_stack"].freeze
  LOBBY_ACTIVITY_POLL_INTERVAL = 5.0
  NOTIFICATION_CONTACT_CACHE_SECONDS = 5 * 60

  SERVER_TABLES = {
    GameRoomTableWatch::TABLE => GameRoomTableWatch::SCHEMA,
    "game_room_users" => {
      "visibility" => "public",
      "columns" => {
        "username" => "string:64",
        "version" => "string:32",
        "build_id" => "integer",
        "capabilities" => "string:256",
        "registered_at" => "integer"
      },
      "permissions" => ["select", "insert", "update"],
      "indexes" => [["username"], ["registered_at"]],
      "limits" => { "max_select_limit" => 1_000 }
    },
    "table_activity" => {
      "visibility" => "public",
      "columns" => {
        "table_id" => "integer",
        "kind" => "string:16",
        "actor" => "string:64",
        "table_owner" => "string:64",
        "game" => "string:32",
        "message" => "string:512",
        "created_at" => "integer"
      },
      "permissions" => ["select", "insert"],
      "indexes" => [["table_id", "created_at"], ["created_at"]],
      "limits" => { "max_select_limit" => 2_000 }
    },
    "krowa_daily_completions" => {
      "visibility" => "shared",
      "columns" => {
        "day_key" => "integer",
        "status" => "integer"
      },
      "permissions" => ["select", "insert"],
      "indexes" => [["day_key"]],
      "limits" => { "max_select_limit" => 500 }
    },
    "krowa_word_scores" => {
      "visibility" => "public",
      "columns" => {
        "word" => "string:32",
        "attempts" => "integer"
      },
      "permissions" => ["select", "insert"],
      "indexes" => [["word", "attempts"]],
      "limits" => { "max_select_limit" => 2_000 }
    },
    "krowa_tower_scores" => {
      "visibility" => "public",
      "columns" => {
        "run_code" => "integer",
        "rounds" => "integer",
        "participants" => "string:1024"
      },
      "permissions" => ["select", "insert"],
      "indexes" => [["run_code"], ["rounds"]],
      "limits" => { "max_select_limit" => 500 }
    },
    "krowa_tower_rounds" => {
      "visibility" => "public",
      "columns" => {
        "run_code" => "integer",
        "round" => "integer",
        "word" => "string:32",
        "attempts" => "integer",
        "solved" => "integer"
      },
      "permissions" => ["select", "insert"],
      "indexes" => [["run_code", "round"]],
      "limits" => { "max_select_limit" => 500 }
    }
  }.freeze

  MAIN_OPTIONS = [
    _("Create a new table"),
    _("Join a table"),
    _("Game rules"),
    _("Invitations"),
    _("Saved games"),
    _("Leaderboards"),
    _("Settings"),
    _("What's new")
  ].freeze

  GAME_REGISTRY = GameRoomGames::Registry.new([
    GameRoomGames::FourInARow,
    GameRoomGames::TicTacToe,
    GameRoomGames::Chess,
    GameRoomGames::Checkers,
    GameRoomGames::Reversi,
    GameRoomGames::Ludo,
    GameRoomGames::Spades,
    GameRoomGames::Farkle,
    GameRoomGames::NinetyNine,
    GameRoomGames::Tysiac,
    GameRoomGames::Categories,
    GameRoomGames::Monopoly,
    GameRoomGames::Yahtzee,
    GameRoomGames::Uno,
    GameRoomGames::Poker,
    GameRoomGames::Makao,
    GameRoomGames::QuizParty,
    GameRoomGames::Rummy,
    GameRoomGames::Domino,
    GameRoomGames::MexicanTrain,
    GameRoomGames::Scrabble,
    GameRoomGames::Taboo,
    GameRoomGames::Biblios,
    GameRoomGames::Krowa
  ])

  DEFAULT_SETTINGS = GameRoomPreferences.defaults(GAME_REGISTRY.ids).freeze

  # All Krowa tables use the canonical Game Room application. A test build
  # must never route production tables through a developer's personal app.
  SERVER_TABLE_APP_UUIDS = {}.freeze

  server_app(
    uuid: "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80",
    tables: SERVER_TABLES,
    protected: true,
    notifications: true
  )

  def self.activate
    return if !respond_to?(:app_runtime) || app_runtime == nil || !respond_to?(:extension)
    return if @game_room_extension_registered == true

    program = new
    extension("game_room_main_tab") do |extension|
      extension.start { table_watch_start }
      extension.tick(interval: 1.0) { table_watch_tick }
      extension.stop { table_watch_stop }
      extension.main_tab(
        "tables",
        label: _("Game Room"),
        visible: -> { normalized_settings["widget_enabled"] }
      ) do |context|
        current = context.current_control
        program.instance_variable_set(:@widget_host_scene, context.scene) if context.respond_to?(:scene)
        current.is_a?(GameRoomWidget::TableList) ? current : program.send(:build_widget_control)
      end
    end
    @game_room_extension_registered = true
  rescue StandardError => error
    Log.warning("ELTEN Game Room extension registration failed: #{error.class}: #{error.message}") if defined?(Log)
  end

  def self.normalized_settings
    GameRoomPreferences.normalize(
      read_json("settings.json", default: DEFAULT_SETTINGS.dup),
      GAME_REGISTRY.ids
    )
  end

  def self.notification_sender_in_contacts?(sender)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if @notification_contacts == nil || @notification_contacts_loaded_at == nil ||
        now - @notification_contacts_loaded_at >= NOTIFICATION_CONTACT_CACHE_SECONDS
      contacts = EltenLink::Contacts.list(EltenLink::Client.new)
      @notification_contacts = contacts.to_a.each_with_object({}) do |user, result|
        result[user.to_s.strip.downcase] = true
      end
      @notification_contacts_loaded_at = now
    end
    @notification_contacts.key?(sender.to_s.strip.downcase)
  rescue StandardError => error
    Log.warning("ELTEN Game Room invitation contact filter failed: #{error.class}: #{error.message}") if defined?(Log)
    @notification_contacts != nil && @notification_contacts.key?(sender.to_s.strip.downcase)
  end

  def self.invitation_notification_allowed?(settings, sender)
    case settings["invitation_notifications"].to_s
    when "nobody" then false
    when "contacts" then notification_sender_in_contacts?(sender)
    else true
    end
  end

  def self.map_notification(notification)
    GameRoomTableWatch::Timing.measure(:mapping) { map_game_room_notification(notification) }
  end

  def self.map_game_room_notification(notification)
    if GameRoomInvitationReceipts::TYPES.include?(notification.type.to_s)
      return notification.presentation(title: "", body: "", sound: nil).suppress_default!
    end
    metadata = notification.metadata.to_h
    settings = normalized_settings
    sound = nil
    if settings["invitation_sounds"]
      notice_sound = respond_to?(:sound_asset_path) ? sound_asset_path("notice") : nil
      sound = notice_sound || "notice"
    end
    presentation = case notification.type.to_s
    when GameRoomTableWatch::TYPE
      receiver = table_watch_receiver
      if receiver.visible?(notification)
        sound = nil if receiver.received?(notification)
        title = [notification.sender, GAME_REGISTRY.name(metadata["game"])].map { |text| GameRoomContent.utf8(text) }.join(", ")
        notification.presentation(title: title, body: GameRoomContent.utf8(_("New table")),
          sound: sound, action: :open_new_table)
      else
        # suppress_default! stops delivery speech, not rows in the host's
        # notification list. Keep a readable fallback until our pruning runs.
        notification.presentation(title: _("New table"),
          body: _("This table announcement has expired or is no longer available."), sound: nil).suppress_default!
      end
    when "game_room.invitation"
      presentation = notification.presentation(
        title: _("Game invitation"),
        body: (metadata["continuation"] == true ? _("%{sender} invites you to resume %{table} (%{game}).") : _("%{sender} invites you to %{table} (%{game}).")) % {
          sender: metadata["sender"].to_s,
          table: metadata["table_name"].to_s,
          game: metadata["game_name"].to_s
        },
        sound: sound,
        action: :open_invitation
      )
      if !invitation_notification_allowed?(settings, metadata["sender"] || notification.sender)
        presentation.suppress_default!
      end
      presentation
    end
    if presentation != nil && sound != nil && respond_to?(:play_sound_from_asset)
      presentation.extend(GameRoomUI::NotificationSound)
      presentation.game_room_notice_player = lambda do
        volume = GameRoomPreferences.sound_volume(normalized_settings, "notice")
        GameRoomTableWatch::Timing.measure(:audio) { play_sound_from_asset("notice", volume: volume) } if volume > 0
      rescue StandardError => error
        Log.warning("ELTEN Game Room notification sound failed: #{error.class}: #{error.message}") if defined?(Log)
      end
    end
    presentation
  end

  def self.receive_invitation_receipt(notification)
    GameRoomInvitationReceipts.enqueue(self, notification)
  end

  def self.notification_received(notification, _presentation = nil)
    receive_invitation_receipt(notification) if GameRoomInvitationReceipts::TYPES.include?(notification.type.to_s)
    if notification.type.to_s == GameRoomTableWatch::TYPE
      received = GameRoomTableWatch::Timing.measure(:receipt) { table_watch_receiver.receive(notification) }
      _presentation&.suppress_default! unless received
    end
  end

  def program_main
    initialize_services
    show_update_changelog
    check_server_table_access
    current = run_network_task(_("Checking your current table")) do
      @transport.start
      register_game_room_user
      row = @lobby.current_table_for(Session.name)
      establish_table_transport(row, bootstrap: true) if row != nil
      row
    end
    play_game_sound("connect") if current != nil
    run_program_interface(current)
  end

  def signaled(user, packet)
    (@transport ||= GameRoomTransport.new(self)).receive(user, packet)
  end

  def notification_action(action, notification)
    return open_new_table_notification(notification) if action.to_s == "open_new_table"
    return false if action.to_s.to_sym != :open_invitation

    initialize_services
    check_server_table_access
    run_network_task(_("Connecting to Elten")) { @transport.start }
    invitation_id = notification.metadata.to_h["invitation_id"].to_i
    expiry = notification.metadata.to_h["expires_at"].to_i
    # Older notifications did not carry an expiry. Their actual invitation
    # still needs the authoritative lookup below, not a false "expired".
    if expiry > 0 && expiry <= Time.now.to_i
      revoke_invitation_notification(invitation_id, notification_id: notification.id)
      alert(_("This invitation has expired."))
      return true
    end
    row = nil
    @invitation_notifications.with_opened(notification) do
      choices = load_pending_invitations
      return true if choices == nil

      selected = choices.find { |choice| choice[:invitation].id == invitation_id }
      if selected == nil
        revoke_invitation_notification(invitation_id, notification_id: notification.id)
        alert(_("This table is no longer available."))
        return true
      end

      case select_notification_invitation_action
      when :accept
        row = accept_pending_invitation(selected[:invitation], notification_id: notification.id)
      when :reject
        reject_pending_invitation(selected[:invitation], notification_id: notification.id)
      end
    end
    run_program_interface(row) if row != nil
    true
  end

  private

  def game_room_server_tables
    @server_tables ||= GameRoomServerTables.new(self, table_app_uuids: SERVER_TABLE_APP_UUIDS)
  end

  def initialize_services
    @transport ||= GameRoomTransport.new(self)
    game_room_server_tables
    @game_room_users ||= GameRoomUserRegistry.new(server_tables: @server_tables)
    @table_activity ||= TableActivityRepository.new(server_tables: @server_tables, transport: @transport)
    @lobby ||= LobbyRepository.new(
      self,
      transport: @transport,
      server_tables: @server_tables,
      activity_repository: @table_activity
    )
    @games ||= GameRepository.new(self, transport: @transport, server_tables: @server_tables)
    @invitations ||= InvitationRepository.new(transport: @transport, notification_source: ->(recipient, now) {
      @invitation_notifications.pending(recipient: recipient, now: now)
    }, response_sender: ->(invitation, response) {
      deliver_invitation_response(invitation, response)
    })
    @invitation_notifications ||= InvitationNotifications.new(
      client: EltenLink::Client.new,
      app_uuid: self.class.server_app_uuid
    )
  end

  def check_server_table_access
    @announced_table_access_state = nil
    # Reset before entering Tasks.run: cancelling before the worker starts must
    # not retain access from an earlier invocation on this same instance.
    @server_tables.reset_access!
    run_network_task(_("Checking server table access"), silent: true) do
      @server_tables.check_access(username: Session.name)
    end
  end

  def announce_server_table_access
    state = @server_tables&.access_state
    return if ![:stamp_required, :unavailable].include?(state)
    return if @announced_table_access_state == state

    @announced_table_access_state = state
    if state == :stamp_required
      alert(_("Development mode without server table access. Global lobby history and sending invitations are unavailable."))
    else
      alert(_("Server table access could not be checked. Global lobby history and sending invitations are unavailable until you reopen Game Room."))
    end
  end

  def invitation_sending_available?
    return true if @server_tables.available?

    if @server_tables.stamp_required?
      alert(_("Sending invitations is unavailable in development mode without server table access."))
    else
      alert(_("Sending invitations is unavailable because server table access could not be confirmed."))
    end
    false
  end

  def run_program_interface(initial_table = nil)
    @lobby_activity_entries = []
    reset_lobby_activity_cursor
    current = initial_table
    loop do
      switched = catch(:game_room_table_switch) do
        show_table_screen(current) if current != nil
        show_main_menu
        return
      end
      current = switched
    end
  end

  def show_main_menu
    @last_seen_lobby_activity_id = nil
    @last_lobby_activity_poll_at = nil
    selected_index = 0
    loop do
      history_items = load_lobby_history
      result = GameRoomScreens::MainMenu.new(
        program: self,
        options: MAIN_OPTIONS,
        history_items: history_items,
        index: selected_index,
        invitations: true,
        refresh: (@server_tables.available? ? ->(form, history) { poll_lobby_activity(form, history) } : nil)
      ).wait
      selected_index = result.index
      case result.action
      when :open
        open_main_option(selected_index)
        reset_lobby_activity_cursor
      when :exit
        return if confirm(_("Do you want to exit ELTEN Game Room?"))
      when :invitations
        switch_to_invited_table
        reset_lobby_activity_cursor
      when :reject_invitation
        show_pending_invitations(mode: :reject)
        reset_lobby_activity_cursor
      when :refresh
        next
      end
    end
  end

  def load_lobby_history
    return [] if !@server_tables.available?

    entries = run_network_task(_("Loading Game Room history"), ui: :none, silent: true) do
      @table_activity.global_entries
    end
    capture_lobby_activity(entries.to_a)
    @lobby_activity_entries.to_a.map do |entry|
      @table_activity.text_for(entry, game_name: ->(id) { game_name(id) }, global: true)
    end.compact
  end

  def capture_lobby_activity(entries)
    newest_id = entries.map(&:id).max.to_i
    if @last_seen_lobby_activity_id == nil
      @last_seen_lobby_activity_id = newest_id
      return
    end

    new_entries = entries.select { |entry| entry.id.to_i > @last_seen_lobby_activity_id.to_i }
    @lobby_activity_entries ||= []
    known_ids = @lobby_activity_entries.each_with_object({}) do |entry, result|
      result[entry.id.to_i] = true
    end
    new_entries.each do |entry|
      @lobby_activity_entries << entry if !known_ids.key?(entry.id.to_i)
    end
    @lobby_activity_entries.sort_by! { |entry| [entry.created_at.to_i, entry.id.to_i] }
    @lobby_activity_entries = @lobby_activity_entries.last(TableActivityRepository::GLOBAL_LIMIT)

    settings = game_room_settings
    new_entries.each do |entry|
      next if GameRoomParticipants.same?(entry.actor, Session.name)
      next if !lobby_announcement_enabled?(entry.kind, entry.game, settings)
      # For subscribed games the notification owns the creation announcement.
      # The lobby history still contains the event, but does not speak it twice.
      next if entry.kind.to_s == "created" && self.class.table_watch_receiver.games.to_a.include?(entry.game.to_s)

      text = @table_activity.text_for(entry, game_name: ->(id) { game_name(id) }, global: true)
      speak(text, stop: false, break_sequence: false) if !text.to_s.empty?
    end
    @last_seen_lobby_activity_id = [@last_seen_lobby_activity_id.to_i, newest_id].max
  end

  def poll_lobby_activity(form, history)
    return false if !@server_tables.available? || @lobby_activity_polling == true

    now = monotonic_time
    if @last_lobby_activity_poll_at != nil && now - @last_lobby_activity_poll_at < LOBBY_ACTIVITY_POLL_INTERVAL
      return false
    end

    @last_lobby_activity_poll_at = now
    @lobby_activity_polling = true
    newest_id = run_network_task(_("Loading Game Room history"), ui: form, silent: true) do
      @table_activity.latest_global_id
    end
    return false if newest_id == nil || newest_id.to_i <= @last_seen_lobby_activity_id.to_i

    index = history.index.to_i
    history.options = load_lobby_history
    history.index = bounded_index(index, history.options)
    false
  ensure
    @lobby_activity_polling = false
  end

  def reset_lobby_activity_cursor
    @last_seen_lobby_activity_id = nil
    @last_lobby_activity_poll_at = nil
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rescue Exception
    Time.now.to_f
  end

  def lobby_announcement_enabled?(kind, game_id, settings)
    GameRoomPreferences.lobby_announcement_enabled?(
      settings, kind, game_id, GAME_REGISTRY.ids
    )
  end

  def open_main_option(index)
    case index.to_i
    when 0
      show_create_table
    when 1
      show_join_table
    when 2
      show_rules_library
    when 3
      switch_to_invited_table
    when 4
      show_saved_games
    when 5
      show_leaderboards
    when 6
      show_settings
    when 7
      show_changelog
    end
  end

  def show_leaderboards
    available = GAME_REGISTRY.ids.select do |game_id|
      game_definition(game_id)&.build_leaderboard_client(self) != nil
    end
    if available.empty?
      alert(_("No leaderboards are available in this version."))
      return
    end

    game_id = select_game(_("Leaderboards"), available)
    return if game_id == nil

    client = game_definition(game_id).build_leaderboard_client(self)
    client.run
  ensure
    client&.close
  end

  def show_update_changelog
    return if !respond_to?(:read_json, true) || !respond_to?(:update_json, true)

    entries = GameRoomChangelog.pending_entries(
      last_seen_changelog_build,
      GAME_ROOM_BUILD_ID
    )
    return if entries.empty?

    show_changelog_entries(entries)
    remember_changelog_build
  end

  def show_changelog
    entries = GameRoomChangelog.available_entries(GAME_ROOM_BUILD_ID)
    return if entries.empty?

    show_changelog_entries(entries)
    remember_changelog_build
  end

  def show_changelog_entries(entries)
    items = GameRoomChangelog.list_items(entries, translator: ->(text) { _(text) })
    GameRoomScreens::Changelog.new(items, program: self).wait
  end

  def last_seen_changelog_build
    state = read_json(GameRoomChangelog::STORAGE_FILE, default: {})
    value = state.is_a?(Hash) ? state[GameRoomChangelog::LAST_SEEN_BUILD_KEY] : nil
    return nil if value == nil

    Integer(value)
  rescue StandardError => error
    Log.warning("ELTEN Game Room changelog state could not be read: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def remember_changelog_build
    update_json(GameRoomChangelog::STORAGE_FILE, default: {}) do |state|
      raise TypeError, "invalid changelog state" if !state.is_a?(Hash)

      previous = begin
        Integer(state[GameRoomChangelog::LAST_SEEN_BUILD_KEY])
      rescue StandardError
        0
      end
      state[GameRoomChangelog::LAST_SEEN_BUILD_KEY] = [previous, GAME_ROOM_BUILD_ID].max
    end
  rescue StandardError => error
    Log.warning("ELTEN Game Room changelog state could not be saved: #{error.class}: #{error.message}") if defined?(Log)
  end

  def show_rules_library
    game_id = select_game(_("Game rules"), GAME_REGISTRY.ids)
    return if game_id == nil

    show_game_rules(game_definition(game_id))
  end

  def show_game_rules(game, options: nil)
    if game == nil
      alert(_("Rules for this game are not available in this version of ELTEN Game Room."))
      return
    end

    GameRoomScreens::GameRules.new(game.rule_book(options: options), program: self).wait
  end

  def show_create_table
    game_id = select_game(_("Create a new table"), GAME_REGISTRY.ids)
    return if game_id == nil

    game = game_definition(game_id)
    configuration = configure_game_options(game, creating_table: true)
    return if configuration == nil

    game_options = configuration.fetch(:game_options)
    privacy = configuration.fetch(:private_table)

    result = run_network_task(_("Creating table")) do
      created = @lobby.create_table(
        name: default_table_name,
        game: game_id,
        owner: Session.name,
        game_options: JSON.generate(game_options),
        private_table: privacy
      )
      activate_table_transport(created&.table)
      created
    end
    return if result == nil

    alert(_("You are already at a table.")) if !result.created?
    if result.created?
      self.class.announce_new_public_table(result.table) unless privacy
      play_game_sound("connect")
      created_message = _("You created a room.").to_s.sub(/\.\z/, "")
      speak("#{created_message}: #{game_name(game_id)}.")
      # The first focused field is Start game. Let the creation confirmation
      # finish before its focus announcement instead of cutting it off.
      speech_wait
    end
    show_table_screen(result.table)
  end

  def saved_games
    @saved_games ||= SavedGames.new(self, owner: Session.name)
  end

  def save_current_game(table, session, game)
    before = run_network_task(_("Checking game before saving"), ui: :none) { @games.snapshot_for(session) }
    return false if before == nil
    error = game.save_game_error(game.replay(before.session, before.events, @games))
    if error != nil
      alert(error)
      return false
    end
    return false if !confirm(_("Save this game and close the table for everyone?"))

    result = run_network_task(_("Saving game")) do
      frozen = false
      begin
        boundary = @transport.freeze_game(session)
        frozen = true
        confirmed = @games.snapshot_for(session, force_events: true)
        raise ArgumentError, "The room is no longer active" if confirmed == nil
        saved_games.put(game: game, table: table, snapshot: confirmed, repository: @games,
          now: (confirmed.session["__frozen_at"] || boundary.created_at).to_i)
      rescue StandardError
        @transport.freeze_game(session, frozen: false) if frozen
        raise
      end
      # A failed close keeps the verified archive and native membership.
      # Release the pause so a still-open room does not become unusable.
      begin
        @transport.deactivate_table(table_id: @lobby.table_id(table))
      rescue StandardError
        @transport.freeze_game(session, frozen: false) if @transport.current_room(Session.name) != nil
        raise
      end
      true
    end
    return false if !result

    forget_room_membership(table)
    play_game_sound("disconnect")
    alert(_("The game has been saved."))
    true
  rescue ArgumentError, IOError, SystemCallError => error
    Log.warning("ELTEN Game Room save failed: #{error.class}") if defined?(Log)
    alert(_("The game could not be saved. The table was not closed by this operation."))
    false
  end

  def show_saved_games
    loop do
      rows = saved_games.list
      if rows.empty?
        alert(_("You have no saved games."))
        return
      end
      selected = select_saved_game_item(rows.map { |row|
        _("%{game}; %{date}; %{players}") % { game: game_name(row["game"]),
          date: Time.at(row["saved_at"]).strftime("%Y-%m-%d %H:%M"),
          players: row["players"].map { |player| GameRoomParticipants.display_name(player) }.join(", ") }
      }, _("Saved games"))
      return if selected == nil
      row = rows[selected]
      operation = select_saved_game_item([_("Resume game"), _("Information"), _("Delete saved game")], game_name(row["game"]))
      case operation
      when 0
        table = create_saved_game_table(row)
        if table != nil
          show_table_screen(table)
          return
        end
      when 1
        game = game_definition(row["game"])
        saved_games.validate(row, game: game)
        speak(game.table_options_announcement(game.options_from_json(row["options"]))) if game != nil
      when 2
        saved_games.delete(row["id"]) if confirm(_("Delete this saved game?"))
      end
    end
  rescue ArgumentError, IOError, SystemCallError
    alert(_("The saved game storage is damaged or incompatible."))
  end

  def select_saved_game_item(labels, header)
    list = ListBox.new(labels, header: header, quiet: true)
    open = Button.new(_("Open"))
    back = Button.new(_("Back"))
    form = GameRoomUI::Form.new([list, open, back], program: self, quiet: true)
    selected = nil
    form.accept_button = open
    form.cancel_button = back
    form.hide(open)
    form.hide(back)
    open.on(:press) { selected = list.index.to_i; form.resume }
    back.on(:press) { form.resume }
    form.wait
    selected
  end

  def create_saved_game_table(saved)
    game = game_definition(saved["game"])
    saved_games.validate(saved, game: game)
    checked = run_network_task(_("Checking the current table"), ui: :none) { [@lobby.current_table_for(Session.name)] }
    return nil if checked == nil
    current = checked.first
    if current != nil
      if current["resume_save_id"] == saved["id"]
        return current
      end
      alert(_("You are already at another table."))
      return nil
    end
    row = run_network_task(_("Preparing saved game")) do
      created = @lobby.create_table(name: saved["table_name"], game: saved["game"], owner: Session.name,
        game_options: saved["options"], private_table: saved["private"], resume_save_id: saved["id"],
        bot_count: saved["players"].count { |player| GameRoomParticipants.bot?(player) },
        bot_names: saved["players"].select { |player| GameRoomParticipants.bot?(player) }.map { |player| GameRoomParticipants.bot_name_token(player) })
      activate_table_transport(created.table)
      created.table
    end
    return nil if row == nil

    saved["players"].each do |player|
      next if GameRoomParticipants.bot?(player) || GameRoomParticipants.same?(player, Session.name)
      run_network_task(_("Sending invitation"), ui: :none) { deliver_table_invitation(row, player, continuation: true) }
    end
    speak(_("The table is waiting for the original players. Start the game when everyone has joined."))
    row
  rescue ArgumentError => error
    Log.warning("ELTEN Game Room cannot restore saved game: #{error.message}") if defined?(Log)
    alert(_("This saved game is not compatible with this version or is damaged."))
    nil
  end

  def resume_saved_game_at_table(row, state)
    saved = saved_games.list.find { |item| item["id"] == row["resume_save_id"] }
    if saved == nil
      alert(_("The local saved game is no longer available."))
      return nil
    end
    game = state.game
    saved_games.validate(saved, game: game)
    restoration = saved_games.restored_data(saved, game: game, table_id: @lobby.table_id(row))
    missing = restoration[:players].reject { |player| GameRoomParticipants.includes?(state.room.game_participants, player) }
    unless missing.empty?
      alert(_("Waiting for these players: %{players}.") % { players: missing.map { |player| GameRoomParticipants.display_name(player) }.join(", ") })
      return nil
    end
    run_network_task(_("Resuming game")) do
      started = @games.restore_session(table: row, game: game.id, players: restoration[:players], options: saved["options"], restore: restoration)
      @lobby.set_game_active(row, true) if started != nil
      started
    end
  rescue ArgumentError, IOError, SystemCallError => error
    Log.warning("ELTEN Game Room restore failed: #{error.class}") if defined?(Log)
    alert(_("This saved game is not compatible with this version or is damaged."))
    nil
  end

  def show_join_table
    selected_index = 0
    loop do
      snapshots = run_network_task(_("Loading available tables")) do
        @lobby.open_table_snapshots
      end
      return if snapshots == nil
      if snapshots.empty?
        alert(_("There are no open tables."))
        return
      end

      game_ids = ordered_game_ids(snapshots)
      selected_index = [selected_index, game_ids.length - 1].min
      action = nil
      games = ListBox.new(
        game_ids.map { |game_id| game_lobby_label(game_id) },
        header: _("Join a table"),
        index: selected_index,
        quiet: true
      )
      open_button = Button.new(_("Open"))
      back_button = Button.new(_("Back"))
      form = GameRoomUI::Form.new([games, open_button, back_button], program: self, quiet: true)
      form.accept_button = open_button
      form.cancel_button = back_button
      form.hide(open_button)
      form.hide(back_button)
      open_button.on(:press) do
        selected_index = games.index.to_i
        action = :open
        form.resume
      end
      back_button.on(:press) do
        action = :back
        form.resume
      end

      form.wait
      return if action != :open
      entered = show_tables_for_game(game_ids[selected_index])
      return if entered == true
    end
  end

  def show_tables_for_game(game_id)
    selected_index = 0
    loop do
      snapshots = run_network_task(_("Loading tables")) do
        @lobby.open_table_snapshots(game: game_id)
      end
      return false if snapshots == nil
      if snapshots.empty?
        alert(_("There are no open tables for this game."))
        return false
      end

      selected_index = [selected_index, snapshots.length - 1].min
      action = nil
      tables = ListBox.new(
        snapshots.map { |snapshot| table_join_label(snapshot) },
        header: game_name(game_id),
        index: selected_index,
        quiet: true
      )
      join_button = Button.new(_("Join"))
      back_button = Button.new(_("Back"))
      form = GameRoomUI::Form.new([tables, join_button, back_button], program: self, quiet: true)
      form.accept_button = join_button
      form.cancel_button = back_button
      form.hide(join_button)
      form.hide(back_button)
      join_button.on(:press) do
        # The settings reader below uses the same selected snapshot as Join.
        selected_index = tables.index.to_i
        action = :join
        form.resume
      end
      back_button.on(:press) do
        action = :back
        form.resume
      end

      form.bind_context do |menu|
        menu.option(_("Read the table variant and settings"), nil, "r") do
          announce_table_options(game, snapshots[tables.index.to_i]&.table)
        end
      end
      GameRoomContextHelp.replace([tables], [_("Press %{key} for %{action}.") % {
        key: "Ctrl+R", action: _("Read the table variant and settings")
      }])
      form.wait
      return false if action != :join

      result = join_table_snapshot(snapshots[selected_index])
      return false if result == nil
      if result == :transport_failed
        alert(_("The real-time connection to this table could not be established. Please try again."))
        next
      end

      case result.status
      when :joined, :already_here
        announce_joined_room(result.table) if result.status == :joined
        show_table_screen(result.table)
        return true
      when :already_at_another_table
        alert(_("You are already at another table."))
        show_table_screen(result.table)
        return true
      when :full
        alert(_("This table is full."))
      when :closed
        self.class.cancel_new_table_notice(row)
        alert(_("This table is no longer available."))
      end
    end
  end

  def join_table_snapshot(snapshot)
    return nil if snapshot == nil

    run_network_task(_("Joining table")) do
      selected_table = snapshot.table
      pending_invitations = pending_invitations_for_table(selected_table)
      connected = establish_table_transport(selected_table, bootstrap: true)
      next :transport_failed if !connected

      joined = @lobby.join_table(selected_table, Session.name, announce: false)
      if joined&.entered?
        @lobby.announce_table_joined(joined.table, joined.members, actor: Session.name) if joined.status == :joined
        complete_joined_table_invitations(joined.table, pending_invitations)
      else
        @transport.deactivate_table(table_id: @lobby.table_id(selected_table))
      end
      joined
    end
  end

  def pending_invitations_for_table(row)
    return [] if row == nil

    @invitations.pending_for(Session.name, tables: [row]).select do |invitation|
      invitation.table_id == @lobby.table_id(row)
    end
  rescue StandardError => error
    Log.warning("ELTEN Game Room joined-table invitation lookup failed: #{error.class}: #{error.message}") if defined?(Log)
    []
  end

  def complete_joined_table_invitations(row, invitations)
    self.class.table_watch_receiver.resolve(row["__live_session_id"])
    invitations.to_a.each do |invitation|
      begin
        @invitations.respond(invitation, recipient: Session.name, response: "accepted")
      rescue StandardError => error
        Log.warning("ELTEN Game Room joined-table invitation response failed: #{error.class}: #{error.message}") if defined?(Log)
      end
    end
    revoke_table_invitation_notifications(@lobby.table_id(row), live_session_id: row["__live_session_id"])
  end

  def select_game(header, game_ids)
    selected_index = 0
    action = nil
    games = ListBox.new(
      game_ids.map { |game_id| game_name(game_id) },
      header: header,
      index: selected_index,
      quiet: true
    )
    select_button = Button.new(_("Select"))
    back_button = Button.new(_("Back"))
    form = GameRoomUI::Form.new([games, select_button, back_button], program: self, quiet: true)
    form.accept_button = select_button
    form.cancel_button = back_button
    form.hide(select_button)
    form.hide(back_button)
    select_button.on(:press) do
      selected_index = games.index.to_i
      action = :select
      form.resume
    end
    back_button.on(:press) { form.resume }

    form.wait
    action == :select ? game_ids[selected_index] : nil
  end

  # Creation returns table privacy separately from game rules; ordinary
  # editing (Ctrl+X) keeps its existing options-only result and controls.
  def configure_game_options(game, initial_options: nil, submit_label: nil, creating_table: false)
    return creating_table ? nil : {} if game == nil

    selected = initial_options == nil ? {} : game.normalize_options(initial_options)
    definitions = game.effective_option_definitions(selected).to_a
    return game.default_options if definitions.empty? && !creating_table
    built_language = selected.fetch(GameRoomContent::LANGUAGE_OPTION_KEY, game.default_options[GameRoomContent::LANGUAGE_OPTION_KEY]).to_s
    private_table = false

    loop do
      controls = [Static.new(_("Choose game options using Tab and the arrow keys. In lists allowing multiple selections, use Space to select or clear an item."))]
      privacy_control = nil
      if creating_table
        privacy_control = CheckBox.new(GameRoomContent.utf8(_("Private table")), checked: private_table)
        controls << privacy_control
      end
      bindings = []
      defaults = remembered_game_option_defaults(game, definitions).merge(selected)
      definitions.each do |definition|
        key = definition.key.to_s
        case definition.kind.to_s
        when "boolean"
          control = CheckBox.new(
            definition.label.to_s,
            checked: defaults[key] == true
          )
          controls << control
          bindings << [definition, control]
        when "choice"
          choices = definition.choices.to_a
          default_index = choices.index do |choice|
            choice.value.to_s == defaults[key].to_s
          end.to_i
          control = ListBox.new(
            choices.map { |choice| choice.label.to_s },
            header: definition.label.to_s,
            index: default_index,
            quiet: true
          )
          controls << control
          bindings << [definition, control]
        when "multiple_choice"
          choices = definition.choices.to_a
          control = ListBox.new(
            choices.map { |choice| choice.label.to_s },
            header: definition.label.to_s,
            index: 0,
            flags: ListBox::Flags::MultiSelection,
            quiet: true
          )
          mask = defaults[key].to_i
          control.select_multiselection_indices(
            choices.each_index.select { |index| (mask & (1 << index)) != 0 }
          )
          controls << control
          bindings << [definition, control]
        when "integer"
          control = EditBox.new(
            definition.label.to_s,
            type: EditBox::Flags::Numbers,
            text: defaults[key].to_i.to_s,
            quiet: true
          )
          control.select_all if !control.text.to_s.empty?
          controls << control
          bindings << [definition, control]
        else
          raise ArgumentError, "Unsupported game option type: #{definition.kind}"
        end
      end

      action = nil
      save_button = Button.new(submit_label || _("Create table"))
      cancel_button = Button.new(_("Cancel"))
      form = GameRoomUI::Form.new(controls + [save_button, cancel_button], program: self, index: creating_table ? 1 : 0, quiet: true)
      form.accept_button = save_button
      form.cancel_button = cancel_button
      previous_options = game.normalize_options(game_option_values(bindings))
      refresh_visibility = lambda do
        values = game.normalize_options(game_option_values(bindings))
        game.option_editor_changes(previous_options, values).each do |key, value|
          binding = bindings.find { |definition, _control| definition.key.to_s == key.to_s }
          binding[1].text = value.to_s if binding && binding[0].kind.to_s == "integer"
        end
        values = game.normalize_options(game_option_values(bindings))
        previous_options = values
        bindings.each do |definition, control|
          if game.option_visible?(definition, values)
            form.show(control)
          else
            form.hide(control)
          end
        end
      end
      bindings.each do |definition, control|
        event = definition.kind.to_s == "boolean" ? :change : :move
        control.on(event) { refresh_visibility.call } if ["boolean", "choice"].include?(definition.kind.to_s)
      end
      refresh_visibility.call
      save_button.on(:press) do
        action = :save
        form.resume
      end
      cancel_button.on(:press) do
        action = :cancel
        form.resume
      end
      language_binding = bindings.find do |definition, _control|
        definition.key.to_s == GameRoomContent::LANGUAGE_OPTION_KEY
      end
      if language_binding != nil
        language_binding[1].on(:move) do
          # Replace only the dependent choices. Recreating the form here
          # steals focus (and speech) from the language being browsed.
          options = game.normalize_options(game_option_values(bindings))
          definitions = game.effective_option_definitions(options).to_a
          set_binding = bindings.find { |definition, _control| definition.key.to_s == GameRoomContent::SET_OPTION_KEY }
          set_definition = definitions.find { |definition| definition.key.to_s == GameRoomContent::SET_OPTION_KEY }
          if set_binding && set_definition
            control = set_binding[1]
            set_binding[0] = set_definition
            control.options = set_definition.choices.map { |choice| choice.label.to_s }
            control.index = set_definition.choices.index { |choice| choice.value.to_s == options[GameRoomContent::SET_OPTION_KEY].to_s }.to_i
          end
          built_language = options[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
          refresh_visibility.call
        end
      end
      form.wait
      return nil if action != :save

      private_table = privacy_control.checked == true if creating_table
      raw = game_option_values(bindings)
      options = game.normalize_options(raw)
      chosen_language = options[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
      if chosen_language != built_language
        selected = options
        built_language = chosen_language
        definitions = game.effective_option_definitions(selected).to_a
        next
      end
      error = game.validation_error(options)
      if error == nil
        remember_multiple_choice_options(game, definitions, options) if initial_options == nil
        return creating_table ? { game_options: options, private_table: private_table } : options
      end

      alert(error)
    end
  end

  def game_option_values(bindings)
    bindings.each_with_object({}) do |(definition, control), raw|
      key = definition.key.to_s
      raw[key] = if definition.kind.to_s == "boolean"
        control.checked == true
      elsif definition.kind.to_s == "integer"
        control.text.to_s
      elsif definition.kind.to_s == "multiple_choice"
        choices = definition.choices.to_a
        control.multiselections.filter_map { |index| choices[index]&.value }
      else
        choices = definition.choices.to_a
        selected = choices[control.index.to_i]
        selected == nil ? definition.default : selected.value
      end
    end
  end

  def remembered_game_option_defaults(game, definitions)
    defaults = game.default_options.dup
    preferences = read_json("game_option_preferences.json", default: {})
    stored = preferences.is_a?(Hash) ? preferences[game.id.to_s] : nil
    return defaults if !stored.is_a?(Hash)

    definitions.each do |definition|
      next if definition.kind.to_s != "multiple_choice" && game.id.to_s != "makao"
      next if game.id.to_s == "makao" && definition.key.to_s == "profile"

      key = definition.key.to_s
      defaults[key] = stored[key] if stored.key?(key)
    end
    defaults
  rescue StandardError => error
    Log.warning("ELTEN Game Room could not read option preferences: #{error.class}: #{error.message}") if defined?(Log)
    game.default_options
  end

  def remember_multiple_choice_options(game, definitions, options)
    remembered = if game.id.to_s == "makao" && options["profile"].to_s == "custom"
      definitions.reject { |definition| definition.key.to_s == "profile" }
    else
      definitions.select { |definition| definition.kind.to_s == "multiple_choice" }
    end
    return if remembered.empty?

    update_json("game_option_preferences.json", default: {}) do |root|
      root = {} if !root.is_a?(Hash)
      stored = root[game.id.to_s]
      stored = {} if !stored.is_a?(Hash)
      remembered.each do |definition|
        key = definition.key.to_s
        stored[key] = options[key]
      end
      root[game.id.to_s] = stored
      root
    end
  rescue StandardError => error
    Log.warning("ELTEN Game Room could not save option preferences: #{error.class}: #{error.message}") if defined?(Log)
  end

  def show_table_screen(row)
    return if row == nil

    @table_layouts ||= {}
    table_id = @lobby.table_id(row)
    layout = nil
    last_room_state = nil
    quiet_reentry = false
    synchronizer = GameRoomSync::Controller.new(
      transport: @transport, table_id: table_id,
      reconnect: -> { activate_table_transport(row) }
    )
    loop do
      state = load_room_state(
        row, title: _("Updating table"), synchronizer: synchronizer,
        ui: layout&.focus_location.to_a[0] == :chat ? layout.chat : :none
      )
      if state == :unavailable
        if last_room_state == nil
          event = GameScreen.wait_for_connection(synchronizer, program: self)
          return if event == nil || event.kind == :closed
          next
        end
        state = last_room_state
      end
      return if state == nil
      last_room_state = state

      snapshot = state.room
      row = snapshot.table
      owner = @lobby.owner_of(row)
      own_table = GameRoomParticipants.same?(owner, Session.name)
      play_game_sounds(room_membership_tracker(row).observe(snapshot.members))
      activity_cursor = announce_new_table_activity(state.activity_entries, after_id: layout&.activity_cursor)
      synchronizer.update_session(state.session_id(@games))
      view_spec = if !state.waiting? && state.replay != nil && state.game != nil
        state.game.game_view_spec(state.replay, Session.name)
      else
        GameRoomLayout::ViewSpec.new(history_empty_label: _("No games have been played yet"))
      end
      options = {
        view_spec: view_spec, history_items: room_history_items(state, state.activity_entries),
        user_items: room_user_rows(state), users_header: table_header(snapshot),
        phase: state.phase, own_table: own_table
      }
      if layout == nil
        layout = GameRoomLayout::Screen.new(**options)
        layout.form.game_room_program = self
        @table_layouts[table_id] = layout
      else
        layout.update(**options)
      end
      layout.activity_cursor = activity_cursor
      layout.primary_button.label = _("Resume game") if own_table && state.session == nil && !row["resume_save_id"].to_s.empty?
      if state.active? || state.finished?
        result = run_game_screen(state.session, state.game, table: row)
        if result == :room_closed
          forget_room_membership(row)
          return
        end
        return if result == :saved
        start_new_game(row) if result == :restart
        return if result == :back && leave_table_from_screen(row)

        quiet_reentry = true
        next
      end

      layout.begin_bindings
      layout.back_button.label = _("Leave")
      form = layout.form
      action = nil
      participant = nil
      dispatch = lambda do |requested, selected = nil|
        next if action != nil

        action = requested
        participant = selected
        form.resume
      end
      layout.primary_button.on(:press) { dispatch.call(:start_game) }
      layout.back_button.on(:press) { dispatch.call(:leave) }
      layout.chat.on_submit do
        if layout.chat.text.to_s.strip.empty?
          alert(_("Type a chat message first."))
        else
          dispatch.call(:chat)
        end
      end
      GameRoomParticipantMenu.bind(layout, available: -> do
        [:invite_online, :invite_contacts, :rules, :leave] +
          GameRoomParticipantMenu.role_actions(room: snapshot, viewer: Session.name) +
          GameRoomParticipantMenu.lifecycle_actions(active: state.active?, viewer: Session.name, owner: owner,
            compatible: !legacy_table?(row),
            restoring: state.session == nil && !row["resume_save_id"].to_s.empty?,
            frozen: state.session.to_h["__frozen"] && !state.session.to_h["__aborted"]) +
          GameRoomParticipantMenu.management_actions(
            room: snapshot, game: state.game, active: state.active?, viewer: Session.name, owner: owner,
            restoring: state.session == nil && !row["resume_save_id"].to_s.empty?
          )
      end, read_options: -> { announce_table_options(state.game, row) }, &dispatch)
      form.add_timer(FormTimer.new(GameScreen::TIMER_INTERVAL, repeat: true) do
        next if action != nil

        event = synchronizer.next_event
        next if event == nil

        action = event.kind == :closed ? :closed : :refresh
        form.resume_for_refresh
      end)
      quiet_reentry ? layout.wait_without_announcement : form.wait
      layout.begin_bindings
      quiet_reentry = false
      case action
      when :closed
        forget_room_membership(row)
        return
      when :start_game
        start_new_game(row)
        quiet_reentry = true
      when :edit_options
        change_table_game_options(row)
        quiet_reentry = true
      when :add_bot, :remove_bot
        change_room_computer(row, action, participant)
        quiet_reentry = true
      when :observe_next_game, :play_next_game
        change_observer_mode(row, action)
        quiet_reentry = true
      when :rules
        show_game_rules(state.game, options: state.game&.options_from_json(row["game_options"]))
      when :invite_online
        show_invite_users(row, source: :online)
      when :invite_contacts
        show_invite_users(row, source: :contacts)
      when :chat
        entry = run_network_task(_("Sending chat message"), ui: :none) do
          saved = @table_activity.append(table: row, kind: "chat", message: layout.chat.text)
          @lobby.announce_table_activity(row, snapshot.members, actor: Session.name) if saved != nil
          saved
        end
        if entry != nil
          play_game_sound("chatmsg")
          text = @table_activity.text_for(entry, game_name: ->(id) { game_name(id) }, global: false)
          speak(text, stop: false, break_sequence: false) if !text.to_s.empty?
          layout.chat.set_text("")
          layout.chat.index = layout.chat.check = 0
        end
        quiet_reentry = true
      when :leave
        return if leave_table_from_screen(row)
      when :refresh
        quiet_reentry = true
      end
    end
  ensure
    layout&.begin_bindings
    @table_layouts&.delete(table_id) if table_id != nil
  end

  def leave_table_from_screen(row)
    own_table = GameRoomParticipants.same?(@lobby.owner_of(row), Session.name)
    question = own_table ? _("Do you want to leave the table? The table will be closed for everyone.") : _("Do you want to leave the table?")
    return false if !confirm(question)

    result = run_network_task(_("Leaving table")) do
      left = @lobby.leave_table(row, Session.name)
      @transport.deactivate_table(table_id: @lobby.table_id(row)) if left != nil
      left
    end
    return false if result == nil

    self.class.cancel_new_table_notice(row)
    play_game_sound("disconnect")
    forget_room_membership(row)
    true
  end

  def change_room_computer(row, action, participant)
    state = load_room_state(row, title: _("Checking the table members"))
    return if state == nil

    available = GameRoomParticipantMenu.management_actions(
      room: state.room, game: state.game, active: state.active?,
      viewer: Session.name, owner: @lobby.owner_of(state.room.table),
      restoring: state.session == nil && !state.room.table["resume_save_id"].to_s.empty?
    )
    return if !available.include?(action)
    return if action == :remove_bot && !GameRoomParticipants.includes?(state.room.bots, participant)

    result = run_network_task(action == :add_bot ? _("Adding computer") : _("Removing computer")) do
      if action == :add_bot
        @lobby.add_bot(row, snapshot: state.room)
      else
        @lobby.remove_bot(row, snapshot: state.room, participant: participant)
      end
    end
    status = result.respond_to?(:status) ? result.status : result
    alert(_("This table is full.")) if status == :full
    alert(_("This table is no longer available.")) if status == :closed
    alert(_("Create a new table to add named computers.")) if status == :old_room
    result
  end

  def change_observer_mode(row, action)
    observing = action == :observe_next_game
    title = observing ? _("Enabling observer mode") : _("Enabling player mode")
    snapshot = run_network_task(title, ui: :none) do
      @lobby.set_observer(row, Session.name, observing)
    end
    return nil if snapshot == nil

    message = observing ? _("You will observe the next game.") : _("You will play in the next game.")
    speak(message, stop: false, break_sequence: false)
    snapshot
  end

  def show_invite_users(row, source:)
    return if !invitation_sending_available?

    payload = run_network_task(_("Loading users")) do
      snapshot = @lobby.snapshot_for(row)
      next nil if snapshot == nil

      client = EltenLink::Client.new
      users = if source == :contacts
        contacts = EltenLink::Contacts.list(client)
        online = EltenLink::Users.online(client).each_with_object({}) do |user, result|
          result[user.to_s.strip.downcase] = true
        end
        contacts.select { |user| online.key?(user.to_s.strip.downcase) }
      else
        EltenLink::Users.online(client)
      end
      participants = snapshot.participants
      candidates = @game_room_users.registered(users).reject do |user|
        user.to_s.casecmp(Session.name.to_s) == 0 ||
          participants.any? { |participant| participant.to_s.casecmp(user.to_s) == 0 }
      end
      [snapshot, candidates]
    end
    return if payload == nil

    snapshot, candidates = payload
    if candidates.empty?
      message = source == :contacts ? _("There are no online contacts available to invite.") : _("There are no online users available to invite.")
      alert(message)
      return
    end

    selected = select_invitation_recipient(
      candidates,
      source == :contacts ? _("Invite from contacts") : _("Invite an online user")
    )
    return if selected == nil

    result = run_network_task(_("Sending invitation"), ui: :none) do
      current = @lobby.snapshot_for(snapshot.table)
      next :closed if current == nil
      next :not_at_table if !current.participants.any? { |participant| participant.to_s.casecmp(Session.name.to_s) == 0 }
      next :already_here if current.participants.any? { |participant| participant.to_s.casecmp(selected.to_s) == 0 }

      created = deliver_table_invitation(current.table, selected)
      next :failed if created == nil
      next :duplicate if !created.created?

      :sent
    end

    case result
    when :sent
      true # The room activity announces the invitation once.
    when :failed
      alert(_("The operation could not be completed. Please try again."))
    when :duplicate
      alert(_("An invitation to this table is already pending for this user."))
    when :already_here
      alert(_("This user is already at the table."))
    when :closed, :not_at_table
      alert(_("This table is no longer available."))
    end
  end

  def select_invitation_recipient(users, header)
    action = nil
    selected_index = 0
    list = ListBox.new(users, header: header, index: selected_index, quiet: true)
    invite_button = Button.new(_("Invite"))
    back_button = Button.new(_("Back"))
    form = GameRoomUI::Form.new([list, invite_button, back_button], program: self, quiet: true)
    form.accept_button = invite_button
    form.cancel_button = back_button
    form.hide(invite_button)
    form.hide(back_button)
    invite_button.on(:press) do
      selected_index = list.index.to_i
      action = :invite
      form.resume
    end
    back_button.on(:press) { form.resume }
    form.wait
    action == :invite ? users[selected_index] : nil
  end

  def deliver_invitation_response(invitation, response)
    send_notification(invitation["sender"], type: "game_room.invitation_resolved", metadata: {
      "invitation_id" => invitation_row_id(invitation), "table_id" => invitation["table_id"],
      "live_session_id" => invitation["live_session_id"],
      "user" => Session.name.to_s, "response" => response
    }, expires_in: 300)
  rescue StandardError => error
    Log.warning("ELTEN Game Room invitation response notification failed: #{error.class}") if defined?(Log)
  end

  def deliver_table_invitation(table, recipient, continuation: false)
    result = @invitations.deliver(table: table, sender: Session.name, recipient: recipient) do |invitation|
      invitation["__history_writer"] = GameRoomInvitationReceipts::HistoryWriter.new(
        repository: @table_activity, table: table, invitation: invitation)
      metadata = invitation_metadata(table, invitation_row_id(invitation))
      metadata["continuation"] = true if continuation
      if table["private"] == true
        delivered = @transport.invite_user(table_id: @lobby.table_id(table), user: recipient, metadata: metadata)
        next false if !delivered
        expiry = delivered.is_a?(Hash) ? (delivered["expires_at"] || delivered.dig("invitation", "expires_at")).to_i : 0
        raise GameRoomNetworkErrors::UnsupportedInvitation, "The server did not provide the private invitation expiration" if expiry <= Time.now.to_i
        invitation["expires_at"] = [invitation["expires_at"], expiry].min
        metadata["expires_at"] = invitation["expires_at"]
      end
      send_notification(recipient, type: "game_room.invitation", metadata: metadata,
        expires_in: [metadata["expires_at"].to_i - Time.now.to_i, 1].max)
      true
    end
    # Delivery succeeded: a later history failure must not release the duplicate
    # lock or claim that an already-delivered invitation was not sent.
    if result&.created?
      begin
        result.invitation["__history_writer"].record("invited")
      rescue StandardError => error
        GameRoomInvitationReceipts.retry_history(self.class, result.invitation["__history_writer"]) if GameRoomNetworkErrors.transient?(error)
        Log.warning("ELTEN Game Room invitation activity failed: #{error.class}") if defined?(Log)
      end
    end
    result
  end

  def show_pending_invitations(preferred_id: nil, mode: :accept)
    choices = load_pending_invitations
    return nil if choices == nil
    if choices.empty?
      alert(_("There are no pending invitations."))
      return nil
    end

    selected = if preferred_id.to_i > 0
      choices.find { |choice| choice[:invitation].id == preferred_id.to_i }
    elsif choices.length == 1
      choices.first
    else
      select_pending_invitation(choices, mode: mode)
    end
    if selected == nil && preferred_id.to_i > 0
      alert(_("This invitation is no longer available."))
      return nil
    end
    return nil if selected == nil

    if mode == :reject
      reject_pending_invitation(selected[:invitation])
      nil
    else
      accept_pending_invitation(selected[:invitation])
    end
  end

  def load_pending_invitations
    run_network_task(_("Loading invitations")) do
      tables = @transport.discover_rooms(include_private: true)
      snapshots = tables.map { |table| @lobby.snapshot_for(table) || LobbyRepository::TableSnapshot.new(table: table, members: [@lobby.owner_of(table)], bots: @lobby.bots_for(table)) }
      by_id = snapshots.to_h { |snapshot| [@lobby.table_id(snapshot.table), snapshot] }
      pending = @invitations.pending_for(
        Session.name,
        tables: snapshots.map(&:table)
      )
      pending.filter_map do |invitation|
        snapshot = by_id[invitation.table_id]
        next nil if snapshot == nil
        { invitation: invitation, snapshot: snapshot }
      end
    end
  end

  def select_pending_invitation(choices, mode: :accept)
    action = nil
    selected_index = 0
    invitations = ListBox.new(
      choices.map { |choice| pending_invitation_label(choice) },
      header: _("Invitations"),
      index: selected_index,
      quiet: true
    )
    join_button = Button.new(mode == :reject ? _("Reject") : _("Accept"))
    back_button = Button.new(_("Back"))
    form = GameRoomUI::Form.new([invitations, join_button, back_button], program: self, quiet: true)
    form.accept_button = join_button
    form.cancel_button = back_button
    form.hide(join_button)
    form.hide(back_button)
    join_button.on(:press) do
      selected_index = invitations.index.to_i
      action = mode
      form.resume
    end
    back_button.on(:press) { form.resume }
    form.wait
    [:accept, :reject].include?(action) ? choices[selected_index] : nil
  end

  def pending_invitation_label(choice)
    invitation = choice[:invitation]
    snapshot = choice[:snapshot]
    _("%{game}; %{table}; invited by %{sender}; %{count}/%{maximum}") % {
      game: game_name(snapshot.table["game"]),
      table: snapshot.table["name"].to_s,
      sender: invitation.sender,
      count: snapshot.participant_count,
      maximum: @lobby.capacity_of(snapshot.table)
    }
  end

  def accept_pending_invitation(invitation, notification_id: nil)
    if invitation.expires_at <= Time.now.to_i
      revoke_invitation_notification(invitation.id, notification_id: notification_id)
      alert(_("This invitation has expired."))
      return nil
    end
    payload = run_network_task(_("Checking invitation")) do
      tables = @transport.discover_rooms(include_private: true)
      snapshots = tables.map { |table| @lobby.snapshot_for(table) || LobbyRepository::TableSnapshot.new(table: table, members: [@lobby.owner_of(table)], bots: @lobby.bots_for(table)) }
      current_invitation = @invitations.pending_by_id(
        invitation.id,
        Session.name,
        tables: snapshots.map(&:table)
      )
      snapshot = snapshots.find { |item| @lobby.table_id(item.table) == invitation.table_id }
      current = @lobby.current_table_for(Session.name)
      [current_invitation, snapshot, current]
    end
    return nil if payload == nil

    current_invitation, snapshot, current = payload
    if invitation.expires_at <= Time.now.to_i
      revoke_invitation_notification(invitation.id, notification_id: notification_id)
      alert(_("This invitation has expired."))
      return nil
    end
    if current_invitation == nil || snapshot == nil
      revoke_invitation_notification(invitation.id, notification_id: notification_id)
      alert(snapshot == nil ? _("This table is no longer available.") : _("This invitation is no longer available."))
      return nil
    end

    if snapshot.participant_count >= @lobby.capacity_of(snapshot.table) && (current == nil || @lobby.table_id(current) != invitation.table_id)
      alert(_("This table is full."))
      return nil
    end

    if current != nil && @lobby.table_id(current) == current_invitation.table_id
      connected = run_network_task(_("Accepting invitation")) do
        pending = pending_invitations_for_table(current_invitation.table)
        accepted = establish_table_transport(current_invitation.table)
        if accepted
          complete_joined_table_invitations(current_invitation.table, pending)
        end
        accepted
      end
      if connected
        alert(_("You are already at this table."))
      else
        alert(_("The real-time connection to this table could not be established. Please try again."))
      end
      return nil
    end

    if current != nil && !confirm(_("Do you want to leave your current table and join the invited table?"))
      return nil
    end

    left_current = false
    result = run_network_task(_("Accepting invitation")) do
      pending = pending_invitations_for_table(current_invitation.table)
      status = establish_invited_table_transport(current_invitation.table)
      if status == :full
        next :table_full
      elsif status == :closed
        revoke_invitation_notification(current_invitation.id, notification_id: notification_id)
        next :table_closed
      elsif ![:joined, :already_here].include?(status)
        next :transport_failed
      end

      if current != nil
        old_table_id = @lobby.table_id(current)
        @lobby.leave_table(current, Session.name)
        @transport.deactivate_table(table_id: old_table_id)
        left_current = true
      end

      joined = @lobby.join_table(current_invitation.table, Session.name, announce: false)
      if joined.entered?
        @lobby.announce_table_joined(joined.table, joined.members, actor: Session.name) if joined.status == :joined
        complete_joined_table_invitations(joined.table, pending)
      elsif joined.status == :closed
        @transport.deactivate_table(table_id: current_invitation.table_id)
        @invitations.respond(current_invitation, recipient: Session.name, response: "expired")
        revoke_invitation_notification(current_invitation.id, notification_id: notification_id)
      else
        @transport.deactivate_table(table_id: current_invitation.table_id)
      end
      joined
    end
    return nil if result == nil

    if left_current
      play_game_sound("disconnect")
      forget_room_membership(current)
    end

    if result == :transport_failed
      alert(_("The real-time connection to this table could not be established. Please try again."))
      return nil
    end
    if [:table_full, :table_closed].include?(result)
      alert(result == :table_full ? _("This table is full.") : _("This table is no longer available."))
      return nil
    end

    case result.status
    when :joined, :already_here
      announce_joined_room(result.table) if result.status == :joined
      result.table
    when :full
      alert(_("This table is full."))
      nil
    when :closed
      alert(_("This table is no longer available."))
      nil
    when :already_at_another_table
      alert(_("You are already at another table."))
      nil
    end
  end

  def reject_pending_invitation(invitation, notification_id: nil)
    result = run_network_task(_("Rejecting invitation")) do
      tables = @transport.discover_rooms(include_private: true)
      current_invitation = @invitations.pending_by_id(
        invitation.id,
        Session.name,
        tables: tables
      )
      next :unavailable if current_invitation == nil

      @transport.reject_discovered_invitation(current_invitation.table) if current_invitation.table["private"] == true
      @invitations.respond(current_invitation, recipient: Session.name, response: "rejected")
      revoke_invitation_notification(current_invitation.id, notification_id: notification_id)
      :rejected
    end

    case result
    when :rejected
      true
    when :unavailable
      revoke_invitation_notification(invitation.id, notification_id: notification_id)
      alert(_("This invitation is no longer available."))
      false
    else
      false
    end
  end

  def select_notification_invitation_action
    action = nil
    choices = [_("Accept invitation"), _("Reject invitation")]
    actions = ListBox.new(choices, header: _("Invitation"), index: 0, quiet: true)
    select_button = Button.new(_("Select"))
    back_button = Button.new(_("Back"))
    form = GameRoomUI::Form.new([actions, select_button, back_button], program: self, quiet: true)
    form.accept_button = select_button
    form.cancel_button = back_button
    form.hide(select_button)
    form.hide(back_button)
    select_button.on(:press) do
      action = actions.index.to_i == 0 ? :accept : :reject
      form.resume
    end
    back_button.on(:press) { form.resume }
    form.wait
    action
  end

  def revoke_invitation_notification(invitation_id, notification_id: nil)
    @invitation_notifications.revoke(invitation_id, notification_id: notification_id)
    true
  rescue StandardError => error
    Log.warning("ELTEN Game Room invitation notification cleanup failed: #{error.class}: #{error.message}") if defined?(Log)
    false
  end

  def revoke_table_invitation_notifications(table_id, live_session_id: nil)
    @invitation_notifications.revoke_for_table(table_id, live_session_id: live_session_id)
    true
  rescue StandardError => error
    Log.warning("ELTEN Game Room table invitation notification cleanup failed: #{error.class}: #{error.message}") if defined?(Log)
    false
  end

  def switch_to_invited_table
    row = show_pending_invitations
    throw(:game_room_table_switch, row) if row != nil
  end

  def announce_joined_room(row)
    play_game_sound("connect")
    speak(_("You joined %{player}'s room.") % {
      player: GameRoomParticipants.display_name(@lobby.owner_of(row))
    })
    # The waiting status is the first focused field for a guest. Queue it
    # after the room confirmation instead of letting it cut that message off.
    speech_wait
  end

  def invitation_metadata(row, invitation_id)
    {
      "kind" => "game_room_invitation",
      "invitation_id" => invitation_id,
      "table_id" => @lobby.table_id(row),
      "live_session_id" => row["__live_session_id"].to_s,
      "table_name" => row["name"].to_s,
      "game" => row["game"].to_s,
      "game_name" => game_name(row["game"]),
      "sender" => Session.name.to_s,
      "created_at" => Time.now.to_i,
      "expires_at" => Time.now.to_i + InvitationRepository::DEFAULT_TTL
    }
  end

  def invitation_row_id(row)
    (row["__id"] || row["id"]).to_i
  end

  def game_room_settings(reload: false)
    if reload || @game_room_settings == nil
      stored = read_json("settings.json", default: DEFAULT_SETTINGS.dup)
      @game_room_settings = GameRoomPreferences.normalize(stored, GAME_REGISTRY.ids)
    end
    @game_room_settings
  end

  def build_widget_control
    initialize_services
    return @widget_control if @widget_control
    @widget_control = GameRoomWidget::TableList.new(
      loader: -> { load_widget_table_snapshots },
      opener: ->(snapshot) { open_widget_table(snapshot) },
      labeler: ->(snapshot) { widget_table_label(snapshot) },
      id_for: ->(snapshot) { @lobby.table_id(snapshot.table) },
      foreground: ->(&operation) { run_network_task(_("Loading Game Room tables"), silent: true, &operation) },
      active: -> { widget_active? }
    )
    self.class.manage(@widget_control) if self.class.respond_to?(:manage)
    @widget_control
  end

  def widget_active?
    scene = @widget_host_scene
    return false if scene == nil || !$scene.equal?(scene)
    return false if defined?(EltenWindow) && (!EltenWindow.active_or_child? || EltenWindow.minimized?)
    # Source-inspected host method returns the current extension control. Do
    # not reach into a scene's instance variables or replace its main loop.
    scene.respond_to?(:program_main_tab_control) && scene.program_main_tab_control.equal?(@widget_control)
  rescue StandardError
    false
  end

  def load_widget_table_snapshots
    initialize_services
    settings = game_room_settings(reload: true)
    allowed_games = settings["widget_games"].to_a.map(&:to_s)
    show_unavailable = settings["widget_show_unavailable"] == true
    # Tab entry uses the original host task before native focus reads the
    # result. Five-second/R refreshes use the finite background worker instead.
    @transport.start
    snapshots = @lobby.open_table_snapshots
    return nil if snapshots == nil

    snapshots.select do |snapshot|
      allowed_games.include?(snapshot.table["game"].to_s) &&
        (show_unavailable || widget_table_available?(snapshot))
    end
  end

  def widget_table_available?(snapshot)
    row = snapshot.table
    return true if GameRoomParticipants.same?(@lobby.owner_of(row), Session.name)
    return true if snapshot.members.to_a.any? { |member| GameRoomParticipants.same?(member, Session.name) }

    discovered = row["__discovered_session"]
    !discovered.respond_to?(:can_join?) || discovered.can_join?
  end

  def widget_table_label(snapshot)
    row = snapshot.table
    label = _("%{game}, %{owner}") % {
      game: game_name(row["game"]),
      owner: GameRoomParticipants.display_name(@lobby.owner_of(row))
    }
    widget_table_available?(snapshot) ? label : _("%{table}, unavailable") % { table: label }
  end

  def open_widget_table(snapshot)
    initialize_services
    if @widget_program_prepared != true
      check_server_table_access
      run_network_task(_("Connecting to Elten"), silent: true) do
        @transport.start
        register_game_room_user
      end
      @widget_program_prepared = true
    end

    result = join_table_snapshot(snapshot)
    return if result == nil
    if result == :transport_failed
      alert(_("The real-time connection to this table could not be established. Please try again."))
      return
    end

    case result.status
    when :joined, :already_here
      announce_joined_room(result.table) if result.status == :joined
      show_table_screen(result.table)
    when :already_at_another_table
      alert(_("You are already at another table."))
      show_table_screen(result.table)
    when :full
      alert(_("This table is full."))
    when :closed
      alert(_("This table is no longer available."))
    end
  end

  def show_settings
    settings = game_room_settings(reload: true)
    watched = run_network_task(_("Loading notification settings")) { self.class.table_watch_repository.load(Session.name) }
    return if watched == nil
    self.class.table_watch_set_games(watched)
    settings = settings.merge("table_watch_games" => watched)
    games = GAME_REGISTRY.ids.map { |game_id| { id: game_id, name: game_name(game_id) } }
    updated = GameRoomScreens::Settings.new(settings, games: games, program: self).wait
    return if updated == nil

    if updated["table_watch_games"].to_a.sort != watched.sort
      saved = run_network_task(_("Saving notification settings")) do
        self.class.table_watch_repository.save(Session.name, updated["table_watch_games"])
      end
      return if saved == nil
      self.class.table_watch_set_games(saved)
    end
    updated = updated.reject { |key, _value| key == "table_watch_games" }

    normalized = GameRoomPreferences.normalize(updated, GAME_REGISTRY.ids)
    update_json("settings.json", default: DEFAULT_SETTINGS.dup) do |state|
      normalized.each { |key, value| state[key] = value }
      state
    end
    @game_room_settings = normalized
    Programs::Extensions.refresh_ui if defined?(Programs::Extensions) && Programs::Extensions.respond_to?(:refresh_ui)
    alert(_("Settings saved."))
  end

  def open_new_table_notification(notification)
    receiver = self.class.table_watch_receiver
    unless receiver.visible?(notification)
      alert(_("This table announcement has expired or is no longer available."))
      return true
    end
    initialize_services
    metadata = receiver.data(notification)
    rows = run_network_task(_("Checking table")) do
      @transport.start
      @lobby.open_table_snapshots(game: metadata["game"])
    end
    return true if rows == nil
    unless receiver.visible?(notification)
      alert(_("This table announcement has expired or is no longer available."))
      return true
    end
    snapshot = rows.find do |candidate|
      row = candidate.table
      row["__id"].to_i == metadata["table_id"] && row["__live_session_id"] == metadata["live_session_id"] &&
        row["owner"].to_s.casecmp?(notification.sender.to_s) && row["private"] != true &&
        row["status"].to_s == "waiting" && row["resume_save_id"].to_s.empty?
    end
    if snapshot
      open_widget_table(snapshot)
    else
      receiver.resolve(metadata["live_session_id"])
      alert(_("This table is no longer available."))
    end
    true
  end

  def run_network_task(title, ui: nil, silent: false, &operation)
    options = { title: title, cancellable: true, show_after: 5.0 }
    options[:ui] = ui if ui != nil
    result = EltenAPI::Tasks.run(**options) do |progress, token|
      token.raise_if_cancelled!
      operation.call
    end
    announce_server_table_access
    result
  rescue EltenAPI::Tasks::Cancelled
    nil
  rescue StandardError => error
    raise if !GameRoomNetworkErrors.expected?(error)

    Log.warning("ELTEN Game Room network operation failed: #{error.class}: #{error.message}")
    if @server_tables&.last_error.equal?(error)
      announce_server_table_access
    else
      alert(_("The operation could not be completed. Please try again.")) if !silent
    end
    nil
  end

  def register_game_room_user
    return if !@server_tables.available?

    @game_room_users.register(
      username: Session.name,
      version: GAME_ROOM_VERSION,
      build_id: GAME_ROOM_BUILD_ID,
      capabilities: GAME_ROOM_CAPABILITIES
    )
  rescue EltenLink::Error => error
    Log.warning("ELTEN Game Room user registration failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def activate_table_transport(row)
    return false if row == nil

    @transport.activate_table(
      table_id: @lobby.table_id(row),
      owner: @lobby.owner_of(row),
      capacity: @lobby.capacity_of(row),
      user: Session.name
    )
  end

  def establish_table_transport(row, invitation_id: nil, bootstrap: false)
    return false if row == nil

    @transport.establish_membership(
      table_id: @lobby.table_id(row),
      owner: @lobby.owner_of(row),
      capacity: @lobby.capacity_of(row),
      user: Session.name,
      invitation_id: invitation_id,
      bootstrap: bootstrap,
      table: row,
      timeout: 10.0
    )
  end

  def establish_invited_table_transport(row)
    @transport.establish_membership_status(table_id: @lobby.table_id(row), owner: @lobby.owner_of(row),
      capacity: @lobby.capacity_of(row), user: Session.name, table: row)
  end

  def missing_live_session_members(snapshot)
    connected = @transport.connected_users(@lobby.table_id(snapshot.table))
    return [] if connected == nil

    snapshot.members.reject do |member|
      connected.any? { |user| GameRoomParticipants.same?(user, member) }
    end
  end

  def ordered_game_ids(snapshots)
    available = snapshots.map { |snapshot| snapshot.table["game"].to_s }.uniq
    available.sort_by { |id| [GameRoomGames::Registry.sort_key(game_name(id)),id] }
  end

  def game_lobby_label(game_id)
    game_name(game_id)
  end

  def table_join_label(snapshot)
    GameRoomParticipants.display_name(@lobby.owner_of(snapshot.table))
  end

  def table_header(snapshot)
    row = snapshot.table
    label = _("Users at the table. %{status}; %{name}; %{game}; host: %{owner}; %{count}/%{maximum}") % {
      status: table_status_label(row),
      name: row["name"].to_s,
      game: game_name(row["game"]),
      owner: @lobby.owner_of(row),
      count: snapshot.participant_count,
      maximum: @lobby.capacity_of(row)
    }
    summary = game_options_summary(row)
    summary.empty? ? label : "#{label}; #{summary}"
  end

  def announce_table_options(game, row)
    return if game == nil || row == nil

    if row["game_options"].to_s.empty?
      speak(_("The settings of this table are not available."))
    else
      speak(game.table_options_announcement(game.options_from_json(row["game_options"])))
    end
  end

  def game_options_summary(row)
    game = game_definition(row["game"])
    return "" if game == nil

    game.combined_options_summary(game.options_from_json(row["game_options"]))
  end

  def room_history_items(state, room_activity = [])
    replay = state.replay
    game_events = replay == nil ? [] : replay.accepted_events
    @table_activity.merge_history(
      game_entries: state.history,
      game_events: game_events,
      activity_entries: room_activity,
      game_name: ->(id) { game_name(id) }
    )
  end

  def announce_new_table_activity(entries, after_id:)
    newest_id = entries.to_a.map(&:id).max.to_i
    return newest_id if after_id == nil

    entries.to_a.select { |entry| entry.id.to_i > after_id.to_i }.each do |entry|
      next if entry.kind == "chat" && GameRoomParticipants.same?(entry.actor, Session.name)

      play_game_sound("chatmsg") if entry.kind == "chat"
      text = @table_activity.text_for(entry, game_name: ->(id) { game_name(id) }, global: false)
      speak(text, stop: false, break_sequence: false) if !text.to_s.empty?
    end
    [after_id.to_i, newest_id].max
  end

  def room_history_header(state)
    return _("Current game history") if active_game?(state)
    return _("Last game history") if state.replay != nil

    _("Game history")
  end

  def room_user_rows(state)
    options = state.session == nil ? {} : state.game&.options_from_json(state.session["options"])
    RoomPresentation.game_users(
      room: state.room, game: state.game, replay: state.replay,
      players: state.players, owner: @lobby.owner_of(state.room.table), options: options
    )
  end

  def table_status_label(row)
    @lobby.playing?(row) ? _("game in progress") : _("open")
  end

  def room_players(state)
    state.players
  end

  def active_game?(state)
    state.active?
  end

  def start_new_game(row, state: nil)
    state ||= load_room_state(row, title: _("Checking the table before starting"))
    return if state == nil

    row = state.room.table
    owner = @lobby.owner_of(row)
    if !GameRoomParticipants.same?(owner, Session.name)
      alert(_("Only the table master may start a game."))
      return
    end
    if state.active?
      alert(_("A game has already started. Opening the current game."))
      return state.session
    end
    if legacy_table?(row)
      alert(_("To use the new game rules, create a table in Game Room 2.0. All players need version 2.0 or later."))
      return
    end

    return resume_saved_game_at_table(row, state) if state.session == nil && !row["resume_save_id"].to_s.empty?

    game = state.game || game_definition(row["game"])
    if game == nil
      alert(_("This game is not supported by this version of ELTEN Game Room."))
      return
    end

    participants = state.room.game_participants
    if !valid_player_count?(game, participants.length)
      alert(invalid_player_count_message(game, participants.length))
      return
    end

    options = game.new_game_options(game.options_from_json(row["game_options"]))
    options_error = game.validation_error(options, player_count: participants.length)
    if options_error != nil
      alert(options_error)
      return
    end

    options = configure_team_assignment(game, options, participants)
    return if options == nil

    refreshed_room = run_network_task(_("Checking the table members")) { @lobby.snapshot_for(row, force: true) }
    return if refreshed_room == nil
    if @lobby.playing?(refreshed_room.table)
      refreshed = load_room_state(refreshed_room.table, title: _("Opening the current game"))
      return if refreshed == nil || !refreshed.active?

      alert(_("A game has already started. Opening the current game."))
      return refreshed.session
    end
    latest_participants = refreshed_room.game_participants
    if !same_participant_order?(participants, latest_participants)
      alert(_("The users at the table changed while teams were being selected. Please start again."))
      return
    end
    missing_live_members = missing_live_session_members(refreshed_room)
    if !missing_live_members.empty?
      alert(
        _("The game cannot start until these players join the real-time session: %{players}.") % {
          players: missing_live_members.map { |player| GameRoomParticipants.display_name(player) }.join(", ")
        }
      )
      return
    end
    row = refreshed_room.table

    previous_id = state.session_id(@games)
    run_network_task(_("Starting game")) do
      started = @games.start_session(
        table: row,
        game: game.id,
        players: participants,
        options: JSON.generate(options),
        recipients: refreshed_room.members,
        expected_previous_session_id: previous_id
      )
      @lobby.set_game_active(row, true, snapshot: refreshed_room) if started != nil
      started
    end
  end

  def configure_team_assignment(game, options, participants)
    assignment = game.team_assignment(options, players: participants)
    return options if assignment == nil

    player_index = 0
    loop do
      player_index = [[player_index, 0].max, assignment.players.length - 1].min
      labels = assignment.players.each_with_index.map do |participant, index|
        _("%{player}, team %{team}") % {
          player: GameRoomParticipants.display_name(participant),
          team: assignment.seats[index] + 1
        }
      end
      players = ListBox.new(
        labels,
        header: _("Players and teams"),
        index: player_index,
        quiet: true
      )
      change_button = Button.new(_("Change team"))
      automatic_button = Button.new(_("Assign automatically"))
      start_button = Button.new(_("Start game"))
      cancel_button = Button.new(_("Cancel"))
      form = GameRoomUI::Form.new(
        [players, change_button, automatic_button, start_button, cancel_button],
        program: self,
        quiet: true
      )
      form.accept_button = change_button
      form.cancel_button = cancel_button
      action = nil
      change_button.on(:press) do
        player_index = players.index.to_i
        action = :change
        form.resume
      end
      automatic_button.on(:press) do
        player_index = players.index.to_i
        action = :automatic
        form.resume
      end
      start_button.on(:press) do
        error = assignment.validation_error
        if error == nil
          action = :start
          form.resume
        else
          alert(error)
        end
      end
      cancel_button.on(:press) do
        action = :cancel
        form.resume
      end
      form.wait

      case action
      when :change
        selected = choose_team(assignment, assignment.seats[player_index])
        assignment.assign(player_index, selected) if selected != nil
      when :automatic
        assignment.reset
      when :start
        return game.with_team_assignment(options, players: participants, seats: assignment.seats)
      when :cancel
        return nil
      end
    end
  end

  def choose_team(assignment, current)
    teams = ListBox.new(
      Array.new(assignment.team_count) { |index| _("Team %{team}") % { team: index + 1 } },
      header: _("Choose a team"),
      index: current.to_i,
      quiet: true
    )
    select_button = Button.new(_("Select"))
    cancel_button = Button.new(_("Cancel"))
    form = GameRoomUI::Form.new([teams, select_button, cancel_button], program: self, quiet: true)
    form.accept_button = select_button
    form.cancel_button = cancel_button
    selected = nil
    select_button.on(:press) do
      selected = teams.index.to_i
      form.resume
    end
    cancel_button.on(:press) { form.resume }
    form.wait
    selected
  end

  def same_participant_order?(first, second)
    left = GameRoomParticipants.unique(first)
    right = GameRoomParticipants.unique(second)
    left.length == right.length && left.each_with_index.all? do |participant, index|
      GameRoomParticipants.same?(participant, right[index])
    end
  end

  def load_room_state(row, title:, synchronizer: nil, ui: nil, force: false)
    return :unavailable if synchronizer != nil && synchronizer.waiting?

    payload = run_network_task(title, ui: ui) do
      operation = lambda do
        room = force ? @lobby.snapshot_for(row, force: true) : @lobby.snapshot_for(row)
        if room == nil
          [nil, nil, []]
        else
          session = force ? @games.session_for_table(room.table, force: true) : @games.session_for_table(room.table)
          [
            room,
            session == nil ? nil : @games.snapshot_for(session, force_events: force),
            @table_activity.entries_for(room.table, viewer: Session.name)
          ]
        end
      end
      synchronizer == nil ? operation.call : synchronizer.synchronize(&operation)
    end
    if payload == nil
      return nil if synchronizer == nil

      synchronizer.request_recovery!(delay: GameRoomSync::ERROR_BACKOFF) if !synchronizer.recovery_pending?
      return :unavailable
    end
    return nil if payload[0] == nil

    room, game_snapshot, activity_entries = payload
    game = game_snapshot == nil ? game_definition(room.table["game"]) : game_definition(game_snapshot.session["game"])
    replay = if game == nil || game_snapshot == nil
      nil
    else
      game.replay(game_snapshot.session, game_snapshot.events, @games)
    end
    players = game_snapshot == nil ? [] : @games.players_for(game_snapshot.session)
    GameRoomLifecycle::State.new(
      room: room,
      game_snapshot: game_snapshot,
      game: game,
      replay: replay,
      players: players,
      activity_entries: activity_entries
    )
  end

  def run_game_screen(session, game = nil, table:)
    self.class.cancel_new_table_notice(table)
    game ||= game_definition(session["game"])
    if game == nil
      alert(_("This game is not supported by this version of ELTEN Game Room."))
      return
    end

    options_error = game.validation_error(game.options_from_json(session["options"]))
    if options_error != nil
      alert(options_error)
      return
    end

    synchronizer = GameRoomSync::Controller.new(
      transport: @transport,
      table_id: @lobby.table_id(table),
      session_id: @games.session_id(session),
      reconnect: -> { activate_table_transport(table) }
    )
    synchronizer.update_session(@games.session_id(session), discard_pending: true)
    GameScreen.new(
      program: self,
      repository: @games,
      game: game,
      session: session,
      table: table,
      table_owner: @lobby.owner_of(table),
      room_snapshot_provider: -> { @lobby.snapshot_for(table) },
      synchronizer: synchronizer,
      invite_online: ->(current_table) { show_invite_users(current_table, source: :online) },
      invite_contacts: ->(current_table) { show_invite_users(current_table, source: :contacts) },
      membership_tracker: room_membership_tracker(table),
      game_status_changed: ->(current_table, active) { @lobby.set_game_active(current_table, active) },
      activity_repository: @table_activity,
      game_name: ->(id) { game_name(id) },
      send_chat: ->(current_table, message, users) do
        saved = @table_activity.append(table: current_table, kind: "chat", message: message)
        @lobby.announce_table_activity(current_table, users, actor: Session.name) if saved != nil
        saved
      end,
      layout: @table_layouts&.[](@lobby.table_id(table)),
      manage_computer: ->(current_table, action, participant) { change_room_computer(current_table, action, participant) },
      manage_observer: ->(current_table, action) { change_observer_mode(current_table, action) },
      edit_options: ->(current_table) { change_table_game_options(current_table) },
      abort_game: ->(current_table, current_session) { abort_current_game(current_table, current_session) },
      save_game: game.supports_saved_games? ? ->(current_table, current_session, current_game) { save_current_game(current_table, current_session, current_game) } : nil
    ).run
  end

  def change_table_game_options(table)
    state = load_room_state(table, title: _("Updating table"), force: true)
    return false unless editable_table_state?(state)
    previous = state.room.table["game_options"].to_s
    options = configure_game_options(state.game, initial_options: state.game.options_from_json(previous), submit_label: _("Save changes"))
    return false if options == nil
    current = load_room_state(table, title: _("Updating table"), force: true)
    unless editable_table_state?(current) && current.session_id(@games) == state.session_id(@games) &&
        current.room.table["game_options"].to_s == previous && same_participant_order?(state.room.participants, current.room.participants) &&
        same_participant_order?(state.room.game_participants, current.room.game_participants)
      alert(_("The table changed while you were editing. Open its settings again."))
      return false
    end
    count = current.room.game_participants.length
    # A waiting room need not yet have enough people to start. Once populated,
    # keep the game's participant-dependent restrictions (e.g. domino set size).
    count = nil if count < current.game.minimum_players
    error = current.game.validation_error(options, player_count: count)
    if error != nil
      alert(error)
      return false
    end
    result = run_network_task(_("Saving table settings")) do
      @transport.change_game_options(table: current.room.table, options: JSON.generate(options),
        expected_options: previous, expected_session_id: current.session_id(@games))
    end
    alert(_("The table changed while you were editing. Open its settings again.")) if result == false
    if result == true
      remember_multiple_choice_options(current.game, current.game.effective_option_definitions(options), options)
    end
    result == true
  end

  def editable_table_state?(state)
    state.is_a?(GameRoomLifecycle::State) && state.available? && !state.active? && state.game != nil &&
      !legacy_table?(state.room.table) &&
      GameRoomParticipants.same?(Session.name, @lobby.owner_of(state.room.table)) &&
      !(state.session == nil && !state.room.table["resume_save_id"].to_s.empty?) &&
      !(state.session.to_h["__frozen"] && !state.session.to_h["__aborted"])
  end

  def abort_current_game(table, session)
    return false if legacy_table?(table)
    return false unless confirm(_("End the current game for everyone? The table and chat will stay open, and no winner will be recorded."))
    state = load_room_state(table, title: _("Updating table"), force: true)
    return false unless state.is_a?(GameRoomLifecycle::State) &&
      GameRoomParticipants.same?(Session.name, @lobby.owner_of(state.room.table)) &&
      state.session_id(@games) == @games.session_id(session)
    return true if state.session.to_h["__aborted"]
    return false unless state.active? && !state.session.to_h["__frozen"]
    run_network_task(_("Ending game")) { @transport.abort_game(state.session) } == true
  end

  def legacy_table?(row)
    row.key?("__discovery_protocol") && row["__discovery_protocol"].to_i < GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL
  end

  def play_game_sound(name)
    GameRoomSounds.play(self, name)
  end

  def play_game_sounds(names)
    GameRoomSounds.play_all(self, names)
  end

  def game_room_sound_enabled?(name)
    GameRoomPreferences.sound_enabled?(game_room_settings, name, GAME_REGISTRY.ids)
  end

  def game_room_sound_volume(name)
    GameRoomPreferences.sound_volume(game_room_settings, name)
  end

  def adjust_game_room_volume(key, reader: nil, writer: nil)
    groups = GameRoomPreferences::SOUND_GROUPS
    @game_room_volume_group ||= 0
    levels = reader == nil ? GameRoomPreferences.sound_volumes(game_room_settings(reload: true)) : reader.call
    if key < 0
      @game_room_volume_group = (@game_room_volume_group + (key == -2 ? -1 : 1)) % groups.length
    else
      group = groups.fetch(@game_room_volume_group)
      level = [[levels.fetch(group) + (key == 2 ? -10 : 10), 0].max, 100].min
      if level != levels[group]
        if writer != nil
          writer.call(group, level)
        else
          update_json("settings.json", default: DEFAULT_SETTINGS.dup) do |state|
            # Merge against the latest disk state; no unrelated setting is
            # overwritten when another Game Room instance has changed it.
            current = GameRoomPreferences.sound_volumes(state)
            current[group] = level
            state["sound_volumes"] = current
          end
          @game_room_settings = nil
        end
        levels[group] = level
      end
    end
    group = groups.fetch(@game_room_volume_group)
    speak(_("%{group}, %{volume}%%") % { group: _(GameRoomUI::VOLUME_LABELS.fetch(group)), volume: levels.fetch(group) })
  rescue StandardError => error
    Log.warning("ELTEN Game Room volume update failed: #{error.class}: #{error.message}") if defined?(Log)
    speak(_("The sound volume could not be saved."))
  end

  def room_membership_tracker(row)
    @room_membership_trackers ||= {}
    @room_membership_trackers[@lobby.table_id(row)] ||= GameRoomSounds::MembershipTracker.new
  end

  def forget_room_membership(row)
    @room_membership_trackers&.delete(@lobby.table_id(row))
  end

  def valid_player_count?(game, count)
    return false if game == nil

    minimum = [game.minimum_players.to_i, 1].max
    maximum = [game.maximum_players.to_i, minimum].max
    count.to_i.between?(minimum, maximum)
  end

  def invalid_player_count_message(game, current_count)
    return _("This game is not supported by this version of ELTEN Game Room.") if game == nil

    minimum = [game.minimum_players.to_i, 1].max
    maximum = [game.maximum_players.to_i, minimum].max
    if minimum == maximum
      _("This game requires exactly %{required} players. There are currently %{current} users at the table.") % {
        required: minimum,
        current: current_count.to_i
      }
    else
      _("This game requires from %{minimum} to %{maximum} players. There are currently %{current} users at the table.") % {
        minimum: minimum,
        maximum: maximum,
        current: current_count.to_i
      }
    end
  end

  def bounded_index(index, items)
    return 0 if items.empty?

    [[index.to_i, 0].max, items.length - 1].min
  end

  def game_definition(game_id)
    GAME_REGISTRY.build(game_id)
  end

  def game_name(game_id)
    GAME_REGISTRY.name(game_id) || game_id.to_s
  end

  def default_table_name
    _("%{user}'s table") % { user: Session.name.to_s }
  end
end

GameRoomInvitationReceipts.install(EltenGameRoom)
