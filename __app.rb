=begin Elten3AppInfo
{
  "id": "c24d98cc-9ccd-4d50-b801-459da324ff60",
  "name": "ELTEN Game Room",
  "description": "Accessible multiplayer games for ELTEN users.",
  "version": "2.0.4",
  "build_id": "239",
  "EltenAPIVersion": "3.0.4",
  "main_language": "en",
  "supported_languages": ["en", "pl", "cs", "es"],
  "localized_descriptions": {
    "pl": "Dostępne gry wieloosobowe dla użytkowników ELTEN-a.",
    "cs": "Přístupné hry pro více hráčů v ELTENu.",
    "es": "Juegos multijugador accesibles para usuarios de ELTEN."
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
      "connect", "disconnect", "chatmsg", "notice", "table_notice", "buzzer", "buzzer2", "war_open", "ding", "shuffle", "draw", "draw2",
      "farkle", "cht-roll-dice", "cht-bank", "cht-lost-points", "cht-cat-minus-8", "cht-cat-plus-8",
      "hit1", "hit_ship1", "hit_ship2", "rocket_launch1", "rocket_launch2", "rocket_launch3", "rocket_miss",
      "interception", "lose1", "lose3", "play", "play2", "replay",
      "reverse", "reverse3", "roll", "skip", "win1", "win2",
      "farkle_bank", "ninety3366", "1000_mariage", "win_party", "lose_party",
      "domino_refill", "domino_move_tile", "domino_take_chip", "card-shuffle",
      "krowa-race", "krowa-word-tower", "krowa-single", "krowa-opponent-guessed",
      "krowa-duplicate", "krowa-unknown", "krowa-length", "krowa-success",
      "pong_ball", "pong_hit", "pong_wall", "pong_move", "pong_op_move", "pong_edge", "pong_goal",
      "pong_move_double",
      "pong_shield_on", "pong_shield_off", "pong_shield_hit", "pong_invisible",
      "pong_goal1", "pong_goal2", "pong_goal3", "pong_goal4", "pong_goal5",
      "pong_goal6", "pong_goal7", "pong_goal8", "pong_score1", "pong_score2",
      "pong_score3", "pong_score4", "pong_scores", "pong_number0", "pong_number1",
      "pong_number2", "pong_number3", "pong_number4", "pong_number5", "pong_number6",
      "pong_number7", "pong_number8", "pong_number9", "pong_number10", "pong_number11",
      "pong_number12", "pong_number13", "pong_number14", "pong_number15", "pong_number16",
      "pong_number17", "pong_number18", "pong_number19", "pong_number20", "pong_number21",
      "pong_op_hit",
      "pong_op_edge",
      "pong_op_shield_on",
      "pong_op_shield_off",
      "pong_gamestart",
      "pong_youwin",
      "pong_theywin",
      "pong_own_shield_hit1",
      "pong_op_shield_hit1",
      "pong_own_shield_hit2",
      "pong_op_shield_hit2",
      "pong_own_shield_hit3",
      "pong_op_shield_hit3",
      "pong_own_shield_hit4",
      "pong_op_shield_hit4",
      "pong_own_shield_hit5",
      "pong_op_shield_hit5",
      "pong_own_shield_hit6",
      "pong_op_shield_hit6",
      "pong_own_shield_hit7",
      "pong_op_shield_hit7",
      "pong_own_shield_hit8",
      "pong_op_shield_hit8",
      "pong_own_shield_hit9",
      "pong_op_shield_hit9",
      "pong_own_shield_hit10",
      "pong_op_shield_hit10",
      "pong_echo_noise_left",
      "pong_echo_noise_right",
      "pong_echo_tone_left",
      "pong_echo_tone_right",
      "audio_ball_up",
      "audio_ball_left",
      "audio_ball_down",
      "audio_ball_prepare",
      "audio_ball_stopped",
      "audio_ball_audiodisc_up",
      "audio_ball_audiodisc_center",
      "audio_ball_audiodisc_down",
      "audio_ball_audiodisc_ready",
      "audio_ball_audiodisc_stop",
      "audio_ball_audiodisc_goal"
    ]
  }
}
=end Elten3AppInfo

require "json"
require_relative "lib/game_room_localization"
# Localization already needs this one startup read. Reuse it for notification
# preferences: callbacks/list rendering must not reopen the file on every notice.
game_room_boot_runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
game_room_boot_settings = game_room_boot_runtime.read_json("settings.json", default: {}) if game_room_boot_runtime
game_room_boot_settings = {} if game_room_boot_runtime && !game_room_boot_settings.is_a?(Hash)
GameRoomLocalization.boot(settings: game_room_boot_settings)
require_relative "lib/game_room_transport"
require_relative "lib/game_sync"
require_relative "lib/game_table_background"
require_relative "lib/game_room_server_tables"
require_relative "lib/game_room_user_registry"
require_relative "lib/game_statistics_service"
require_relative "lib/game_room_presence_store"
require_relative "lib/game_room_presence_collector"
require_relative "lib/game_room_presence_screen"
require_relative "lib/game_statistics_screen"
require_relative "lib/table_activity_repository"
require_relative "lib/game_rules"
require_relative "lib/game_room_changelog"
require_relative "lib/game_room_screens"
require_relative "lib/game_option_editor"
require_relative "lib/audio_ball/settings"
require_relative "lib/invitation_repository"
require_relative "lib/invitation_notifications"
require_relative "lib/table_watch_runtime"
require_relative "lib/contact_filters_runtime"
require_relative "lib/invitation_receipts"
require_relative "lib/game_participants"
require_relative "lib/game_sounds"
require_relative "lib/game_room_preferences"
require_relative "lib/game_room_widget"
require_relative "lib/game_teams"
require_relative "lib/game_bots"
require_relative "lib/lobby_repository"
require_relative "lib/game_repository"
require_relative "lib/account_saved_games"
require_relative "lib/game_lifecycle"
require_relative "lib/room_presentation"
require_relative "lib/game_random"
require_relative "lib/hidden_submissions"
require_relative "lib/game_shortcuts"
require_relative "lib/game_surfaces"
require_relative "lib/game_layout"
require_relative "lib/game_simulation"
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
require_relative "games/cat_head_tail"
require_relative "games/ninety_nine"
require_relative "games/tysiac"
require_relative "games/three_five_eight"
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
require_relative "games/battleship"
require_relative "games/mancala"
require_relative "games/krowa"
require_relative "games/axel_pong"
require_relative "games/audio_ball"
require_relative "games/war"
require_relative "games/scientific_war"
require_relative "games/krowa_support/server_schema"
require_relative "games/registry"

