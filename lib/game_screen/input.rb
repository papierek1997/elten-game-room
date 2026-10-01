require_relative '../game_room_localization'

class GameScreen
  WaitState = Struct.new(:replay, :revision, :action, keyword_init: true)
  WaitView = Struct.new(:layout, :silent_entry, :announce_finished_focus, keyword_init: true)

  module Input
    using GameRoomLocalization::Translations
    private

    def wait_for_action(replay, revision)
      replay = event_presenter.event_presentation.visible_replay if event_presentation_busy? && event_presenter.event_presentation.visible_replay != nil
      wait = WaitState.new(replay: replay, revision: revision)
      view = prepare_action_view(replay)
      layout = view.layout
      form = layout.form
      remember_position = -> { remember_layout_position(layout) }
      bind_wait_status(wait, layout, remember_position)
      bind_wait_shortcuts(wait, layout, remember_position)
      bind_wait_history(wait, layout, remember_position)
      bind_wait_participants(wait, layout, remember_position)
      bind_wait_restart(wait, layout, remember_position)
      bind_wait_surface(wait, layout, remember_position)
      bind_wait_chat(wait, layout, remember_position)
      bind_wait_timer(wait, layout, remember_position)
      if view.announce_finished_focus
        speech_wait
        form.wait
      elsif !view.silent_entry
        form.wait
      else
        layout.wait_without_announcement
      end
      loop do
        break if handle_wait_result(wait, layout)
        wait.action = nil
        layout.wait_without_announcement
      end
      @latest_wait_replay = wait.replay
      wait.action
    ensure
      @rules_shortcut_snapshot = if wait&.action == :rules && @layout != nil
        GameRoomContextHelp.game_field_tips(@layout.game_help_fields)
      end
    end

    def handle_wait_result(wait, layout)
      case wait.action
      when :inline_game_action then handle_inline_wait(wait, layout)
      when :check_signal then handle_signal_wait(wait, layout)
      when :room_refresh then handle_room_wait(wait, layout)
      when :recovery_refresh then handle_recovery_wait(wait, layout)
      else true
      end
    end

    def prepare_action_view(replay)
      user_items = room_user_items(replay)
      @game.board_presentation_preferences = @board_preferences.values
      @game.prepare_view(replay, Session.name, context: action_context)
      view_spec = @game.game_view_spec(replay, Session.name)
      @board_view_spec = view_spec.surface
      @surface_state = @board_preferences.restore(@board_view_spec, @surface_state)
      history_items = combined_history_items(replay)
      phase = replay.finished? ? :finished : :active
      @finished_at = phase == :finished ? (@layout&.phase == :active ? monotonic_time : @finished_at) : nil
      phase_changed = @layout != nil && (@layout.phase != phase || @focus_new_game == true)
      if @layout == nil
        @layout = GameRoomLayout::Screen.new(
          view_spec: view_spec, surface_state: @surface_state, history_items: history_items, user_items: user_items,
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
      @layout.game_client = @game_client
      layout = @layout
      layout.begin_bindings
      layout.back_button.label = _("Leave")
      layout.activity_cursor = event_presenter.last_seen_activity_id
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
      form = layout.form
      form.game_room_background_help_enabled = true

      WaitView.new(layout: layout, silent_entry: silent_entry, announce_finished_focus: announce_finished_focus)
    end

    def bind_wait_status(wait, layout, remember_position)
      form = layout.form
      layout.bind_status_commands do |command|
        next if wait.action != nil
        remember_position.call
        @selected_surface_action = {"kind" => "command", "action" => command}
        wait.action = :game_action
        form.resume
      end
    end

    def bind_wait_shortcuts(wait, layout, remember_position)
      surface = layout.surface
      form = layout.form
      history = layout.history
      shortcuts = normalized_game_shortcuts(@game.game_shortcuts(wait.replay, Session.name))
      handle_shortcut = lambda do |shortcut|
        pending = form.game_room_pending_operation
        if pending
          next pending.reject_action unless pending.safe_shortcut?(shortcut)
        else
          next if wait.action != nil
        end
        next if event_presentation_busy? && ![:announcement, :browse, :surface].include?(shortcut.kind)
        next if @session["__frozen"] && ![:announcement, :browse, :surface].include?(shortcut.kind)

        active_shortcut = refreshed_announcement_shortcut(shortcut, wait.replay, Session.name)
        selection = activate_game_shortcut(active_shortcut, surface, replay: wait.replay)
        if active_shortcut.kind == :staged_form && @latest_wait_replay != nil
          # Preparing an offer has already committed a real event. Continue from
          # that confirmed revision; otherwise the wait's old replay overwrites
          # it and the executor correctly rejects the final proposal as stale.
          wait.replay = @latest_wait_replay
          wait.revision = @repository.events_revision(wait.replay.accepted_events)
          @latest_wait_replay = nil
        end
        if selection == :surface_handled
          if active_shortcut.payload["focus_surface"] == true
            field_index = surface.respond_to?(:command_field_index) ? surface.command_field_index : 0
            layout.focus_game(field_index: field_index || 0, silent: true)
          end
          remember_position.call
          refresh_history_control(history, wait.replay) if @game.history_presentation_depends_on_surface_state?
          next
        end
        if selection == :inline_refresh
          remember_position.call
          if pending
            refresh_history_control(history, wait.replay)
            next
          end
          wait.action = :refresh
          form.resume
          next
        end
        next if selection == nil || @session["__frozen"] || event_presentation_busy?

        remember_position.call
        @selected_surface_action = selection
        wait.action = :game_action
        form.resume
      end
      bind_game_shortcuts(
        form,
        layout.shortcut_fields,
        shortcuts,
        &handle_shortcut
      )
    end

    def bind_wait_history(wait, layout, remember_position)
      form = layout.form
      history = layout.history
      bind_history_navigation(form) do |operation, value|
        entries = combined_history_entries(wait.replay)
        message = @history_navigator.navigate(entries, operation, value, view: history,
          focused: form.fields[form.index.to_i].equal?(history))
        speak(message.to_s) if !message.to_s.empty?
      end
    end

    def bind_wait_participants(wait, layout, remember_position)
      form = layout.form
      GameRoomParticipantMenu.bind(layout, available: -> do
        actions = [:rules, :leave]
        actions << :save_table_history if @save_table_history != nil
        actions << :save_game if @save_game != nil && same_user?(@table_owner, Session.name)
        compatible = !@table.key?("__discovery_protocol") || @table["__discovery_protocol"].to_i >= GameRoomLiveSessionStore::CURRENT_DISCOVERY_PROTOCOL
        if compatible && same_user?(@table_owner, Session.name) && !@session["__frozen"]
          actions << :edit_options if wait.replay.finished? && @edit_options != nil
          if wait.replay.finished? && @manage_teams && @room_snapshot && @game.team_assignment(
              @game.options_from_json(@room_snapshot.table["game_options"]), players: @room_snapshot.game_participants)
            actions << :edit_teams
          end
          actions << :abort_game if !wait.replay.finished? && @abort_game != nil
        end
        actions << :invite_online if @invite_online != nil
        actions << :invite_contacts if @invite_contacts != nil
        if @manage_observer != nil
          actions.concat(GameRoomParticipantMenu.role_actions(room: @room_snapshot, viewer: Session.name, owner: @table_owner))
        end
        if @manage_computer != nil
          actions.concat(GameRoomParticipantMenu.management_actions(
            room: @room_snapshot, game: @game, active: !wait.replay.finished?, viewer: Session.name, owner: @table_owner
          ))
        end
        actions
      end, game: @game, options: @game.options_from_json(@session["options"]), room: -> { @room_snapshot },
        user_menu: ->(user) { @program.__send__(:usermenu, user) if wait.action == nil },
        control: -> { {active: !wait.replay.finished?, players: @repository.players_for(@session), controllers: @session.fetch('__controllers', {})} },
        settings: GameRoomParticipantMenu.settings_callback(@game, client: @game_client),
        read_options: -> {
        source = wait.replay.finished? ? @room_snapshot&.table.to_h["game_options"] : @session["options"]
        speak(@game.table_options_announcement(@game.options_from_json(source)))
      }) do |requested, participant|
        if form.game_room_pending_operation
          if requested == :rules
            show_game_rules(wait.replay)
          else
            form.game_room_pending_operation.reject_action
          end
          next
        end
        next if wait.action != nil

        remember_position.call
        @selected_participant = participant
        wait.action = requested == :leave ? :back : requested
        form.resume
      end
    end

    def bind_wait_restart(wait, layout, remember_position)
      form = layout.form
      layout.restart_button.on(:press) do
        next if wait.action != nil || !wait.replay.finished? || !same_user?(@table_owner, Session.name)
        next if event_presentation_busy?
        next if @finished_at && monotonic_time - @finished_at < @game.restart_guard_seconds.to_f

        remember_position.call
        wait.action = :restart
        form.resume
      end
    end

    def bind_wait_surface(wait, layout, remember_position)
      surface = layout.surface
      form = layout.form
      back_button = layout.back_button
      surface.on_action do |selection|
        next if wait.action != nil
        next if @session["__frozen"]
        if selection["kind"] == "surface" && selection["action"] == "refresh"
          remember_position.call
          wait.action = :presentation_refresh
          form.resume_for_refresh
          next
        end
        next if event_presentation_busy?


        if selection["_stay_open"] == true
          remember_position.call
          @selected_surface_action = selection
          wait.action = :inline_game_action
          form.resume
        else
          remember_position.call
          @selected_surface_action = selection
          wait.action = :game_action
          form.resume
        end
      end
      @game_client.attach_view(form, surface) if @game_client.respond_to?(:attach_view)
      back_button.on(:press) do
        next form.game_room_pending_operation.reject_action if form.game_room_pending_operation
        next if wait.action != nil
        if surface.cancel_pending_action?
          surface.cancel_pending_action!
          remember_position.call
        else
          remember_position.call
          wait.action = :back
          form.resume
        end
      end
    end

    def bind_wait_chat(wait, layout, remember_position)
      surface = layout.surface
      form = layout.form
      chat = layout.chat
      chat.on_submit do
        next if wait.action != nil

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
          @chat_submission = GameRoomUI::ChatSubmission.capture(chat, session_id: layout.session_id)
          @pending_chat_message = submission.text
          wait.action = :chat
          form.resume
        elsif submission.kind == :movement
          next if @session["__frozen"] || event_presentation_busy?
          @chat_submission = GameRoomUI::ChatSubmission.capture(chat, session_id: layout.session_id)
          @selected_surface_action = submission.action
          @clear_chat_after_action = true
          wait.action = :game_action
          form.resume
        end
      end
    end

    def bind_wait_timer(wait, layout, remember_position)
      surface = layout.surface
      form = layout.form
      form.add_timer(FormTimer.new(TIMER_INTERVAL, repeat: true) do
        next if form.game_room_pending_operation
        next if wait.action != nil

        presentation_changed = event_presenter.event_presentation&.advance
        @game_client&.tick
        announce_due_timers(wait.replay)
        publish_session_view(wait.replay, surface)
        automatic_due = automatic_action_due?(wait.replay)
        sync_event = @synchronizer.next_event(
          allow_recovery: recovery_allowed?(automatic_due)
        )
        local_action = if @session_runner || wait.replay.finished? || connection_recovery_pending? || event_presentation_busy? || presentation_changed
          nil
        else
          @game.automatic_surface_action(
            wait.replay,
            Session.name,
            surface: surface,
            context: action_context
          )
        end
        if local_action != nil && sync_event == nil
          remember_position.call
          @selected_surface_action = local_action
          wait.action = :game_action
          form.resume_for_refresh
          next
        end

        if sync_event&.kind == :closed
          wait.action = :room_closed
          form.resume_for_refresh
        elsif sync_event&.kind == :game_started
          remember_position.call
          @new_session_id = sync_event.session_id
          wait.action = :new_session
          form.resume_for_refresh
        elsif sync_event&.kind == :game_changed
          remember_position.call
          received_at = sync_event.received_at
          @pending_signal_received_at = received_at.is_a?(Numeric) ? received_at.to_f : monotonic_time
          log_signal_timing("signal_consumed", @pending_signal_received_at)
          # A LiveSessions wake-up only says that something may have changed.
          # Confirm the event revision before rebuilding the form so duplicate
          # or already-applied notifications stay invisible to the user.
          wait.action = :check_signal
          form.resume_for_refresh
        elsif sync_event&.kind == :table_changed
          remember_position.call
          wait.action = :room_refresh
          form.resume_for_refresh
        elsif sync_event&.kind == :recovery
          remember_position.call
          wait.action = :recovery_refresh
          form.resume_for_refresh
        elsif presentation_changed || @game_client&.refresh_due?
          remember_position.call
          wait.action = :presentation_refresh
          form.resume_for_refresh
        elsif automatic_due && !connection_recovery_pending?
          remember_position.call
          wait.action = :refresh
          form.resume_for_refresh
        end
      end)
    end

    def handle_inline_wait(wait, layout)
      selection = @selected_surface_action
      @selected_surface_action = nil
      inline_result = submit_inline_action(wait.replay, selection)
      if inline_result != nil
        wait.replay, inserted = inline_result
        newest_id = inserted.map { |event| @repository.event_id(event) }.max.to_i
        wait.revision = [wait.revision[0].to_i + inserted.length, [wait.revision[1].to_i, newest_id].max]
      end
      false
    end

    def handle_signal_wait(wait, layout)
      remote_action, remote_session_id = synchronized_network_task(
        _("Checking for game updates"),
        ui: refresh_input_ui, complete: false
      ) do
        remote_game_update(wait.revision)
      end || [nil, nil]
      if remote_action == :new_session
        @new_session_id = remote_session_id
        wait.action = :new_session
        return true
      elsif remote_action == :refresh
        wait.action = :refresh
        return true
      end
      @pending_signal_received_at = nil
      false
    end

    def handle_room_wait(wait, layout)
      history = layout.history
      users = layout.users
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
        room_update + (room_update.first == :updated ? remote_game_update(wait.revision) : [nil, nil])
      end || [:failed, nil, []]
      if room_status == :closed
        wait.action = :room_closed
        return true
      elsif room_status == :updated
        apply_room_snapshot(users, history, wait.replay, snapshot, activity_entries)
      end
      if remote_action == :new_session
        @new_session_id = remote_session_id
        wait.action = :new_session
        return true
      elsif remote_action == :refresh || (room_status == :updated && !departed_players_for_replacement(wait.replay, snapshot).empty?)
        wait.action = :refresh
        return true
      end
      false
    end

    def handle_recovery_wait(wait, layout)
      history = layout.history
      users = layout.users
      recovery_started_at = monotonic_time
      payload = synchronized_network_task(_("Updating game"), ui: refresh_input_ui) do
        recover_game_update(wait.revision)
      end
      room_status, snapshot, activity_entries, remote_action, remote_session_id = payload || [:failed, nil, [], nil, nil]
      Log.debug(
        "ELTEN Game Room connection recovery " \
        "table=#{table_id} session=#{@repository.session_id(@session)} " \
        "elapsed_ms=#{((monotonic_time - recovery_started_at) * 1_000).round(1)} " \
        "room_status=#{room_status} remote_action=#{remote_action || 'none'}"
      )
      if room_status == :closed
        wait.action = :room_closed
        return true
      end
      apply_room_snapshot(users, history, wait.replay, snapshot, activity_entries) if room_status == :updated
      if remote_action == :new_session
        @new_session_id = remote_session_id
        wait.action = :new_session
        return true
      elsif remote_action == :refresh || (room_status == :updated && !departed_players_for_replacement(wait.replay, snapshot).empty?)
        wait.action = :refresh
        return true
      end
      false
    end

  end

  include Input
end
