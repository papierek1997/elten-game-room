require_relative "specifications"
module GameSurfaces



  # A compact, accessible surface for race games in which the meaningful
  # information is a pawn's logical position, not its coordinates on a drawn
  # board. Games provide already translated labels and optional actions; the
  # surface only preserves selection and emits the chosen action.
  class PawnTrackSurface
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      @player_labels = @spec.player_labels
      @menus = @spec.menus || {}
      @menu_positions = state_value(state, "menu_positions", {}).to_h.select { |key, _| key == "" || @menus.key?(key) }.transform_values(&:dup)
      @menu = state_value(state, "menu", "").to_s
      @menu = "" if @menus[@menu].to_a.empty?
      @items = @menu.empty? ? @spec.items.to_a : @menus[@menu]
      validate_spec!
      @index = restored_index(state)
      @control = RefreshAwareListBox.new(
        @items.map { |item| item.label.to_s },
        header: @spec.header.to_s,
        index: @index,
        quiet: true,
        empty_label: @spec.empty_label.to_s
      )
      @control.on(:select) do |params|
        item = @items[params.to_a[0].to_i]
        action = item&.action || (@menu.empty? ? @spec.activation_action : nil)
        emit_surface_action(action) if action != nil
      end
    end

    def fields
      [@control]
    end

    def state
      item = @items[@control.index.to_i]
      {
        "index" => @control.index.to_i,
        "item_id" => item&.id.to_s,
        "menu" => @menu,
        "player_labels" => @player_labels,
        "menu_positions" => @menu_positions.transform_values(&:dup)
      }
    end

    # Local navigation only; Enter still uses the ordinary game action path.
    # Menu choice IDs survive replay refresh, and the game regenerates legal
    # entries/costs after each confirmed operation. An exhausted menu closes.
    def handle_command(command, payload = {})
      if command.to_s == "toggle_player_labels" && @player_labels
        @player_labels = @player_labels == "colours" ? "names" : "colours"
        speak(payload.fetch(@player_labels))
        return true
      end
      return false unless command.to_s == "open_menu"
      menu = payload["menu"].to_s
      return false if @menus[menu].to_a.empty?
      remember_menu_position
      @menu = menu
      replace_items(@menus[menu], position: @menu_positions[menu])
      true
    end

    def cancel_pending_action?
      !@menu.empty?
    end

    def cancel_pending_action!
      return false if @menu.empty?
      remember_menu_position
      @menu = ""
      replace_items(@spec.items.to_a, position: @menu_positions[""])
      true
    end

    def suppress_next_focus!(_field_index = 0)
      @control.suppress_next_focus!
    end

    private

    def remember_menu_position
      @menu_positions[@menu] = {"index" => @control.index.to_i, "item_id" => @items[@control.index.to_i]&.id}
    end

    def replace_items(items, position: nil)
      @items = items
      @control.options = items.map(&:label)
      position = position.to_h
      @control.index = @items.index { |item| item.id == position["item_id"] } ||
        position.fetch("index", 0).to_i.clamp(0, [@items.size - 1, 0].max)
      # Changing a local menu is not entering the table again. Announce the
      # selected entry, retaining native focus/braille without the full status.
      @control.focus(nil, nil, "")
    end

    def emit_surface_action(action)
      return handle_command(action.name, action.payload) if action.kind == "surface" && action.name == "open_menu"
      emit_action(action.kind, action.name, action.payload, source: action.source)
    end

    def restored_index(state)
      remembered_id = state_value(state, "item_id", "").to_s
      by_id = @items.index { |item| item.id.to_s == remembered_id } if !remembered_id.empty?
      return by_id if by_id != nil

      requested = state_value(state, "index", 0).to_i
      return 0 if @items.empty?

      [[requested, 0].max, @items.length - 1].min
    end

    def validate_spec!
      raise ArgumentError, "a pawn track requires an id" if @spec.id.to_s.empty?
      ids = @items.map { |item| item.id.to_s }
      raise ArgumentError, "pawn track item ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "pawn track item ids must be unique" if ids.uniq.length != ids.length
      raise ArgumentError, "pawn track item labels must not be empty" if @items.any? { |item| item.label.to_s.empty? }
      actions = @items.map(&:action).compact
      actions << @spec.activation_action if @spec.activation_action != nil
      if actions.any? { |action| !action.is_a?(Action) }
        raise ArgumentError, "pawn track actions must be surface actions"
      end
    end


  end
end
