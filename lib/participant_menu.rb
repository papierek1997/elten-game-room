require_relative "game_participants"
require_relative "game_rules"
require_relative "context_help"

# One native global menu for the waiting room, active game and final-position
# view. Removing/replacing a participant belongs to the selected Users row.
require_relative "game_room_localization"

module GameRoomParticipantMenu
  using GameRoomLocalization::Translations
  Entry = Struct.new(:action, :label, :menu_key, :help_key, keyword_init: true)

  module_function

  def entries(game: nil)
    [
      Entry.new(action: :invite_online, label: _("Invite an online Elten user"), menu_key: "i", help_key: "Ctrl+I"),
      Entry.new(action: :invite_contacts, label: _("Invite someone from your contacts"), menu_key: "I", help_key: "Ctrl+Shift+I"),
      Entry.new(action: :add_bot, label: _("Add a computer"), menu_key: "o", help_key: "Ctrl+O"),
      Entry.new(action: :observe_next_game, label: _("Observe the next game"), menu_key: "O", help_key: "Ctrl+Shift+O"),
      Entry.new(action: :play_next_game, label: _("Play in the next game"), menu_key: "O", help_key: "Ctrl+Shift+O"),
      Entry.new(action: :rules, label: _("Game rules"), menu_key: :ctrl_f1, help_key: "Ctrl+F1"),
      Entry.new(action: :table_options, label: _("Read the table variant and settings"), menu_key: "r", help_key: "Ctrl+R"),
      personal_settings_entry(game),
      Entry.new(action: :edit_options, label: _("Change settings for the next game"), menu_key: "x", help_key: "Ctrl+X"),
      Entry.new(action: :edit_teams, label: _("Choose teams"), menu_key: ""),
      Entry.new(action: :abort_game, label: _("End the current game without closing the table"), menu_key: "q", help_key: "Ctrl+Q"),
      Entry.new(action: :save_table_history, label: _("Save table history"), menu_key: "S", help_key: "Ctrl+Shift+S"),
      Entry.new(action: :save_game, label: _("Save the game and close the table"), menu_key: "s", help_key: "Ctrl+S"),
      Entry.new(action: :close_table, label: _("Close the table for everyone"), menu_key: ""),
      Entry.new(action: :leave, label: _("Leave"), menu_key: "")
    ].compact
  end

  def personal_settings_entry(game)
    label = game&.personal_settings_label
    return nil if label == nil

    Entry.new(action: :personal_settings, label: GameRoomContent.utf8(label), menu_key: "p", help_key: "Ctrl+P")
  end

  # The game describes an action, while this UI boundary chooses the waiting
  # room or the active client. Active clients retain their modal timer/tick.
  def settings_callback(game, program: nil, client: nil)
    action = game&.personal_settings_action
    return nil if action == nil
    return -> { client.show_settings } if client.respond_to?(:show_settings)
    return -> { program.__send__(action) } if program

    nil
  end

  def replacement_entry
    Entry.new(action: :replace_player, label: _("Replace this player"), menu_key: "R", help_key: "Ctrl+Shift+R")
  end

  def replacement_candidates(room:, players:, participant:, game:)
    return [] unless GameRoomParticipants.includes?(players, participant)

    candidates = GameRoomParticipants.humans(room.members).reject { |person| GameRoomParticipants.includes?(players, person) }
    candidates << :new_bot if GameRoomParticipants.human?(participant) && game&.supports_bots?
    candidates
  end

  def management_actions(room:, game:, active:, viewer:, owner:, restoring: false)
    return [] if room == nil || active || restoring || !GameRoomParticipants.same?(viewer, owner)

    actions = []
    maximum = game == nil ? 0 : [room.table["max_players"].to_i, game.maximum_players.to_i].min
    actions << :add_bot if game&.supports_bots? && room.participants.length < maximum
    actions << :remove_bot if !room.bots.to_a.empty?
    actions
  end

  def role_actions(room:, viewer:, owner: nil)
    return [] if room == nil || GameRoomParticipants.bot?(viewer)
    return [] if !GameRoomParticipants.includes?(room.members, viewer)

    actions = room.observer?(viewer) ? [:play_next_game] : [:observe_next_game]
    actions << :manage_roles if owner && GameRoomParticipants.same?(viewer, owner)
    actions.concat([:manage_control, :close_table]) if owner && GameRoomParticipants.same?(viewer, owner)
    actions
  end

  def lifecycle_actions(active:, viewer:, owner:, restoring: false, frozen: false, compatible: true)
    return [] unless GameRoomParticipants.same?(viewer, owner)
    return [] if restoring || frozen || !compatible
    active ? [:abort_game] : [:edit_options]
  end

  def bind(layout, available:, read_options: nil, game: nil, options: nil, settings: nil, pong_settings: nil, room: nil, control: nil, user_menu: nil, &dispatch)
    # Keep the former keyword as a compatibility alias for its host action.
    settings ||= pong_settings if game&.personal_settings_action == :show_pong_settings
    if user_menu
      layout.users.on(:select) do
        participant = layout.selected_participant.to_s.dup
        next if participant.empty? || !GameRoomParticipants.human?(participant)

        # The row is a presentation, not a login. Capture the real identity
        # before the native menu can open another scene or update the roster.
        result = user_menu.call(participant)
        if result != "ALT" && layout.form.fields[layout.form.index.to_i].equal?(layout.users)
          layout.users.focus
        end
      end
    end
    supplied = available
    available = -> do
      actions = supplied.call + (read_options == nil ? [] : [:table_options])
      actions << :personal_settings if settings && game&.personal_settings_action
      actions -= [:invite_online, :invite_contacts] if game && !game.table_invitations_allowed?(options.to_h)
      actions -= [:observe_next_game, :play_next_game, :manage_roles] if game && !game.role_selection_allowed?(options.to_h)
      actions
    end
    layout.form.bind_context do |menu|
      actions = available.call
      entries(game: game).each do |entry|
        next if !actions.include?(entry.action)

        # Ctrl+X belongs to the text editor while typing. The same command is
        # still available by selecting its context-menu item with the arrows.
        focused = layout.form.fields[layout.form.index.to_i]
        key = entry.action == :edit_options && focused.is_a?(EditBox) ? "" : entry.menu_key
        menu.option(entry.label, nil, key) do
          next if !available.call.include?(entry.action)
          if layout.form.game_room_pending_operation && ![:table_options, :rules].include?(entry.action)
            next layout.form.game_room_pending_operation.reject_action
          end

          if entry.action == :table_options
            read_options.call
          elsif entry.action == :personal_settings
            settings.call
          else
            dispatch.call(entry.action, nil)
          end
        end
      end
    end

    add_context_help(layout, available, game: game)
    # Resolve per-row actions when help is opened, as the selection and owner
    # can change without rebuilding the whole form.
    layout.users.game_room_context_help_provider = lambda do
      tips = context_tips(available.call, game: game)
      participant = layout.selected_participant
      snapshot = room&.call
      if available.call.include?(:manage_control) && snapshot
        if transfer_candidate?(snapshot, participant)
          tips << GameRoomContextHelp.shortcut_tip("Ctrl+M", _("Transfer table master to this person"))
        end
        seats = control&.call
        if seats&.dig(:active) && GameRoomParticipants.includes?(seats[:players], participant)
          entry = replacement_entry
          tips << GameRoomContextHelp.shortcut_tip(entry.help_key, entry.label)
        end
      end
      tips
    end
    GameRoomRules.bind_ctrl_f1(layout.form, []) do
      dispatch.call(:rules, nil) if available.call.include?(:rules)
    end

    layout.users.bind_context do |menu|
      actions = available.call
      participant = layout.selected_participant
      if actions.include?(:remove_bot) && GameRoomParticipants.bot?(participant)
        menu.option(_("Remove computer"), nil, :del) do
        # Keep the original row for the UI's permission/type check, even if a
        # remote update moves the selection. The repository removes one
        # numbered computer slot using its unchanged count operation.
          dispatch.call(:remove_bot, participant) if available.call.include?(:remove_bot)
        end
      end
      snapshot = room&.call
      if actions.include?(:manage_control) && snapshot
        if transfer_candidate?(snapshot, participant)
          menu.option(_("Transfer table master to this person"), nil, "m") do
            current = room&.call
            if available.call.include?(:manage_control) && current && transfer_candidate?(current, participant)
              dispatch.call(:transfer_master, participant)
            end
          end
        end
        seats = control&.call
        if seats && seats[:active] && GameRoomParticipants.includes?(seats[:players], participant)
          entry = replacement_entry
          menu.option(entry.label, nil, entry.menu_key) do
            current = control&.call
            if available.call.include?(:manage_control) && current&.dig(:active) && GameRoomParticipants.includes?(current[:players], participant)
              dispatch.call(:replace_player, participant)
            end
          end
        end
      end
      if actions.include?(:manage_roles) && snapshot && GameRoomParticipants.human?(participant) &&
          GameRoomParticipants.includes?(snapshot.members, participant) && !GameRoomParticipants.same?(participant, Session.name)
        observing = snapshot.observer?(participant)
        label = observing ? _("Make a player for the next game") : _("Make an observer for the next game")
        menu.option(label) do
          dispatch.call(observing ? :make_player : :make_observer, participant) if available.call.include?(:manage_roles)
        end
      end
    end
  end

  def add_context_help(layout, actions, game: nil)
    layout.form.fields.reject { |field| field.equal?(layout.back_button) }.each do |field|
      resolve = -> { context_tips(actions.respond_to?(:call) ? actions.call : actions, game: game, text: field.is_a?(EditBox)) }
      GameRoomContextHelp.replace([field], resolve.call)
      field.game_room_context_help_provider = resolve
    end
  end

  def transfer_candidate?(room, participant)
    GameRoomParticipants.human?(participant) && GameRoomParticipants.includes?(room.members, participant) &&
      !GameRoomParticipants.same?(participant, Session.name)
  end

  def context_tips(actions, game: nil, text: false)
    entries(game: game).filter_map do |entry|
      next if !actions.include?(entry.action) || entry.help_key == nil
      next if text && entry.action == :edit_options

      GameRoomContextHelp.shortcut_tip(entry.help_key, entry.label)
    end
  end
end