class EltenGameRoom < Program
  using GameRoomLocalization::Translations
  extend GameRoomTableWatchRuntime
  extend GameRoomContactFiltersRuntime
  GAME_ROOM_VERSION = "2.0.4".freeze
  GAME_ROOM_BUILD_ID = 239
  GAME_ROOM_CAPABILITIES = ["invitations", "live_sessions", "live_session_stack"].freeze
  LOBBY_ACTIVITY_POLL_INTERVAL = 5.0

  SERVER_TABLES = GameRoomGames::KrowaServerSchema::TABLES.merge(GameRoomStatistics::Schema::TABLES).merge(GameRoomPresence::Schema::TABLES).merge({
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
    }
  }).freeze

  MAIN_OPTIONS = [
    _("Create a new table"),
    _("Join a table"),
    _("Game rules"),
    _("Invitations"),
    _("Saved games"),
    _("Leaderboards"),
    _("Statistics"),
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
    GameRoomGames::CatHeadTail,
    GameRoomGames::NinetyNine,
    GameRoomGames::Tysiac,
    GameRoomGames::ThreeFiveEight,
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
    GameRoomGames::Battleship,
    GameRoomGames::Mancala,
    GameRoomGames::Krowa,
    GameRoomGames::AxelPong,
    GameRoomGames::AudioBall,
    GameRoomGames::War,
    GameRoomGames::ScientificWar
  ])

  DEFAULT_SETTINGS = GameRoomPreferences.defaults(GAME_REGISTRY.ids).freeze

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
    @statistics_extension = extension("game_room_main_tab") do |extension|
      extension.every("statistics_upload", seconds: 30, autorun: true, persistent: false, first: :after_interval) do |context|
        statistics_service&.flush(context.token)
      end
      extension.every("room_presence", seconds: 30, autorun: true, persistent: false, first: :after_interval) do |context|
        room_presence_collector&.heartbeat(context.token)
      end
      extension.start { table_watch_start }
      extension.tick(interval: 1.0) { contacts_tick; table_watch_tick; InvitationResponseOutbox.tick_default }
      extension.stop { table_watch_stop; contacts_stop }
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

  def self.analytics_enabled?
    $developer_mode != true
  end

  def self.statistics_service
    return nil unless analytics_enabled?
    return nil unless respond_to?(:app_runtime) && app_runtime && !Session.name.to_s.empty?
    @statistics_lock ||= Mutex.new
    @statistics_lock.synchronize do
      user = Session.name.to_s.downcase
      if @statistics_user != user
        service = GameRoomStatistics::Service.new(program: self, user: user,
          trigger: -> { @statistics_extension&.trigger("statistics_upload") })
        return nil if service.last_error
        @statistics_service = service
        @statistics_user = user
      end
      @statistics_service
    end
  rescue StandardError
    nil
  end

  def self.room_presence_collector
    return nil unless analytics_enabled?
    return nil unless respond_to?(:app_runtime) && app_runtime && !Session.name.to_s.empty?
    @presence_lock ||= Mutex.new
    @presence_lock.synchronize do
      user = Session.name.to_s.downcase
      if @presence_user != user
        collector = GameRoomPresence::Collector.new(user: user, enabled: -> { analytics_enabled? }, store_factory: -> {
          reporter = GameRoomPresence::Collector.reporter_key(storage: self, user: user)
          GameRoomPresence::Store.new(app_uuid: server_app_uuid, user: user, reporter_key: reporter)
        })
        @presence_collector, @presence_user = collector, user
      end
      @presence_collector
    end
  rescue StandardError
    nil
  end

  def self.normalized_settings
    @normalized_settings || remember_settings(read_json("settings.json", default: DEFAULT_SETTINGS.dup))
  end

  def self.remember_settings(values)
    # Publish a complete, detached snapshot. A callback never waits for a save
    # or sees a partially edited hash; explicit reads/successful saves refresh it.
    normalized = GameRoomPreferences.normalize(values, GAME_REGISTRY.ids)
    @normalized_settings = JSON.parse(JSON.generate(normalized), freeze: true)
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
    contact_allowed = contact_notification_allowed?(notification, settings: settings)
    sound_name = notification.type.to_s == GameRoomTableWatch::TYPE ? "table_notice" : "notice"
    sound = nil
    if settings["invitation_sounds"] && contact_allowed == true
      # Managed playback reads the packaged asset directly from memory. Asking
      # for its path first needlessly materializes it on disk, even for a row
      # that is never played. Keep the path only for older host fallback.
      sound = sound_name
      sound = sound_asset_path(sound_name) || sound_name if !respond_to?(:play_sound_from_asset) && respond_to?(:sound_asset_path)
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
        sound = nil
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
      presentation
    end
    presentation&.suppress_default! if contact_allowed != true
    if presentation != nil && sound != nil && respond_to?(:play_sound_from_asset)
      presentation.extend(GameRoomUI::NotificationSound)
      presentation.game_room_notice_player = lambda do
        volume = GameRoomPreferences.sound_volume(normalized_settings, sound_name)
        GameRoomTableWatch::Timing.measure(:audio) { play_sound_from_asset(sound_name, volume: volume) } if volume > 0
      rescue StandardError => error
        Log.warning("ELTEN Game Room notification sound failed: #{error.class}: #{error.message}") if defined?(Log)
      end
    end
    presentation
  end

  def self.receive_invitation_receipt(notification)
    GameRoomInvitationReceipts.enqueue(self, notification)
  end

  def self.notification_received(notification, _presentation = nil, deferred: false)
    receive_invitation_receipt(notification) if GameRoomInvitationReceipts::TYPES.include?(notification.type.to_s)
    return unless contact_notification_received(notification, _presentation, deferred: deferred)
    if notification.type.to_s == GameRoomTableWatch::TYPE
      received = GameRoomTableWatch::Timing.measure(:receipt) { table_watch_receiver.receive(notification) }
      _presentation&.suppress_default! unless received
    end
  end

  def program_main
    initialize_services
    record_statistics_visit
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

  def notification_action(action, notification)
    return open_new_table_notification(notification) if action.to_s == "open_new_table"
    return false if action.to_s.to_sym != :open_invitation

    initialize_services
    record_statistics_visit
    check_server_table_access
    connected = run_network_task(_("Connecting to Elten")) { @transport.start }
    return true unless connected
    invitation_id = notification.metadata.to_h["invitation_id"].to_i
    expiry = GameRoomNotificationTime.expires_at(notification)
    # Older notifications did not carry an expiry. Their actual invitation
    # still needs the authoritative lookup below, not a false "expired".
    if expiry > 0 && expiry <= GameRoomClock.now.to_i
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

  # Called only by an active Game Room form on a parallel host scene. Keep
  # this safe before service initialization and after normal resource cleanup.
  def dispatch_pending_game_room_events
    @transport ? @transport.dispatch_pending_events : 0
  end

  private

  def record_statistics_visit
    self.class.statistics_service&.visit
  rescue StandardError
    nil
  end

  def record_statistics_start(session, game, service: self.class.statistics_service)
    return unless self.class.analytics_enabled?
    service&.started(session: session, game_id: game.id)
  rescue StandardError => error
    log_statistics_failure("Statistics start recording failed: #{error.class}")
  end

  def statistics_observer_for(game, service: self.class.statistics_service, viewer: Session.name.to_s.dup.freeze)
    return nil unless service && self.class.analytics_enabled?
    lambda do |session, replay|
      next unless self.class.analytics_enabled?
      service.observe(session: session, replay: replay, game_id: game.id,
        viewer: viewer, participants: session.fetch("__players", []))
    rescue StandardError => error
      log_statistics_failure("Statistics observation failed: #{error.class}")
    end
  end

  def log_statistics_failure(message)
    Log.warning(message) if defined?(Log)
  rescue StandardError
    nil
  end

  def register_room_presence
    collector = self.class.room_presence_collector
    return unless collector
    endpoint = live_sessions
    return if @presence_source_endpoint.equal?(endpoint) && @presence_source_collector.equal?(collector)
    @presence_source_registration&.close
    user, transport = Session.name.to_s.dup.freeze, @transport
    registration = collector.register do |token|
      next [] if endpoint.closed?
      raise IOError, "Room presence endpoint belongs to another account" unless GameRoomParticipants.same?(endpoint.user, user)
      endpoint.sessions.filter_map do |session|
        token&.raise_if_cancelled!
        next if session.closed?
        metadata = session.metadata.to_h
        next unless metadata["kind"] == GameRoomLiveSessionStore::KIND && GameRoomPresence::Identity.valid?(metadata["statistics_room_id"])
        snapshot = transport.room_snapshot(metadata["table_id"], force: true, read_only: true, timeout: 5, cancellation_token: token)
        LobbyRepository::TableSnapshot.new(**snapshot) if snapshot
      end
    end
    manage(registration)
    @presence_source_registration, @presence_source_endpoint, @presence_source_collector = registration, endpoint, collector
  rescue StandardError => error
    registration&.close
    log_statistics_failure("Room presence registration failed: #{error.class}")
  end

  def initialize_services
    @transport ||= GameRoomTransport.new(self)
    @server_tables ||= GameRoomServerTables.new(self)
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
    register_room_presence
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
      when :room_activity
        show_room_activity
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
    @lobby_activity_entries.sort_by!(&:id)
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

    history.replace_entries(load_lobby_history)
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
      show_statistics
    when 7
      show_settings
    when 8
      show_changelog
    end
  end

  def game_local_services
    {server_tables: @server_tables, transport: @transport}
  end

  def show_leaderboards
    ids = GAME_REGISTRY.ids.select { |id| game_definition(id).supports_leaderboards? }
    selected = select_game(_("Leaderboards"), ids)
    return if selected == nil
    client = game_definition(selected).build_leaderboard_client(self, **game_local_services)
    client&.run
  ensure
    client&.close
  end

  def show_room_activity
    user = Session.name.to_s.dup.freeze
    GameRoomPresenceScreen.new(program: self, reader: -> {
      read_statistics do |token|
        next unless !user.empty? && GameRoomParticipants.same?(Session.name, user)
        collector = self.class.room_presence_collector
        if collector
          GameRoomClock.synchronize
          collector.store.report(cancellation_token: token)
        end
      end
    }).run
  end

  def show_statistics
    service = self.class.statistics_service
    GameRoomStatisticsScreen.new(
      program: self,
      registry: GAME_REGISTRY,
      reader: ->(period) { read_statistics { |token| service&.store&.report(period, cancellation_token: token) } },
      years_reader: -> { read_statistics { |token| service&.store&.years(today: GameRoomStatistics::Periods.today, cancellation_token: token) } }
    ).run
  end

  def read_statistics
    return nil unless self.class.analytics_enabled?
    EltenAPI::Tasks.run(title: _("Loading statistics"), cancellable: true, show_after: 5.0) do |_progress, token|
      next unless self.class.analytics_enabled?
      token.raise_if_cancelled!
      yield token
    end
  end

  def bind_game_room_shortcuts(form, game, &dispatch)
    return if game == nil
    form.game_shortcut_signatures = game.room_shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers] } if form.respond_to?(:game_shortcut_signatures=)
    game.room_shortcuts.each do |shortcut|
      form.on(:"key_#{shortcut.key}") do |parameters|
        shift, control, alt = parameters.to_a
        held = []
        held << :shift if shift == true
        held << :control if control == true
        held << :alt if alt == true
        next unless held.sort == shortcut.modifiers.sort
        dispatch.call(shortcut.action_name)
      end
      prefixes = []
      prefixes << _("Ctrl") if shortcut.modifiers.include?(:control)
      prefixes << _("Alt") if shortcut.modifiers.include?(:alt)
      prefixes << _("Shift") if shortcut.modifiers.include?(:shift)
      key = shortcut.key == "space" ? _("Space") : shortcut.key.upcase
      form.add_tip(GameRoomContextHelp.shortcut_tip((prefixes + [key]).join("+"), shortcut.label))
    end
  end

  def game_join_allowed?(table)
    game = game_definition(table["game"])
    return true unless game
    error = game.table_join_error(game.options_from_json(table["game_options"]),
      viewer: Session.name, owner: @lobby.owner_of(table))
    alert(error) if error
    error == nil
  end

  def apply_game_join_role(table)
    game = game_definition(table["game"])
    if game && game.join_as_observer?(game.options_from_json(table["game_options"]),
        viewer: Session.name, owner: @lobby.owner_of(table))
      @lobby.set_observer(table, Session.name, true)
    end
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

    GameRoomScreens::GameRules.new(game.rule_book(options: options), program: self,
      audio_tutorial: game.audio_tutorial_entries).wait
  end

  def show_create_table
    game_id = select_game(_("Create a new table"), GAME_REGISTRY.ids)
    return if game_id == nil

    game = game_definition(game_id)
    configuration = configure_game_options(game, creating_table: true)
    return if configuration == nil

    create_configured_table(game, configuration)
  end

  def create_configured_table(game, configuration)
    game_id = game.id
    game_options = configuration.fetch(:game_options)
    privacy = configuration.fetch(:private_table) || game.private_table_required?(game_options)

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
    @saved_games ||= AccountSavedGames.new(self, owner: Session.name)
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
      rows = run_network_task(_("Loading saved games")) { saved_games.list }
      return if rows == nil
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
        row = run_network_task(_("Loading saved game")) { saved_games.fetch(row["id"]) }
        return unless row
        table = create_saved_game_table(row)
        if table != nil
          show_table_screen(table)
          return
        end
      when 1
        row = run_network_task(_("Loading saved game")) { saved_games.fetch(row["id"]) }
        return unless row
        game = game_definition(row["game"])
        saved_games.validate(row, game: game)
        speak(game.table_options_announcement(game.options_from_json(row["options"]))) if game != nil
      when 2
        run_network_task(_("Deleting saved game")) { saved_games.delete(row["id"]) } if confirm(_("Delete this saved game?"))
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
      # Ownership of the archive is independent of its playing seats.
      @lobby.set_observer(created.table, Session.name, true) unless GameRoomParticipants.includes?(saved["players"], Session.name)
      created.table
    end
    return nil if row == nil

    saved["players"].each do |player|
      next if GameRoomParticipants.bot?(player) || saved.fetch('controllers', {})[player] == 'bot' || GameRoomParticipants.same?(player, Session.name)
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
    saved = run_network_task(_("Loading saved game")) { saved_games.fetch(row["resume_save_id"]) }
    if saved == nil
      alert(_("The saved game is no longer available."))
      return nil
    end
    game = state.game
    saved_games.validate(saved, game: game)
    restoration = saved_games.restored_data(saved, game: game, table_id: @lobby.table_id(row))
    missing = restoration[:players].reject { |player| restoration.fetch(:controllers, {})[player] == 'bot' || GameRoomParticipants.includes?(state.room.game_participants, player) }
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
          announce_table_options(game_definition(game_id), snapshots[tables.index.to_i]&.table)
        end
      end
      GameRoomContextHelp.replace([tables], [GameRoomContextHelp.shortcut_tip(
        "Ctrl+R", _("Read the table variant and settings"))])
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
        self.class.cancel_new_table_notice(snapshots[selected_index]&.table)
        alert(_("This table is no longer available."))
      end
    end
  end

  def join_table_snapshot(snapshot)
    return nil if snapshot == nil
    return nil unless game_join_allowed?(snapshot.table)

    run_network_task(_("Joining table")) do
      selected_table = snapshot.table
      pending_invitations = pending_invitations_for_table(selected_table)
      if @transport.live_store?
        status = establish_invited_table_transport(selected_table)
        unless [:joined, :already_here].include?(status)
          next LobbyRepository::JoinResult.new(table: selected_table, status: status, members: [])
        end
      else
        connected = establish_table_transport(selected_table, bootstrap: true)
        next :transport_failed if !connected
      end

      joined = @lobby.join_table(selected_table, Session.name, announce: false)
      apply_game_join_role(joined.table) if joined.entered?
      if joined&.entered?
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

  def configure_game_options(game, **options)
    GameRoomOptionEditor.new(program: self,
      defaults: method(:remembered_game_option_defaults),
      remember: method(:remember_multiple_choice_options), alert: ->(message) { alert(message) }).edit(game, **options)
  end

  def remembered_game_option_defaults(game, definitions)
    defaults = game.default_options.dup
    preferences = read_json("game_option_preferences.json", default: {})
    stored = preferences.is_a?(Hash) ? preferences[game.id.to_s] : nil
    return defaults if !stored.is_a?(Hash)

    game.remembered_option_definitions(definitions).each do |definition|
      key = definition.key.to_s
      defaults[key] = stored[key] if stored.key?(key)
    end
    defaults
  rescue StandardError => error
    Log.warning("ELTEN Game Room could not read option preferences: #{error.class}: #{error.message}") if defined?(Log)
    game.default_options
  end

  def remember_multiple_choice_options(game, definitions, options)
    remembered = game.remembered_option_definitions(definitions, options: options)
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
    background_table = prepared_screen = nil
    last_room_state = nil
    quiet_reentry = false
    synchronizer = GameRoomSync::Controller.new(
      transport: @transport, table_id: table_id,
      reconnect: -> { activate_table_transport(row) }
    )
    loop do
      # Keep the monitor alive through room commands/dialogs too. A native
      # window can cover Start/inviting/settings after the waiting form resumes.
      if background_table
        layout.activity_cursor = background_table.activity_cursor
        prepared_screen = background_table.take_game_screen
        stop_table_background(background_table)
        background_table = nil
      end
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
      if prepared_screen
        prepared_screen.send(:present_session_membership, snapshot.members)
      else
        play_game_sounds(room_membership_tracker(row).observe(snapshot.members))
      end
      activity_cursor = announce_new_table_activity(state.activity_entries, after_id: layout&.activity_cursor)
      synchronizer.update_session(state.session_id(@games))
      view_spec = if !state.waiting? && state.replay != nil && state.game != nil
        state.game.game_view_spec(state.replay, Session.name)
      else
        state.game ? state.game.waiting_view_spec(Session.name, history_empty_label: _("No games have been played yet")) :
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
        current_screen, prepared_screen = prepared_screen, nil
        result = run_game_screen(state.session, state.game, table: row, prepared_screen: current_screen)
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

      prepared_screen&.close_covered_session
      prepared_screen = nil
      layout.begin_bindings
      layout.back_button.label = _("Leave")
      form = layout.form
      history_navigator ||= GameRoomHistory::Navigator.new
      GameRoomHistory.bind(form) do |operation, value|
        entries = room_history_entries(state, state.activity_entries)
        message = history_navigator.navigate(entries, operation, value, view: layout.history,
          focused: form.fields[form.index.to_i].equal?(layout.history))
        speak(message.to_s) unless message.to_s.empty?
      end
      action = nil
      participant = nil
      dispatch = lambda do |requested, selected = nil|
        next if action != nil

        action = requested
        participant = selected
        form.resume
      end
      layout.primary_button.on(:press) { dispatch.call(:start_game) }
      layout.bind_status_commands { |command| dispatch.call(:local_game_command, command) }
      bind_game_room_shortcuts(form, state.game) { |command| dispatch.call(:local_game_command, command) }
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
          GameRoomParticipantMenu.role_actions(room: snapshot, viewer: Session.name, owner: owner) +
          (editable_table_state?(state) && state.game.team_assignment(state.game.options_from_json(row["game_options"]), players: snapshot.game_participants) ? [:edit_teams] : []) +
          GameRoomParticipantMenu.lifecycle_actions(active: state.active?, viewer: Session.name, owner: owner,
            compatible: !legacy_table?(row),
            restoring: state.session == nil && !row["resume_save_id"].to_s.empty?,
            frozen: state.session.to_h["__frozen"] && !state.session.to_h["__aborted"]) +
          GameRoomParticipantMenu.management_actions(
            room: snapshot, game: state.game, active: state.active?, viewer: Session.name, owner: owner,
            restoring: state.session == nil && !row["resume_save_id"].to_s.empty?
          )
      end, game: state.game, options: state.game&.options_from_json(row["game_options"]), room: -> { snapshot },
        read_options: -> { announce_table_options(state.game, row) },
        settings: GameRoomParticipantMenu.settings_callback(state.game, program: self), &dispatch)
      form.add_timer(FormTimer.new(GameScreen::TIMER_INTERVAL, repeat: true) do
        next if action != nil

        event = synchronizer.next_event
        next if event == nil

        action = event.kind == :closed ? :closed : :refresh
        form.resume_for_refresh
      end)
      if @transport.respond_to?(:live_store?) && @transport.live_store?
        background_table = GameRoomTableBackground.new(program: self, transport: @transport,
          repository: @games, lobby: @lobby, activity_repository: @table_activity,
          table: row, session_id: state.session_id(@games), activity_cursor: layout.activity_cursor,
          screen_builder: ->(session, game, table) { build_game_screen(session, game, table: table, layout: nil) }).start
      end
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
      when :local_game_command
        state.game&.run_room_command(self, participant, viewer: Session.name, **game_local_services)
        quiet_reentry = true
      when :edit_options
        change_table_game_options(row)
        quiet_reentry = true
      when :edit_teams
        change_table_teams(row)
        quiet_reentry = true
      when :add_bot, :remove_bot
        change_room_computer(row, action, participant)
        quiet_reentry = true
      when :observe_next_game, :play_next_game
        change_observer_mode(row, action)
        quiet_reentry = true
      when :make_observer, :make_player
        change_observer_mode(row, action, participant)
        quiet_reentry = true
      when :transfer_master, :replace_player, :restore_player, :close_table
        changed = change_table_control(row, action, participant)
        return if changed == :closed
        quiet_reentry = true
      when :rules
        show_game_rules(state.game, options: state.game&.options_from_json(row["game_options"]))
      when :invite_online
        show_invite_users(row, source: :online)
      when :invite_contacts
        show_invite_users(row, source: :contacts)
      when :chat
        entry = run_network_task(_("Sending chat message"), ui: :none) do
          @table_activity.append(table: row, kind: "chat", message: layout.chat.text)
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
    stop_table_background(background_table) if background_table
    prepared_screen&.close_covered_session
    layout&.begin_bindings
    @table_layouts&.delete(table_id) if table_id != nil
  end

  def stop_table_background(background)
    background.close
    if background.alive?
      EltenAPI::Tasks.run(title: _("Updating table"), ui: :none, cancellable: false, show_after: 5.0) { background.join }
    end
  end

  def leave_table_from_screen(row)
    own_table = GameRoomParticipants.same?(@lobby.owner_of(row), Session.name)
    question = _("Do you want to leave the table?")
    game = game_definition(row["game"])
    if own_table
      state = load_room_state(row, title: _("Updating table"))
      return false unless state
      if state.active? && state.room.members.any? { |user| !GameRoomParticipants.same?(user, Session.name) }
        error = game&.controller_change_error(state.replay)
        if error
          alert(error)
          return false
        end
      end
    end
    if game && game.private_table_required?(game.options_from_json(row["game_options"]))
      state = load_room_state(row, title: _("Updating table"))
      replay = state.respond_to?(:replay) ? state.replay : nil
      question = game.leave_confirmation(replay, Session.name, own_table: own_table) || question
    end
    return false if !confirm(question)

    result = run_network_task(_("Leaving table")) do
      GameRoomSessionRunner.synchronize_table(program: self, table_id: @lobby.table_id(row), viewer: Session.name) do
        guard = if own_table && state && game
          @games.control_change_guard(table: row, game: game, session: state.session)
        end
        left = @lobby.leave_table(row, Session.name, **(guard ? {control_guard: guard} : {}))
        @transport.deactivate_table(table_id: @lobby.table_id(row)) if left != nil
        left
      end
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

  def change_observer_mode(row, action, participant = nil)
    return change_table_control(row, action, participant) if [:transfer_master, :replace_player, :restore_player, :close_table].include?(action)
    game = game_definition(row["game"])
    return nil if game && !game.role_selection_allowed?(game.options_from_json(row["game_options"]))
    observing = [:observe_next_game, :make_observer].include?(action)
    participant ||= Session.name
    title = observing ? _("Enabling observer mode") : _("Enabling player mode")
    snapshot = run_network_task(title, ui: :none) do
      @lobby.set_observer(row, participant, observing)
    end
    return nil if snapshot == nil

    message = observing ? _("You will observe the next game.") : _("You will play in the next game.")
    speak(message, stop: false, break_sequence: false) if GameRoomParticipants.same?(participant, Session.name)
    snapshot
  end

  def change_table_control(row, action, participant = nil, replacement: :choose)
    state = load_room_state(row, title: _("Updating table"))
    return unless state && GameRoomParticipants.same?(@lobby.owner_of(state.room.table), Session.name)
    if action == :close_table
      return unless confirm(_("Close the table for everyone?"))
      closed = run_network_task(_("Closing table")) { @lobby.close_table(state.room.table) }
      forget_room_membership(row) if closed
      return closed ? :closed : nil
    end
    error = if action == :transfer_master
      state.game.controller_change_error(state.replay)
    else
      state.game.participant_replacement_error(state.replay, player: participant, replacement: replacement)
    end
    if error
      alert(error)
      return nil
    end
    players = state.session ? @games.players_for(state.session) : []
    if participant == nil
      return nil unless action == :transfer_master
      candidates = state.room.members.reject { |person| GameRoomParticipants.same?(person, Session.name) }
      participant = choose_table_participant(candidates, _("Choose the new table master"))
      return nil unless participant
    end
    if action != :transfer_master && (!state.active? || !GameRoomParticipants.includes?(players, participant))
      alert(_("Choose a player in the current game."))
      return nil
    end
    if action == :transfer_master && !GameRoomParticipants.includes?(state.room.members, participant)
      alert(_("This player is no longer at the table."))
      return nil
    end
    if action != :transfer_master
      candidates = GameRoomParticipantMenu.replacement_candidates(room: state.room, players: players, participant: participant, game: state.game)
      if replacement == :choose
        if candidates.empty?
          alert(_("There is nobody available to replace this player."))
          return nil
        end
        replacement = choose_table_participant(candidates, _("Choose the replacement"))
        return nil unless replacement
      end
      unless candidates.include?(replacement) || (replacement == nil && candidates.include?(:new_bot))
        alert(_("This participant cannot replace the selected player."))
        return nil
      end
      replacement = nil if replacement == :new_bot
    end
    run_network_task(_("Updating table"), ui: :none) do
      GameRoomSessionRunner.synchronize_table(program: self, table_id: @lobby.table_id(state.room.table), viewer: Session.name) do
        guard = @games.control_change_guard(table: state.room.table, game: state.game, session: state.session,
          player: action == :transfer_master ? nil : participant, replacement: replacement)
        if action == :transfer_master
          @transport.transfer_room_owner(state.room.table, participant, control_guard: guard)
        else
          @transport.replace_game_player(state.room.table, session_id: @games.session_id(state.session),
            player: participant, replacement: replacement, control_guard: guard)
        end
        @lobby.snapshot_for(state.room.table)
      end
    end
  end

  def choose_table_participant(candidates, header)
    return nil if candidates.empty?
    labels = candidates.map do |person|
      person == :new_bot ? _("Add a new computer in this place") : GameRoomParticipants.display_name(person)
    end.map { |label| GameRoomContent.utf8(label) }
    selected = nil
    list = ListBox.new(labels, header: GameRoomContent.utf8(header), index: 0, quiet: true)
    accept = Button.new(_("Accept"))
    cancel = Button.new(_("Cancel"))
    form = GameRoomUI::Form.new([list, accept, cancel], program: self, quiet: true)
    form.accept_button, form.cancel_button = accept, cancel
    form.hide(accept)
    form.hide(cancel)
    accept.on(:press) { selected = candidates[list.index.to_i]; form.resume }
    cancel.on(:press) { form.resume }
    form.wait
    selected
  end

  def show_invite_users(row, source:)
    return if !invitation_sending_available?
    game = game_definition(row["game"])
    return if game && !game.table_invitations_allowed?(game.options_from_json(row["game_options"]))

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
      "user" => invitation["recipient"].to_s, "response" => response
    }, expires_in: 300)
  end

  def deliver_table_invitation(table, recipient, continuation: false)
    game = game_definition(table["game"])
    return nil if game && !game.table_invitations_allowed?(game.options_from_json(table["game_options"]))
    result = @invitations.deliver(table: table, sender: Session.name, recipient: recipient) do |invitation|
      invitation["__history_writer"] = GameRoomInvitationReceipts::HistoryWriter.new(
        repository: @table_activity, table: table, invitation: invitation)
      metadata = invitation_metadata(table, invitation_row_id(invitation))
      metadata["continuation"] = true if continuation
      if table["private"] == true
        delivered = @transport.invite_user(table_id: @lobby.table_id(table), user: recipient, metadata: metadata)
        next false if !delivered
        expiry = delivered.is_a?(Hash) ? (delivered["expires_at"] || delivered.dig("invitation", "expires_at")).to_i : 0
        raise GameRoomNetworkErrors::UnsupportedInvitation, "The server did not provide the private invitation expiration" if expiry <= GameRoomClock.now.to_i
        invitation["expires_at"] = [invitation["expires_at"], expiry].min
        metadata["expires_at"] = invitation["expires_at"]
        metadata["native_expires_at"] = expiry
      end
      remaining = [metadata["expires_at"].to_i - GameRoomClock.now.to_i, 0].max
      raise GameRoomNetworkErrors::UnsupportedInvitation, "The invitation expired before delivery" if remaining <= 0
      metadata["expires_in"] = [remaining, InvitationRepository::DEFAULT_TTL].min
      send_notification(recipient, type: "game_room.invitation", metadata: metadata, expires_in: metadata["expires_in"])
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
    if invitation.expires_at <= GameRoomClock.now.to_i
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
    if invitation.expires_at <= GameRoomClock.now.to_i
      revoke_invitation_notification(invitation.id, notification_id: notification_id)
      alert(_("This invitation has expired."))
      return nil
    end
    if current_invitation == nil || snapshot == nil
      revoke_invitation_notification(invitation.id, notification_id: notification_id)
      alert(snapshot == nil ? _("This table is no longer available.") : _("This invitation is no longer available."))
      return nil
    end

    return nil unless game_join_allowed?(current_invitation.table)
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
      apply_game_join_role(joined.table) if joined.entered?
      if joined.entered?
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
    now = GameRoomClock.now.to_i
    {
      "kind" => "game_room_invitation",
      "invitation_id" => invitation_id,
      "table_id" => @lobby.table_id(row),
      "live_session_id" => row["__live_session_id"].to_s,
      "table_name" => row["name"].to_s,
      "game" => row["game"].to_s,
      "game_name" => game_name(row["game"]),
      "sender" => Session.name.to_s,
      "created_at" => now,
      "expires_at" => now + InvitationRepository::DEFAULT_TTL
    }
  end

  def invitation_row_id(row)
    (row["__id"] || row["id"]).to_i
  end

  def game_room_settings(reload: false)
    if reload || @game_room_settings == nil
      @pong_preferences = nil
      @audio_ball_preferences = nil
      stored = read_json("settings.json", default: DEFAULT_SETTINGS.dup)
      @game_room_settings = GameRoomPreferences.normalize(stored, GAME_REGISTRY.ids)
      self.class.remember_settings(@game_room_settings)
    end
    @game_room_settings
  end

  def update_game_room_settings
    snapshot = nil
    result = update_json("settings.json", default: DEFAULT_SETTINGS.dup) do |state|
      yield state
      snapshot = JSON.parse(JSON.generate(state))
      state
    end
    # Only commit after the host confirms the write. A failed save must not
    # silently enable sounds, notifications or less restrictive contact filters.
    self.class.remember_settings(snapshot)
    result
  end

  def pong_preferences
    @pong_preferences ||= GameRoomPong::Preferences.normalize(game_room_settings['pong']).freeze
  end

  def show_pong_settings(tick: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    # The fast entry point is deliberately local: no notification preferences,
    # contacts, or table requests are loaded while opening or saving this panel.
    updated = GameRoomPong::Settings.new(pong_preferences, program: self, tick: tick, clock: clock).wait
    return unless updated
    update_game_room_settings do |state|
      state['pong'] = updated
      state
    end
    @game_room_settings = game_room_settings.merge('pong' => updated)
    @pong_preferences = updated.freeze
  end

  def audio_ball_preferences
    @audio_ball_preferences ||= GameRoomAudioBall::Preferences.normalize(game_room_settings['audio_ball']).freeze
  end

  def show_audio_ball_settings(tick: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    updated = GameRoomAudioBall::Settings.new(audio_ball_preferences, program: self, tick: tick, clock: clock).wait
    return unless updated
    update_game_room_settings do |state|
      state['audio_ball'] = updated
      state
    end
    @game_room_settings = game_room_settings.merge('audio_ball' => updated)
    @audio_ball_preferences = updated.freeze
  end

  def build_widget_control
    initialize_services
    return @widget_control if @widget_control
    @widget_control = GameRoomWidget::TableList.new(
      program: self,
      loader: -> { load_widget_table_snapshots },
      opener: ->(snapshot) { open_widget_table(snapshot) },
      on_visit: -> { record_statistics_visit },
      creator: ->(slot) { create_table_from_widget(slot) },
      invitations: -> { accept_invitation_from_widget },
      labeler: ->(snapshot) { widget_table_label(snapshot) },
      manual_refresh: lambda {
        self.class.contacts_cache.snapshot(force: true) if game_room_settings(reload: true)["widget_contacts_only"]
      },
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
    contact_cache = self.class.contacts_cache if settings["widget_contacts_only"] == true
    contacts = contact_cache&.snapshot
    if contact_cache && contacts == nil
      return GameRoomWidget::Loading.new(GameRoomContent.utf8(_("Loading contacts")))
    end
    show_unavailable = settings["widget_show_unavailable"] == true
    # Tab entry uses the original host task before native focus reads the
    # result. Five-second/R refreshes use the finite background worker instead.
    @transport.start
    snapshots = @lobby.open_table_snapshots
    return nil if snapshots == nil

    snapshots.select do |snapshot|
      allowed_games.include?(snapshot.table["game"].to_s) &&
        (!contact_cache || (contact_cache.user == Session.name.to_s.strip.downcase &&
          contacts.key?(@lobby.owner_of(snapshot.table).to_s.strip.downcase))) &&
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
    label = GameRoomContent.utf8(_("%{game}, %{table}")) % {
      game: GameRoomContent.utf8(game_name(row["game"])),
      table: table_join_label(snapshot)
    }
    widget_table_available?(snapshot) ? label : _("%{table}, unavailable") % { table: label }
  end

  def open_widget_table(snapshot)
    prepare_widget_program

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

  def prepare_widget_program
    initialize_services
    record_statistics_visit
    if @widget_program_prepared != true
      check_server_table_access
      run_network_task(_("Connecting to Elten"), silent: true) do
        @transport.start
        register_game_room_user
      end
      @widget_program_prepared = true
    end
  end

  def create_table_from_widget(slot = nil)
    if slot == nil
      prepare_widget_program
      show_create_table
      return
    end
    return unless slot.is_a?(Integer) && slot.between?(0, GameRoomTablePresets::COUNT - 1)

    entry = GameRoomTablePresets.slots(game_room_settings(reload: true)["table_presets"])[slot]
    unless entry
      alert(_("No table preset is assigned to this shortcut."))
      return
    end
    game = game_definition(entry["game"])
    unless GameRoomTablePresets.valid?(entry, game)
      alert(_("This preset needs updating. Check its game and options before creating a table."))
      entry = edit_table_preset(entry)
      return unless entry
      save_table_preset(slot, entry)
      game = game_definition(entry["game"])
    end
    prepare_widget_program
    create_configured_table(game, game_options: entry.fetch("options"), private_table: entry.fetch("private_table"))
  end

  def accept_invitation_from_widget
    prepare_widget_program
    # Share Ctrl+J's picker, admission checks and notification cleanup. Only
    # the outer UI entry differs on ELTEN's main-screen widget.
    row = catch(:game_room_table_switch) do
      switch_to_invited_table
      nil
    end
    run_program_interface(row) if row != nil
  end

  def edit_table_preset(entry)
    # Always offer a game choice, also when repairing a preset for a game
    # removed by an update. Editing never creates or modifies a live table.
    game_id = select_game(_("Choose a game for the preset"), GAME_REGISTRY.ids)
    return unless game_id
    game = game_definition(game_id)
    previous = entry.is_a?(Hash) && entry["game"] == game_id ? entry : {}
    configuration = configure_game_options(game,
      initial_options: previous["options"] || game.default_options,
      initial_private_table: previous["private_table"],
      submit_label: _("Save preset"), creating_table: true)
    return unless configuration
    # The options confirmation is the final step; no separate naming dialog.
    GameRoomTablePresets.build(game, configuration, name: game.name)
  end

  def save_table_preset(slot, entry)
    raise ArgumentError, 'Unknown table shortcut' unless slot.is_a?(Integer) && slot.between?(0, GameRoomTablePresets::COUNT - 1)
    # One local write only on explicit editing, never while navigating the widget.
    update_game_room_settings do |state|
      slots = GameRoomTablePresets.slots(state["table_presets"])
      slots[slot] = entry
      state["table_presets"] = slots
      state
    end
    @game_room_settings = nil
  end

  def show_settings
    settings = game_room_settings(reload: true)
    # Only subscriptions need the server. A denied, failed or cancelled read
    # must not block local preferences or turn unknown subscriptions into [].
    watched = nil
    unless @server_tables && !@server_tables.available?
      watched = run_network_task(_("Loading notification settings"), silent: true) do
        self.class.table_watch_repository.load(Session.name)
      end
    end
    if watched != nil
      self.class.table_watch_set_games(watched)
      settings = settings.merge("table_watch_games" => watched)
    end
    games = GAME_REGISTRY.ids.map { |game_id| { id: game_id, name: game_name(game_id) } }
    updated = GameRoomScreens::Settings.new(settings, games: games, program: self,
      table_watch_available: watched != nil,
      preset_editor: ->(entry) { edit_table_preset(entry) },
      preset_writer: ->(slot, entry) { save_table_preset(slot, entry) }).wait
    return if updated == nil

    watch_save_failed = false
    if watched != nil && updated["table_watch_games"].to_a.sort != watched.sort
      saved = run_network_task(_("Saving notification settings"), silent: true) do
        self.class.table_watch_repository.save(Session.name, updated["table_watch_games"])
      end
      watch_save_failed = saved == nil
      self.class.table_watch_set_games(saved) unless watch_save_failed
    end
    updated = updated.reject { |key, _value| %w[table_watch_games table_presets].include?(key) }

    normalized = GameRoomPreferences.normalize(updated, GAME_REGISTRY.ids)
    update_game_room_settings do |state|
      normalized.each { |key, value| state[key] = value }
      state
    end
    @game_room_settings = nil
    @pong_preferences = nil
    self.class.contacts_settings_changed(normalized)
    Programs::Extensions.refresh_ui if defined?(Programs::Extensions) && Programs::Extensions.respond_to?(:refresh_ui)
    language_changed = GameRoomLocalization.normalize_settings(settings) != GameRoomLocalization.normalize_settings(normalized)
    if watch_save_failed
      message = _("Local settings saved. New-table notification subscriptions could not be saved.")
      message += " " + _("Restart ELTEN to apply the interface language preferences.") if language_changed
      alert(message)
    elsif language_changed
      alert(_("Settings saved. Restart ELTEN to apply the interface language preferences."))
    else
      alert(_("Settings saved."))
    end
  end

  def open_new_table_notification(notification)
    record_statistics_visit
    receiver = self.class.table_watch_receiver
    initialize_services
    result = run_network_task(_("Checking table")) do
      @transport.start
      if receiver.visible?(notification)
        metadata = receiver.data(notification)
        [metadata, @lobby.open_table_snapshots(game: metadata["game"])]
      else
        [nil, nil]
      end
    end
    return true if result == nil
    metadata, rows = result
    unless metadata && receiver.visible?(notification)
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
    GameRoomContent.utf8(_("%{owner}, %{count}/%{maximum}, %{status}")) % {
      owner: GameRoomContent.utf8(GameRoomParticipants.display_name(@lobby.owner_of(snapshot.table))),
      count: snapshot.participant_count, maximum: @lobby.capacity_of(snapshot.table),
      status: table_status_label(snapshot.table)
    }
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
    room_history_entries(state, room_activity).map(&:text)
  end

  def room_history_entries(state, room_activity = [])
    replay = state.replay
    game_events = replay == nil ? [] : replay.accepted_events
    @table_activity.merged_history_entries(
      game_entries: state.history,
      game_events: game_events,
      activity_entries: room_activity,
      game_name: ->(id) { game_name(id) }
    )
  end

  def announce_new_table_activity(entries, after_id:, covered: false)
    newest_id = entries.to_a.map(&:id).max.to_i
    return newest_id if after_id == nil

    entries.to_a.select { |entry| entry.id.to_i > after_id.to_i }.each do |entry|
      next if entry.kind == "chat" && GameRoomParticipants.same?(entry.actor, Session.name)

      play_game_sound("chatmsg") if entry.kind == "chat"
      text = @table_activity.text_for(entry, game_name: ->(id) { game_name(id) }, global: false)
      if !text.to_s.empty? && GameRoomBackgroundPolicy.speech?(self, covered: covered)
        speak(text, stop: false, break_sequence: false)
      end
    end
    [after_id.to_i, newest_id].max
  end

  def room_user_rows(state)
    source = state.active? ? state.session["options"] : state.room.table["game_options"]
    options = state.game&.options_from_json(source)
    RoomPresentation.game_users(
      room: state.room, game: state.game, replay: state.waiting? ? nil : state.replay,
      players: state.waiting? ? [] : state.players, owner: @lobby.owner_of(state.room.table), options: options
    )
  end

  def table_status_label(row)
    @lobby.playing?(row) ? _("game in progress") : _("open")
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
    options = game.options_for_team_roster(options, players: participants)
    options_error = game.validation_error(options, player_count: participants.length)
    if options_error != nil
      alert(options_error)
      return
    end

    if game.team_assignment(options, players: participants) && !game.prepared_team_assignment(options, players: participants)
      change_table_teams(row, state: state)
      # Accept saves only the team choice. Start remains an explicit room action.
      return nil
    end

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
    statistics_service = self.class.statistics_service
    result = run_network_task(_("Starting game")) do
      guard = game.build_start_guard(self, user: Session.name, **game_local_services)
      if guard != nil
        consumed = guard.consume(options)
        next [:start_error, consumed] unless consumed == true
      end
      started = @games.start_session(
        table: row,
        game: game.id,
        players: participants,
        options: JSON.generate(options),
        recipients: refreshed_room.members,
        expected_previous_session_id: previous_id
      )
      record_statistics_start(started, game, service: statistics_service) if started != nil
      @lobby.set_game_active(row, true, snapshot: refreshed_room) if started != nil
      started
    end
    if result.is_a?(Array) && result.first == :start_error
      alert(result.last)
      return nil
    end
    result
  end

  def configure_team_assignment(game, options, participants)
    assignment = game.team_assignment(options, players: participants)
    return options if assignment == nil

    player_index = 0
    loop do
      player_index = [[player_index, 0].max, assignment.players.length - 1].min
      players = GameRoomScreens::TeamList.new(assignment, index: player_index)
      change_button = Button.new(_("Change team"))
      automatic_button = Button.new(_("Choose teams randomly"))
      start_button = Button.new(_("Accept"))
      cancel_button = Button.new(_("Cancel"))
      form = GameRoomUI::Form.new(
        [players, automatic_button, start_button, change_button, cancel_button],
        program: self,
        quiet: true
      )
      form.accept_button = change_button
      form.cancel_button = cancel_button
      form.hide(change_button)
      form.hide(cancel_button)
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
        assignment.randomize
      when :start
        return game.with_team_assignment(options, players: participants, seats: assignment.seats_for(participants))
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

  def change_table_teams(table, state: nil)
    state ||= load_room_state(table, title: _("Updating table"), force: true)
    return false unless editable_table_state?(state)
    game = state.game
    participants = state.room.game_participants
    previous = state.room.table["game_options"].to_s
    options = game.options_for_team_roster(game.options_from_json(previous), players: participants)
    return false unless game.team_assignment(options, players: participants)
    selected = configure_team_assignment(game, options, participants)
    return false unless selected
    current = load_room_state(table, title: _("Updating table"), force: true)
    unless editable_table_state?(current) && current.session_id(@games) == state.session_id(@games) &&
        current.room.table["game_options"].to_s == previous &&
        same_participant_order?(participants, current.room.game_participants)
      alert(_("The users at the table changed while teams were being selected. Please start again."))
      return false
    end
    error = game.validation_error(selected, player_count: participants.length)
    if error
      alert(error)
      return false
    end
    result = run_network_task(_("Saving teams")) do
      @transport.change_game_options(table: current.room.table, options: JSON.generate(selected),
        expected_options: previous, expected_session_id: current.session_id(@games))
    end
    alert(_("The table changed while you were editing. Open its settings again.")) if result == false
    result == true
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

    statistics_service = self.class.statistics_service
    statistics_viewer = Session.name.to_s.dup.freeze
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
    if replay != nil
      statistics_observer_for(game, service: statistics_service, viewer: statistics_viewer)&.call(game_snapshot.session, replay)
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

  def run_game_screen(session, game = nil, table:, prepared_screen: nil)
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

    if prepared_screen
      prepared_screen.attach_table_layout(@table_layouts&.[](@lobby.table_id(table)))
      return prepared_screen.run
    end
    build_game_screen(session, game, table: table, layout: @table_layouts&.[](@lobby.table_id(table))).run
  ensure
    prepared_screen&.close_covered_session
  end

  def build_game_screen(session, game, table:, layout:)
    synchronizer = GameRoomSync::Controller.new(
      transport: @transport,
      table_id: @lobby.table_id(table),
      session_id: @games.session_id(session),
      reconnect: -> { activate_table_transport(table) }
    )
    synchronizer.update_session(@games.session_id(session), discard_pending: true)
    GameScreen.new(
      program: self,
      game_services: game_local_services,
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
      statistics_observer: statistics_observer_for(game),
      activity_repository: @table_activity,
      game_name: ->(id) { game_name(id) },
      send_chat: ->(current_table, message, _users) do
        @table_activity.append(table: current_table, kind: "chat", message: message)
      end,
      layout: layout,
      manage_computer: ->(current_table, action, participant) { change_room_computer(current_table, action, participant) },
      manage_observer: ->(current_table, action, participant = nil) { change_observer_mode(current_table, action, participant) },
      manage_teams: ->(current_table) { change_table_teams(current_table) },
      edit_options: ->(current_table) { change_table_game_options(current_table) },
      abort_game: ->(current_table, current_session) { abort_current_game(current_table, current_session) },
      save_game: game.supports_saved_games? ? ->(current_table, current_session, current_game) { save_current_game(current_table, current_session, current_game) } : nil
    )
  end

  def change_table_game_options(table)
    state = load_room_state(table, title: _("Updating table"), force: true)
    return false unless editable_table_state?(state)
    previous = state.room.table["game_options"].to_s
    options = configure_game_options(state.game, initial_options: state.game.options_from_json(previous), submit_label: _("Save changes"))
    return false if options == nil
    # Editing an unrelated option must not throw away the accepted line-up.
    participants = state.room.game_participants
    assignment = state.game.prepared_team_assignment(state.game.options_from_json(previous), players: participants)
    if assignment && state.game.team_size(options, player_count: participants.length) == assignment.team_size
      options = state.game.with_team_assignment(options, players: participants, seats: assignment.seats_for(participants))
    else
      options = options.reject { |key, _| [GameRoomTeams::OPTION_KEY, GameRoomTeams::PLAYERS_KEY].include?(key) }
    end
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
    if current.game.private_table_required?(options) && current.room.table["private"] != true
      error = _("Daily Krowa requires a private table. Create a new private table for this variant.")
    end
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
          update_game_room_settings do |state|
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

EltenGameRoom.remember_settings(game_room_boot_settings) if game_room_boot_settings
GameRoomInvitationReceipts.install(EltenGameRoom)
