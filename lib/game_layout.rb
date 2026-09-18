require_relative "context_help"

module GameRoomLayout
  STANDARD_SECTIONS = [:status, :game, :chat, :history, :users].freeze

  class ViewSpec
    attr_reader :surface, :sections, :history_header, :history_empty_label,
      :trailing_parts, :restartable, :finished_text, :status_commands

    def initialize(surface: nil, history_header: nil, history_empty_label: nil,
      trailing_parts: [], restartable: true, finished_text: nil, status_commands: [])
      @trailing_parts = trailing_parts.map(&:to_s).freeze
      @sections = @trailing_parts.empty? ? STANDARD_SECTIONS : (STANDARD_SECTIONS + [:game_actions]).freeze
      @restartable = restartable
      @finished_text = finished_text
      @status_commands = status_commands.to_a.freeze
      @surface = surface
      @history_header = history_header == nil ? nil : history_header.to_s
      @history_empty_label = history_empty_label == nil ? nil : history_empty_label.to_s
    end
  end

  Snapshot = Struct.new(
    :surface_state,
    :history_index,
    :users_index,
    :form_index,
    :focus_location,
    :surface_identity,
    :history_follows_tail,
    :chat_text,
    :chat_index,
    :chat_check,
    keyword_init: true
  )

  module ShortcutFormBehavior
    def game_shortcut_keys=(keys)
      @game_shortcut_keys = keys.to_a.map do |key|
        key.to_s.sub(/\Akey_/, "").downcase
      end.uniq
    end

    def game_shortcut_signatures=(signatures)
      @game_shortcut_signatures = signatures.to_a.map do |key, modifiers|
        [key.to_s.sub(/\Akey_/, "").downcase, modifiers.to_a.map(&:to_sym).uniq.sort]
      end
      self.game_shortcut_keys = @game_shortcut_signatures.map(&:first)
    end

    def history_navigation_signatures=(signatures)
      @history_navigation_signatures = signatures.to_a.map do |key, modifiers|
        [key.to_s.sub(/\Akey_/, "").downcase, modifiers.to_a.map(&:to_sym).uniq.sort]
      end
    end

    def key_processed(key)
      normalized = key.to_s.sub(/\Akey_/, "").downcase
      modifiers = active_shortcut_modifiers
      if @history_navigation_signatures.to_a.include?([normalized, modifiers])
        return true if editable_text_field?

        return false
      end
      if @game_shortcut_keys.to_a.include?(normalized)
        if editable_text_field?
          return true if !modifiers.include?(:control) && !modifiers.include?(:alt)
          return false if @game_shortcut_signatures.to_a.include?([normalized, modifiers])

          return true
        end
        return false
      end

      super
    end

    private

    def editable_text_field?
      field = fields[index.to_i] if respond_to?(:fields) && respond_to?(:index)
      return false if !defined?(EditBox) || !field.is_a?(EditBox)

      flags = field.respond_to?(:flags) ? field.flags.to_i : field.instance_variable_get(:@flags).to_i
      (flags & EditBox::Flags::ReadOnly) == 0
    end

    def active_shortcut_modifiers
      modifiers = []
      modifiers << :shift if respond_to?(:raw_key_held?, true) && raw_key_held?(:key_shift)
      modifiers << :control if respond_to?(:modifier_held?, true) && modifier_held?(:main_modifier)
      modifiers << :alt if respond_to?(:modifier_held?, true) && modifier_held?(:option)
      modifiers.sort
    end
  end

  # These controls survive game updates. Install each native handler once,
  # then replace only our callbacks; leave the control's own handlers intact.
  module Bindings
    def reset_bindings!
      @screen_events = {}
      @screen_contexts = []
      @screen_timers.to_a.each { |timer| delete_timer(timer) }
      @screen_timers = []
    end

    def on(event, *arguments, &handler)
      @screen_events ||= {}
      @screen_event_proxies ||= {}
      unless @screen_event_proxies[event]
        super(event, *arguments) do |*params|
          @screen_events.fetch(event, []).dup.each { |callback| callback.call(*params) }
        end
        @screen_event_proxies[event] = true
      end
      (@screen_events[event] ||= []) << handler
    end

    def bind_context(header = "", &handler)
      unless @screen_context_proxy
        super(header) { |menu| @screen_contexts.to_a.each { |callback| callback.call(menu) } }
        @screen_context_proxy = true
      end
      (@screen_contexts ||= []) << handler
    end

    def add_timer(timer, *arguments)
      (@screen_timers ||= []) << timer
      super
    end

    def add_tip(tip)
      @screen_tips ||= []
      return if @screen_tips.include?(tip)

      @screen_tips << tip
      super
    end
  end

  class Screen
    attr_accessor :activity_cursor, :session_id
    attr_reader :surface, :history, :users, :chat, :back_button, :form,
      :primary_button, :restart_button, :waiting_status, :phase

    def initialize(
      view_spec:, surface_state: {}, history_items: [], user_items: [],
      history_index: nil, users_index: 0,
      focus_location: nil, previous_surface_identity: nil,
      users_header: "", chat_text: "", chat_index: 0, chat_check: 0,
      chat_control: nil, phase: :active, own_table: false
    )
      @surface_identity = previous_surface_identity
      @history_items = []
      @user_items = []
      @history = GameSurfaces::RefreshAwareListBox.new([], header: "", quiet: true)
      @users = GameSurfaces::RefreshAwareListBox.new([], header: "", quiet: true)
      @chat = chat_control || GameSurfaces::RefreshAwareEditBox.new(
        _("Chat"), text: chat_text.to_s, quiet: true, max_length: 400
      )
      @chat.restore_selection(index: chat_index, check: chat_check) if chat_control == nil
      @primary_button = Button.new(_("Start game"))
      @restart_button = Button.new(_("Restart game"))
      @waiting_status = GameSurfaces::RefreshAwareListBox.new([], header: "", quiet: true)
      @status_command_buttons = {}
      @back_button = Button.new(_("Leave"))
      @form = GameSurfaces::RefreshAwareForm.new([], index: 0, quiet: true)
      @preserved_hand_surface_state = nil
      @form.extend(ShortcutFormBehavior)
      binding_controls.each { |control| control.extend(Bindings) }
      update(
        view_spec: view_spec, surface_state: surface_state,
        history_items: history_items, user_items: user_items, users_header: users_header,
        phase: phase, own_table: own_table, focus_location: focus_location,
        history_index: history_index, users_index: users_index
      )
    end

    def begin_bindings
      binding_controls.each(&:reset_bindings!)
      GameRoomContextHelp.replace(@form.fields, [], source: :game)
      @form.game_shortcut_signatures = []
      @form.history_navigation_signatures = []
      @form.game_room_general_help_tips = []
    end

    def selected_participant
      item = @user_items[@users.index.to_i]
      item.respond_to?(:participant) ? item.participant : item&.to_s
    end

    def update_users(items, header: @users.header)
      selected = selected_participant
      previous_index = @users.index.to_i
      @user_items = items.to_a
      labels = @user_items.map(&:to_s)
      @users.options = labels if @users.options != labels
      selected_index = @user_items.index do |item|
        id = item.respond_to?(:participant) ? item.participant : item.to_s
        selected != nil && id.to_s.casecmp(selected.to_s) == 0
      end
      @users.index = selected_index || bounded_index(previous_index, labels)
      @users.header = header
    end

    def update_history(items, header: @history.header)
      follows_tail = focus_location.to_a[0] != :history || @history.index.to_i >= @history_items.length - 1
      old_index = @history.index.to_i
      @history_items = items.to_a.map(&:to_s)
      @history.options = @history_items if @history.options != @history_items
      @history.index = follows_tail ? [@history_items.length - 1, 0].max : bounded_index(old_index, @history_items)
      @history.header = header
    end

    def update(view_spec:, history_items:, user_items:, users_header:,
      phase: :active, own_table: false, surface_state: nil, focus_location: nil,
      history_index: nil, users_index: nil, reset_surface: false, new_game: false)
      raise ArgumentError, "a game screen requires a view specification" if !view_spec.is_a?(ViewSpec)

      # Phase transitions focus the first meaningful field: the start/restart
      # status before and after a game, and the game surface while it is active.
      # Ordinary updates preserve the user's field, including board inspection.
      phase_transition = @phase == nil || @phase != phase || new_game
      location = if phase_transition && phase == :active
        [:game, 0]
      elsif phase_transition
        [:status, 0]
      else
        focus_location || self.focus_location || [:status, 0]
      end
      old_identity = @surface_identity
      old_field = @form.fields[@form.index.to_i]
      hand_update = GameSurfaces.hand_surface?(view_spec.surface)
      previous_hand = GameSurfaces.hand_surface?(@view_spec&.surface)
      if new_game || reset_surface
        @preserved_hand_surface_state = nil
      elsif previous_hand && @surface != nil
        # A staged action may temporarily replace the hand with another
        # control, such as UNO's colour selector. Keep the hand cursor until
        # the hand returns instead of replacing it with the transient list's
        # position.
        @preserved_hand_surface_state = @surface.state
      end
      state = surface_state || @surface&.state || {}
      if hand_update && !previous_hand && @preserved_hand_surface_state != nil
        state = @preserved_hand_surface_state
      end
      if reset_surface || @view_spec == nil || @view_spec.surface != view_spec.surface
        previous = new_game || reset_surface ? nil : @surface
        @surface = if view_spec.surface == nil
          nil
        elsif hand_update || view_spec.surface.is_a?(GameSurfaces::WordBoardSpec) || view_spec.surface.is_a?(GameSurfaces::TabooSpec)
          GameSurfaces.reconcile(view_spec.surface, previous: previous, state: state)
        else
          GameSurfaces.build(view_spec.surface, state: state)
        end
      end
      @preserved_hand_surface_state = @surface.state if hand_update && @surface != nil
      @view_spec = view_spec
      @surface_identity = surface_identity_for(view_spec.surface)
      location = [:game, 0] if location[0] == :game && old_identity != @surface_identity
      if hand_update && !phase_transition && location[0] == :game && @surface != nil && @surface.fields.include?(old_field)
        location = [:game, @surface.fields.index(old_field)]
      end
      update_users(user_items, header: users_header)
      update_history(history_items, header: text_or_default(view_spec.history_header, _("Game history")))
      @history.empty_label = text_or_default(view_spec.history_empty_label, _("No moves yet")) if @history.respond_to?(:empty_label=)
      @history.index = bounded_index(history_index, @history_items) if history_index != nil
      @users.index = bounded_index(users_index, @user_items) if users_index != nil
      @phase = phase
      waiting_text = phase == :finished ? _("Waiting for a new game to start") : _("Waiting for the game to start")
      waiting_text = view_spec.finished_text if phase == :finished && view_spec.finished_text != nil
      @waiting_status.options = [waiting_text] if @waiting_status.options != [waiting_text]
      @waiting_status.index = 0
      reconcile_status_command_buttons(view_spec.status_commands)
      status_actions = view_spec.status_commands.filter_map do |command|
        @status_command_buttons[command.id.to_s]
      end
      status_fields = if phase == :waiting
        (own_table ? [@primary_button] : [@waiting_status]) + status_actions
      elsif phase == :finished
        (own_table && view_spec.restartable ? [@restart_button] : [@waiting_status]) + status_actions
      else
        []
      end
      game_fields = @surface == nil ? [] : @surface.fields
      trailing_fields = @surface.respond_to?(:fields_for_parts) ? @surface.fields_for_parts(view_spec.trailing_parts) : []
      section_fields = {
        status: status_fields,
        game: game_fields - trailing_fields,
        game_actions: trailing_fields,
        users: [@users],
        chat: [@chat], history: [@history]
      }
      @content_fields = []
      @field_locations = []
      view_spec.sections.each do |section|
        section_fields.fetch(section).each_with_index do |field, index|
          @content_fields << field
          @field_locations << ([:game, :game_actions].include?(section) ? [:game, game_fields.index(field)] : [section, index])
        end
      end
      new_fields = @content_fields + [@back_button]
      if @form.fields != new_fields
        @form.show_all
        @form.fields.replace(new_fields)
        @form.hide(@back_button)
      end
      @form.cancel_button = @back_button
      new_index = form_index_for_location(location)
      @form.index = new_index if @form.index.to_i != new_index
      self
    end

    def focus_location
      @field_locations&.[](@form.index.to_i)
    end

    def focus_users
      @form.index = form_index_for_location([:users, 0])
    end

    def focus_game(field_index: 0, silent: false)
      index = form_index_for_location([:game, field_index.to_i])
      return if @form.index.to_i == index
      field = @form.fields[index]
      field.suppress_next_focus! if silent && field.respond_to?(:suppress_next_focus!)
      @form.index = index
    ensure
      field.clear_suppressed_focus! if silent && field.respond_to?(:clear_suppressed_focus!)
    end

    def shortcut_fields
      @content_fields.reject { |field| field.equal?(@chat) }
    end

    # Only visible game controls, never the participant list, history or chat.
    def game_help_fields
      @content_fields.each_with_index.filter_map do |field, index|
        field if @field_locations[index].to_a.first == :game
      end
    end

    def suppress_focus!
      field = @form.fields[@form.index.to_i]
      field.suppress_next_focus! if field.respond_to?(:suppress_next_focus!)
    end

    def wait_without_announcement
      @form.wait_without_announcement
    end

    def snapshot
      location = focus_location
      follows_tail = location.to_a[0] != :history || @history.index.to_i >= @history_items.length - 1
      Snapshot.new(
        surface_state: @surface&.state || {},
        history_index: follows_tail ? [@history_items.length - 1, 0].max : @history.index.to_i,
        users_index: @users.index.to_i, form_index: @form.index.to_i,
        focus_location: location, surface_identity: @surface_identity,
        history_follows_tail: follows_tail, chat_text: @chat.text,
        chat_index: @chat.index.to_i, chat_check: @chat.check.to_i
      )
    end

    def take_cursor_announcement
      location = focus_location.to_a
      field_index = @phase == :active && location[0] == :game ? location[1] : nil
      @surface&.take_cursor_announcement(field_index)
    end

    private

    def binding_controls
      [@form, @users, @history, @primary_button, @restart_button, @waiting_status,
        *@status_command_buttons.values, @back_button]
    end

    def reconcile_status_command_buttons(commands)
      current = @status_command_buttons
      @status_command_buttons = commands.to_a.each_with_object({}) do |command, buttons|
        id = command.id.to_s
        button = current[id] || Button.new(command.label.to_s)
        button.extend(Bindings) unless button.is_a?(Bindings)
        button.label = command.label.to_s
        buttons[id] = button
      end
    end

    def bounded_index(index, items)
      return 0 if items.empty?

      [[index.to_i, 0].max, items.length - 1].min
    end

    def form_index_for_location(location)
      exact = @field_locations.index(location)
      return exact if exact != nil

      matches = @field_locations.each_index.select { |index| @field_locations[index][0] == location.to_a[0] }
      if matches.empty?
        return @field_locations.index([:status, 0]) ||
          @field_locations.index([:game, 0]) ||
          @field_locations.index([:users, 0]) || 0
      end

      matches[[[location.to_a[1].to_i, 0].max, matches.length - 1].min]
    end

    def surface_identity_for(spec)
      if spec.is_a?(GameSurfaces::CompositeSpec)
        children = spec.parts.to_a.map { |part| "#{part.id}=#{surface_identity_for(part.surface)}" }
        return "#{spec.class.name}[#{children.join('|')}]"
      end
      id = spec.respond_to?(:id) ? spec.id.to_s : ""
      "#{spec.class.name}:#{id}"
    end

    def text_or_default(value, default)
      value.to_s.empty? ? default : value.to_s
    end
  end
end
