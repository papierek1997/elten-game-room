require_relative "specifications"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations



  class PieceBoard
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      @width = @spec.width.to_i
      @height = @spec.height.to_i
      @pieces = normalize_rows(@spec.pieces, "piece rows")
      @cell_labels = if @spec.cell_labels == nil
        Array.new(@height) { Array.new(@width, "") }
      else
        normalize_rows(@spec.cell_labels, "cell label rows", allow_any: true)
      end
      validate_spec!
      @navigable = normalize_navigable
      @selectable = normalize_selectable
      @targets = normalize_targets
      @activation_action = @spec.activation_action
      @selected = restore_selection(state)
      @orientation = normalized_orientation(state_value(state, "orientation", @spec.default_orientation || "normal"))
      @coordinate_label_sets = normalize_coordinate_label_sets
      @coordinate_label_names = normalize_coordinate_label_names
      @coordinate_label_set = normalized_coordinate_label_set(
        state_value(state, "coordinate_label_set", @spec.default_coordinate_label_set)
      )
      @default_navigable = @navigable
      @navigable_by_coordinate_label_set = normalize_navigable_by_coordinate_label_set
      @navigable = active_navigable
      @silent_positions_by_coordinate_label_set = normalize_silent_positions_by_coordinate_label_set
      @silent_positions = active_silent_positions
      @square_details = normalize_square_details

      initial_position = [state_integer(state, "x", 0), state_integer(state, "y", 0)]
      if @navigable != nil && !@navigable.include?(initial_position)
        initial_position = @navigable.first
      end

      @control = OrientedGridBox.new(
        @width,
        @height,
        row_origin: effective_row_origin,
        column_origin: effective_column_origin,
        coordinate_labels: active_coordinate_labels,
        coordinate_first: true,
        header: @spec.header.to_s,
        x: internal_x(initial_position[0]),
        y: internal_y(initial_position[1]),
        quiet: true
      )
      if @navigable != nil
        refresh_navigable_positions!
      end
      refresh_silent_positions!
      @control.silent_focus_handler = -> { play_surface_sound }
      refresh_labels!
      @control.on(:select) do |params|
        coordinates = params.to_a
        handle_selection(logical_x(coordinates[0]), logical_y(coordinates[1]))
      end
    end

    def fields
      [@control]
    end

    def sound_player=(player)
      @sound_player = player
    end

    def state
      result = {
        "x" => logical_x(@control.x),
        "y" => logical_y(@control.y),
        "orientation" => @orientation,
        "coordinate_label_set" => @coordinate_label_set
      }
      if @selected != nil
        result["selected"] = { "x" => @selected[0], "y" => @selected[1] }
      end
      result
    end

    def handle_command(command, payload = {})
      case command.to_s
      when "toggle_orientation"
        toggle_orientation
      when "toggle_coordinate_labels"
        toggle_coordinate_labels
      when "announce_moves"
        announce_moves
      when "navigate_piece"
        navigate_piece(payload)
      when "announce_square_details"
        announce_square_details
      else
        false
      end
    end

    def suppress_next_focus!(_field_index = 0)
      @control.suppress_next_focus!
    end

    def cancel_pending_action?
      @selected != nil
    end

    def cancel_pending_action!
      return false if @selected == nil

      clear_selection(_("Piece selection cancelled."))
      true
    end

    def movement_command(arguments)
      values = arguments.to_a.map { |value| value.to_s.strip }
      if values.length != 2
        return MovementCommandResult.new(message: _("Enter a source and destination, for example /A1 B2."))
      end

      origin = command_coordinate(values[0])
      destination = command_coordinate(values[1])
      missing = origin == nil ? values[0] : values[1]
      if origin == nil || destination == nil
        return MovementCommandResult.new(
          message: _("Field %{field} is not available in the current board notation.") % { field: missing }
        )
      end
      if !@selectable.include?(origin) || piece_at(origin) == nil
        return MovementCommandResult.new(message: origin_error_message(origin))
      end
      if origin == destination || !target_allowed?(origin, destination)
        return MovementCommandResult.new(message: destination_error_message(origin, destination))
      end

      MovementCommandResult.new(action: move_action(origin, destination, source: "chat_command"))
    end

    private

    def handle_selection(x, y)
      position = [x, y].freeze
      if @silent_positions.include?(position)
        play_surface_sound
      elsif @selected == nil && @activation_action != nil
        emit_action(
          @activation_action.kind,
          @activation_action.name,
          @activation_action.payload,
          source: @activation_action.source
        )
      elsif @selected == nil
        select_origin(position)
      elsif position == @selected
        clear_selection(_("Piece selection cancelled."))
      elsif target_allowed?(@selected, position)
        emit_move(position)
      elsif @selectable.include?(position)
        select_origin(position)
      else
        announce(destination_error_message(@selected, position))
      end
    end

    def select_origin(position)
      if !@selectable.include?(position) || piece_at(position) == nil
        announce(origin_error_message(position))
        return
      end

      @selected = position
      refresh_labels!
      targets = @targets[position]
      message = if targets == nil
        _("Selected %{piece} on %{field}. Choose its destination.") % {
          piece: piece_at(position).label.to_s,
          field: coordinate_label(position)
        }
      elsif targets.empty?
        _("Selected %{piece} on %{field}. There are no available moves.") % {
          piece: piece_at(position).label.to_s,
          field: coordinate_label(position)
        }
      else
        _("Selected %{piece} on %{field}. Available moves: %{targets}.") % {
          piece: piece_at(position).label.to_s,
          field: coordinate_label(position),
          targets: targets.map { |target| coordinate_label(target) }.join(", ")
        }
      end
      announce(message)
    end

    def emit_move(destination)
      action = move_action(@selected, destination)
      emit_action(action.kind, action.name, action.payload, source: action.source)
    end

    def move_action(origin, destination, source: nil)
      piece = piece_at(origin)
      Action.new(
        kind: "piece_board",
        name: "move",
        payload: {
          "board_id" => @spec.id.to_s,
          "piece_id" => piece.id.to_s,
          "piece_owner" => piece.owner,
          "piece_kind" => piece.kind,
          "piece_value" => piece.value,
          "from_x" => origin[0],
          "from_y" => origin[1],
          "from_field" => coordinate_label(origin),
          "to_x" => destination[0],
          "to_y" => destination[1],
          "to_field" => coordinate_label(destination)
        },
        source: source
      )
    end

    def clear_selection(message)
      @selected = nil
      refresh_labels!
      announce(message)
    end

    def announce(message)
      speak(message.to_s)
    end

    def origin_error_message(position)
      handler = @spec.origin_error
      if handler.respond_to?(:call)
        message = handler.call(position, coordinate_label(position), piece_at(position), method(:coordinate_label))
        return message.to_s if !message.to_s.empty?
      end

      piece = piece_at(position)
      return _("Field %{field} is empty.") % { field: coordinate_label(position) } if piece == nil

      _("The %{piece} on %{field} cannot be selected.") % {
        piece: piece.label.to_s,
        field: coordinate_label(position)
      }
    end

    def destination_error_message(origin, destination)
      handler = @spec.destination_error
      if handler.respond_to?(:call)
        message = handler.call(
          origin,
          destination,
          coordinate_label(origin),
          coordinate_label(destination),
          piece_at(origin),
          piece_at(destination),
          method(:coordinate_label)
        )
        return message.to_s if !message.to_s.empty?
      end

      _("You cannot move the selected piece to %{field}. Press V to hear its available moves.") % {
        field: coordinate_label(destination)
      }
    end

    def refresh_labels!
      @control.set_cells(display_rows)
    end

    def display_rows
      Array.new(@height) do |internal_row|
        Array.new(@width) do |internal_column|
          decorated_cell_label(logical_x(internal_column), logical_y(internal_row))
        end
      end
    end

    def decorated_cell_label(x, y)
      position = [x, y]
      piece = piece_at(position)
      terrain = @cell_labels[y][x].to_s
      base = piece == nil ? @spec.empty_label.to_s : piece.label.to_s
      if !terrain.empty?
        base = base.empty? ? terrain : _("%{piece}; %{cell}") % { piece: base, cell: terrain }
      end
      return _("%{cell}; selected") % { cell: base } if position == @selected
      if @selected != nil && @targets[@selected].to_a.include?(position)
        return _("%{cell}; available move") % { cell: base }
      end

      base
    end

    def target_allowed?(origin, destination)
      return true if !@targets.key?(origin)

      @targets[origin].include?(destination)
    end

    def piece_at(position)
      @pieces[position[1]][position[0]]
    end

    def validate_spec!
      raise ArgumentError, "a piece board requires an id" if @spec.id.to_s.empty?
      raise ArgumentError, "piece board width must be positive" if @width <= 0
      raise ArgumentError, "piece board height must be positive" if @height <= 0
      raise ArgumentError, "unsupported row origin" if ![:top, :bottom].include?(row_origin)

      pieces = @pieces.flatten.compact
      if pieces.any? { |piece| !piece.is_a?(Piece) }
        raise ArgumentError, "piece board cells must contain Piece objects or nil"
      end
      if @spec.activation_action != nil && !@spec.activation_action.is_a?(Action)
        raise ArgumentError, "piece board activation action must be a surface action"
      end
      ids = pieces.map { |piece| piece.id.to_s }
      raise ArgumentError, "piece ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "piece ids must be unique" if ids.uniq.length != ids.length
      raise ArgumentError, "piece labels must not be empty" if pieces.any? { |piece| piece.label.to_s.empty? }
    end

    def normalize_rows(value, label, allow_any: false)
      rows = value.to_a
      if rows.length != @height || rows.any? { |row| row.to_a.length != @width }
        raise ArgumentError, "#{label} must match piece board dimensions"
      end
      rows.map do |row|
        row.to_a.map do |cell|
          allow_any ? cell.to_s : cell
        end
      end
    end

    def normalize_selectable
      source = if @spec.selectable == nil
        positions_with_pieces
      else
        @spec.selectable.to_a.map { |position| normalize_coordinate(position) }
      end
      positions = source.uniq
      if positions.any? { |position| piece_at(position) == nil }
        raise ArgumentError, "selectable positions must contain pieces"
      end
      if @navigable != nil && positions.any? { |position| !@navigable.include?(position) }
        raise ArgumentError, "selectable positions must be navigable"
      end
      positions
    end

    def normalize_targets
      return {} if @spec.targets == nil
      raise ArgumentError, "piece board targets must be a hash" if !@spec.targets.respond_to?(:each_pair)

      @spec.targets.each_pair.each_with_object({}) do |(origin, destinations), result|
        normalized_origin = normalize_coordinate(origin)
        if !@selectable.include?(normalized_origin)
          raise ArgumentError, "move targets require a selectable origin"
        end
        result[normalized_origin] = destinations.to_a.map do |destination|
          normalize_coordinate(destination)
        end.uniq
        if @navigable != nil && result[normalized_origin].any? { |position| !@navigable.include?(position) }
          raise ArgumentError, "move targets must be navigable"
        end
      end
    end

    def normalize_navigable(value = @spec.navigable)
      return nil if value == nil

      positions = value.to_a.map { |position| normalize_coordinate(position) }.uniq
      raise ArgumentError, "a navigable piece board requires at least one field" if positions.empty?
      positions.freeze
    end

    def normalize_navigable_by_coordinate_label_set
      source = @spec.navigable_by_coordinate_label_set
      return {} if source == nil

      source.to_h.each_with_object({}) do |(key, positions), result|
        result[key.to_s] = normalize_navigable(positions)
      end
    end

    def active_navigable
      return @default_navigable if !@navigable_by_coordinate_label_set.key?(@coordinate_label_set)

      @navigable_by_coordinate_label_set[@coordinate_label_set]
    end

    def normalize_silent_positions_by_coordinate_label_set
      @spec.silent_positions_by_coordinate_label_set.to_h.each_with_object({}) do |(key, positions), result|
        result[key.to_s] = positions.to_a.map { |position| normalize_coordinate(position) }.uniq.freeze
      end
    end

    def active_silent_positions
      @silent_positions_by_coordinate_label_set.fetch(@coordinate_label_set, []).to_a
    end

    def nearest_navigable_position(position)
      @navigable.min_by do |x, y|
        [
          (x - position[0]).abs + (y - position[1]).abs,
          internal_y(y),
          internal_x(x)
        ]
      end
    end

    def positions_with_pieces
      positions = []
      @pieces.each_with_index do |row, y|
        row.each_with_index { |piece, x| positions << [x, y].freeze if piece != nil }
      end
      positions
    end

    def restore_selection(state)
      value = state_value(state, "selected", nil)
      return nil if value == nil

      position = normalize_coordinate(value)
      @selectable.include?(position) && piece_at(position) != nil ? position : nil
    rescue ArgumentError
      nil
    end

    def normalize_coordinate(value)
      x, y = if value.is_a?(Array)
        value
      elsif value.respond_to?(:key?)
        [value["x"] || value[:x], value["y"] || value[:y]]
      else
        coordinate_from_label(value.to_s)
      end
      raise ArgumentError, "a board coordinate requires x and y" if x == nil || y == nil

      position = [Integer(x), Integer(y)].freeze
      if !position[0].between?(0, @width - 1) || !position[1].between?(0, @height - 1)
        raise ArgumentError, "board coordinate is outside the board"
      end
      position
    rescue TypeError, ArgumentError
      raise ArgumentError, "invalid board coordinate: #{value.inspect}"
    end

    def coordinate_from_label(value)
      match = /\A([A-Za-z]+)([1-9]\d*)\z/.match(value.strip)
      raise ArgumentError, "invalid field label" if match == nil

      column = match[1].upcase.each_byte.reduce(0) do |number, character|
        number * 26 + character - 64
      end
      [column - 1, match[2].to_i - 1]
    end

    def command_coordinate(value)
      labels = active_coordinate_labels
      if labels != nil
        labels.each_with_index do |row, y|
          row.to_a.each_with_index do |label, x|
            return [x, y].freeze if !label.to_s.empty? && label.to_s.casecmp?(value.to_s)
          end
        end
        return nil
      end

      normalize_coordinate(value)
    rescue ArgumentError
      nil
    end

    def coordinate_label(position)
      custom = active_coordinate_labels&.dig(position[1].to_i, position[0].to_i).to_s
      return custom if !custom.empty?

      column = position[0].to_i
      letters = ""
      loop do
        letters = (65 + (column % 26)).chr + letters
        column = column / 26 - 1
        break if column < 0
      end
      "#{letters}#{position[1].to_i + 1}"
    end

    def row_origin
      (@spec.row_origin || :top).to_sym
    end

    def effective_row_origin
      @orientation == "rotated" ? opposite_row_origin(row_origin) : row_origin
    end

    def effective_column_origin
      @orientation == "rotated" ? :right : :left
    end

    def logical_x(internal_x)
      effective_column_origin == :right ? @width - internal_x.to_i - 1 : internal_x.to_i
    end

    def logical_y(internal_y)
      effective_row_origin == :bottom ? @height - internal_y.to_i - 1 : internal_y.to_i
    end

    def internal_y(logical_y)
      value = [[logical_y.to_i, 0].max, @height - 1].min
      effective_row_origin == :bottom ? @height - value - 1 : value
    end

    def internal_x(logical_x)
      value = [[logical_x.to_i, 0].max, @width - 1].min
      effective_column_origin == :right ? @width - value - 1 : value
    end

    def toggle_orientation
      @orientation = @orientation == "rotated" ? "normal" : "rotated"
      @control.set_orientation(row_origin: effective_row_origin, column_origin: effective_column_origin)
      refresh_navigable_positions!
      refresh_silent_positions!
      refresh_labels!
      message = @spec.orientation_labels.to_h[@orientation] ||
        (@orientation == "rotated" ? _("The board is rotated.") : _("The board uses its normal orientation."))
      announce(message)
      true
    end

    def toggle_coordinate_labels
      keys = @coordinate_label_sets.keys
      if keys.length < 2
        announce(_("No other field notation is available."))
        return true
      end

      index = keys.index(@coordinate_label_set).to_i
      @coordinate_label_set = keys[(index + 1) % keys.length]
      current_position = [logical_x(@control.x), logical_y(@control.y)]
      @navigable = active_navigable
      @silent_positions = active_silent_positions
      if @navigable != nil && !@navigable.include?(current_position)
        current_position = nearest_navigable_position(current_position)
        @control.set_logical_position(*current_position)
      end
      refresh_navigable_positions!
      refresh_silent_positions!
      @control.coordinate_labels = active_coordinate_labels
      refresh_labels!
      announce(
        _("Field notation: %{notation}.") % {
          notation: @coordinate_label_names.fetch(@coordinate_label_set, @coordinate_label_set)
        }
      )
      true
    end

    def announce_moves
      position = [logical_x(@control.x), logical_y(@control.y)]
      moves = @targets[position].to_a
      if moves.empty?
        announce(_("There are no available moves from %{field}.") % { field: coordinate_label(position) })
      else
        announce(
          _("Available moves from %{field}: %{moves}.") % {
            field: coordinate_label(position),
            moves: moves.map { |target| coordinate_label(target) }.join(", ")
          }
        )
      end
      true
    end

    def navigate_piece(payload)
      values = payload.respond_to?(:to_h) ? payload.to_h : {}
      owner = values["owner"] || values[:owner]
      raw_kinds = values["kinds"] || values[:kinds] || values["kind"] || values[:kind]
      kinds = raw_kinds == nil ? [] : (raw_kinds.is_a?(Array) ? raw_kinds : [raw_kinds]).map(&:to_s)
      positions = positions_with_pieces.select do |position|
        piece = piece_at(position)
        (owner.to_s.empty? || piece.owner.to_s.casecmp?(owner.to_s)) &&
          (kinds.empty? || kinds.include?(piece.kind.to_s))
      end
      if positions.empty?
        announce((values["empty_message"] || values[:empty_message] || _("No matching pieces were found.")).to_s)
        return true
      end

      positions.sort_by! { |x, y| [internal_y(y), internal_x(x)] }
      current = [logical_x(@control.x), logical_y(@control.y)]
      current_index = positions.index(current)
      destination = current_index == nil ? positions.first : positions[(current_index + 1) % positions.length]
      @control.set_logical_position(*destination)
      piece = piece_at(destination)
      announce(_("%{field}, %{piece}.") % { field: coordinate_label(destination), piece: piece.label })
      true
    end

    def announce_square_details
      position = [logical_x(@control.x), logical_y(@control.y)]
      message = @square_details&.dig(position[1], position[0]).to_s
      message = _("No additional information is available for %{field}.") % { field: coordinate_label(position) } if message.empty?
      announce(message)
      true
    end

    def refresh_navigable_positions!
      positions = @navigable&.map { |x, y| [internal_x(x), internal_y(y)] }
      @control.navigable_positions = positions
    end

    def refresh_silent_positions!
      positions = @silent_positions.map { |x, y| [internal_x(x), internal_y(y)] }
      @control.silent_positions = positions
    end

    def play_surface_sound
      name = @spec.silent_sound.to_s
      @sound_player&.call(name) if !name.empty?
      true
    end

    def active_coordinate_labels
      @coordinate_label_sets[@coordinate_label_set]
    end

    def normalize_coordinate_label_sets
      source = @spec.coordinate_label_sets
      return {} if source == nil

      source.to_h.each_with_object({}) do |(key, rows), result|
        result[key.to_s] = normalize_rows(rows, "coordinate label rows", allow_any: true)
      end
    end

    def normalize_coordinate_label_names
      @spec.coordinate_label_names.to_h.each_with_object({}) do |(key, value), result|
        result[key.to_s] = value.to_s
      end
    end

    def normalized_coordinate_label_set(value)
      key = value.to_s
      return key if @coordinate_label_sets.key?(key)

      @coordinate_label_sets.keys.first
    end

    def normalize_square_details
      return nil if @spec.square_details == nil

      normalize_rows(@spec.square_details, "square detail rows", allow_any: true)
    end

    def normalized_orientation(value)
      value.to_s == "rotated" ? "rotated" : "normal"
    end

    def opposite_row_origin(value)
      value == :bottom ? :top : :bottom
    end

    def state_integer(state, key, default)
      state_value(state, key, default).to_i
    end


  end
end
