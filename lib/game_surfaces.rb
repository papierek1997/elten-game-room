require_relative "game_surfaces/specifications"
require_relative "game_surfaces/state_reader"
require_relative "game_layout"
require_relative "game_surfaces/card_hand_cursor"
require_relative "game_surfaces/card_sorting"
require_relative "game_room_ui"

require_relative "game_room_localization"
require_relative "game_surfaces/card_actions"

module GameSurfaces
  using GameRoomLocalization::Translations
  SHIFTED_DIGIT_CHARACTERS = {
    "1" => "!", "2" => "@", "3" => "#", "4" => "$", "5" => "%",
    "6" => "^", "7" => "&", "8" => "*", "9" => "(", "0" => ")"
  }.freeze





  module ActionEmitter
    include StateReader
    def action_guard=(guard)
      @action_guard = guard
    end

    def action_allowed?
      @action_guard == nil || @action_guard.call
    end

    def on_action(&handler)
      @action_handler = handler
      self
    end

    def suppress_next_focus!(_field_index = 0)
      nil
    end

    def cancel_pending_action?
      false
    end

    def cancel_pending_action!
      false
    end

    def take_cursor_announcement(_field_index = nil)
      nil
    end

    private

    def emit_action(kind, name, payload = {}, source: nil)
      return unless action_allowed?
      @action_handler&.call(
        Action.new(kind: kind, name: name, payload: payload, source: source)
      )
    end
  end

  # ELTEN 3.0.4 owns quiet refresh and input-safe resume. Only the surface's
  # one-shot focus suppression needs clearing before returning to its wait.
  class RefreshAwareForm < GameRoomUI::Form
    def wait_without_announcement
      current = fields[@index.to_i]
      current.clear_suppressed_focus! if current.respond_to?(:clear_suppressed_focus!)
      super
    end
  end










  class OrientedGridBox < GridBox
    def initialize(width, height, row_origin:, column_origin: :left, coordinate_labels: nil, coordinate_first: false, **options)
      @row_origin = row_origin.to_sym
      @column_origin = column_origin.to_sym
      @coordinate_labels = coordinate_labels
      @coordinate_first = coordinate_first == true
      super(width, height, **options)
    end

    def set_orientation(row_origin:, column_origin:)
      logical = logical_position
      @row_origin = row_origin.to_sym
      @column_origin = column_origin.to_sym
      set_logical_position(*logical)
    end

    def coordinate_labels=(labels)
      @coordinate_labels = labels
    end

    def logical_position
      [logical_x(@x), logical_y(@y)]
    end

    def set_logical_position(x, y)
      @x = internal_x(x)
      @y = internal_y(y)
    end

    def suppress_next_focus!
      @suppress_next_focus = true
    end

    attr_writer :silent_focus_handler

    def silent_positions=(positions)
      @silent_position_lookup = positions.to_a.each_with_object({}) do |position, lookup|
        lookup[[position[0].to_i, position[1].to_i]] = true
      end.freeze
    end

    def clear_suppressed_focus!
      @suppress_next_focus = false
    end

    # Limits arrow navigation to meaningful cells while preserving the
    # original grid coordinates announced by GridBox.  A nil value keeps the
    # normal rectangular navigation used by chess, checkers and other boards.
    def navigable_positions=(positions)
      if positions == nil
        @navigable_positions = nil
        @navigable_position_lookup = nil
        return
      end

      @navigable_positions = positions.to_a.map do |position|
        [position[0].to_i, position[1].to_i].freeze
      end.uniq.freeze
      @navigable_position_lookup = @navigable_positions.each_with_object({}) do |position, lookup|
        lookup[position] = true
      end.freeze
      if !@navigable_position_lookup[[@x, @y]] && (first = @navigable_positions.first) != nil
        @x, @y = first
      end
    end

    def move_by(dx, dy)
      return super if @navigable_position_lookup == nil

      step_x = dx.to_i <=> 0
      step_y = dy.to_i <=> 0
      return if step_x == 0 && step_y == 0

      if step_x == 0
        candidate_y = @y + step_y
        while candidate_y.between?(0, @height - 1)
          current_row = @navigable_positions.select { |position| position[1] == @y }.sort_by(&:first)
          current_column = current_row.index([@x, @y])
          candidates = @navigable_positions.select { |position| position[1] == candidate_y }.sort_by(&:first)
          if !candidates.empty?
            nearest = candidates.each_with_index.min_by do |position, column|
              column_distance = current_column == nil ? 0 : (column - current_column).abs
              [(position[0] - @x).abs, column_distance, position[0]]
            end.first
            @x, @y = nearest
            return
          end
          candidate_y += step_y
        end
      end

      candidate_x = @x + step_x
      candidate_y = @y + step_y
      while candidate_x.between?(0, @width - 1) && candidate_y.between?(0, @height - 1)
        if @navigable_position_lookup[[candidate_x, candidate_y]]
          @x = candidate_x
          @y = candidate_y
          return
        end
        candidate_x += step_x
        candidate_y += step_y
      end

      play_sound("border", volume: 100, pitch: 100, pan: lpos) if @border_sound && !@silent && respond_to?(:play_sound, true)
      trigger(:border, @x, @y, border_direction(step_x, step_y), step_x, step_y)
    end

    def focus(index = nil, count = nil, spk = true, include_header: true)
      if @suppress_next_focus
        @suppress_next_focus = false
        spk = false
      end
      if @silent_position_lookup&.key?([@x, @y])
        @silent_focus_handler&.call if spk && !@silent
        NVDA.braille("") if defined?(NVDA) && NVDA.check
        return true
      end
      return super(index, count, spk, include_header: include_header) if !@coordinate_first

      position = respond_to?(:lpos) ? lpos : (@width <= 1 ? 50 : @x.to_f / (@width - 1).to_f * 100.0)
      if spk && !@silent && defined?(Configuration) && Configuration.controlspresentation != :voice_only && respond_to?(:play_sound, true)
        play_sound("listbox_marker", volume: 100, pitch: 100, pan: position)
      end
      return if instance_variable_defined?(:@speech) && !@speech

      label = if respond_to?(:cell_label)
        cell_label.to_s
      else
        @cells.to_a[@y].to_a[@x].to_s
      end
      value = cell_announcement(label)
      if include_header && instance_variable_defined?(:@header) && !@header.to_s.empty?
        separator = " .:?!,".include?(@header.to_s[-1..-1].to_s) ? " " : ": "
        value = "#{@header}#{separator}#{value}"
      end
      speak(value, pan: position) if spk
      NVDA.braille(value) if defined?(NVDA) && NVDA.check
      true
    end

    def cell_announcement(label)
      label.empty? ? coordinate_label : "#{coordinate_label}, #{label}"
    end

    def coordinate_label(x = @x, y = @y)
      logical_column = logical_x(x)
      logical_row = logical_y(y)
      custom = @coordinate_labels&.dig(logical_row, logical_column).to_s
      return custom if !custom.empty?

      column = logical_column
      letters = ""
      loop do
        letters = (65 + (column % 26)).chr + letters
        column = column / 26 - 1
        break if column < 0
      end
      "#{letters}#{logical_row + 1}"
    end

    def logical_x(internal_x = @x)
      return @width - internal_x.to_i - 1 if @column_origin == :right

      internal_x.to_i
    end

    def logical_y(internal_y = @y)
      return @height - internal_y.to_i - 1 if @row_origin == :bottom

      internal_y.to_i
    end

    def internal_y(logical_y)
      return @height - logical_y.to_i - 1 if @row_origin == :bottom

      logical_y.to_i
    end

    def internal_x(logical_x)
      return @width - logical_x.to_i - 1 if @column_origin == :right

      logical_x.to_i
    end
  end

  class RefreshAwareListBox < ListBox
    attr_reader :last_focus_spoken

    def game_shortcut_signatures=(signatures)
      keys = signatures.to_a.map do |key, modifiers|
        normalized = key.to_s.downcase
        if modifiers.to_a.map(&:to_sym).include?(:shift)
          SHIFTED_DIGIT_CHARACTERS.fetch(normalized, normalized)
        else
          normalized
        end
      end
      self.game_shortcut_keys = keys
    end

    def game_shortcut_keys=(keys)
      @game_shortcut_character_keys = keys.to_a.each_with_object([]) do |key, result|
        normalized = key.to_s.downcase
        result << normalized if normalized.length == 1 && !result.include?(normalized)
      end
    end

    def suppress_next_focus!
      @suppress_next_focus = true
    end

    def clear_suppressed_focus!
      @suppress_next_focus = false
    end

    def focus(index = nil, count = nil, header = @header, spk = true)
      if @suppress_next_focus
        @suppress_next_focus = false
        spk = false
      end
      @last_focus_spoken = spk
      super(index, count, header, spk)
    end

    # Card navigation changes the selected option, not the surrounding form.
    # Retain native focus/braille behaviour without repeating the hand caption.
    # Other lists and ordinary focus transitions continue to use #focus.
    def announce_current_card
      focus(nil, nil, "", true)
    end

    private

    def getkeychar(*arguments)
      character = super
      return "" if @game_shortcut_character_keys.to_a.include?(character.to_s.downcase)

      character
    end

  end

  class RefreshAwareEditBox < EditBox
    def initialize(*arguments, **options)
      super
      on(:change) { @game_room_edit_generation = game_room_edit_generation + 1 }
    end

    def game_room_edit_generation
      @game_room_edit_generation.to_i
    end

    def set_text(*arguments, **options)
      @game_room_edit_generation = game_room_edit_generation + 1
      super
    end
    alias settext set_text

    attr_reader :last_focus_spoken

    class ContextShortcutFilter
      def initialize(menu, blocked_shortcuts)
        @menu = menu
        @blocked_shortcuts = blocked_shortcuts
      end

      def option(label, value = nil, shortcut = "", &handler)
        filtered = @blocked_shortcuts.include?(shortcut.to_s) ? "" : shortcut
        @menu.option(label, value, filtered, &handler)
      end

      def submenu(label, &handler)
        return @menu.submenu(label) if handler == nil

        @menu.submenu(label) do |submenu|
          filtered_submenu = self.class.new(submenu, @blocked_shortcuts)
          if handler.arity <= 0
            filtered_submenu.instance_eval(&handler)
          else
            handler.call(filtered_submenu)
          end
        end
      end

      def method_missing(name, *arguments, &handler)
        @menu.public_send(name, *arguments, &handler)
      end

      def respond_to_missing?(name, include_private = false)
        @menu.respond_to?(name, include_private) || super
      end
    end

    def game_shortcut_signatures=(signatures)
      @blocked_context_shortcuts = signatures.to_a.each_with_object([]) do |signature, result|
        key, modifiers = signature
        modifiers = modifiers.to_a.map(&:to_sym)
        next if key.to_s.length != 1
        next if (modifiers - [:control, :shift]).any? || !modifiers.include?(:control)

        shortcut = modifiers.include?(:shift) ? key.to_s.upcase : key.to_s.downcase
        result << shortcut if !result.include?(shortcut)
      end
    end

    def context(menu, submenu = false)
      if submenu == false && !@blocked_context_shortcuts.to_a.empty?
        menu = ContextShortcutFilter.new(menu, @blocked_context_shortcuts)
      end
      super(menu, submenu)
    end

    def suppress_next_focus!
      @suppress_next_focus = true
    end

    def clear_suppressed_focus!
      @suppress_next_focus = false
    end

    # A chat control can survive several surrounding form instances. Keep one
    # submit bridge and replace only its current screen callback, rather than
    # accumulating :select handlers on every refresh.
    def on_submit(&handler)
      @submit_handler = handler
      if !@submit_handler_bound
        @submit_handler_bound = true
        on(:select) { @submit_handler&.call }
      end
      self
    end

    def restore_selection(index:, check:)
      maximum = text.to_s.length
      self.index = [[index.to_i, 0].max, maximum].min
      self.check = [[check.to_i, 0].max, maximum].min
    end

    def focus(index = nil, count = nil, spk = true)
      if @suppress_next_focus
        @suppress_next_focus = false
        spk = false
      end
      @last_focus_spoken = spk
      super(index, count, spk)
    end
  end

  class GridBoard
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      validate_spec!
      x = state_value(state, "x", 0)
      y = state_value(state, "y", 0)
      @control = OrientedGridBox.new(
        @spec.width,
        @spec.height,
        row_origin: row_origin,
        header: @spec.header.to_s,
        x: x,
        y: internal_y(y),
        quiet: true
      )
      @control.set_cells(display_rows)
      @control.on(:select) do |params|
        coordinates = params.to_a
        emit_selection(coordinates[0].to_i, logical_y(coordinates[1]))
      end
    end

    def emit_selection(x, y)
      emit_action("grid", "select", { "x" => x, "y" => y })
    end

    def fields
      [@control]
    end

    def suppress_next_focus!(_field_index = 0)
      @control.suppress_next_focus!
    end

    def state
      {
        "x" => @control.x.to_i,
        "y" => logical_y(@control.y)
      }
    end

    def movement_command(arguments)
      values = arguments.to_a.map { |value| value.to_s.strip }
      if values.length != 1
        return MovementCommandResult.new(message: _("Enter one destination field, for example /C4."))
      end

      position = command_coordinate(values.first)
      if position == nil
        return MovementCommandResult.new(
          message: _("Field %{field} is outside this board.") % { field: values.first }
        )
      end

      MovementCommandResult.new(
        action: Action.new(
          kind: "grid",
          name: "select",
          payload: { "x" => position[0], "y" => position[1] },
          source: "chat_command"
        )
      )
    end

    private

    def command_coordinate(value)
      match = /\A([A-Za-z]+)([1-9]\d*)\z/.match(value)
      return nil if match == nil

      column = match[1].upcase.each_byte.reduce(0) do |number, character|
        number * 26 + character - 64
      end - 1
      row = match[2].to_i - 1
      return nil if !column.between?(0, @spec.width.to_i - 1) || !row.between?(0, @spec.height.to_i - 1)

      [column, row]
    end

    def validate_spec!
      raise ArgumentError, "grid width must be positive" if @spec.width.to_i <= 0
      raise ArgumentError, "grid height must be positive" if @spec.height.to_i <= 0
      rows = @spec.cells.to_a
      raise ArgumentError, "grid cells must match its height" if rows.length != @spec.height.to_i
      if rows.any? { |row| row.to_a.length != @spec.width.to_i }
        raise ArgumentError, "grid cells must match its width"
      end
      raise ArgumentError, "unsupported row origin" if ![:top, :bottom].include?(row_origin)
    end

    def display_rows
      rows = @spec.cells.to_a.map { |row| row.to_a.map(&:to_s) }
      row_origin == :bottom ? rows.reverse : rows
    end

    def row_origin
      (@spec.row_origin || :top).to_sym
    end

    def logical_y(internal_y)
      row_origin == :bottom ? @spec.height.to_i - internal_y.to_i - 1 : internal_y.to_i
    end

    def internal_y(logical_y)
      value = [[logical_y.to_i, 0].max, @spec.height.to_i - 1].min
      row_origin == :bottom ? @spec.height.to_i - value - 1 : value
    end

    def state_value(state, key, default)
      GameSurfaces::StateReader.integer(state, key, default)
    end
  end

  class CardTable
    include CardSorting
    include CardActions
    include ActionEmitter

    attr_reader :command_field_index

    def initialize(spec, state: {})
      @spec = spec
      @zones = @spec.zones.to_a
      raise ArgumentError, "a card table requires at least one zone" if @zones.empty?

      remembered = state.respond_to?(:[]) ? (state["zones"] || state[:zones] || {}) : {}
      remembered_choices = state.respond_to?(:[]) ? (state["card_choices"] || state[:card_choices] || {}) : {}
      @card_sort_mode = state.respond_to?(:[]) ? (state["card_sort_mode"] || state[:card_sort_mode]).to_s : ""
      @card_sort_direction = state.respond_to?(:[]) && (state["card_sort_direction"] || state[:card_sort_direction]).to_s == "descending" ? "descending" : "ascending"
      @controls = []
      @cards = {}
      @pending_choices = {}
      @cursor_announcements = {}
      @zones.each do |zone|
        changed = false
        same_epoch = true
        cards = sorted_cards(zone.cards.to_a, @card_sort_mode)
        validate_card_choices!(cards)
        zone_id = zone.id.to_s
        @cards[zone_id] = cards
        index = remembered_index(remembered, zone.id)
        if zone.hand_order != nil
          cursors = state["hand_cursors"] || {}
          same_epoch = cursors.fetch(zone_id, {}).fetch("epoch", nil) == zone.hand_epoch.to_s
          cards, index, changed = CardHandCursor.resolve(cards, zone.hand_order, zone.hand_epoch,
            cursors[zone_id], index, sorted: sorted_hand?)
          @cards[zone_id] = cards
          @cursor_announcements[zone_id] = card_label(cards[index]) if changed
        end
        pending = changed || !same_epoch ? nil : remembered_choice(remembered_choices, zone_id, cards)
        labels = cards.map { |card| card_label(card) }
        header = zone.header.to_s
        if pending != nil
          @pending_choices[zone_id] = pending
          labels = card_choices(pending[:card]).map { |choice| choice_label(choice) }
          header = choice_header(pending[:card])
          index = pending[:choice_index]
        end
        control = card_list_control_class.new(
          labels,
          header: header,
          index: index,
          quiet: true,
          empty_label: zone.empty_label.to_s
        )
        control.on(:select) do |params|
          next if respond_to?(:intercept_card_selection, true) && intercept_card_selection(zone_id, params.to_a[0].to_i)
          zone = @zones.find { |item| item.id.to_s == zone_id }
          cards = @cards.fetch(zone_id)
          selected_index = params.to_a[0].to_i
          pending = @pending_choices[zone_id]
          if pending != nil
            choice = card_choices(pending[:card])[selected_index]
            next if choice == nil

            payload = {
              "zone" => zone_id,
              "index" => pending[:card_index],
              "card_id" => card_id(pending[:card]),
              "card" => choice_value(choice),
              "choice_id" => choice_id(choice)
            }
            restore_card_list(zone, control, speak: false)
            emit_action("card", "select", payload)
            next
          end

          card = cards[selected_index]
          next if card == nil

          choices = card_choices(card)
          if shift_pressed?
            quick_choice = shifted_choice(card, choices)
            if quick_choice != nil
              emit_action(
                "card",
                "select",
                {
                  "zone" => zone.id.to_s,
                  "index" => selected_index,
                  "card_id" => card_id(card),
                  "card" => choice_value(quick_choice),
                  "choice_id" => choice_id(quick_choice)
                }
              )
              next
            end

            # A card may advertise a Shift action even when that action is
            # currently unavailable. Emit the ordinary card payload together
            # with the requested choice so the game can report the reason,
            # instead of silently playing the card as a normal move.
            unavailable_choice = shift_choice_id(card)
            if !unavailable_choice.empty?
              emit_action(
                "card",
                "select",
                {
                  "zone" => zone.id.to_s,
                  "index" => selected_index,
                  "card_id" => card_id(card),
                  "card" => card_value(card),
                  "choice_id" => unavailable_choice
                }
              )
              next
            end
          end

          if !choices.empty?
            begin_card_choice(zone, control, card, selected_index)
            next
          end

          submit_card_selection(zone, card, selected_index)
        end
        @controls << control
      end
    end

    def fields
      @controls
    end

    def suppress_next_focus!(field_index = 0)
      control = @controls[field_index.to_i]
      control.suppress_next_focus! if control != nil
    end

    def state
      indices = {}
      choices = {}
      cursors = {}
      @zones.each_with_index do |zone, index|
        zone_id = zone.id.to_s
        pending = @pending_choices[zone_id]
        if pending == nil
          indices[zone_id] = @controls[index].index.to_i
        else
          indices[zone_id] = pending[:card_index]
          choices[zone_id] = {
            "card_id" => card_id(pending[:card]),
            "card_index" => pending[:card_index],
            "choice_index" => @controls[index].index.to_i
          }
        end
        if zone.hand_order != nil
          cursors[zone_id] = CardHandCursor.snapshot(@cards.fetch(zone_id), zone.hand_order,
            zone.hand_epoch, indices[zone_id])
        end
      end
      result = { "zones" => indices }
      result["hand_cursors"] = cursors unless cursors.empty?
      result["card_choices"] = choices if !choices.empty?
      result["card_sort_mode"] = @card_sort_mode if !@card_sort_mode.empty?
      result["card_sort_direction"] = @card_sort_direction if !@card_sort_mode.empty?
      result
    end

    def reusable_for?(spec)
      spec.is_a?(CardTableSpec) && @zones.map { |zone| zone.id.to_s } == spec.zones.map { |zone| zone.id.to_s } &&
        @zones.all? { |zone| zone.hand_order != nil } && spec.zones.all? { |zone| zone.hand_order != nil }
    end

    def update_spec(spec)
      remembered = state
      @spec = spec
      @zones = spec.zones.to_a
      @cursor_announcements.clear
      @zones.each_with_index do |zone, field_index|
        zone_id = zone.id.to_s
        next_cards = sorted_cards(zone.cards.to_a, @card_sort_mode)
        validate_card_choices!(next_cards)
        next_cards, index, changed = CardHandCursor.resolve(next_cards, zone.hand_order, zone.hand_epoch,
          remembered.fetch("hand_cursors", {})[zone_id], remembered["zones"][zone_id], sorted: sorted_hand?)
        @cards[zone_id] = next_cards
        same_epoch = remembered.fetch("hand_cursors", {}).fetch(zone_id, {})["epoch"] == zone.hand_epoch.to_s
        pending = changed || !same_epoch ? nil : remembered_choice(remembered["card_choices"] || {}, zone_id, next_cards)
        @pending_choices.delete(zone_id)
        @pending_choices[zone_id] = pending if pending
        control = @controls[field_index]
        labels = pending ? card_choices(pending[:card]).map { |choice| choice_label(choice) } : next_cards.map { |card| card_label(card) }
        control.options = labels if control.options != labels
        control.header = pending ? choice_header(pending[:card]) : zone.header.to_s
        control.empty_label = zone.empty_label.to_s if control.respond_to?(:empty_label=)
        control.index = pending ? pending[:choice_index] : index
        @cursor_announcements[zone_id] = card_label(next_cards[index]) if changed && !pending
      end
      self
    end

    def take_cursor_announcement(field_index = nil)
      zone = field_index == nil ? nil : @zones[field_index.to_i]
      message = zone == nil ? nil : @cursor_announcements[zone.id.to_s]
      @cursor_announcements.clear
      message
    end

    def handle_command(command, payload = {})
      @command_field_index = nil
      return selected_card_action(payload) if command.to_s == "selected_card_action"
      if command.to_s == "navigate_playable_card"
        return navigate_playable_card(payload)
      end
      return false if command.to_s != "sort_cards" || !@pending_choices.empty?

      mode = (payload["mode"] || payload[:mode]).to_s
      return false if mode.empty?

      toggle = payload["toggle"] || payload[:toggle]
      direction = toggle && @card_sort_mode == mode && @card_sort_direction == "ascending" ? "descending" : "ascending"
      sorted_any = false
      @zones.each_with_index do |zone, index|
        cards = @cards.fetch(zone.id.to_s)
        next if cards.none? { |card| card_sort_keys(card).key?(mode) }

        control = @controls[index]
        selected = cards[control.index.to_i]
        cards.replace(sorted_cards(cards, mode, direction))
        control.options = cards.map { |card| card_label(card) }
        selected_index = cards.index { |card| card_id(card) == card_id(selected) }
        control.index = selected_index || 0
        sorted_any = true
      end
      return false if !sorted_any

      @card_sort_mode = mode
      @card_sort_direction = direction
      @cursor_announcements.clear
      message = payload["#{direction}_message"] || payload["message"] || payload[:message]
      speak(message.to_s) if !message.to_s.empty?
      true
    end

    def cancel_pending_action?
      !@pending_choices.empty?
    end

    def cancel_pending_action!
      zone_index = @zones.index { |zone| @pending_choices.key?(zone.id.to_s) }
      return false if zone_index == nil

      restore_card_list(@zones[zone_index], @controls[zone_index], speak: true)
      true
    end

    private

    def card_list_control_class
      RefreshAwareListBox
    end

    def navigate_playable_card(payload)
      zone_id = (payload["hand_id"] || payload[:hand_id]).to_s
      zone_index = @zones.index { |zone| zone.id.to_s == zone_id }
      return false if zone_index == nil
      if @pending_choices.key?(zone_id)
        speak(_("Finish or cancel the current card choice first."))
        return true
      end

      cards = @cards.fetch(zone_id)
      target, auto_action = CardHandCursor.playable_navigation(
        cards.map { |card| card_id(card) },
        @controls[zone_index].index,
        payload
      )
      if target == nil
        speak((payload["empty_message"] || payload[:empty_message] || _("You have no playable card.")).to_s)
        return true
      end

      if auto_action
        shortcut = payload["shortcut"] || payload[:shortcut]
        return Action.from_h(auto_action, source: "shortcut:#{shortcut}")
      end

      control = @controls[zone_index]
      control.index = target
      control.announce_current_card
      @command_field_index = zone_index
      true
    end

    def shifted_choice(card, choices)
      id = shift_choice_id(card)
      return nil if id.to_s.empty?

      choices.find { |choice| choice_id(choice) == id.to_s }
    end

    def shift_choice_id(card)
      value = if card.respond_to?(:shift_choice)
        card.shift_choice
      elsif card.respond_to?(:key?)
        card["shift_choice"] || card[:shift_choice]
      end
      value.to_s
    end

    def shift_pressed?
      key_held?(0x10) == true
    rescue Exception
      false
    end

    def validate_card_choices!(cards)
      cards.each do |card|
        choices = card_choices(card)
        ids = choices.map { |choice| choice_id(choice) }
        raise ArgumentError, "card choice ids must not be empty" if ids.any?(&:empty?)
        raise ArgumentError, "card choice ids must be unique" if ids.uniq.length != ids.length
        raise ArgumentError, "card choices require labels" if choices.any? { |choice| choice_label(choice).empty? }
      end
    end

    def begin_card_choice(zone, control, card, card_index)
      zone_id = zone.id.to_s
      @pending_choices[zone_id] = { card: card, card_index: card_index.to_i }
      control.options = card_choices(card).map { |choice| choice_label(choice) }
      control.header = choice_header(card)
      control.index = 0
      control.focus(0)
    end

    def restore_card_list(zone, control, speak:)
      zone_id = zone.id.to_s
      pending = @pending_choices.delete(zone_id)
      return false if pending == nil

      control.options = @cards.fetch(zone_id).map { |card| card_label(card) }
      control.header = zone.header.to_s
      control.index = pending[:card_index]
      control.focus(control.index) if speak
      true
    end

    def remembered_choice(remembered, zone_id, cards)
      return nil if !remembered.respond_to?(:key?)
      value = remembered[zone_id]
      value = remembered[zone_id.to_sym] if value == nil && zone_id.respond_to?(:to_sym)
      return nil if !value.respond_to?(:[])

      card_id_value = value["card_id"] || value[:card_id]
      card_index = (value["card_index"] || value[:card_index]).to_i
      card = cards[card_index]
      card = cards.find { |candidate| card_id(candidate) == card_id_value.to_s } if card_id(card) != card_id_value.to_s
      return nil if card == nil || card_choices(card).empty?

      {
        card: card,
        card_index: cards.index(card),
        choice_index: (value["choice_index"] || value[:choice_index]).to_i
      }
    end

    def choice_header(card)
      custom = if card.respond_to?(:choice_header)
        card.choice_header
      elsif card.respond_to?(:key?)
        card["choice_header"] || card[:choice_header]
      end
      return custom.to_s if !custom.to_s.empty?

      _("%{card}. Choose how to play it") % { card: card_label(card) }
    end

    def remembered_index(remembered, zone_id)
      value = remembered[zone_id.to_s]
      value = remembered[zone_id.to_sym] if value == nil && zone_id.respond_to?(:to_sym)
      value.to_i
    end

    def card_label(card)
      return card.label.to_s if card.respond_to?(:label)
      return (card["label"] || card[:label]).to_s if card.respond_to?(:[])

      card.to_s
    end

    def card_value(card)
      return card.value if card.respond_to?(:value)
      if card.respond_to?(:[])
        return card["value"] if card.respond_to?(:key?) && card.key?("value")
        return card[:value] if card.respond_to?(:key?) && card.key?(:value)
      end

      card
    end

    def card_choices(card)
      return card.choices.to_a if card.respond_to?(:choices)
      if card.respond_to?(:key?)
        return card["choices"].to_a if card.key?("choices")
        return card[:choices].to_a if card.key?(:choices)
      end

      []
    end

    def choice_id(choice)
      return choice.id.to_s if choice.respond_to?(:id)
      if choice.respond_to?(:key?)
        return choice["id"].to_s if choice.key?("id")
        return choice[:id].to_s if choice.key?(:id)
      end

      ""
    end

    def choice_label(choice)
      return choice.label.to_s if choice.respond_to?(:label)
      if choice.respond_to?(:key?)
        return choice["label"].to_s if choice.key?("label")
        return choice[:label].to_s if choice.key?(:label)
      end

      choice.to_s
    end

    def choice_value(choice)
      return choice.value if choice.respond_to?(:value)
      if choice.respond_to?(:key?)
        return choice["value"] if choice.key?("value")
        return choice[:value] if choice.key?(:value)
      end

      choice
    end

    def card_id(card)
      return card.id.to_s if card.respond_to?(:id)
      if card.respond_to?(:key?)
        return card["id"].to_s if card.key?("id")
        return card[:id].to_s if card.key?(:id)
      end

      ""
    end
  end

  require_relative "game_surfaces/command_panel"
  require_relative "game_surfaces/pong_surface"
  require_relative "game_surfaces/audio_ball_surface"
  require_relative "game_surfaces/pawn_track"
  require_relative "game_surfaces/piece_board"
  require_relative "game_surfaces/dice_tray"
  require_relative "game_surfaces/roll_and_score"
  require_relative "game_surfaces/packet_cards"
  require_relative "game_surfaces/meld_cards"
  require_relative "game_surfaces/tile_hand"
  require_relative "game_surfaces/word_board"
  require_relative "game_surfaces/taboo_surface"
  require_relative "game_surfaces/question_surface"
  require_relative "game_surfaces/answer_sheet"
  require_relative "game_surfaces/review_surface"
  require_relative "game_surfaces/composite_surface"

  def self.hand_surface?(spec)
    case spec
    when CardTableSpec
      spec.zones.any? { |zone| zone.hand_order != nil }
    when PacketCardSpec
      spec.hand_order != nil
    when MeldHandSpec, TileHandSpec
      true
    when CompositeSpec
      spec.parts.any? { |part| hand_surface?(part.surface) }
    else
      false
    end
  end

  # A grid on which a fleet is laid out locally. Marking a bow and a stern
  # places one ship, and nothing leaves the computer until the fleet is
  # complete, so placing costs no game event and no network round trip.
  class FleetGrid < GridBoard
    def initialize(spec, state: {})
      @fleet = spec
      stored = state_value_object(state, "ships")
      @epoch = state_value_object(state, "epoch").to_s
      @ships = @epoch == spec.epoch.to_s ? stored.to_a.map { |cells| cells.to_a.map(&:to_i) } : []
      @bow = @epoch == spec.epoch.to_s ? state_value(state, "bow", -1) : -1
      @setup_mode = @epoch == spec.epoch.to_s ? state_value_object(state, "setup_mode").to_s : ""
      @setup_announced = @epoch == spec.epoch.to_s && state_value_object(state, "setup_announced") == true
      @setup_mode = "manual" if spec.setup_header.to_s.empty? || !@ships.empty? || @bow.to_i >= 0
      @epoch = spec.epoch.to_s
      @bow = nil if @bow.to_i.negative?
      super(
        GridSpec.new(
          width: spec.width, height: spec.height, header: spec.header,
          cells: spec.cells, row_origin: spec.row_origin
        ),
        state: state
      )
      @setup_choice = RefreshAwareListBox.new(
        [spec.random_label.to_s, spec.manual_label.to_s], header: spec.setup_header.to_s,
        index: state_value(state, "setup_index", 0), quiet: true
      )
      @setup_choice.on(:select) do
        if @setup_choice.index.to_i == 0
          @setup_mode = "random"
          emit_action("command", "random_fleet")
        else
          @setup_mode = "manual"
          emit_action("surface", "refresh")
          @control.focus
        end
      end
    end

    def fields
      @setup_mode == "manual" ? super : [@setup_choice]
    end

    def suppress_next_focus!(_field_index = 0)
      fields.first.suppress_next_focus!
    end

    # Automatic game initialization enters the form silently. Queue this local
    # prompt once through the same non-interrupting channel as cursor updates.
    def take_cursor_announcement(field_index = nil)
      return nil if field_index != 0 || @setup_mode == "manual" || @setup_announced

      @setup_announced = true
      [@fleet.setup_header.to_s, @setup_choice.options[@setup_choice.index.to_i].to_s].join(" ")
    end

    def state
      super.merge("ships" => @ships, "bow" => @bow == nil ? -1 : @bow, "epoch" => @epoch,
        "setup_mode" => @setup_mode, "setup_index" => @setup_choice.index.to_i, "setup_announced" => @setup_announced)
    end

    def movement_command(arguments)
      return MovementCommandResult.new(message: @fleet.setup_header.to_s) if @setup_mode != "manual"

      super
    end

    def handle_command(name, _payload = {})
      return false if @setup_mode != "manual"
      return false if name.to_s != "undo"

      if @bow != nil
        @bow = nil
        redraw
        speak(@fleet.cancel_message.to_s)
        return true
      end
      if @ships.empty?
        speak(@fleet.empty_message.to_s)
        return true
      end

      @ships = @ships[0..-2]
      redraw
      speak([@fleet.removed_message, status_text].reject(&:empty?).join(" "))
      true
    end

    def emit_selection(x, y)
      return if @setup_mode != "manual"
      cell = y * @spec.width.to_i + x
      return seal_if_confirmed if @fleet.complete.call(@ships)

      if @bow == nil
        refusal = @fleet.bow_check == nil ? nil : @fleet.bow_check.call(@ships, cell)
        if refusal != nil
          speak(refusal.to_s)
          return
        end

        @bow = cell
        redraw
        speak(@fleet.bow_message.to_s)
        return
      end
      bow = @bow
      cells, message = @fleet.place.call(@ships, bow, cell)
      if cells == nil
        speak(message.to_s)
        return
      end

      @bow = nil
      @ships = @ships + [cells]
      redraw
      announce_placement(cells)
      seal_if_confirmed if @fleet.complete.call(@ships)
    end

    def seal_if_confirmed
      message = @fleet.confirm_message.to_s
      if !message.empty? && !confirm(message)
        return if @ships.empty?

        @ships = @ships[0..-2]
        redraw
        speak([@fleet.removed_message, status_text].reject(&:empty?).join(" "))
        return
      end

      emit_action("grid", (@fleet.action_name || "seal").to_s, { "ships" => JSON.generate(@ships) })
    end

    private

    def announce_placement(cells)
      spoken = @fleet.placed_message == nil ? nil : @fleet.placed_message.call(cells, @ships)
      speak([spoken.to_s, status_text].reject(&:empty?).join(" "))
    end

    def status_text
      @fleet.status == nil ? "" : @fleet.status.call(@ships).to_s
    end

    def redraw
      @control.set_cells(display_rows)
      @control.header = header_text
    end

    def header_text
      text = @fleet.status == nil ? @fleet.header.to_s : @fleet.status.call(@ships).to_s
      return text if @bow == nil

      "#{@fleet.bow_message} #{text}"
    end

    def display_rows
      width = @spec.width.to_i
      occupied = @ships.flatten
      rows = @spec.cells.to_a.each_with_index.map do |row, y|
        row.to_a.each_with_index.map do |value, x|
          cell = y * width + x
          marks = []
          marks << @fleet.bow_label.to_s if cell == @bow
          marks << @fleet.ship_label.to_s if occupied.include?(cell)
          marks << value.to_s if !value.to_s.empty?
          marks.reject(&:empty?).join(", ")
        end
      end
      row_origin == :bottom ? rows.reverse : rows
    end

    def state_value_object(state, key)
      return nil if !state.respond_to?(:key?)
      return state[key] if state.key?(key)

      state[key.to_sym]
    end
  end

  def self.reconcile(spec, previous: nil, state: {})
    candidates = previous.to_a if previous.is_a?(Array)
    candidates ||= previous.respond_to?(:reuse_candidates) ? previous.reuse_candidates : [previous].compact
    if spec.is_a?(CompositeSpec)
      return CompositeSurface.new(spec, state: state, previous: candidates)
    end
    match = candidates.find { |surface| surface.respond_to?(:reusable_for?) && surface.reusable_for?(spec) }
    match ? match.update_spec(spec) : build(spec, state: state)
  end

  def self.build(spec, state: {})
    case spec
    when TabooSpec
      TabooSurface.new(spec, state: state)
    when WordBoardSpec
      WordBoardSurface.new(spec, state: state)
    when FleetGridSpec
      FleetGrid.new(spec, state: state)
    when GridSpec
      GridBoard.new(spec, state: state)
    when CardTableSpec
      CardTable.new(spec, state: state)
    when MeldHandSpec
      MeldHandSurface.new(spec, state: state)
    when TileHandSpec
      TileHandSurface.new(spec, state: state)
    when CommandPanelSpec
      CommandPanel.new(spec, state: state)
    when PongSpec
      PongSurface.new(spec, state: state)
    when AudioBallSpec
      AudioBallSurface.new(spec, state: state)
    when PawnTrackSpec
      PawnTrackSurface.new(spec, state: state)
    when PieceBoardSpec
      PieceBoard.new(spec, state: state)
    when DiceTraySpec
      DiceTray.new(spec, state: state)
    when RollAndScoreSpec
      RollAndScoreSurface.new(spec, state: state)
    when PacketCardSpec
      PacketCardSurface.new(spec, state: state)
    when QuestionSpec
      QuestionSurface.new(spec, state: state)
    when AnswerSheetSpec
      AnswerSheet.new(spec, state: state)
    when ReviewSpec
      ReviewSurface.new(spec, state: state)
    when CompositeSpec
      CompositeSurface.new(spec, state: state)
    else
      raise ArgumentError, "unsupported game surface: #{spec.class}"
    end
  end
end
