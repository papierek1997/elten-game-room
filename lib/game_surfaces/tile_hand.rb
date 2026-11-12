require_relative "specifications"
# encoding: UTF-8
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations





  # An explicit tile adapter shares only the physical-hand cursor/control.
  # It does not opt board games into card shortcuts or card semantics.
  class TileHandSurface < CardTable
    def reusable_for?(spec); spec.is_a?(TileHandSpec); end

    def state
      current = @controls.first.index
      view = table_view_state
      @controls.first.index = @hand_index if @view
      result = super.merge(view)
      result.fetch("card_choices", {}).each do |zone, remembered|
        pending = @pending_choices[zone]
        selected = pending && card_choices(pending[:card])[remembered["choice_index"]]
        remembered["choice_id"] = choice_id(selected) if selected
      end
      result["tile_side"] = @preferred_target if @spec.default_target
      result
    ensure
      @controls.first.index = current if @view && current
    end

    def initialize(spec, state: {})
      super
      @preferred_target = %w[l r].include?(state["tile_side"]) ? state["tile_side"] : spec.default_target
      # An older saved UI may still contain the removed Domino side picker.
      clear_destination_choice if spec.default_target
      restore_table_view(state)
    end

    def update_spec(spec)
      remembered = table_view_state
      close_table(speak: false) if @view
      super
      @preferred_target = spec.default_target ? (@preferred_target || spec.default_target) : nil
      clear_destination_choice if spec.default_target
      restore_table_view(remembered)
      self
    end

    def take_cursor_announcement(field_index = nil)
      super(@view ? nil : field_index)
    end

    def handle_command(command, payload = {})
      @command_field_index = nil
      return open_table if command == "tile_table"
      if command == "tile_side"
        target = payload["target"]
        return unavailable unless @spec.default_target && %w[l r].include?(target)
        @preferred_target = target
        speak(target == "l" ? _("Left") : _("Right"))
        return true
      end
      return unavailable if @view || !@pending_choices.empty?
      if command == "navigate_playable_tile"
        return super("navigate_playable_card", payload)
      end
      false
    end

    def cancel_pending_action?; @view || super; end
    def cancel_pending_action!
      if @detail
        index = @detail
        @detail = nil
        open_table(speak: false)
        @controls.first.index = index
        @controls.first.focus
        return true
      end
      return close_table if @view
      super
    end

    private

    def remembered_choice(remembered, zone_id, cards)
      result = super
      choice = remembered.dig(zone_id, "choice_id") if remembered.respond_to?(:dig)
      if result && choice
        result[:choice_index] = card_choices(result[:card]).index { |item| choice_id(item) == choice } || 0
      end
      result
    end

    def emit_action(kind, name, payload = {}, source: nil)
      if kind == "card"
        data = payload["card"]
        return unavailable unless data.is_a?(Hash)
        action = Action.from_h(data, source: source)
        super(action.kind, action.name, action.payload, source: action.source)
      else
        super
      end
    end

    def intercept_card_selection(zone, index)
      unless @view
        # A game may show unavailable destinations, while keeping the reasons
        # and all legality rules in its own current view specification.
        if @spec.selection_error
          pending = @pending_choices[zone]
          item = pending ? pending[:card] : @cards.fetch(zone)[index]
          return true unless item
          choice = pending && card_choices(item)[index]
          return true if pending && !choice
          error = @spec.selection_error.call(card_id(item), choice && choice_id(choice))
          if error
            speak(error)
            return true # Keep the choice open; do not emit a game action.
          end
        end
        # Only games opting into a preferred destination use this shortcut.
        # Mexican Train retains its explicit choice of train.
        return false unless @spec.default_target && @pending_choices.empty?
        item = @cards.fetch(zone)[index]
        choices = card_choices(item)
        return false if choices.empty?
        choice = choices.find { |candidate| choice_id(candidate) == @preferred_target } || choices.first
        emit_action("card", "select", { "card" => choice_value(choice) })
        return true
      end
      if @detail
        speak(@controls.first.options[index].to_s)
        return true
      end
      row = @spec.table[index]
      if row && row[:items]
        open_details(index)
      elsif row
        speak(row[:detail].to_s)
      end
      true
    end

    def open_table(speak: true)
      # Inspection replaces a destination choice; never interpret its option
      # index as a tile index, and never leave an invisible picker behind.
      clear_destination_choice
      @hand_index = @controls.first.index unless @view
      @view = true
      @detail = nil
      control = @controls.first
      control.header = @spec.table_header
      control.options = @spec.table.map { |row| row[:label] }
      control.empty_label = _("The table is empty.") if control.respond_to?(:empty_label=)
      control.index = 0
      @cursor_announcements.clear
      control.focus if speak
      true
    end

    def close_table(speak: true)
      @view = false
      @detail = nil
      control = @controls.first
      zone = @zones.first
      control.header = zone.header
      control.empty_label = zone.empty_label if control.respond_to?(:empty_label=)
      control.options = @cards.fetch(zone.id.to_s).map(&:label)
      control.index = @hand_index.to_i
      control.announce_current_card if speak
      true
    end

    def open_details(index, speak: true)
      row = @spec.table[index]
      return false unless row && row[:items]
      @detail = index
      @controls.first.options = row[:items]
      @controls.first.header = row[:label]
      @controls.first.index = 0
      @controls.first.focus if speak
      true
    end

    def restore_card_list(zone, control, speak:)
      restored = super(zone, control, speak: false)
      control.announce_current_card if restored && speak
      restored
    end

    def clear_destination_choice
      @zones.each_with_index do |zone, index|
        restore_card_list(zone, @controls[index], speak: false) if @pending_choices.key?(zone.id.to_s)
      end
    end

    def table_view_state
      return {} unless @view
      index = @controls.first.index.to_i
      row = @spec.table[@detail || index]
      { "tile_view" => true, "tile_table_epoch" => @spec.table_epoch,
        "tile_view_index" => index, "tile_row_id" => row && row[:id],
        "tile_detail" => @detail,
        "tile_detail_id" => @detail && row && row[:id],
        "tile_item_id" => @detail && row && row[:item_ids].to_a[index] }
    end

    def restore_table_view(remembered)
      # A new deal can reuse IDs/indices for different trains and tiles.
      # Return to the new hand instead of reopening unrelated old details.
      return unless remembered["tile_view"] && remembered["tile_table_epoch"] == @spec.table_epoch
      open_table(speak: false)
      row_index = @spec.table.index { |row| row[:id] == remembered["tile_row_id"] }
      if remembered["tile_detail_id"]
        detail = @spec.table.index { |row| row[:id] == remembered["tile_detail_id"] }
        return unless detail && open_details(detail, speak: false)
        item_index = @spec.table[detail][:item_ids].to_a.index(remembered["tile_item_id"])
        @controls.first.index = bounded_index(item_index || remembered["tile_view_index"])
      else
        @controls.first.index = bounded_index(row_index || remembered["tile_view_index"])
      end
    end

    def bounded_index(value)
      [[value.to_i, 0].max, [@controls.first.options.length - 1, 0].max].min
    end

    def unavailable
      speak(_("This move is not available."))
      true
    end
  end
end
