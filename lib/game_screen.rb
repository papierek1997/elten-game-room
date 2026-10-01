require_relative 'game_event_presenter'
require_relative "network_task"
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
require_relative "board_preferences"

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
    save_table_history: nil,
    save_game: nil,
    edit_options: nil,
    abort_game: nil,
    leave_table: nil,
    game_services: {}
  )
    @layout = layout
    @manage_computer = manage_computer
    @manage_observer = manage_observer
    @manage_teams = manage_teams
    @save_table_history = save_table_history
    @save_game = save_game
    @edit_options = edit_options
    @abort_game = abort_game
    @leave_table = leave_table
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
    @board_preferences = GameRoomBoardPreferences.new(program, game)
    @game.board_presentation_preferences = @board_preferences.values
    @selected_surface_action = nil
    @history_index = 0
    @users_index = 0
    @form_index = 0
    @focus_location = [:game, 0]
    @surface_identity = nil
    @pending_event_ids = []
    @history_follows_tail = true
    @new_session_id = nil
    @automatic_recovery_pending = false
    @focus_new_game = false
    @pending_signal_received_at = nil
    @suppress_surface_focus = false
    @latest_wait_replay = nil
    @rules_shortcut_snapshot = nil
    @activity_entries = nil
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
  end

  def attach_table_layout(layout)
    @layout = layout
    if layout != nil
      layout.form.game_room_program = @program
      # The waiting-room refresh may have announced a last activity between
      # uncovering the window and adopting this prestarted game screen.
      if event_presenter.last_seen_activity_id != nil
        event_presenter.last_seen_activity_id = [event_presenter.last_seen_activity_id.to_i, layout.activity_cursor.to_i].max
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
    event_presenter.last_seen_event_id = @session["__event_id_base"].to_i
    event_presenter.last_seen_activity_id = activity_cursor
    start_game_client if @game.background_client?
    start_session_runner
    self
  end

  def close_covered_session
    stop_session_runner
    event_presenter.event_presentation&.close
    @game_client&.close
  end

  def table_activity_cursor; event_presenter.last_seen_activity_id; end

  def run
    return :back unless start_game_client
    start_session_runner
    loop do
      signal_received_at = @pending_signal_received_at
      using_cached_payload = false
      snapshot_started_at = monotonic_time
      log_signal_timing("snapshot_started", signal_received_at)
      presentation_only = @presentation_refresh_requested && @last_game_payload != nil
      @presentation_refresh_requested = false
      payload = presentation_only ? @last_game_payload : nil
      payload = fetch_game_payload unless presentation_only || @synchronizer.waiting?
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
      next if !departed_players.empty? && replace_departed_players(departed_players)
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
      verify_pending_move(replay) unless using_cached_payload

      if !@session["__frozen"] && !replay.finished? && !using_cached_payload && perform_automatic_action(replay)
        @suppress_surface_focus = true
        next
      end
      @game_client&.after_events(replay, Session.name, context: action_context)
      revision = @repository.events_revision(snapshot.events)
      action = wait_for_action(replay, revision)
      if @latest_wait_replay != nil
        replay = @latest_wait_replay
        @latest_wait_replay = nil
      end

      case action
      when :game_action
        accepted = submit_action(replay)
        clear_chat_draft(receipt: @chat_submission) if accepted && @clear_chat_after_action
        @chat_submission = nil
        @clear_chat_after_action = false
        @suppress_surface_focus = true
      when :new_session
        return :back if switch_to_new_session == false
      when :rules
        show_game_rules(replay)
      when :save_table_history
        @save_table_history&.call(combined_history_entries(replay))
        @suppress_surface_focus = true
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
      when :back
        # The confirmation is a covered view, not a departure. Keep the
        # runner, realtime client and presentation alive until leaving succeeds.
        if @leave_table
          unless @leave_table.call(@table)
            @suppress_surface_focus = true
            next
          end
          stop_pending_speech
          return :left_table
        end
        stop_pending_speech
        return :back
      when :room_closed
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
    event_presenter.event_presentation&.close
    @game_client&.close
    @layout&.begin_bindings
    @layout.game_client = nil if @layout
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
      activity_repository: @activity_repository, covered: @runner_covered || -> {
        GameRoomBackgroundPolicy.covered?(@presentation_ui_thread, program: @program, form: -> { @layout&.form })
      }).start
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
  # refresh controls, focus, input or local dialogs. A realtime client receives
  # copied durable state; its independent active-UI timer advances the engine.
  # The same event/activity cursors and sound queue are used before/after cover.
  def present_background_session(runner)
    return if event_presenter.last_seen_event_id == nil
    packet = runner.presentation_snapshot
    if packet && !packet.equal?(@background_presented_snapshot)
      @background_presented_snapshot = packet
      data = Marshal.load(Marshal.dump(packet))
      @background_timer_data = nil
      present_session_membership(data[:members])
      if @game.background_client? && !data[:session]["__aborted"]
        start_game_client(session: data[:session], owner: data[:session]["__table_owner"] || @table_owner)
        @game_client.update_table_control(data[:session]) if @game_client&.respond_to?(:update_table_control)
        @game_client&.before_wait(data[:replay], Session.name)
      end
      process_new_table_activity(data[:replay], entries: data[:activity], background: true)
      if !data[:session]["__aborted"] && prepare_presentation_session(data[:session], background: true)
        @background_timer_data = data
        process_new_events(data[:replay], session: data[:session], background: true)
      elsif data[:session]["__aborted"] && @game.background_client?
        @game_client&.close
      end
    end
    event_presenter.event_presentation&.advance
    if @background_timer_data
      data = @background_timer_data
      clock = @action_clock ||= GameRoomSessionClock.new
      now = clock.public_send(@game.precise_action_clock? ? :now_f : :now, data[:session])
      announce_due_timers(data[:replay], now: now)
      if @game.background_client?
        runner.publish_view(session: data[:session], replay: data[:replay], busy: event_presentation_busy?,
          context: action_context(session: data[:session], table_owner: data[:session]["__table_owner"] || @table_owner))
      end
    end
  end

  def background_session_closed
    @game_client&.close if @game.background_client?
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



  # Do not reconnect across an automatic realtime point submission.
  def recovery_allowed?(automatic_due)
    return true if connection_recovery_pending? || @new_session_id != nil

    !automatic_due
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

      payload = shortcut.payload
      if @layout&.form&.game_room_pending_operation && %w[navigate_playable_card navigate_playable_tile].include?(shortcut.action_name.to_s)
        payload = payload.merge("auto_action" => nil, "auto_card_id" => nil)
      end
      result = surface.handle_command(shortcut.action_name, payload)
      return result if result.is_a?(GameSurfaces::Action)

      if result && @board_preferences && @board_preferences.remember(shortcut.action_name, @board_view_spec, surface.state)
        @game.board_presentation_preferences = @board_preferences.values
        return :inline_refresh if shortcut.action_name == "toggle_player_labels"
      end

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
    if @layout&.form&.game_room_pending_operation
      @layout.form.open_game_room_background_help(form)
    else
      form.wait
    end
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

  def start_game_client(session: @session, owner: @table_owner)
    id = @repository.session_id(session)
    return true if @game_client && @client_session_id == id
    @game_client&.close
    @game_client = @game.build_client(@program, **@game_services)
    @client_session_id = id
    if @game_client.respond_to?(:bind_screen)
      @game_client.bind_screen(session_id: id, table_id: table_id,
        owner: owner, viewer: Session.name, members: -> { game_recipients })
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
    if @client_session_id != @repository.session_id(session)
      @game_client&.close
      @game_client = nil
    end
    @session = session
    @new_session_id = nil
    prepare_presentation_session(session)
    @presentation_refresh_requested = false
    @automatic_recovery_pending = false
    @focus_new_game = true
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

  def fetch_game_payload
    network_task(_("Updating game"), ui: refresh_input_ui,
      silent: @automatic_recovery_pending || @new_session_id != nil) do
      @synchronizer.synchronize(complete: @new_session_id == nil) do
        room = @room_snapshot || @room_snapshot_provider.call
        # Notifications carry persisted events. Only failed/uncertain reads
        # bypass local stack metadata; retain the complete room projection.
        snapshot = @repository.snapshot_for(@session,
          force_events: @automatic_recovery_pending && !@synchronizer.reconciled?)
        [snapshot, room, @activity_entries || activity_entries_for(room)]
      end
    end
  end

  def replace_departed_players(players)
    network_task(_("Updating table"), ui: :none) do
      replaced = false
      players.each do |seat|
        current = @repository.snapshot_for(@session).session
        guard = @repository.control_change_guard(table: @table, game: @game, session: current, player: seat)
        replaced = @game_services[:transport].set_seat_controller(@table,
          session_id: @repository.session_id(@session), seat: seat, bot: true, control_guard: guard) || replaced
      end
      replaced
    end
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
   event_presenter.last_seen_activity_id = @layout.activity_cursor if !background && event_presenter.last_seen_activity_id == nil && @layout != nil
   changed = event_presenter.process_table_activity(entries, viewer: Session.name,
     text: ->(entry) { @activity_repository&.text_for(entry, game_name: @game_name, global: false) })
   follow_presentation_history(replay) if !background && changed
   @layout.activity_cursor = event_presenter.last_seen_activity_id if !background && @layout != nil
 end

  def submit_chat
    pending_message = @pending_chat_message
    @pending_chat_message = nil
    message = (pending_message == nil ? @chat_text : pending_message).to_s.strip
    return if message.empty? || @send_chat == nil

    receipt = @chat_submission
    @chat_submission = nil

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
    clear_chat_draft(receipt: receipt)
  end

  def clear_chat_draft(receipt: nil)
    if receipt
      return false unless receipt.clear_if_current(@chat_control, session_id: @layout&.session_id)
    end
    @chat_text = ""
    @chat_index = 0
    @chat_check = 0
    if @chat_control != nil && receipt == nil
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

  def action_context(session: @session, table_owner: @table_owner)
    GameRoomGames::ActionContext.new(
      session_id: @repository.session_id(session),
      table_id: table_id,
      hidden_submissions: @hidden_submissions,
      random_source: @random_source,
      options: @game.options_from_json(session["options"]),
      table_owner: table_owner,
      local_data: @game_client&.context_data,
      now: (@action_clock ||= GameRoomSessionClock.new).public_send(@game.precise_action_clock? ? :now_f : :now, session)
    )
  end

  def action_time
    (@action_clock ||= GameRoomSessionClock.new).public_send(@game.precise_action_clock? ? :now_f : :now, @session)
  end

  def automatic_actor_for(replay)
    @game.automatic_actor(replay, Session.name, table_owner: @table_owner)
  end

  def game_recipients
    packet = @session_runner&.presentation_snapshot
    return packet[:members] if packet
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

  def table_presentation_covered?
    return @session_runner.covered? if @session_runner
    return @runner_covered.call if @runner_covered
    defined?($currentthread) && $currentthread && @presentation_ui_thread &&
      !@presentation_ui_thread.equal?($currentthread)
  end

  def speak_table_automatically(message)
    return unless GameRoomBackgroundPolicy.speech?(@program, covered: table_presentation_covered?)
    speak(message, stop: false, break_sequence: false)
  end

  def event_presenter
    @event_presenter ||= GameRoomEventPresenter.new(
      game: -> { @game }, repository: -> { @repository }, program: -> { @program }, viewer: -> { Session.name },
      client: -> { @game_client }, surface_state: -> { @surface_state }, clock: -> { monotonic_time },
      covered: -> { table_presentation_covered? }, speech: ->(message) { speak_table_automatically(message) },
      trace: method(:log_signal_timing), session_changed: -> { @background_timer_data = nil },
      history_changed: ->(replay, initial) { follow_presentation_history(replay, initial: initial) }
    )
  end

  def follow_presentation_history(replay, initial: false)
    @history_index = [combined_history_items(replay).length - 1, 0].max if initial || @history_follows_tail
  end

  def event_presentation_busy?(*args, **options)
    event_presenter.event_presentation_busy?(*args, **options)
  end

  def prepare_presentation_session(*args, **options)
    event_presenter.prepare_presentation_session(*args, **options)
  end

  def process_new_events(*args, session: @session, **options)
    event_presenter.process_new_events(*args, session: session, **options)
  end

  def present_game_event(*args, **options)
    event_presenter.present_game_event(*args, **options)
  end

  def present_turn_transition(*args, **options)
    event_presenter.present_turn_transition(*args, **options)
  end

  def present_initial_decision(*args, **options)
    event_presenter.present_initial_decision(*args, **options)
  end

  def present_required_decision(*args, **options)
    event_presenter.present_required_decision(*args, **options)
  end

  def present_game_result(*args, **options)
    event_presenter.present_game_result(*args, **options)
  end

  def event_replays_for(*args, session: @session, **options)
    event_presenter.event_replays_for(*args, session: session, **options)
  end

  def presentation_replay(*args, **options)
    event_presenter.presentation_replay(*args, **options)
  end

  def remember_turn_transition(*args, **options)
    event_presenter.remember_turn_transition(*args, **options)
  end

  def merge_turn_history!(*args, **options)
    event_presenter.merge_turn_history!(*args, **options)
  end

  def normalize_event_descriptions(*args, **options)
    event_presenter.normalize_event_descriptions(*args, **options)
  end

  def announce_due_timers(replay, now: action_time)
    event_presenter.announce_due_timers(replay, now: now)
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

    task = GameRoomNetworkTask.new
    pending_table_id = table_id if @layout&.binding_generation.to_i > 0
    task.run(title, layout: @layout, table_id: pending_table_id, ui: ui,
      client: @game_client, runner: @session_runner,
      before_close: -> { remember_layout_position }, &operation)
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
    task&.close
  end

  def remember_layout_position(layout = @layout)
    snapshot = layout.snapshot
    @surface_state, @surface_identity = snapshot.surface_state, snapshot.surface_identity
    @history_index, @history_follows_tail = snapshot.history_index, snapshot.history_follows_tail
    @users_index, @form_index, @focus_location = snapshot.users_index, snapshot.form_index, snapshot.focus_location
    @chat_text, @chat_index, @chat_check = snapshot.chat_text, snapshot.chat_index, snapshot.chat_check
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

require_relative 'game_screen/input'
