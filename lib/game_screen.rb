require_relative "game_bots"
require_relative "game_participants"
require_relative "game_repository"
require_relative "game_layout"
require_relative "game_sync"
require_relative "game_simulation"
require_relative "game_rules"
require_relative "game_sounds"
require_relative "game_event_presentation"
require_relative "game_chat_commands"
require_relative "game_history_navigation"
require_relative "game_shortcut_bindings"
require_relative "room_presentation"
require_relative "participant_menu"
require_relative "network_errors"
require_relative "game_session_clock"
require_relative "game_session_runner"
require_relative "presentation_replay"
require_relative "game_background_presentation"
require_relative "game_background_policy"

require_relative "game_room_localization"

class GameScreen
  using GameRoomLocalization::Translations
  TIMER_INTERVAL = 0.05

  def initialize(
    program:,
    repository:,
    game:,
    session:,
    table:,
    table_owner:,
    room_snapshot_provider:,
    synchronizer:,
    invite_online: nil,
    invite_contacts: nil,
    membership_tracker: nil,
    game_status_changed: nil,
    statistics_observer: nil,
    activity_repository: nil,
    game_name: nil,
    send_chat: nil,
    layout: nil,
    manage_computer: nil,
    manage_observer: nil,
    manage_teams: nil,
    save_game: nil,
    edit_options: nil,
    abort_game: nil,
    game_services: {}
  )
    @layout = layout
    @manage_computer = manage_computer
    @manage_observer = manage_observer
    @manage_teams = manage_teams
    @save_game = save_game
    @edit_options = edit_options
    @abort_game = abort_game
    @program = program
    @presentation_ui_thread = Thread.current
    @layout.form.game_room_program = program if @layout != nil
    @repository = repository
    @game = game
    @game_services = game_services
    @session = session
    @table = table
    @table_owner = table_owner
    @room_snapshot_provider = room_snapshot_provider
    @synchronizer = synchronizer
    @invite_online = invite_online
    @invite_contacts = invite_contacts
    @membership_tracker = membership_tracker
    @game_status_changed = game_status_changed
    @statistics_observer = statistics_observer
    @activity_repository = activity_repository
    @game_name = game_name || ->(id) { id.to_s }
    @send_chat = send_chat
    @room_snapshot = nil
    @surface_state = {}
    @selected_surface_action = nil
    @history_index = 0
    @users_index = 0
    @form_index = 0
    @focus_location = [:game, 0]
    @surface_identity = nil
    @last_seen_event_id = nil
    @turn_history_entries = {}
    @pending_event_ids = []
    @history_follows_tail = true
    @new_session_id = nil
    @automatic_recovery_pending = false
    @focus_new_game = false
    @pending_signal_received_at = nil
    @suppress_surface_focus = false
    @latest_wait_replay = nil
    @rules_shortcut_snapshot = nil
    @spoken_timer_announcements = {}
    @activity_entries = nil
    @last_seen_activity_id = nil
    @last_game_payload = nil
    @chat_text = ""
    @chat_index = 0
    @chat_check = 0
    @chat_control = nil
    attach_table_layout(@layout) if @layout != nil
    @pending_chat_message = nil
    @clear_chat_after_action = false
    @history_navigator = GameRoomHistory::Navigator.new
    @hidden_submissions = HiddenSubmissions::Vault.new(
      HiddenSubmissions::ProgramStorage.new(@program)
    )
    @random_source = GameRoomRandom::LocalSecureSource.new
    @bot_coordinator = GameRoomBots::Coordinator.new
    @bot_turn_controller = @repository.bot_turn_controller(table_id)
  end

  def attach_table_layout(layout)
    @layout = layout
    if layout != nil
      layout.form.game_room_program = @program
      # The waiting-room refresh may have announced a last activity between
      # uncovering the window and adopting this prestarted game screen.
      if @last_seen_activity_id != nil
        @last_seen_activity_id = [@last_seen_activity_id.to_i, layout.activity_cursor.to_i].max
      end
      initial_view = layout.snapshot
      @focus_location = initial_view.focus_location
      @chat_control = @layout.chat
      @chat_text = initial_view.chat_text
      @chat_index = initial_view.chat_index
      @chat_check = initial_view.chat_check
      if @layout.session_id == @repository.session_id(@session)
        @surface_state = initial_view.surface_state
        @surface_identity = initial_view.surface_identity
      else
        @focus_new_game = true
      end
    end
  end

  # Called on the active UI without a layout/client when a match starts behind
  # native Messages. The normal screen later adopts this exact presentation.
  def start_covered_session(covered:, activity_cursor:)
    @runner_covered = covered
    # Restoring a saved match must not announce its archived moves again.
    @last_seen_event_id = @session["__event_id_base"].to_i
    @last_seen_activity_id = activity_cursor
    start_session_runner
    self
  end

  def close_covered_session
    stop_session_runner
    @event_presentation&.close
  end

  def table_activity_cursor; @last_seen_activity_id; end

  def run
    return :back unless start_game_client
    start_session_runner
    loop do
      signal_received_at = @pending_signal_received_at
      confirmation_pending = !@session_runner && @bot_turn_controller.waiting_for_confirmation?
      verification_forced = !@session_runner && @bot_turn_controller.verification_due?
      using_cached_payload = false
      snapshot_started_at = monotonic_time
      log_signal_timing("snapshot_started", signal_received_at)
      presentation_only = @presentation_refresh_requested && @last_game_payload != nil
      @presentation_refresh_requested = false
      verification_forced = false if presentation_only
      payload = presentation_only ? @last_game_payload : nil
      payload = network_task(
        _("Updating game"),
        ui: refresh_input_ui,
        silent: confirmation_pending || @automatic_recovery_pending || @new_session_id != nil
      ) do
        @synchronizer.synchronize(complete: @new_session_id == nil) do
          room_snapshot = @room_snapshot || @room_snapshot_provider.call
          [
            @repository.snapshot_for(
              @session,
              # Native notifications already carry persisted events. Only a
              # failed/uncertain operation needs to bypass local stack metadata.
              force_events: (@automatic_recovery_pending || verification_forced) && !@synchronizer.reconciled?
            ),
            room_snapshot,
            @activity_entries || activity_entries_for(room_snapshot)
          ]
        end
      end unless presentation_only || @synchronizer.waiting?
      log_signal_timing(
        "snapshot_finished",
        signal_received_at,
        stage_started_at: snapshot_started_at
      )
      if payload == nil
        # nil from the network boundary means an unavailable read, NOT a
        # confirmed room closure. Keep the last complete projection.
        @automatic_recovery_pending = true
        @synchronizer.request_recovery!(delay: GameRoomSync::ERROR_BACKOFF) if !@synchronizer.recovery_pending?
        if @last_game_payload == nil
          event = self.class.wait_for_connection(@synchronizer, program: @program)
          return :back if event == nil
          return :room_closed if event.kind == :closed
          if event.kind == :game_started
            @new_session_id = event.session_id
            return :back if switch_to_new_session == false
          end
          next
        end
        @bot_turn_controller.defer_verification
        verification_forced = false
        payload = @last_game_payload
        using_cached_payload = true
      elsif payload[0] == nil || payload[1] == nil
        return :room_closed
      else
        @last_game_payload = payload
        @automatic_recovery_pending = false if !@synchronizer.recovery_pending?
      end

      snapshot, next_room_snapshot, next_activity_entries = payload
      present_session_membership(next_room_snapshot.members)
      @room_snapshot = next_room_snapshot
      @activity_entries = next_activity_entries.to_a
      @session = snapshot.session
      @table_owner = @session["__table_owner"] if @session["__table_owner"]
      return :game_aborted if @session["__aborted"]
      replay_started_at = monotonic_time
      replay = @game.replay(@session, snapshot.events, @repository)
      departed_players = using_cached_payload ? [] : departed_players_for_replacement(replay, next_room_snapshot)
      unless departed_players.empty?
        changed = network_task(_("Updating table"), ui: :none) do
          replaced = false
          departed_players.each do |seat|
            current = @repository.snapshot_for(@session).session
            guard = @repository.control_change_guard(table: @table, game: @game, session: current, player: seat)
            replaced = @game_services[:transport].set_seat_controller(@table, session_id: @repository.session_id(@session), seat: seat, bot: true,
              control_guard: guard) || replaced
          end
          replaced
        end
        next if changed
      end
      @statistics_observer&.call(@session, replay) unless using_cached_payload
      @game_client.update_table_control(@session) if @game_client&.respond_to?(:update_table_control)
      @game_client&.before_wait(replay, Session.name)
      synchronize_table_status(replay) if !using_cached_payload && !@session_runner
      log_signal_timing(
        "replay_finished",
        signal_received_at,
        stage_started_at: replay_started_at
      )
      process_new_events(replay, signal_received_at: signal_received_at)
      process_new_table_activity(replay)
      @pending_signal_received_at = nil
      if !using_cached_payload
        verify_pending_move(replay)
        confirmation = @bot_turn_controller.observe(
          session_id: @repository.session_id(@session),
          events: snapshot.events,
          confirmed_event_ids: @repository.confirmed_event_ids(@session),
          verified: verification_forced
        ) unless @session_runner
        log_bot_confirmation(confirmation) if ![:idle, :cooldown, :waiting_for_confirmation].include?(confirmation)
      end

      if !@session["__frozen"] && !replay.finished? && !using_cached_payload && perform_automatic_action(replay)
        @suppress_surface_focus = true
        next
      end
      @game_client&.after_events(replay, Session.name, context: action_context)
      revision = @repository.events_revision(snapshot.events)
      bot_actor = @session["__frozen"] || event_presentation_busy? ? nil : pending_bot_actor(replay)
      if bot_actor != nil
        @bot_turn_controller.schedule_decision(
          session_id: @repository.session_id(@session), actor: bot_actor,
          revision: @game.bot_delay_revision(replay, revision),
          delay: @game.bot_move_delay(replay, bot_actor, context: action_context)
        )
      end
      bot_lease = if bot_actor == nil
        nil
      else
        @bot_turn_controller.acquire(
          session_id: @repository.session_id(@session),
          actor: bot_actor,
          revision: revision
        )
      end
      action = wait_for_action(replay, revision, bot_actor: bot_actor, bot_lease: bot_lease)
      if @latest_wait_replay != nil
        replay = @latest_wait_replay
        @latest_wait_replay = nil
      end

      case action
      when :game_action
        submit_action(replay)
        clear_chat_draft if @clear_chat_after_action
        @clear_chat_after_action = false
        @suppress_surface_focus = true
      when :new_session
        return :back if switch_to_new_session == false
      when :rules
        show_game_rules(replay)
      when :save_game
        surface = @layout&.surface
        if surface.respond_to?(:save_game_error) && (error = surface.save_game_error)
          speak(error)
          @suppress_surface_focus = true
          next
        end
        return :saved if @save_game&.call(@table, @session, @game)
        @suppress_surface_focus = true
      when :edit_options
        @edit_options&.call(@table)
        @room_snapshot = nil
        @activity_entries = nil
        @suppress_surface_focus = true
      when :edit_teams
        @manage_teams&.call(@table)
        @room_snapshot = nil
        @activity_entries = nil
        @suppress_surface_focus = true
      when :abort_game
        return :game_aborted if @abort_game&.call(@table, @session)
        @suppress_surface_focus = true
      when :invite_online
        @invite_online&.call(@table)
      when :invite_contacts
        @invite_contacts&.call(@table)
      when :add_bot, :remove_bot
        @manage_computer&.call(@table, action, @selected_participant)
        @room_snapshot = nil
        @activity_entries = nil
        @suppress_surface_focus = true
      when :observe_next_game, :play_next_game
        updated_room = @manage_observer&.call(@table, action)
        @room_snapshot = updated_room if updated_room != nil
        @suppress_surface_focus = true
      when :make_observer, :make_player, :transfer_master, :replace_player, :restore_player, :close_table
        updated_room = @manage_observer&.call(@table, action, @selected_participant)
        return :room_closed if updated_room == :closed
        @room_snapshot = updated_room if updated_room
        @activity_entries = nil
        @suppress_surface_focus = true
      when :restart
        return :restart
      when :chat
        submit_chat
        @suppress_surface_focus = true
      when :back, :room_closed
        stop_pending_speech
        return action
      when :refresh
        @suppress_surface_focus = true
        next
      when :presentation_refresh
        # Repaint a local playback step from the already received snapshot.
        # Ending a sound is not a reason to send a new network request.
        @presentation_refresh_requested = true
        @suppress_surface_focus = true
        next
      end
    end
  ensure
    stop_session_runner
    @layout&.form&.clear_game_room_background_help
    @layout.form.game_room_background_help_enabled = false if @layout
    @event_presentation&.close
    @game_client&.close
  end

  # Used only when a screen has not received its first valid snapshot yet.
  # Timers consume existing recovery wake-ups; they never poll the server.
  def self.wait_for_connection(synchronizer, program: nil)
    back = Button.new(_("Back"))
    form = GameSurfaces::RefreshAwareForm.new([back], program: program, quiet: true)
    result = nil
    back.on(:press) { form.resume }
    form.cancel_button = back
    form.add_timer(FormTimer.new(TIMER_INTERVAL, repeat: true) do
      event = synchronizer.next_event
      if event != nil
        result = event
        form.resume_for_refresh
      end
    end)
    form.wait
    result
  end

  private

  def start_session_runner
    return if @session_runner
    transport = @game_services[:transport]
    return unless @game.session_runner? && transport&.live_store?
    @session_runner = GameRoomSessionRunner.new(program: @program, transport: transport,
      repository: @repository, game: @game, session: @session, table: @table,
      owner: @table_owner, viewer: Session.name, room_snapshot_provider: @room_snapshot_provider,
      context: action_context, game_status_changed: @game_status_changed, statistics_observer: @statistics_observer,
      activity_repository: @activity_repository, covered: @runner_covered).start
    @background_presentation = GameRoomBackgroundPresentation.attach(self,
      program: @program, runner: @session_runner, key: [@program.class, table_id, Session.name.to_s.downcase])
  end

  def stop_session_runner
    @background_presentation&.close
    @background_presentation = nil
    runner, @session_runner = @session_runner, nil
    return unless runner
    runner.close
    if runner.alive?
      EltenAPI::Tasks.run(title: _("Updating game"), ui: :none, cancellable: false, show_after: 5.0) { runner.join }
    end
  end

  # Invoked by the active native UI loop, NOT by the model worker. Do not
  # refresh controls, focus, input, local dialogs or the suspended game client.
  # The same event/activity cursors and sound queue are used before/after cover.
  def present_background_session(runner)
    return if @last_seen_event_id == nil
    packet = runner.presentation_snapshot
    if packet && !packet.equal?(@background_presented_snapshot)
      @background_presented_snapshot = packet
      data = Marshal.load(Marshal.dump(packet))
      @background_timer_data = nil
      present_session_membership(data[:members])
      process_new_table_activity(data[:replay], entries: data[:activity], background: true)
      if !data[:session]["__aborted"] && prepare_presentation_session(data[:session], background: true)
        @background_timer_data = data
        process_new_events(data[:replay], session: data[:session], background: true)
      end
    end
    @event_presentation&.advance
    if @background_timer_data
      data = @background_timer_data
      clock = @action_clock ||= GameRoomSessionClock.new
      now = clock.public_send(@game.precise_action_clock? ? :now_f : :now, data[:session])
      announce_due_timers(data[:replay], now: now)
    end
  end

  def present_session_membership(members)
    return unless @membership_tracker
    # A suspended screen can resume with an old cached room payload. Keep the
    # same runner-owned projection for sounds in both foreground/background,
    # otherwise one real join could sound like join, leave, then join again.
    packet = @session_runner&.presentation_snapshot
    current = packet ? packet[:members] : members
    GameRoomSounds.play_all(@program, @membership_tracker.observe(current))
  end

  def publish_session_view(replay, surface)
    return unless @session_runner
    @session_runner.publish_view(session: @session, replay: replay,
      busy: event_presentation_busy? || connection_recovery_pending?, context: action_context, surface: surface)
    status = @session_runner.take_action_error(@session, replay)
    @game_client.automatic_error(status) if status && @game_client&.respond_to?(:automatic_error)
    error = @session_runner.take_error
    if error
      raise error unless GameRoomNetworkErrors.expected?(error) || GameRoomNetworkErrors.cancelled?(error)
      @automatic_recovery_pending = true
      @synchronizer.request_recovery!(delay: @session_runner.recovery_delay)
    end
  end

  def wait_for_action(replay, revision, bot_actor: nil, bot_lease: nil)
    replay = @event_presentation.visible_replay if event_presentation_busy? && @event_presentation.visible_replay != nil
    action = nil
    bot_token = bot_lease == nil ? nil : EltenAPI::Tasks::CancellationToken.new
    history_items = combined_history_items(replay)
    user_items = room_user_items(replay)
    @game.prepare_view(replay, Session.name, context: action_context)
    view_spec = @game.game_view_spec(replay, Session.name)
    phase = replay.finished? ? :finished : :active
    @finished_at = phase == :finished ? (@layout&.phase == :active ? monotonic_time : @finished_at) : nil
    phase_changed = @layout != nil && (@layout.phase != phase || @focus_new_game == true)
    if @layout == nil
      @layout = GameRoomLayout::Screen.new(
        view_spec: view_spec, history_items: history_items, user_items: user_items,
        users_header: users_header, chat_control: @chat_control,
        phase: phase,
        own_table: same_user?(@table_owner, Session.name)
      )
      @layout.form.game_room_program = @program
    else
      @layout.update(
        view_spec: view_spec, history_items: history_items, user_items: user_items,
        users_header: users_header, phase: phase,
        own_table: same_user?(@table_owner, Session.name),
        surface_state: @surface_state, reset_surface: @surface_identity == nil,
        new_game: @focus_new_game == true
      )
    end
    @focus_new_game = false
    @layout.session_id = @repository.session_id(@session)
    layout = @layout
    layout.begin_bindings
    layout.back_button.label = _("Leave")
    layout.activity_cursor = @last_seen_activity_id
    @chat_control = layout.chat
    # Moving to Restart/Waiting after the final event must preserve the result
    # announcements, but the newly focused status should still be spoken after
    # them. speech_wait below queues that focus instead of letting it interrupt.
    room_focus_retained = phase_changed && [:chat, :history, :users].include?(layout.focus_location.to_a.first)
    announce_finished_focus = phase_changed && phase == :finished && !room_focus_retained
    silent_entry = room_focus_retained || (@suppress_surface_focus && !announce_finished_focus)
    @suppress_surface_focus = false
    cursor_message = layout.take_cursor_announcement
    if !cursor_message.to_s.empty?
      speak(cursor_message, stop: false, break_sequence: false)
      silent_entry = true
    end
    surface = layout.surface
    surface.program = @program if surface.respond_to?(:program=)
    surface.sound_player = ->(name) { GameRoomSounds.play(@program, name) } if surface.respond_to?(:sound_player=)
    history = layout.history
    users = layout.users
    chat = layout.chat
    back_button = layout.back_button
    form = layout.form
    form.game_room_background_help_enabled = true

    remember_position = lambda do
      snapshot = layout.snapshot
      @surface_state = snapshot.surface_state
      @history_index = snapshot.history_index
      @users_index = snapshot.users_index
      @history_follows_tail = snapshot.history_follows_tail
      @form_index = snapshot.form_index
      @focus_location = snapshot.focus_location
      @surface_identity = snapshot.surface_identity
      @chat_text = snapshot.chat_text
      @chat_index = snapshot.chat_index
      @chat_check = snapshot.chat_check
    end
    layout.bind_status_commands do |command|
      next if action != nil
      remember_position.call
      @selected_surface_action = {"kind" => "command", "action" => command}
      action = :game_action
      form.resume
    end
    shortcuts = normalized_game_shortcuts(@game.game_shortcuts(replay, Session.name))
    handle_shortcut = lambda do |shortcut|
      next if action != nil
      next if event_presentation_busy? && ![:announcement, :browse, :surface].include?(shortcut.kind)
      next if @session["__frozen"] && ![:announcement, :browse, :surface].include?(shortcut.kind)
      if bot_actor != nil && !@game.actions_during_bot_turn? && ![:announcement, :browse, :surface].include?(shortcut.kind)
        next
      end

      active_shortcut = refreshed_announcement_shortcut(shortcut, replay, Session.name)
      selection = activate_game_shortcut(active_shortcut, surface, replay: replay)
      if active_shortcut.kind == :staged_form && @latest_wait_replay != nil
        # Preparing an offer has already committed a real event. Continue from
        # that confirmed revision; otherwise the wait's old replay overwrites
        # it and the executor correctly rejects the final proposal as stale.
        replay = @latest_wait_replay
        revision = @repository.events_revision(replay.accepted_events)
        @latest_wait_replay = nil
      end
      if selection == :surface_handled
        if active_shortcut.payload["focus_surface"] == true
          field_index = surface.respond_to?(:command_field_index) ? surface.command_field_index : 0
          layout.focus_game(field_index: field_index || 0, silent: true)
        end
        remember_position.call
        refresh_history_control(history, replay) if @game.history_presentation_depends_on_surface_state?
        next
      end
      if selection == :inline_refresh
        remember_position.call
        action = :refresh
        cancel_bot_decision(bot_token, :human_shortcut)
        form.resume
        next
      end
      next if selection == nil || @session["__frozen"] || event_presentation_busy?

      remember_position.call
      @selected_surface_action = selection
      action = :game_action
      cancel_bot_decision(bot_token, :human_shortcut)
      form.resume
    end
    bind_game_shortcuts(
      form,
      layout.shortcut_fields,
      shortcuts,
      &handle_shortcut
    )
    bind_history_navigation(form) do |operation, value|
      entries = combined_history_entries(replay)
      message = @history_navigator.navigate(entries, operation, value, view: history,
        focused: form.fields[form.index.to_i].equal?(history))
      speak(message.to_s) if !message.to_s.empty?
    end
    GameRoomParticipantMenu.bind(layout, available: -> do
      actions = [:rules, :leave]
      actions << :save_game if @save_game != nil && same_user?(@table_owner, Session.name)
      compatible = !@table.key?("__discovery_protocol") || @table["__discovery_protocol"].to_i >= GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL
      if compatible && same_user?(@table_owner, Session.name) && !@session["__frozen"]
        actions << :edit_options if replay.finished? && @edit_options != nil
        if replay.finished? && @manage_teams && @room_snapshot && @game.team_assignment(
            @game.options_from_json(@room_snapshot.table["game_options"]), players: @room_snapshot.game_participants)
          actions << :edit_teams
        end
        actions << :abort_game if !replay.finished? && @abort_game != nil
      end
      actions << :invite_online if @invite_online != nil
      actions << :invite_contacts if @invite_contacts != nil
      if @manage_observer != nil
        actions.concat(GameRoomParticipantMenu.role_actions(room: @room_snapshot, viewer: Session.name, owner: @table_owner))
      end
      if @manage_computer != nil
        actions.concat(GameRoomParticipantMenu.management_actions(
          room: @room_snapshot, game: @game, active: !replay.finished?, viewer: Session.name, owner: @table_owner
        ))
      end
      actions
    end, game: @game, options: @game.options_from_json(@session["options"]), room: -> { @room_snapshot },
      control: -> { {active: !replay.finished?, players: @repository.players_for(@session), controllers: @session.fetch('__controllers', {})} },
      settings: GameRoomParticipantMenu.settings_callback(@game, client: @game_client),
      read_options: -> {
      source = replay.finished? ? @room_snapshot&.table.to_h["game_options"] : @session["options"]
      speak(@game.table_options_announcement(@game.options_from_json(source)))
    }) do |requested, participant|
      next if action != nil

      remember_position.call
      @selected_participant = participant
      action = requested == :leave ? :back : requested
      cancel_bot_decision(bot_token, :participant_menu)
      form.resume
    end
    layout.restart_button.on(:press) do
      next if action != nil || !replay.finished? || !same_user?(@table_owner, Session.name)
      next if event_presentation_busy?
      next if @finished_at && monotonic_time - @finished_at < @game.restart_guard_seconds.to_f

      remember_position.call
      action = :restart
      form.resume
    end
    surface.on_action do |selection|
      next if action != nil
      next if @session["__frozen"]
      if selection["kind"] == "surface" && selection["action"] == "refresh"
        remember_position.call
        action = :presentation_refresh
        form.resume_for_refresh
        next
      end
      next if event_presentation_busy?
      next if bot_actor != nil && !@game.actions_during_bot_turn?

      cancel_bot_decision(bot_token, :human_surface_action)

      if selection["_stay_open"] == true
        remember_position.call
        @selected_surface_action = selection
        action = :inline_game_action
        form.resume
      else
        remember_position.call
        @selected_surface_action = selection
        action = :game_action
        form.resume
      end
    end
    @game_client.attach_view(form, surface) if @game_client.respond_to?(:attach_view)
    back_button.on(:press) do
      if surface.cancel_pending_action?
        surface.cancel_pending_action!
        remember_position.call
      else
        remember_position.call
        action = :back
        form.resume
      end
    end
    chat.on_submit do
      next if action != nil

      remember_position.call
      submission = GameRoomChatCommands.interpret(@chat_text, surface)
      if submission.kind == :empty
        alert(_("Type a chat message first."))
      elsif submission.kind == :error
        alert(submission.message.to_s)
        clear_chat_draft
      elsif submission.kind == :chat && @send_chat == nil
        alert(_("Chat is not available."))
      elsif submission.kind == :chat
        @pending_chat_message = submission.text
        action = :chat
        cancel_bot_decision(bot_token, :chat)
        form.resume
      elsif submission.kind == :movement
        next if @session["__frozen"] || event_presentation_busy?
        @selected_surface_action = submission.action
        @clear_chat_after_action = true
        action = :game_action
        cancel_bot_decision(bot_token, :chat_command)
        form.resume
      end
    end
    form.add_timer(FormTimer.new(TIMER_INTERVAL, repeat: true) do
      next if action != nil

      presentation_changed = @event_presentation&.advance
      @game_client&.tick
      announce_due_timers(replay)
      publish_session_view(replay, surface)
      automatic_due = automatic_action_due?(replay)
      sync_event = @synchronizer.next_event(
        allow_recovery: recovery_allowed?(automatic_due, bot_actor)
      )
      local_action = if @session_runner || replay.finished? || connection_recovery_pending? || event_presentation_busy? || presentation_changed
        nil
      else
        @game.automatic_surface_action(
          replay,
          Session.name,
          surface: surface,
          context: action_context
        )
      end
      if local_action != nil && sync_event == nil
        remember_position.call
        @selected_surface_action = local_action
        action = :game_action
        form.resume_for_refresh
        next
      end

      if sync_event&.kind == :closed
        action = :room_closed
        cancel_bot_decision(bot_token, :room_closed)
        form.resume_for_refresh
      elsif sync_event&.kind == :game_started
        remember_position.call
        @new_session_id = sync_event.session_id
        action = :new_session
        cancel_bot_decision(bot_token, :new_session_signal)
        form.resume_for_refresh
      elsif sync_event&.kind == :game_changed
        remember_position.call
        received_at = sync_event.received_at
        @pending_signal_received_at = received_at.is_a?(Numeric) ? received_at.to_f : monotonic_time
        log_signal_timing("signal_consumed", @pending_signal_received_at)
        # A LiveSessions wake-up only says that something may have changed.
        # Confirm the event revision before rebuilding the form so duplicate
        # or already-applied notifications stay invisible to the user.
        action = :check_signal
        cancel_bot_decision(bot_token, :game_signal)
        form.resume_for_refresh
      elsif sync_event&.kind == :table_changed
        remember_position.call
        action = :room_refresh
        cancel_bot_decision(bot_token, :room_change_signal)
        form.resume_for_refresh
      elsif sync_event&.kind == :recovery
        remember_position.call
        action = :recovery_refresh
        cancel_bot_decision(bot_token, :connection_recovery)
        form.resume_for_refresh
      elsif presentation_changed || @game_client&.refresh_due?
        remember_position.call
        action = :presentation_refresh
        form.resume_for_refresh
      elsif automatic_due && !connection_recovery_pending?
        remember_position.call
        action = :refresh
        form.resume_for_refresh
      elsif bot_actor != nil && bot_lease == nil && !connection_recovery_pending? && @bot_turn_controller.verification_due?
        remember_position.call
        action = :bot_verification
        form.resume_for_refresh
      elsif bot_actor != nil && bot_lease == nil && !connection_recovery_pending? && @bot_turn_controller.ready?(
        session_id: @repository.session_id(@session),
        actor: bot_actor
      )
        remember_position.call
        action = :bot_ready
        form.resume_for_refresh
      end
    end)

    run_bot_turn = lambda do
      next :idle if bot_token == nil || bot_lease == nil

      bot_started_at = monotonic_time
      bot_phase = replay.state.is_a?(Hash) ? replay.state[:phase] : nil
      Log.debug(
        "ELTEN Game Room bot decision started " \
        "table=#{table_id} session=#{@repository.session_id(@session)} " \
        "game=#{@game.id} actor=#{bot_actor} phase=#{bot_phase || 'none'} " \
        "events=#{replay.accepted_events.length}"
      )
      decision = begin
        calculate_bot_decision(replay, form: form, cancellation_token: bot_token)
      rescue EltenAPI::Tasks::Cancelled => error
        Log.debug(
          "ELTEN Game Room bot decision cancelled " \
          "table=#{table_id} session=#{@repository.session_id(@session)} " \
          "actor=#{bot_actor} elapsed_ms=#{((monotonic_time - bot_started_at) * 1_000).round(1)} " \
          "reason=#{error.message}"
        )
        nil
      end
      Log.debug(
        "ELTEN Game Room bot decision finished " \
        "table=#{table_id} session=#{@repository.session_id(@session)} " \
        "actor=#{bot_actor} elapsed_ms=#{((monotonic_time - bot_started_at) * 1_000).round(1)} " \
        "decision=#{decision == nil ? 'none' : 'ready'}"
      )
      if decision == nil || action != nil
        @bot_turn_controller.cancel(bot_lease)
        bot_lease = nil
        bot_token = nil
        next action == nil ? :idle : :interrupted
      end

      remember_position.call
      changed = perform_bot_turn(replay, decision, lease: bot_lease, form: form)
      # The form remains interactive while the network task submits the bot's
      # move. Preserve anything typed during that task before deciding whether
      # the screen needs to be rebuilt.
      remember_position.call
      waiting_for_confirmation = @bot_turn_controller.waiting_for_confirmation?
      @bot_turn_controller.cancel(bot_lease) if !waiting_for_confirmation
      bot_lease = nil
      bot_token = nil
      changed ? :changed : :unchanged
    end

    waited_once = false
    background_work = false
    pending_game_refresh = false
    loop do
      if bot_token != nil
        background_work = true
        bot_result = run_bot_turn.call
        if bot_result == :changed
          @latest_wait_replay = replay
          return action if action != nil && !maintenance_action?(action)
          return :refresh if action == nil

          pending_game_refresh = true
        end
        return action if action != nil && !maintenance_action?(action)
      end

      if action == nil
        if !waited_once && announce_finished_focus && !background_work
          speech_wait
          form.wait
        elsif !waited_once && !silent_entry && !background_work
          form.wait
        else
          layout.wait_without_announcement
        end
        waited_once = true
      end

      restart_bot = false
      loop do
        cancelled_bot = bot_token != nil && bot_token.cancelled?
        case action
        when :inline_game_action
          selection = @selected_surface_action
          @selected_surface_action = nil
          inline_result = submit_inline_action(replay, selection)
          if inline_result != nil
            replay, inserted = inline_result
            newest_id = inserted.map { |event| @repository.event_id(event) }.max.to_i
            revision = [revision[0].to_i + inserted.length, [revision[1].to_i, newest_id].max]
          end
        when :check_signal
          remote_action, remote_session_id = synchronized_network_task(
            _("Checking for game updates"),
            ui: refresh_input_ui, complete: false
          ) do
            remote_game_update(revision)
          end || [nil, nil]
          if remote_action == :new_session
            @new_session_id = remote_session_id
            action = :new_session
            break
          elsif remote_action == :refresh
            action = :refresh
            break
          end
          @pending_signal_received_at = nil
        when :room_refresh
          room_status, snapshot, activity_entries, remote_action, remote_session_id = synchronized_network_task(
            _("Updating table"),
            ui: refresh_input_ui, complete: false
          ) do
            room_update = fetch_room_snapshot
            # Replacing a participant and changing the master are table
            # notifications, not game moves. The persisted move revision can
            # stay unchanged while the hand, turn and permissions all change.
            # Consult the already received session projection as well; this
            # does not force another network read or rebuild for ordinary chat.
            room_update + (room_update.first == :updated ? remote_game_update(revision) : [nil, nil])
          end || [:failed, nil, []]
          if room_status == :closed
            action = :room_closed
            break
          elsif room_status == :updated
            apply_room_snapshot(users, history, replay, snapshot, activity_entries)
          end
          if remote_action == :new_session
            @new_session_id = remote_session_id
            action = :new_session
            break
          elsif remote_action == :refresh || (room_status == :updated && !departed_players_for_replacement(replay, snapshot).empty?)
            action = :refresh
            break
          end
        when :recovery_refresh
          recovery_started_at = monotonic_time
          payload = synchronized_network_task(_("Updating game"), ui: refresh_input_ui) do
            recover_game_update(revision)
          end
          room_status, snapshot, activity_entries, remote_action, remote_session_id = payload || [:failed, nil, [], nil, nil]
          Log.debug(
            "ELTEN Game Room connection recovery " \
            "table=#{table_id} session=#{@repository.session_id(@session)} " \
            "elapsed_ms=#{((monotonic_time - recovery_started_at) * 1_000).round(1)} " \
            "room_status=#{room_status} remote_action=#{remote_action || 'none'}"
          )
          if room_status == :closed
            action = :room_closed
            break
          end
          apply_room_snapshot(users, history, replay, snapshot, activity_entries) if room_status == :updated
          if remote_action == :new_session
            @new_session_id = remote_session_id
            action = :new_session
            break
          elsif remote_action == :refresh || (room_status == :updated && !departed_players_for_replacement(replay, snapshot).empty?)
            action = :refresh
            break
          end
        when :bot_verification
          background_work = true
          verified_snapshot = network_task(_("Checking computer move"), ui: form, silent: true) do
            @synchronizer.synchronize do
              @repository.snapshot_for(@session, force_events: true)
            end
          end
          remember_position.call
          if verified_snapshot == nil
            @bot_turn_controller.defer_verification
          else
            @session = verified_snapshot.session
            verified_revision = @repository.events_revision(verified_snapshot.events)
            confirmation = @bot_turn_controller.observe(
              session_id: @repository.session_id(@session),
              events: verified_snapshot.events,
              confirmed_event_ids: @repository.confirmed_event_ids(@session),
              verified: true
            )
            log_bot_confirmation(confirmation) if ![:idle, :cooldown, :waiting_for_confirmation].include?(confirmation)
            if @last_game_payload != nil
              @last_game_payload = [verified_snapshot, @last_game_payload[1], @last_game_payload[2]]
            end
            if verified_revision != revision
              action = :refresh
              break
            end
          end
          if @bot_turn_controller.ready?(
            session_id: @repository.session_id(@session),
            actor: bot_actor
          )
            action = :bot_ready
            next
          end
        when :bot_ready
          bot_lease = @bot_turn_controller.acquire(
            session_id: @repository.session_id(@session),
            actor: bot_actor,
            revision: revision
          )
          if bot_lease != nil
            bot_token = EltenAPI::Tasks::CancellationToken.new
            action = nil
            restart_bot = true
            break
          end
        else
          break
        end

        if pending_game_refresh
          action = :refresh
          break
        end

        if cancelled_bot
          @bot_turn_controller.cancel(bot_lease)
          bot_lease = nil
          bot_token = nil
          if bot_actor != nil && @bot_turn_controller.ready?(
            session_id: @repository.session_id(@session),
            actor: bot_actor
          )
            action = :bot_ready
            next
          end
        end

        action = nil
        layout.wait_without_announcement
      end
      next if restart_bot

      @latest_wait_replay = replay
      return action
    end
  ensure
    # Ctrl+F1 opens its background help only after this wait returns. Preserve the
    # current game-field descriptions before removing handlers and their tips.
    @rules_shortcut_snapshot = if action == :rules && @layout != nil
      GameRoomContextHelp.game_field_tips(@layout.game_help_fields)
    end
    @game_client.detach_view if @game_client.respond_to?(:detach_view)
    @bot_turn_controller.cancel(bot_lease)
    @layout&.begin_bindings
  end

  def maintenance_action?(action)
    [
      :inline_game_action,
      :check_signal,
      :room_refresh,
      :recovery_refresh,
      :bot_verification,
      :bot_ready
    ].include?(action)
  end

  # Recovery waits until no automatic action or bot calculation is active, so
  # reconnecting cannot interrupt a valid move and strand the current turn.
  def recovery_allowed?(automatic_due, bot_actor)
    return true if connection_recovery_pending? || @new_session_id != nil

    !automatic_due && bot_actor == nil
  end

  def normalized_game_shortcuts(shortcuts)
    GameRoomShortcutBindings.normalize(shortcuts)
  end

  def show_game_rules(replay)
    tips = @rules_shortcut_snapshot
    @rules_shortcut_snapshot = nil
    source = replay.finished? ? @room_snapshot&.table.to_h["game_options"] : @session["options"]
    options = @game.options_from_json(source)
    tips = @layout && GameRoomContextHelp.game_field_tips(@layout.game_help_fields) if tips == nil
    screen = GameRoomScreens::GameRules.new(@game.rule_book(options: options),
      program: @program, game_shortcuts: tips, audio_tutorial: @game.audio_tutorial_entries)
    if @layout&.form&.game_room_background_help_enabled
      screen.open_on(@layout.form)
    else
      screen.wait
    end
  end

  def bind_game_shortcuts(form, fields, shortcuts, &handler)
    GameRoomShortcutBindings.bind(form, fields, shortcuts, consume: method(:consume_game_shortcut_key), &handler)
  end

  def bind_history_navigation(form, &handler)
    GameRoomHistory.bind(form, &handler)
  end

  def consume_game_shortcut_key(key)
    getkeychar if key.to_s.length == 1 || key.to_s == "space"
    EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
  end

  def activate_game_shortcut(shortcut, surface = nil, replay: nil)
    case shortcut.kind
    when :announcement
      speak(shortcut.message) if !shortcut.message.to_s.empty?
      nil
    when :browse
      browse_shortcut_choices(shortcut)
      nil
    when :number_input
      number_shortcut_action(shortcut)
    when :choice
      choice_shortcut_action(shortcut)
    when :staged_form
      staged_form_shortcut_action(shortcut, replay)
    when :form
      form_shortcut_action(shortcut)
    when :action
      GameSurfaces::Action.new(
        kind: shortcut.action_kind,
        name: shortcut.action_name,
        payload: shortcut.payload,
        source: "shortcut:#{shortcut.key}"
      )
    when :surface
      return nil if surface == nil || !surface.respond_to?(:handle_command)

      result = surface.handle_command(shortcut.action_name, shortcut.payload)
      return result if result.is_a?(GameSurfaces::Action)

      result ? :surface_handled : nil
    else
      raise ArgumentError, "unsupported game shortcut kind: #{shortcut.kind}"
    end
  end

  # The first selection is a small public event. Once it has been accepted,
  # the game supplies the actual form. Cancelling that form returns to the
  # player list; cancelling the player list refreshes the replay if at least
  # one preparation event has already been sent.
  def staged_form_shortcut_action(shortcut, replay)
    current_replay = replay
    prepared = false
    loop do
      selection = choice_shortcut_action(shortcut)
      return prepared ? :inline_refresh : nil if selection == nil

      submitted = submit_inline_action(current_replay, selection, title: _("Preparing trade"))
      return prepared ? :inline_refresh : nil if submitted == nil

      current_replay, = submitted
      prepared = true
      @latest_wait_replay = current_replay
      form_shortcut = @game.staged_form_shortcut(shortcut, current_replay, Session.name, selection)
      return :inline_refresh if form_shortcut == nil

      result = form_shortcut_action(form_shortcut)
      return result if result != nil
    end
  end

  def refreshed_announcement_shortcut(shortcut, replay, viewer)
    return shortcut if shortcut.kind != :announcement

    normalized_game_shortcuts(@game.game_shortcuts(replay, viewer)).find do |candidate|
      candidate.key == shortcut.key && candidate.modifiers.to_a == shortcut.modifiers.to_a
    end || shortcut
  end

  def number_shortcut_action(shortcut)
    value_text = shortcut.default_value == nil ? "" : shortcut.default_value.to_i.to_s
    loop do
      entered = input_text(
        shortcut.prompt,
        flags: EditBox::Flags::Numbers,
        text: value_text,
        escapable: true,
        select_all: !value_text.empty?
      )
      if entered == nil
        EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
        return nil
      end

      value_text = entered.to_s.strip
      value = Integer(value_text, 10) rescue nil
      if value != nil && shortcut.allowed_value?(value)
        return GameSurfaces::Action.new(
          kind: shortcut.action_kind,
          name: shortcut.action_name,
          payload: shortcut.payload.merge(shortcut.value_key => value),
          source: "shortcut:#{shortcut.key}"
        )
      end

      allowed = allowed_values_text(shortcut.allowed_values)
      message = shortcut.invalid_message.to_s
      message = _("This value is not allowed.") if message.empty?
      alert(
        _("%{message} Allowed values: %{values}.") % {
          message: message,
          values: allowed
        }
      )
    end
  end

  def choice_shortcut_action(shortcut)
    selected_index = 0
    result = nil
    choices = shortcut.choices.to_a
    list = ListBox.new(
      choices.map(&:label),
      header: shortcut.prompt,
      index: selected_index,
      quiet: true
    )
    select_button = Button.new(_("Select"))
    cancel_button = Button.new(_("Cancel"))
    form = GameRoomUI::Form.new([list, select_button, cancel_button], program: @program, quiet: true)
    form.accept_button = select_button
    form.cancel_button = cancel_button
    form.hide(select_button)
    form.hide(cancel_button)
    select_button.on(:press) do
      selected_index = list.index.to_i
      result = choices[selected_index]
      form.resume
    end
    cancel_button.on(:press) { form.resume }
    form.wait
    EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
    return nil if result == nil

    GameSurfaces::Action.new(
      kind: shortcut.action_kind,
      name: shortcut.action_name,
      payload: { shortcut.value_key => result.value },
      source: "shortcut:#{shortcut.key}"
    )
  end

  # Reuse the same controls and visibility declarations as table options.
  # No network action is emitted until the entire proposal is submitted.
  def form_shortcut_action(shortcut)
    bindings = shortcut.fields.map do |definition|
      control = case definition.kind.to_sym
      when :integer
        field = EditBox.new(definition.label, type: EditBox::Flags::Numbers, text: definition.default.to_i.to_s, quiet: true)
        field.select_all
        field
      when :boolean
        CheckBox.new(definition.label, checked: definition.default == true)
      when :choice
        ListBox.new(definition.choices.map(&:label), header: definition.label, index: 0, quiet: true)
      when :multiple_choice
        ListBox.new(definition.choices.map(&:label), header: definition.label, index: 0,
          flags: ListBox::Flags::MultiSelection, quiet: true)
      end
      [definition, control]
    end
    submit = Button.new(_("Send proposal"))
    cancel = Button.new(_("Cancel"))
    form = GameRoomUI::Form.new(bindings.map(&:last) + [submit, cancel], program: @program, quiet: true)
    form.accept_button = submit
    form.cancel_button = cancel
    read_values = lambda do
      bindings.to_h do |definition, control|
        value = case definition.kind.to_sym
        when :integer then control.text.to_s
        when :boolean then control.checked == true
        when :choice then definition.choices[control.index.to_i]&.value
        when :multiple_choice then control.multiselections.map { |index| definition.choices[index]&.value }.compact
        end
        [definition.key.to_s, value]
      end
    end
    refresh_visibility = lambda do
      values = read_values.call
      bindings.each do |definition, control|
        @game.option_visible?(definition, values, normalize: false) ? form.show(control) : form.hide(control)
      end
    end
    bindings.each do |definition, control|
      control.on(definition.kind.to_sym == :boolean ? :change : :move) { refresh_visibility.call } if [:choice, :boolean].include?(definition.kind.to_sym)
    end
    refresh_visibility.call
    result = nil
    submit.on(:press) do
      values = read_values.call
      result = bindings.select { |definition, _control| @game.option_visible?(definition, values, normalize: false) }.to_h { |definition, _control| [definition.key.to_s, values[definition.key.to_s]] }
      form.resume
    end
    cancel.on(:press) { form.resume }
    form.wait
    EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
    return nil if result == nil
    GameSurfaces::Action.new(kind: shortcut.action_kind, name: shortcut.action_name, payload: shortcut.payload.merge(result), source: "shortcut:#{shortcut.key}")
  end

  def browse_shortcut_choices(shortcut)
    choices = shortcut.choices.to_a
    list = ListBox.new(
      choices.map(&:label),
      header: shortcut.prompt,
      index: 0,
      quiet: true
    )
    back_button = Button.new(_("Back"))
    form = GameRoomUI::Form.new([list, back_button], program: @program, quiet: true)
    form.cancel_button = back_button
    form.hide(back_button)
    back_button.on(:press) { form.resume }
    list.on(:select) do
      choice = choices[list.index.to_i]
      children = choice&.value
      next unless children.is_a?(Array) && !children.empty? && children.all? { |child| child.is_a?(GameRoomGames::ShortcutChoice) }
      nested = GameRoomGames::GameShortcut.new(key: shortcut.key, kind: :browse, label: choice.label, prompt: choice.label, choices: children)
      browse_shortcut_choices(nested)
    end
    form.wait
    EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
  end

  def allowed_values_text(values)
    if values.is_a?(Range)
      return values.begin.to_s if values.begin == values.end
      return _("%{minimum} to %{maximum}") % { minimum: values.begin, maximum: values.end }
    end
    normalized = values.to_a.map(&:to_i).uniq.sort
    return normalized.first.to_s if normalized.length == 1

    continuous = normalized == (normalized.first..normalized.last).to_a
    return _("%{minimum} to %{maximum}") % {
      minimum: normalized.first,
      maximum: normalized.last
    } if continuous

    normalized.join(", ")
  end

  def submit_action(replay)
    previous_players = @session.fetch('__initial_players', []) + @session.fetch('__seat_changes', []).flat_map { |change| change['players'] }
    if GameRoomParticipants.includes?(previous_players, Session.name) && !GameRoomParticipants.includes?(replay.players, Session.name) &&
        !@game.moderator_action?(@selected_surface_action.to_h)
      @selected_surface_action = nil
      speak(_("You are observing the game."))
      return false
    end
    if @game_client && @game_client.action(@selected_surface_action.to_h, replay, Session.name)
      @selected_surface_action = nil
      return true
    end
    return false if connection_recovery_pending? || event_presentation_busy?

    selection = @selected_surface_action
    @selected_surface_action = nil
    actor = selected_action_actor(selection, replay)
    if @session_runner
      result = submit_runner_action(replay, selection, actor, title: _("Sending action"))
      return false unless result
      @pending_event_ids = result.map { |event| @repository.event_id(event) }
      return true
    end
    status, plan = @game.action_for(
      selection,
      replay,
      actor,
      context: action_context
    )
    if status != :ok
      @game_client&.error(status)
      alert(@game.move_error_for(status, selection: selection, replay: replay, actor: Session.name))
      return false
    end

    recipients = game_recipients
    validate_action_plan!(plan)
    return false if !action_plan_fits_transport?(plan)
    inserted = network_task(_("Sending action")) do
      @repository.append_events(
        session: @session,
        sequence: @repository.next_sequence(@session, replay.accepted_events),
        events: plan.events,
        recipients: recipients,
        actor: actor,
        controller: !same_user?(actor, Session.name)
      )
    end
    return false if inserted == nil || inserted.empty?

    @pending_event_ids = inserted.map { |event| @repository.event_id(event) }
    true
  end

  def submit_inline_action(replay, selection, title: _("Sending assessment"))
    return nil if connection_recovery_pending? || event_presentation_busy?

    if @session_runner
      inserted = submit_runner_action(replay, selection, Session.name, title: title)
      return nil unless inserted
      updated = @game.replay(@session, replay.accepted_events + inserted, @repository)
      accepted_ids = updated.accepted_events.map { |event| @repository.event_id(event) }
      if inserted.any? { |event| !accepted_ids.include?(@repository.event_id(event)) }
        alert(_("The game changed before your action was accepted. Please choose again."))
        return nil
      end
      return [updated, inserted]
    end

    status, plan = @game.action_for(
      selection,
      replay,
      Session.name,
      context: action_context
    )
    if status != :ok
      alert(@game.move_error_for(status, selection: selection, replay: replay, actor: Session.name))
      return nil
    end

    validate_action_plan!(plan)
    return nil if !action_plan_fits_transport?(plan)
    inserted = network_task(title) do
      @repository.append_events(
        session: @session,
        sequence: @repository.next_sequence(@session, replay.accepted_events),
        events: plan.events,
        recipients: game_recipients,
        actor: Session.name
      )
    end
    return nil if inserted == nil || inserted.empty?

    updated = @game.replay(@session, replay.accepted_events + inserted, @repository)
    accepted_ids = updated.accepted_events.map { |event| @repository.event_id(event) }
    if inserted.any? { |event| !accepted_ids.include?(@repository.event_id(event)) }
      alert(_("The game changed before your action was accepted. Please choose again."))
      return nil
    end
    [updated, inserted]
  end

  def submit_runner_action(replay, selection, actor, title:)
    result = network_task(title) do
      @session_runner.submit(session: @session, replay: replay, selection: selection,
        actor: actor, controller: !same_user?(actor, Session.name))
    end
    return nil unless result
    status, inserted = result
    if status != :ok
      if status == :oversized_session_action
        alert(_("This action contains too much data and was not sent."))
        return nil
      end
      @game_client&.error(status)
      alert(@game.move_error_for(status, selection: selection, replay: replay, actor: Session.name))
      return nil
    end
    inserted
  end

  def selected_action_actor(selection, replay)
    if same_user?(@table_owner, Session.name) && @game.moderator_action?(selection)
      replay.players.first
    else
      Session.name
    end
  end

  def start_game_client
    @game_client = @game.build_client(@program, **@game_services)
    if @game_client.respond_to?(:bind_screen)
      @game_client.bind_screen(session_id: @repository.session_id(@session), table_id: table_id,
        owner: @table_owner, viewer: Session.name, members: -> { game_recipients })
    end
    @game_client == nil || !!@game_client.start
  end

  def switch_to_new_session
    requested_id = @new_session_id
    session = synchronized_network_task(_("Opening the new game"), complete: false) do
      @repository.session_by_id(requested_id, table: @table)
    end
    if session == nil
      @synchronizer.request_recovery!(delay: GameRoomSync::ERROR_BACKOFF) if @synchronizer.next_reconcile_at.infinite?
      return
    end
    if @repository.session_id(session) == @repository.session_id(@session)
      @new_session_id = nil
      return true
    end

    # A screen survives rematches, but its client belongs to one game session.
    # In particular Pong closes Communications at the final point and retains
    # match-scoped packet/announcement counters. Never reopen that old channel.
    # Wait for a confirmed new session before disposing the current client.
    @game_client&.close
    @game_client = nil
    @session = session
    @new_session_id = nil
    prepare_presentation_session(session)
    @presentation_refresh_requested = false
    @automatic_recovery_pending = false
    @focus_new_game = true
    @bot_turn_controller.switch_session(@repository.session_id(session)) unless @session_runner
    @synchronizer.update_session(@repository.session_id(session), discard_pending: true).synchronized!
    @surface_state = {}
    @selected_surface_action = nil
    @history_index = 0
    @users_index = 0
    @form_index = @layout ? @layout.form.index.to_i : 0
    @focus_location = @layout&.focus_location || [:game, 0]
    @surface_identity = nil
    @pending_event_ids = []
    @history_follows_tail = true
    @suppress_surface_focus = false
    @latest_wait_replay = nil
    @rules_shortcut_snapshot = nil
    @last_game_payload = nil
    @clear_chat_after_action = false
    @history_navigator = GameRoomHistory::Navigator.new
    start_game_client
  end

  # Membership-only notifications must wake the outer replacement task in
  # realtime games too. Never perform a server write in the UI callback, nor
  # replace someone for a lost Communications connection or a covered window.
  def departed_players_for_replacement(replay, room)
    return [] if @session_runner
    GameRoomExecutionPolicy.departed_players(game: @game, replay: replay, session: @session,
      players: @repository.players_for(@session), members: room&.members, owner: @table_owner,
      viewer: Session.name, transport: @game_services[:transport])
  end

  def fetch_room_snapshot
    snapshot = @room_snapshot_provider.call
    return [:closed, nil, []] if snapshot == nil

    [:updated, snapshot, activity_entries_for(snapshot)]
  end

  def apply_room_snapshot(users, history, replay, snapshot, activity_entries)
    present_session_membership(snapshot.members)
    @room_snapshot = snapshot
    @table = snapshot.table
    @table_owner = @table["owner"] || @table["__insertion_user"]
    @activity_entries = activity_entries.to_a
    process_new_table_activity(replay)
    @layout.update_users(room_user_items(replay), header: users_header)
    @layout.update_history(combined_history_items(replay))
    @users_index = users.index.to_i
    @history_index = history.entry_index
  end

  def remote_game_update(revision, force: false)
    latest = if force
      @repository.session_for_table(@table, force: true)
    else
      @repository.session_for_table(@table)
    end
    latest_id = @repository.session_id(latest)
    current_id = @repository.session_id(@session)
    return [:new_session, latest_id] if latest_id > 0 && latest_id != current_id
    return [:refresh, nil] if latest != nil && latest["__aborted"] != @session["__aborted"]
    return [:refresh, nil] if latest != nil && latest["__frozen"] != @session["__frozen"]
    return [:refresh, nil] if latest != nil && %w[__control_epoch __table_owner __control_ready].any? { |key| latest[key] != @session[key] }
    if latest != nil && %w[__clock_revision __server_started_at __clock_offset __frozen_at].any? { |key| latest[key] != @session[key] }
      return [:refresh, nil]
    end
    return [:refresh, nil] if @repository.event_revision(@session, known_revision: revision) != revision

    [nil, nil]
  end

  def recover_game_update(revision)
    room_status, snapshot, activity_entries = fetch_room_snapshot
    return [room_status, snapshot, activity_entries, nil, nil] if room_status == :closed

    # This reads the native stack even when its locally advertised last_seq is
    # stale. It also finds a newer game if a prior opening attempt failed.
    remote_action, remote_session_id = remote_game_update(revision, force: !@synchronizer.reconciled?)
    remote_action = :refresh if remote_action == nil && @automatic_recovery_pending
    @automatic_recovery_pending = false
    [room_status, snapshot, activity_entries, remote_action, remote_session_id]
  end

  def room_user_items(replay)
    return [] if @room_snapshot == nil

    RoomPresentation.game_users(
      room: @room_snapshot, game: @game, replay: replay,
      players: @repository.players_for(@session), owner: @table_owner,
      controllers: @session.fetch("__controllers", {}),
      options: @game.options_from_json(replay.finished? ? @room_snapshot.table["game_options"] : @session["options"])
    )
  end

  def activity_entries_for(snapshot)
    return [] if snapshot == nil || @activity_repository == nil

    @activity_repository.entries_for(snapshot.table, viewer: Session.name)
  end

  def combined_history_entries(replay)
    game_entries = @game.history_entries_for_display(
      replay,
      Session.name,
      surface_state: @surface_state
    )
    if @activity_repository == nil
      return game_entries.map do |entry|
        GameRoomHistory::Entry.new(text: entry.text.to_s, category: :game)
      end
    end

    @activity_repository.merged_history_entries(
      game_entries: game_entries,
      game_events: replay.accepted_events,
      activity_entries: @activity_entries.to_a,
      game_name: @game_name
    )
  end

  def combined_history_items(replay)
    combined_history_entries(replay).map(&:text)
  end

  def refresh_history_control(history, replay)
    @layout.update_history(combined_history_items(replay))
    @history_index = history.entry_index
  end

  def process_new_table_activity(replay, entries: @activity_entries, background: false)
    @last_seen_activity_id = @layout.activity_cursor if !background && @last_seen_activity_id == nil && @layout != nil
    newest_id = entries.to_a.map(&:id).max.to_i
    if @last_seen_activity_id == nil
      @last_seen_activity_id = newest_id
      @layout.activity_cursor = newest_id if !background && @layout != nil
      return
    end

    new_entries = entries.to_a.select { |entry| entry.id.to_i > @last_seen_activity_id.to_i }
    new_entries.each do |entry|
      next if entry.kind == "chat" && same_user?(entry.actor, Session.name)

      GameRoomSounds.play(@program, "chatmsg") if entry.kind == "chat"
      text = @activity_repository&.text_for(entry, game_name: @game_name, global: false)
      speak_table_automatically(text) if !text.to_s.empty?
    end
    if !background && !new_entries.empty? && @history_follows_tail
      @history_index = [combined_history_items(replay).length - 1, 0].max
    end
    @last_seen_activity_id = [@last_seen_activity_id.to_i, newest_id].max
    @layout.activity_cursor = @last_seen_activity_id if !background && @layout != nil
  end

  def submit_chat
    pending_message = @pending_chat_message
    @pending_chat_message = nil
    message = (pending_message == nil ? @chat_text : pending_message).to_s.strip
    return if message.empty? || @send_chat == nil

    entry = network_task(_("Sending chat message"), ui: :none) do
      @synchronizer.synchronize(complete: false) do
        @send_chat.call(@table, message, @room_snapshot&.members.to_a)
      end
    end
    return if entry == nil

    @activity_entries ||= []
    @activity_entries << entry if !@activity_entries.any? { |candidate| candidate.id.to_i == entry.id.to_i }
    @activity_entries.sort_by!(&:id)
    GameRoomSounds.play(@program, "chatmsg")
    text = @activity_repository&.text_for(entry, game_name: @game_name, global: false)
    speak(text, stop: false, break_sequence: false) if !text.to_s.empty?
    clear_chat_draft
  end

  def clear_chat_draft
    @chat_text = ""
    @chat_index = 0
    @chat_check = 0
    if @chat_control != nil
      @chat_control.set_text("")
      @chat_control.index = 0
      @chat_control.check = 0
    end
  end

  def stop_pending_speech
    send(:speech_stop) if respond_to?(:speech_stop, true)
  end

  def synchronize_table_status(replay)
    return if @game_status_changed == nil || !same_user?(@table_owner, Session.name)

    desired = replay.finished? ? "waiting" : "playing"
    return if @table["status"].to_s == desired

    updated = network_task(_("Updating table status"), ui: :none, silent: true) do
      @game_status_changed.call(@table, !replay.finished?)
    end
    return if !updated.is_a?(Hash)

    @table = updated
    @room_snapshot.table = updated if @room_snapshot != nil
  end

  def users_header
    count = @room_snapshot == nil ? 0 : @room_snapshot.participants.length
    _("Users at the table (%{count})") % { count: count }
  end

  def pending_bot_actor(replay)
    return nil if @session_runner
    return nil if @session["__frozen"]
    return nil if connection_recovery_pending? || @new_session_id != nil
    return nil if !same_user?(@table_owner, Session.name)

    @bot_coordinator.pending_bot(@game, replay)
  end

  def calculate_bot_decision(replay, form:, cancellation_token:)
    context = action_context
    players = @repository.players_for(@session)
    bot_task(form: form, cancellation_token: cancellation_token) do
      GameRoomExecutionPolicy.bot_decision(game: @game, session: @session, replay: replay,
        repository: @repository, coordinator: @bot_coordinator, context: context, players: players)
    end
  end

  def perform_bot_turn(replay, decision, lease:, form:)
    return false if connection_recovery_pending? || event_presentation_busy?
    return false if !same_user?(@table_owner, Session.name)
    return false if decision == nil

    context = action_context
    status, plan = @game.action_for(
      decision.action,
      replay,
      decision.actor,
      context: context
    )
    if status != :ok
      # Storage reports this failure once until a write succeeds. It is not
      # a bad bot decision and must not flood logs on every automatic check.
      if status != :local_storage_unavailable
        Log.warning("ELTEN Game Room bot chose a rejected action: #{@game.id}, #{status}")
      end
      return false
    end
    validate_action_plan!(plan)
    return false if !action_plan_fits_transport?(plan, silent: true)
    return false if !@bot_turn_controller.submitting(lease, events: plan.events)

    submission_started_at = monotonic_time
    Log.debug(
      "ELTEN Game Room bot submission started " \
      "table=#{table_id} session=#{@repository.session_id(@session)} " \
      "game=#{@game.id} actor=#{decision.actor} events=#{plan.events.length}"
    )
    inserted = begin
      network_task(_("Computer is moving"), ui: form, silent: true) do
        @repository.append_events(
          session: @session,
          sequence: @repository.next_sequence(@session, replay.accepted_events),
          events: plan.events,
          recipients: game_recipients,
          actor: decision.actor
        )
      end
    rescue Exception
      @bot_turn_controller.submission_failed(lease)
      raise
    end
    Log.debug(
      "ELTEN Game Room bot submission finished " \
      "table=#{table_id} session=#{@repository.session_id(@session)} " \
      "actor=#{decision.actor} elapsed_ms=#{((monotonic_time - submission_started_at) * 1_000).round(1)} " \
      "inserted=#{inserted == nil ? 0 : inserted.length}"
    )
    if inserted == nil
      @bot_turn_controller.submission_failed(lease)
      Log.warning(
        "ELTEN Game Room bot submission is uncertain; waiting for server state " \
        "table=#{table_id} session=#{@repository.session_id(@session)} actor=#{decision.actor}"
      )
      return false
    end

    event_ids = inserted.map { |event| @repository.event_id(event) }
    @pending_event_ids = event_ids
    @bot_turn_controller.submitted(lease, event_ids: event_ids)
    true
  end

  def log_bot_confirmation(result)
    Log.debug(
      "ELTEN Game Room bot confirmation " \
      "table=#{table_id} session=#{@repository.session_id(@session)} result=#{result}"
    )
  end

  def perform_automatic_action(replay)
    return false if @session_runner
    return false if event_presentation_busy?
    return false if @session["__frozen"]
    return false if connection_recovery_pending? || @new_session_id != nil
    return false if !@game.automatic_action_allowed?(
      replay,
      Session.name,
      table_owner: @table_owner
    )

    context = action_context
    automatic_actor = automatic_actor_for(replay)
    return false if automatic_actor.to_s.empty?

    selection = @game.automatic_action(replay, automatic_actor, context: context)
    return false if selection == nil

    status, plan = @game.action_for(
      selection,
      replay,
      automatic_actor,
      context: context
    )
    if status != :ok
      Log.warning("ELTEN Game Room automatic action was rejected: #{@game.id}, #{status}")
      @game_client&.automatic_error(status)
      return false
    end
    validate_action_plan!(plan)
    return false if !action_plan_fits_transport?(plan, silent: true)

    inserted = network_task(_("Preparing the next round")) do
      @repository.append_events(
        session: @session,
        sequence: @repository.next_sequence(@session, replay.accepted_events),
        events: plan.events,
        recipients: game_recipients,
        actor: automatic_actor,
        controller: !same_user?(automatic_actor, Session.name)
      )
    end
    if inserted == nil
      # Cancellation may happen before Tasks.run enters the operation block.
      # It must not strand an automatic transition either.
      if !@automatic_recovery_pending
        @automatic_recovery_pending = true
        @synchronizer.request_recovery!(delay: GameRoomSync::ERROR_BACKOFF)
      end
      return false
    end

    @pending_event_ids = inserted.map { |event| @repository.event_id(event) }
    true
  end

  def automatic_action_due?(replay)
    return false if @session_runner
    return false if event_presentation_busy?
    return false if @session["__frozen"]
    return false if connection_recovery_pending? || @new_session_id != nil
    return false if !@game.automatic_action_allowed?(
      replay,
      Session.name,
      table_owner: @table_owner
    )

    actor = automatic_actor_for(replay)
    return false if actor.to_s.empty?
    @game.automatic_action_due?(replay, actor, context: action_context)
  rescue StandardError => error
    Log.warning("ELTEN Game Room automatic-action deadline check failed: #{error.class}: #{error.message}")
    false
  end

  def action_context
    GameRoomGames::ActionContext.new(
      session_id: @repository.session_id(@session),
      table_id: table_id,
      hidden_submissions: @hidden_submissions,
      random_source: @random_source,
      options: @game.options_from_json(@session["options"]),
      table_owner: @table_owner,
      local_data: @game_client&.context_data,
      now: action_time
    )
  end

  def action_time
    (@action_clock ||= GameRoomSessionClock.new).public_send(@game.precise_action_clock? ? :now_f : :now, @session)
  end

  def automatic_actor_for(replay)
    @game.automatic_actor(replay, Session.name, table_owner: @table_owner)
  end

  def game_recipients
    participants = if @room_snapshot == nil
      @repository.players_for(@session)
    else
      @room_snapshot.members
    end
    GameRoomParticipants.humans(participants)
  end

  def validate_action_plan!(plan)
    if !plan.is_a?(GameRoomGames::ActionPlan) || plan.events.to_a.empty?
      raise ArgumentError, "a successful game action must return an ActionPlan"
    end
  end

  def action_plan_fits_transport?(plan, silent: false)
    oversized = plan.events.to_a.find do |event|
      event["action"].to_s.length > GameRepository::MAX_ACTION_LENGTH ||
        event["value"].to_s.length > GameRepository::MAX_VALUE_LENGTH
    end
    return true if oversized == nil

    action = oversized["action"].to_s
    action_length = action.length
    value_length = oversized["value"].to_s.length
    Log.warning(
      "ELTEN Game Room rejected oversized event " \
      "game=#{@game.id} action=#{action} action_length=#{action_length} " \
      "action_limit=#{GameRepository::MAX_ACTION_LENGTH} value_length=#{value_length} " \
      "value_limit=#{GameRepository::MAX_VALUE_LENGTH}"
    ) if defined?(Log)
    alert(_("This action contains too much data and was not sent.")) if !silent
    false
  end

  def same_user?(first, second)
    GameRoomParticipants.same?(first, second)
  end

  def table_id
    (@table["__id"] || @table["id"]).to_i
  end

  def event_presentation_busy?
    @event_presentation != nil && @event_presentation.busy?
  end

  def prepare_presentation_session(session, background: false)
    id = (session["__id"] || session["id"]).to_i
    return true if @presentation_session_id == id
    # Native IDs are random, not an ordering clock. A suspended foreground
    # replay may still refer to a match already replaced by the background UI.
    @retired_presentation_sessions ||= {}
    return false if @retired_presentation_sessions[id]
    if @presentation_session_id
      @retired_presentation_sessions[@presentation_session_id] = true
      @event_presentation&.close
      @event_presentation = nil
      @last_seen_event_id = background ? 0 : nil
      @turn_history_entries = {}
      @spoken_timer_announcements = {}
      @background_timer_data = nil
    end
    @presentation_session_id = id
    @decision_presentation_started = false
    true
  end

  def process_new_events(replay, signal_received_at: nil, session: @session, background: false)
    return unless prepare_presentation_session(session, background: background)
    newest_id = replay.accepted_events.map { |event| @repository.event_id(event) }.max.to_i
    if @last_seen_event_id == nil
      @last_seen_event_id = newest_id
      presentation_replay.remember(session, replay)
      @history_index = [combined_history_items(replay).length - 1, 0].max unless background
      present_initial_decision(replay)
      return
    end

    new_events = replay.accepted_events.select do |event|
      @repository.event_id(event) > @last_seen_event_id
    end
    event_replays = event_replays_for(replay, new_events, session: session)
    # Reconnection can deliver several already completed turns together.
    # Alert only for a decision still pending in the latest state, once per
    # batch; a delayed sound sequence must not announce an obsolete turn.
    decision_key = @game.required_decision_key(replay, Session.name)
    decision_new = !@decision_presentation_started || event_replays.values.any? do |before, after|
      decision_key && @game.required_decision_key(after, Session.name) == decision_key &&
        @game.required_decision_key(before, Session.name) != decision_key
    end
    @decision_presentation_started = true
    decision_boundary = @decision_boundary = [@presentation_session_id, newest_id]
    present_decision = lambda do
      if decision_new && decision_boundary == @decision_boundary
        present_required_decision(nil, replay)
      end
    end
    if !new_events.empty? && @game.respond_to?(:serial_event_presentation?) && @game.serial_event_presentation?
      first_before = event_replays[@repository.event_id(new_events.first)]&.first
      @event_presentation ||= GameRoomEventPresentation.new(clock: -> { monotonic_time }, initial_replay: first_before)
    end
    new_events.each do |event|
      event_id = @repository.event_id(event)

      before_replay, after_replay = event_replays.fetch(event_id, [nil, replay])
      turn_entry = remember_turn_transition(before_replay, after_replay, event_id)
      if @event_presentation != nil
        @event_presentation.enqueue(
          replay: after_replay, defer_replay: after_replay.finished?,
          start: -> { present_game_event(event, before_replay, after_replay, after_replay, signal_received_at) },
          finish: -> do
            present_decision.call if event_id == newest_id
            present_turn_transition(turn_entry, after_replay)
            present_game_result(after_replay, signal_received_at) if event_id == newest_id
          end
        )
      else
        present_game_event(event, before_replay, after_replay, replay, signal_received_at)
        present_turn_transition(turn_entry, after_replay)
      end
    end
    merge_turn_history!(replay)
    if newest_id > @last_seen_event_id
      present_game_result(replay, signal_received_at) if @event_presentation == nil
      @history_index = [combined_history_items(replay).length - 1, 0].max if !background && @history_follows_tail
    end
    @last_seen_event_id = [@last_seen_event_id, newest_id].max
    present_decision.call if @event_presentation == nil || new_events.empty? && !event_presentation_busy?
    @event_presentation&.advance
  end

  def present_game_event(event, before_replay, after_replay, description_replay, signal_received_at)
    @game_client&.event(event, before_replay, after_replay, Session.name, @repository)
    sounds = begin
      cues = GameRoomSounds.event_cue(
        game: @game, event: event, before_replay: before_replay, after_replay: after_replay,
        repository: @repository, viewer: Session.name
      )
      Array(cues).map { |cue| GameRoomSounds.play(@program, cue) }
    rescue StandardError => error
      Log.warning("ELTEN Game Room event sound failed: #{error.class}: #{error.message}") if defined?(Log)
      []
    end
    descriptions = normalize_event_descriptions(
      @game.describe_event_for_display(event, @repository, description_replay, Session.name, surface_state: @surface_state)
    )
    descriptions = [] if @game_client&.respond_to?(:presents_game_event?) && @game_client.presents_game_event?(event)
    # The result remains in canonical history, but the common result presenter
    # owns its automatic announcement (also after serialized sound playback).
    result = @game.result_text(after_replay) if after_replay != nil
    descriptions = descriptions.reject { |text| GameRoomContent.utf8(text) == GameRoomContent.utf8(result) } if result != nil
    descriptions.each_with_index do |description, index|
      log_signal_timing("speech_queued", signal_received_at,
        details: "event_id=#{@repository.event_id(event)} item=#{index + 1}/#{descriptions.length}")
      speak_table_automatically(description)
    end
    sounds
  end

  def present_turn_transition(turn_entry, replay)
    return if turn_entry == nil

    message = @game.turn_announcement(replay, Session.name)
    speak_table_automatically(message) if !message.to_s.empty?
  end

  def present_initial_decision(replay)
    return if @decision_presentation_started
    @decision_presentation_started = true
    present_required_decision(nil, replay)
  end

  def present_required_decision(before_replay, after_replay)
    return unless @game.respond_to?(:required_decision_key)
    return unless GameRoomParticipants.includes?(after_replay.players, Session.name)
    key = @game.required_decision_key(after_replay, Session.name)
    return if key == nil || key == @game.required_decision_key(before_replay, Session.name)
    return unless GameRoomBackgroundPolicy.turn_sound?(@program, covered: table_presentation_covered?)
    GameRoomSounds.play(@program, "ding")
  end

  def table_presentation_covered?
    return @runner_covered.call if @runner_covered
    defined?($currentthread) && $currentthread && @presentation_ui_thread &&
      !@presentation_ui_thread.equal?($currentthread)
  end

  def speak_table_automatically(message)
    return unless GameRoomBackgroundPolicy.speech?(@program, covered: table_presentation_covered?)
    speak(message, stop: false, break_sequence: false)
  end

  def present_game_result(replay, signal_received_at)
    return if @game_client&.respond_to?(:presents_game_result?) && @game_client.presents_game_result?(replay)
    result = @game.result_text(replay)
    return if result == nil

    log_signal_timing("result_speech_queued", signal_received_at)
    speak_table_automatically(result)
  end

  def event_replays_for(replay, new_events, session: @session)
    presentation_replay.transitions(session, replay, new_events)
  rescue StandardError => error
    @presentation_replay = nil
    Log.warning("ELTEN Game Room could not reconstruct sound events: #{error.class}: #{error.message}; #{Array(error.backtrace).first}") if defined?(Log)
    {}
  end

  def presentation_replay
    @presentation_replay ||= GameRoomPresentationReplay.new(@game, @repository)
  end

  def remember_turn_transition(before_replay, after_replay, event_id)
    entry = @game.turn_transition_history_entry(
      before_replay,
      after_replay,
      event_id: event_id
    )
    @turn_history_entries[entry.event_id.to_i] = entry if entry != nil
    entry
  rescue StandardError => error
    Log.warning("ELTEN Game Room turn transition failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def merge_turn_history!(replay)
    return replay if replay == nil || @turn_history_entries.empty?

    source = replay.history.reject { |entry| entry.kind == :turn }
    pending = @turn_history_entries.dup
    pending_ids = pending.keys.sort
    pending_index = 0
    merged = []
    source.each_with_index do |entry, index|
      event_id = entry.event_id.to_i
      while pending_index < pending_ids.length && pending_ids[pending_index] < event_id
        pending_id = pending_ids[pending_index]
        merged << pending.delete(pending_id) if pending.key?(pending_id)
        pending_index += 1
      end

      merged << entry
      next_event_id = source[index + 1]&.event_id&.to_i
      if next_event_id != event_id && pending.key?(event_id)
        merged << pending.delete(event_id)
        pending_index += 1 if pending_ids[pending_index] == event_id
      end
    end
    while pending_index < pending_ids.length
      pending_id = pending_ids[pending_index]
      merged << pending[pending_id] if pending.key?(pending_id)
      pending_index += 1
    end
    replay.history = merged
    replay
  end

  def normalize_event_descriptions(description)
    Array(description).compact.map(&:to_s).reject(&:empty?)
  end

  def announce_due_timers(replay, now: action_time)
    @game.timer_announcements(replay, Session.name, now: now).to_a.each do |announcement|
      key, message = announcement.to_a
      next if key.to_s.empty? || message.to_s.empty? || @spoken_timer_announcements[key.to_s]

      @spoken_timer_announcements[key.to_s] = true
      speak_table_automatically(message.to_s)
    end
  rescue StandardError => error
    Log.warning("ELTEN Game Room timer announcement failed: #{error.class}: #{error.message}") if defined?(Log)
  end

  def verify_pending_move(replay)
    if @repository.respond_to?(:consume_recovered_events)
      recovered = @repository.consume_recovered_events(@session)
      @pending_event_ids = (@pending_event_ids.to_a + recovered.map { |event| @repository.event_id(event) }).uniq
    end
    return if @pending_event_ids.empty?

    accepted_ids = replay.accepted_events.map { |event| @repository.event_id(event) }
    accepted = @pending_event_ids.all? { |event_id| accepted_ids.include?(event_id) }
    alert(_("The game changed before your action was accepted. Please choose again.")) if !accepted
    @pending_event_ids = []
  end

  def network_task(title, ui: nil, silent: false, &operation)
    return nil if @synchronizer&.waiting?

    ui = @layout.form if @layout&.form&.game_room_background_help?
    options = { title: title, cancellable: true, show_after: 5.0 }
    options[:ui] = ui if ui != nil
    if @game_client.respond_to?(:network_task_ui)
      token = EltenAPI::Tasks::CancellationToken.new
      task_ui = @game_client.network_task_ui(ui: ui, title: title, show_after: 5.0, cancellation_token: token)
      options[:ui], options[:cancellation_token] = task_ui, token
    end
    EltenAPI::Tasks.run(**options) do |progress, token|
      token.raise_if_cancelled!
      if @session_runner
        @session_runner.synchronize do
          token.raise_if_cancelled!
          operation.call
        end
      else
        operation.call
      end
    end
  rescue EltenAPI::Tasks::Cancelled
    @automatic_recovery_pending = true
    @synchronizer&.request_recovery!(delay: GameRoomSync::ERROR_BACKOFF)
    nil
  rescue StandardError => error
    if error.is_a?(GameRoomSessionRunner::StaleView)
      @automatic_recovery_pending = true
      @synchronizer&.request_recovery!
      return nil
    end
    if error.is_a?(GameRoomNetworkErrors::GamePaused)
      # A confirmed save boundary can arrive between choosing and sending a
      # move. Refresh the pause, without reporting an outage or delaying 30s.
      @automatic_recovery_pending = true
      @synchronizer&.request_recovery!
      return nil
    end
    raise if !GameRoomNetworkErrors.expected?(error)

    @automatic_recovery_pending = true
    @synchronizer&.failed!(error)
    Log.warning("ELTEN Game Room network operation failed: #{error.class}: #{error.message}")
    alert(_("The operation could not be completed. Please try again.")) if !silent
    nil
  ensure
    task_ui&.close
  end

  def connection_recovery_pending?
    @automatic_recovery_pending || (@synchronizer != nil && @synchronizer.recovery_pending?)
  end

  def synchronized_network_task(title, ui: :none, complete: true, &operation)
    network_task(title, ui: ui, silent: true) do
      @synchronizer.synchronize(complete: complete, &operation)
    end
  end

  def refresh_input_ui
    return :none if @chat_control == nil
    return :none if @focus_location.to_a[0]&.to_sym != :chat

    @chat_control
  end

  # Bot policies may perform a complete-round search. The worker calculates the
  # decision while Tasks.run keeps the owned game form active, so navigation,
  # informational shortcuts, speech and audio continue during the search.
  def bot_task(form:, cancellation_token:, &operation)
    EltenAPI::Tasks.run(
      title: _("Computer is thinking"),
      ui: form,
      cancellable: false,
      cancellation_token: cancellation_token,
      &operation
    )
  end

  def cancel_bot_decision(token, reason)
    return false if token == nil

    Log.debug(
      "ELTEN Game Room bot cancellation requested " \
      "table=#{table_id} session=#{@repository.session_id(@session)} reason=#{reason}"
    )
    token.cancel
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rescue Exception
    Time.now.to_f
  end

  def log_signal_timing(stage, signal_received_at, stage_started_at: nil, details: nil)
    return if signal_received_at == nil

    now = monotonic_time
    fields = [
      "ELTEN Game Room timing",
      "stage=#{stage}",
      "signal_to_stage_ms=#{((now - signal_received_at.to_f) * 1_000).round(1)}"
    ]
    if stage_started_at != nil
      fields << "stage_ms=#{((now - stage_started_at.to_f) * 1_000).round(1)}"
    end
    fields << details.to_s if details != nil && !details.to_s.empty?
    Log.debug(fields.join(" "))
  end

end
