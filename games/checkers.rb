require_relative '../lib/board_preference_definition'
require_relative "../lib/colour_board_presentation"
require_relative "../lib/game_bots"
require_relative "../lib/game_tree_search"
require_relative "board_game"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Checkers < TurnBasedBoardGame
    include GameRoomColourBoardPresentation
    MEN_CAPTURE_BACKWARD = 1
    FLYING_KINGS = 2
    MANDATORY_CAPTURE = 4
    MAXIMUM_CAPTURE = 8
    CONTINUE_CAPTURE = 16
    MEN_MOVE_BACKWARD = 32
    PROMOTE_DURING_CAPTURE = 64
    KING_PRIORITY = 128
    DEFER_CAPTURE_REMOVAL = 256
    CLASSIC_RULES = MEN_CAPTURE_BACKWARD | FLYING_KINGS | MANDATORY_CAPTURE |
      MAXIMUM_CAPTURE | CONTINUE_CAPTURE | DEFER_CAPTURE_REMOVAL
    DIAGONALS = [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(&:freeze).freeze
    FORWARD_DIRECTIONS = {
      0 => [[-1, 1], [1, 1]].map(&:freeze).freeze,
      1 => [[-1, -1], [1, -1]].map(&:freeze).freeze
    }.freeze
    PLAYABLE_COORDINATES = [8, 10, 12].each_with_object({}) do |size, result|
      result[size] = Array.new(size) do |y|
        Array.new(size) { |x| [x, y].freeze if (x + y).even? }
      end.flatten(1).compact.freeze
    end.freeze

    def board_preference_definitions
      [GameRoomBoardPreference.orientation,
        GameRoomBoardPreference::Definition.new(key: 'coordinate_label_set', values: %w[numeric algebraic],
          command: 'toggle_coordinate_labels', state_key: 'coordinate_label_set')]
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      action == "move" ? "play2" : nil
    end

    def notification_option_keys(_options); %w[board_size]; end

    def id
      "checkers"
    end

    def name
      _("Checkers")
    end

    def short_description
      _("Capture your opponent's pieces, crown your own and win by leaving your opponent with no legal moves.")
    end

    def supports_bots?
      true
    end

    def shareable_simulation_snapshot?
      true
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "board_size",
          label: _("Board size"),
          kind: :choice,
          default: 8,
          choices: [8, 10, 12].map { |size| OptionChoice.new(value: size, label: _("%{size} by %{size} (%{fields} fields)") % { size: size, fields: size * size }) }
        ),
        OptionDefinition.new(
          key: "rules",
          label: _("Optional rules. Use Space to select or clear"),
          kind: :multiple_choice,
          default: CLASSIC_RULES,
          choices: [
            OptionChoice.new(value: MEN_CAPTURE_BACKWARD, label: _("Men may capture backward")),
            OptionChoice.new(value: FLYING_KINGS, label: _("Kings move and capture over any distance")),
            OptionChoice.new(value: MANDATORY_CAPTURE, label: _("Capturing is mandatory")),
            OptionChoice.new(value: MAXIMUM_CAPTURE, label: _("The move capturing the most pieces is mandatory")),
            OptionChoice.new(value: CONTINUE_CAPTURE, label: _("A capture sequence must be completed")),
            OptionChoice.new(value: MEN_MOVE_BACKWARD, label: _("Men may move backward without capturing")),
            OptionChoice.new(value: PROMOTE_DURING_CAPTURE, label: _("Promote immediately during a capture sequence")),
            OptionChoice.new(value: KING_PRIORITY, label: _("Prefer a king when equally long captures are available")),
            OptionChoice.new(value: DEFER_CAPTURE_REMOVAL, label: _("Captured pieces block the board until the capture sequence ends"))
          ]
        )
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      rules = values["rules"].to_i
      if rule?(rules, MAXIMUM_CAPTURE) && !rule?(rules, MANDATORY_CAPTURE)
        return _("Maximum capture requires mandatory capturing.")
      end
      if rule?(rules, KING_PRIORITY) && !rule?(rules, MAXIMUM_CAPTURE)
        return _("King priority requires the maximum-capture rule.")
      end
      if rule?(rules, MAXIMUM_CAPTURE) && !rule?(rules, CONTINUE_CAPTURE)
        return _("Maximum capture requires completing capture sequences.")
      end

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      _("%{size} by %{size}; selected rule set") % { size: values["board_size"] }
    end

    def rule_sections
      generated_rule_sections
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::AlphaBetaStrategy.new(
        max_depth: 7,
        node_limit: 60_000,
        optimize_transpositions: true
      )
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = initial_state(players, options)
      history = [starting_history(players)]
      accepted = []
      apply_events!(state, events, repository, session, accepted, history)

      Replay.new(
        board: state[:board], players: players, current_player: state[:current_player],
        winner: state[:winner], draw: state[:draw], accepted_events: accepted,
        history: history, state: state
      )
    end

    def incremental_replay(replay, session, events, repository)
      return nil if replay == nil

      state = duplicate_state(replay.state)
      history = replay.history.dup
      accepted = replay.accepted_events.dup
      apply_events!(state, events, repository, session, accepted, history)
      Replay.new(
        board: state[:board], players: state[:players], current_player: state[:current_player],
        winner: state[:winner], draw: state[:draw], accepted_events: accepted,
        history: history, state: state
      )
    end

    def available_board_moves(replay, actor)
      cached = replay.instance_variable_get(:@checkers_available_moves)
      if cached != nil && same_user?(cached[:actor], actor)
        return cached[:moves]
      end

      moves = moves_for_state(replay.state, actor).freeze
      cache_available_moves(replay, actor, moves)
      moves
    end

    def history_presentation_depends_on_surface_state?
      true
    end

    def history_entries_for_display(replay, _viewer, surface_state: {})
      presentation = surface_state.respond_to?(:to_h) ? surface_state.to_h : {}
      notation = presentation["coordinate_label_set"] || presentation[:coordinate_label_set]
      return replay.history if notation.to_s != "algebraic"

      replay.history.map do |entry|
        data = entry.kind == :move && entry.value.respond_to?(:to_h) ? entry.value.to_h : nil
        next entry if data == nil || data["from_x"] == nil || data["to_x"] == nil

        displayed = entry.dup
        displayed.text = checkers_move_history_text(data, notation: "algebraic")
        displayed.field = checkers_history_field(data, "to", notation: "algebraic")
        displayed
      end
    end

    def describe_event_for_display(event, repository, replay, viewer, surface_state: {})
      event_id = repository.event_id(event).to_i
      entry = history_entries_for_display(
        replay,
        viewer,
        surface_state: surface_state
      ).find do |candidate|
        candidate.kind == :move && candidate.event_id.to_i == event_id
      end
      entry&.text
    end

    def surface_spec(replay, viewer)
      state = replay.state
      size = state[:size]
      pieces = Array.new(size) { Array.new(size) }
      state[:board].each_with_index do |row, y|
        row.each_with_index do |code, x|
          next if code == nil

          owner = state[:players][piece_owner(code)]
          pieces[y][x] = GameSurfaces::Piece.new(
            id: "#{code}:#{x}:#{y}",
            label: piece_label(code),
            owner: owner,
            kind: king?(code) ? "king" : "man",
            value: code
          )
        end
      end
      moves = !replay.finished? && same_user?(replay.current_player, viewer) ? moves_for_state(state, viewer) : []
      orientation = board_orientation(replay, viewer)
      build_piece_board(
        replay,
        viewer,
        width: size,
        height: size,
        pieces: pieces,
        moves: moves,
        navigable: nil,
        navigable_by_coordinate_label_set: {
          "numeric" => nil,
          "algebraic" => nil
        },
        silent_positions_by_coordinate_label_set: {
          "numeric" => unplayable_fields(size)
        },
        silent_sound: "ding",
        coordinate_label_sets: checkers_coordinate_label_sets(size),
        coordinate_label_names: {
          "numeric" => _("draughts numbering"),
          "algebraic" => _("chess coordinates")
        },
        default_coordinate_label_set: "numeric",
        default_orientation: orientation[:default],
        orientation_labels: orientation[:labels]
      )
    end

    def board_origin_error(replay, actor, position, field:, piece:, labeler:)
      contextual = board_selection_context_error(replay, actor, field: field, piece: piece)
      return contextual if contextual != nil

      state = replay.state
      marker = player_index(state[:players], actor)
      if state[:forced_from] != nil && position != state[:forced_from]
        forced_piece = state[:board][state[:forced_from][1]][state[:forced_from][0]]
        return _("You must continue capturing with %{piece} on %{field}.") % {
          piece: piece_label(forced_piece),
          field: labeler.call(state[:forced_from])
        }
      end

      captures = raw_captures(state, marker)
      if !captures.empty? && rule?(state[:rules], MANDATORY_CAPTURE)
        candidates = captures
        if rule?(state[:rules], MAXIMUM_CAPTURE)
          maximum = filter_maximum_captures(state, candidates)
          if candidates.any? { |move| move.from == position } && maximum.none? { |move| move.from == position }
            return _("The longest capture is mandatory. This piece cannot begin the required sequence. Choose: %{fields}.") % {
              fields: checkers_origin_fields(maximum, labeler)
            }
          end
          candidates = maximum
        end
        if rule?(state[:rules], KING_PRIORITY) &&
            candidates.any? { |move| king?(state[:board][move.from[1]][move.from[0]]) }
          kings = candidates.select { |move| king?(state[:board][move.from[1]][move.from[0]]) }
          if !king?(piece.value)
            return _("A king has priority for an equally long capture. Choose a king on %{fields}.") % {
              fields: checkers_origin_fields(kings, labeler)
            }
          end
          candidates = kings
        end
        if candidates.none? { |move| move.from == position }
          return _("Capturing is mandatory. Choose a piece on %{fields}.") % {
            fields: checkers_origin_fields(candidates, labeler)
          }
        end
      end

      super(replay, actor, position, field: field, piece: piece, labeler: labeler)
    end

    def board_destination_error(
      replay,
      actor,
      origin,
      destination,
      origin_field:,
      destination_field:,
      piece:,
      target:,
      labeler:
    )
      contextual = board_turn_error(replay, actor)
      return contextual if contextual != nil
      if target != nil
        if !same_user?(target.owner, actor)
          return _("To capture %{piece} on %{field}, choose an empty landing field beyond it.") % {
            piece: target.label.to_s,
            field: destination_field
          }
        end
        return super(
          replay,
          actor,
          origin,
          destination,
          origin_field: origin_field,
          destination_field: destination_field,
          piece: piece,
          target: target,
          labeler: labeler
        )
      end

      moves = available_board_moves(replay, actor).select { |move| move.from == origin }
      destinations = moves.map(&:to).uniq
      if replay.state[:forced_from] != nil
        return _("You must continue the capture from %{from}. Available destinations: %{fields}.") % {
          from: origin_field,
          fields: destinations.map { |position| labeler.call(position) }.join(", ")
        }
      end
      if moves.any? { |move| !move.metadata["capture"].to_s.empty? } &&
          rule?(replay.state[:rules], MANDATORY_CAPTURE)
        return _("Capturing is mandatory. Available destinations from %{from}: %{fields}.") % {
          from: origin_field,
          fields: destinations.map { |position| labeler.call(position) }.join(", ")
        }
      end

      super(
        replay,
        actor,
        origin,
        destination,
        origin_field: origin_field,
        destination_field: destination_field,
        piece: piece,
        target: target,
        labeler: labeler
      )
    end

    def custom_game_shortcuts(replay, viewer)
      own_index = player_index(replay.players, viewer)
      own_index = 0 if own_index == nil
      opponent_index = own_index == 0 ? 1 : 0
      [
        announcement_shortcut(
          key: "c",
          label: _("read who plays each colour"),
          message: colour_assignments(replay)
        ),
        surface_shortcut(
          key: "v",
          label: _("read the available moves of the current piece"),
          command: "announce_moves"
        ),
        surface_shortcut(
          key: "k",
          label: _("go to your next king"),
          command: "navigate_piece",
          payload: {
            "owner" => replay.players[own_index],
            "kind" => "king",
            "empty_message" => _("You have no kings.")
          }
        ),
        surface_shortcut(
          key: "k",
          modifiers: [:shift],
          label: _("go to the opponent's next king"),
          command: "navigate_piece",
          payload: {
            "owner" => replay.players[opponent_index],
            "kind" => "king",
            "empty_message" => _("The opponent has no kings.")
          }
        ),
        surface_shortcut(
          key: "h",
          modifiers: [:control],
          label: _("change the field notation"),
          command: "toggle_coordinate_labels"
        ),
        surface_shortcut(
          key: "h",
          modifiers: [:control, :shift],
          label: _("rotate the board"),
          command: "toggle_orientation"
        )
      ]
    end

    def remaining_piece_counts(replay)
      pieces = replay.board.flatten.compact
      [0, 1].map do |marker|
        _("men: %{men}, kings: %{kings}") % {
          men: pieces.count("#{marker}m"), kings: pieces.count("#{marker}k")
        }
      end
    end

    def bot_search_key(replay, actor)
      state = replay.state
      board_key = compact_board_key(state[:board])
      # Captures only remove pieces. Positions with more pieces can never
      # recur, so they do not distinguish future draw results. Retain every
      # still-reachable repetition count, not just the current position.
      piece_count = board_key.count("mk")
      @checkers_repetition_sizes ||= {}
      @checkers_repetition_sizes.clear if @checkers_repetition_sizes.length >= 20_000
      repetitions = state[:positions].select do |position, _count|
        count = @checkers_repetition_sizes[position] ||= position.rpartition(":").last.count("mk")
        count == piece_count
      end.freeze
      [
        state[:size],
        state[:rules],
        player_index(replay.players, actor),
        player_index(replay.players, replay.current_player),
        state[:forced_from]&.dup&.freeze,
        state.fetch(:capture_blockers, []).sort,
        state[:captured_this_turn] == true ? 1 : 0,
        state[:promoted_this_turn] == true ? 1 : 0,
        state[:quiet_moves].to_i,
        state[:last_to]&.dup&.freeze,
        state[:winner],
        state[:draw] == true ? 1 : 0,
        board_key,
        repetitions
      ].freeze
    end

    def bot_forced_continuation?(replay)
      replay.state[:forced_from] != nil
    end

    def bot_move_order_key(replay, actor)
      # A remembered MOVE may order another search with a different draw
      # history. Its SCORE may not: bot_search_key retains that entire history.
      state = replay.state
      [state[:size], state[:rules], player_index(replay.players, actor),
        state[:forced_from]&.dup, state.fetch(:capture_blockers, []).sort, compact_board_key(state[:board])]
    end

    # The static evaluation reads only the board, rule set and point of view.
    # Repetition and quiet-move counters remain in bot_search_key for deeper
    # searches, but do not prevent safe reuse of an identical leaf evaluation.
    def bot_evaluation_key(replay, actor)
      state = replay.state
      [
        state[:size],
        state[:rules],
        player_index(replay.players, actor),
        state.fetch(:capture_blockers, []).sort,
        compact_board_key(state[:board])
      ].freeze
    end

    # Search receives one of available_board_moves, so this transition can use
    # that already validated move directly. It produces the same rule state as
    # the event/replay path without serializing, parsing and validating it two
    # more times. Real game actions never call this method.
    def bot_search_transition(replay, selection, actor, event_id:, context: nil)
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] if !same_user?(replay.current_player, actor)

      requested = action_to_move(selection)
      move = available_board_moves(replay, actor).find do |candidate|
        same_board_move?(candidate, requested)
      end
      return [:invalid_move, nil] if move == nil

      state = duplicate_state(replay.state)
      search_history = []
      apply_move!(state, move, actor)
      next_moves = finish_turn!(state, actor, event_id, search_history)
      next_replay = Replay.new(
        board: state[:board],
        players: state[:players],
        current_player: state[:current_player],
        winner: state[:winner],
        draw: state[:draw],
        accepted_events: replay.accepted_events,
        history: search_history,
        state: state
      )
      if !next_replay.finished? && next_replay.current_player != nil && next_moves != nil
        cache_available_moves(next_replay, next_replay.current_player, next_moves.freeze)
      end
      [:ok, next_replay]
    end

    def bot_action_score(replay, actor, action, context: nil)
      move = action_to_move(action)
      return -10_000.0 if move == nil

      capture = move.metadata["capture"]
      score = capture.to_s.empty? ? 0.0 : 200.0
      code = replay.state[:board][move.from[1]][move.from[0]]
      score += 120 if capture != nil && king?(piece_at_coordinate(replay.state[:board], capture))
      score += 90 if !king?(code) && promotion_row?(replay.state, piece_owner(code), move.to[1])
      score += 12 - (move.to[0] - (replay.state[:size] - 1) / 2.0).abs * 2
      score
    end

    def bot_position_value(replay, actor)
      return bot_reward(replay, actor) * 1_000_000.0 if replay.finished?

      state = replay.state
      marker = player_index(replay.players, actor)
      opponent = marker == 0 ? 1 : 0
      value = 0.0
      state[:board].each_with_index do |row, y|
        row.each_with_index do |code, x|
          next if code == nil

          sign = piece_owner(code) == marker ? 1 : -1
          base = king?(code) ? (rule?(state[:rules], FLYING_KINGS) ? 260.0 : 185.0) : 100.0
          advancement = king?(code) ? 0 : (piece_owner(code) == 0 ? y : state[:size] - y - 1) * 3
          unless king?(code)
            owner = piece_owner(code)
            distance = owner == 0 ? state[:size] - y - 1 : y
            advancement += 24 if distance == 1
            directions = forward_directions(owner)
            blocked = directions.all? do |dx, dy|
              !inside?(state, x + dx, y + dy) || state[:board][y + dy][x + dx] != nil || capture_blocked?(state, x + dx, y + dy)
            end
            advancement -= 12 if blocked && !rule?(state[:rules], MEN_MOVE_BACKWARD)
          end
          center = x.between?(2, state[:size] - 3) && y.between?(2, state[:size] - 3) ? 8 : 0
          edge = [0, state[:size] - 1].include?(x) ? 4 : 0
          value += sign * (base + advancement + center + edge)
        end
      end
      own_moves = raw_mobility(state, marker)
      other_moves = raw_mobility(state, opponent)
      value + (own_moves - other_moves) * 2.5
    end

    private

    def cache_available_moves(replay, actor, moves)
      replay.instance_variable_set(
        :@checkers_available_moves,
        { actor: actor.to_s, moves: moves }.freeze
      )
    end

    def checkers_origin_fields(moves, labeler)
      moves.map(&:from).uniq.map { |position| labeler.call(position) }.join(", ")
    end

    def apply_events!(state, events, repository, session, accepted, history)
      events.each do |event|
        break if state[:winner] != nil || state[:draw]
        next if event["action"].to_s != board_event_action

        actor = repository.actor_of(event, session)
        next if !same_user?(actor, state[:current_player])
        requested = parse_board_move(event["value"])
        move = moves_for_state(state, actor).find { |candidate| same_board_move?(candidate, requested) }
        next if move == nil

        captured = apply_move!(state, move, actor)
        accepted << event
        event_id = repository.event_id(event)
        history << move_history(event_id, actor, move, captured)
        finish_turn!(state, actor, event_id, history)
      end
    end

    def initial_state(players, options)
      size = options["board_size"].to_i
      board = Array.new(size) { Array.new(size) }
      rows = size / 2 - 1
      (0...rows).each do |y|
        (0...size).each { |x| board[y][x] = "0m" if dark?(x, y) }
      end
      ((size - rows)...size).each do |y|
        (0...size).each { |x| board[y][x] = "1m" if dark?(x, y) }
      end
      state = {
        board: board, players: players, options: options, size: size, rules: options["rules"].to_i,
        current_player: players[0], forced_from: nil, captured_this_turn: false,
        promoted_this_turn: false, quiet_moves: 0, positions: Hash.new(0), winner: nil, draw: false,
        last_to: nil
      }
      state[:positions][position_key(state)] = 1
      state
    end

    def moves_for_state(state, actor)
      marker = player_index(state[:players], actor)
      return [] if marker == nil || !same_user?(state[:current_player], actor)

      forced = state[:forced_from]
      captures = raw_captures(state, marker, only: forced)
      if !captures.empty?
        captures = filter_maximum_captures(state, captures) if rule?(state[:rules], MAXIMUM_CAPTURE)
        if rule?(state[:rules], KING_PRIORITY) && captures.any? { |move| king?(state[:board][move.from[1]][move.from[0]]) }
          captures = captures.select { |move| king?(state[:board][move.from[1]][move.from[0]]) }
        end
        return captures if forced != nil || rule?(state[:rules], MANDATORY_CAPTURE)

        return captures + raw_moves(state, marker)
      end
      return [] if forced != nil
      return raw_moves(state, marker) if !rule?(state[:rules], MANDATORY_CAPTURE)

      raw_moves(state, marker)
    end

    def raw_moves(state, marker)
      moves = []
      each_raw_move(state, marker) do |x, y, tx, ty|
        moves << BoardMove.new(from: [x, y], to: [tx, ty])
      end
      moves
    end

    def raw_captures(state, marker, only: nil)
      moves = []
      each_raw_capture(state, marker, only: only) do |x, y, tx, ty, mx, my|
        moves << BoardMove.new(from: [x, y], to: [tx, ty], metadata: { "capture" => "#{mx},#{my}" })
      end
      moves
    end

    def raw_mobility(state, marker)
      count = 0
      each_raw_move(state, marker) { count += 1 }
      each_raw_capture(state, marker) { count += 1 }
      count
    end

    def each_raw_move(state, marker, &block)
      each_piece(state[:board], marker) do |x, y, code|
        each_move_for_piece(state, x, y, marker, code, &block)
      end
    end

    def each_raw_capture(state, marker, only: nil, &block)
      if only != nil
        x, y = only
        return if !inside?(state, x, y)

        code = state[:board][y][x]
        return if code == nil || piece_owner(code) != marker

        each_capture_for_piece(state, x, y, marker, code, &block)
        return
      end

      each_piece(state[:board], marker) do |x, y, code|
        each_capture_for_piece(state, x, y, marker, code, &block)
      end
    end

    def each_move_for_piece(state, x, y, marker, code)
      directions = if king?(code) || rule?(state[:rules], MEN_MOVE_BACKWARD)
        DIAGONALS
      else
        forward_directions(marker)
      end
      directions.each do |dx, dy|
        if king?(code) && rule?(state[:rules], FLYING_KINGS)
          cx = x + dx
          cy = y + dy
          while inside?(state, cx, cy) && state[:board][cy][cx] == nil && !capture_blocked?(state, cx, cy)
            yield x, y, cx, cy
            cx += dx
            cy += dy
          end
        else
          tx = x + dx
          ty = y + dy
          yield x, y, tx, ty if inside?(state, tx, ty) && state[:board][ty][tx] == nil && !capture_blocked?(state, tx, ty)
        end
      end
    end

    def each_capture_for_piece(state, x, y, marker, code, &block)
      capture_directions = if king?(code) || rule?(state[:rules], MEN_CAPTURE_BACKWARD)
        DIAGONALS
      else
        forward_directions(marker)
      end
      capture_directions.each do |dx, dy|
        if king?(code) && rule?(state[:rules], FLYING_KINGS)
          each_flying_capture(state, x, y, marker, dx, dy, &block)
        else
          mx = x + dx
          my = y + dy
          tx = x + dx * 2
          ty = y + dy * 2
          next if !inside?(state, tx, ty) || capture_blocked?(state, tx, ty) || capture_blocked?(state, mx, my)
          victim = state[:board][my][mx]
          next if victim == nil || piece_owner(victim) == marker || state[:board][ty][tx] != nil

          yield x, y, tx, ty, mx, my
        end
      end
    end

    def each_flying_capture(state, x, y, marker, dx, dy)
      cx = x + dx
      cy = y + dy
      cx, cy = cx + dx, cy + dy while inside?(state, cx, cy) && state[:board][cy][cx] == nil && !capture_blocked?(state, cx, cy)
      return if !inside?(state, cx, cy) || capture_blocked?(state, cx, cy)
      victim = state[:board][cy][cx]
      return if victim == nil || piece_owner(victim) == marker

      tx = cx + dx
      ty = cy + dy
      while inside?(state, tx, ty) && state[:board][ty][tx] == nil && !capture_blocked?(state, tx, ty)
        yield x, y, tx, ty, cx, cy
        tx += dx
        ty += dy
      end
    end

    def filter_maximum_captures(state, moves)
      continuation_cache = {}
      lengths = moves.map { |move| [move, capture_length_after(state, move, continuation_cache)] }
      maximum = lengths.map(&:last).max
      lengths.select { |_move, length| length == maximum }.map(&:first)
    end

    def capture_length_after(state, move, continuation_cache = nil)
      continuation_cache ||= {}
      copy = duplicate_state(state)
      marker = piece_owner(copy[:board][move.from[1]][move.from[0]])
      apply_step_to_board!(copy, move)
      key = [marker, move.to, compact_board_key(copy[:board]), copy.fetch(:capture_blockers, []).sort]
      remaining = continuation_cache[key]
      if remaining == nil
        continuations = raw_captures(copy, marker, only: move.to)
        remaining = if continuations.empty?
          0
        else
          continuations.map do |candidate|
            capture_length_after(copy, candidate, continuation_cache)
          end.max
        end
        continuation_cache[key] = remaining
      end
      1 + remaining
    end

    def apply_move!(state, move, actor)
      code = state[:board][move.from[1]][move.from[0]]
      captured = move.metadata["capture"]
      apply_step_to_board!(state, move)
      promoted = false
      if !king?(code) && promotion_row?(state, piece_owner(code), move.to[1]) &&
          (captured.to_s.empty? || rule?(state[:rules], PROMOTE_DURING_CAPTURE))
        state[:board][move.to[1]][move.to[0]] = "#{piece_owner(code)}k"
        state[:promoted_this_turn] = true
        promoted = true
      end
      state[:captured_this_turn] ||= !captured.to_s.empty?
      state[:last_to] = move.to.dup

      state[:forced_from] = nil
      if !captured.to_s.empty? && rule?(state[:rules], CONTINUE_CAPTURE)
        further = raw_captures(state, player_index(state[:players], actor), only: move.to)
        state[:forced_from] = move.to if !further.empty?
      end
      if state[:forced_from] == nil && !king?(state[:board][move.to[1]][move.to[0]]) &&
          promotion_row?(state, piece_owner(code), move.to[1])
        state[:board][move.to[1]][move.to[0]] = "#{piece_owner(code)}k"
        state[:promoted_this_turn] = true
        promoted = true
      end
      { coordinate: captured, promoted: promoted, piece: code, size: state[:size] }
    end

    def apply_step_to_board!(state, move)
      board = state[:board]
      code = board[move.from[1]][move.from[0]]
      board[move.from[1]][move.from[0]] = nil
      captured = parse_coordinate(move.metadata["capture"])
      board[captured[1]][captured[0]] = nil if captured != nil
      if captured != nil && rule?(state[:rules], DEFER_CAPTURE_REMOVAL)
        (state[:capture_blockers] ||= []) << captured
      end
      board[move.to[1]][move.to[0]] = code
      if !king?(code) && rule?(state[:rules], PROMOTE_DURING_CAPTURE) && promotion_row?(state, piece_owner(code), move.to[1])
        board[move.to[1]][move.to[0]] = "#{piece_owner(code)}k"
      end
    end

    def finish_turn!(state, actor, event_id, history)
      return moves_for_state(state, actor) if state[:forced_from] != nil

      state[:capture_blockers] = []

      x, y = state[:last_to]
      code = x == nil ? nil : state[:board][y][x]
      if code != nil && !king?(code) && promotion_row?(state, piece_owner(code), y)
        state[:board][y][x] = "#{piece_owner(code)}k"
        state[:promoted_this_turn] = true
      end
      state[:quiet_moves] = state[:captured_this_turn] || state[:promoted_this_turn] ? 0 : state[:quiet_moves] + 1
      state[:captured_this_turn] = false
      state[:promoted_this_turn] = false
      state[:last_to] = nil
      opponent = other_player(state[:players], actor)
      opponent_marker = player_index(state[:players], opponent)
      if count_pieces(state[:board], opponent_marker) == 0
        state[:winner] = actor
        state[:current_player] = nil
        history << result_history(event_id: event_id, winner: actor)
        return []
      end
      state[:current_player] = opponent
      opponent_moves = moves_for_state(state, opponent)
      if opponent_moves.empty?
        state[:winner] = actor
        state[:current_player] = nil
        history << result_history(event_id: event_id, winner: actor)
        return []
      end
      key = position_key(state)
      state[:positions][key] += 1
      if state[:positions][key] >= 3 || state[:quiet_moves] >= 80
        state[:draw] = true
        state[:current_player] = nil
        history << result_history(event_id: event_id, draw: true)
        return []
      end
      opponent_moves
    end

    def move_history(event_id, actor, move, result)
      size = result[:size].to_i
      size = 8 if size <= 0
      data = {
        "size" => size,
        "from_x" => move.from[0],
        "from_y" => move.from[1],
        "to_x" => move.to[0],
        "to_y" => move.to[1],
        "piece" => result[:piece].to_s,
        "capture" => !result[:coordinate].to_s.empty?,
        "promoted" => result[:promoted] == true
      }.freeze
      HistoryEntry.new(
        key: "move:#{event_id}",
        text: checkers_move_history_text(data, notation: "numeric"),
        event_id: event_id,
        actor: actor,
        kind: :move,
        field: checkers_history_field(data, "to", notation: "numeric"),
        value: data
      )
    end

    def checkers_move_history_text(data, notation:)
      piece = piece_label(data["piece"])
      from = checkers_history_field(data, "from", notation: notation)
      to = checkers_history_field(data, "to", notation: notation)
      text = if data["capture"] == true
        _("%{piece} from %{from} to %{to}, captures.") % { piece: piece, from: from, to: to }
      else
        _("%{piece} from %{from} to %{to}.") % { piece: piece, from: from, to: to }
      end
      data["promoted"] == true ? _("%{text} Promoted to a king.") % { text: text } : text
    end

    def checkers_history_field(data, prefix, notation:)
      x = data["#{prefix}_x"].to_i
      y = data["#{prefix}_y"].to_i
      return field_label(x, y) if notation.to_s == "algebraic"

      checkers_field_number(data["size"].to_i, x, y)
    end

    def piece_label(code)
      case code.to_s
      when "0m" then _("white man")
      when "0k" then _("white draughts king")
      when "1m" then _("black man")
      when "1k" then _("black draughts king")
      else code.to_s
      end
    end

    def playable_fields(size)
      Array.new(size) do |y|
        Array.new(size) { |x| [x, y] if dark?(x, y) }
      end.flatten(1).compact
    end

    def unplayable_fields(size)
      Array.new(size) do |y|
        Array.new(size) { |x| [x, y] if !dark?(x, y) }
      end.flatten(1).compact
    end

    def checkers_coordinate_label_sets(size)
      numeric = Array.new(size) { Array.new(size, "") }
      algebraic = Array.new(size) do |y|
        Array.new(size) { |x| field_label(x, y) }
      end
      number = 1
      (size - 1).downto(0) do |y|
        (0...size).each do |x|
          next if !dark?(x, y)

          numeric[y][x] = number.to_s
          number += 1
        end
      end
      { "numeric" => numeric, "algebraic" => algebraic }
    end

    def checkers_field_number(size, x, y)
      ((size - 1 - y.to_i) * (size / 2) + x.to_i / 2 + 1).to_s
    end





    def action_to_move(action)
      BoardMove.new(
        from: [selection_value(action, "from_x"), selection_value(action, "from_y")],
        to: [selection_value(action, "to_x"), selection_value(action, "to_y")],
        metadata: action["capture"].to_s.empty? ? {} : { "capture" => action["capture"].to_s }
      )
    rescue StandardError
      nil
    end

    def duplicate_state(state)
      state.merge(board: state[:board].map(&:dup), positions: state[:positions].dup,
        forced_from: state[:forced_from]&.dup, capture_blockers: state.fetch(:capture_blockers, []).map(&:dup))
    end

    def capture_blocked?(state, x, y)
      blockers = state[:capture_blockers]
      blockers != nil && !blockers.empty? && blockers.include?([x, y])
    end

    def each_piece(board, marker)
      coordinates = PLAYABLE_COORDINATES[board.length] || playable_fields(board.length)
      coordinates.each do |x, y|
        code = board[y][x]
        yield(x, y, code) if code != nil && piece_owner(code) == marker
      end
    end

    def count_pieces(board, marker)
      board.flatten.count { |code| code != nil && piece_owner(code) == marker }
    end

    def piece_owner(code)
      code == "1m" || code == "1k" ? 1 : 0
    end

    def king?(code)
      code == "0k" || code == "1k"
    end

    def piece_at_coordinate(board, value)
      coordinate = parse_coordinate(value)
      coordinate == nil ? nil : board[coordinate[1]][coordinate[0]]
    end

    def parse_coordinate(value)
      match = /\A(\d+),(\d+)\z/.match(value.to_s)
      match == nil ? nil : [match[1].to_i, match[2].to_i]
    end

    def forward_directions(marker)
      FORWARD_DIRECTIONS.fetch(marker)
    end

    def promotion_row?(state, marker, y)
      marker == 0 ? y == state[:size] - 1 : y == 0
    end

    def inside?(state, x, y)
      x.between?(0, state[:size] - 1) && y.between?(0, state[:size] - 1)
    end

    def dark?(x, y)
      (x + y).even?
    end

    def rule?(mask, flag)
      (mask.to_i & flag) != 0
    end

    def position_key(state)
      "#{state[:current_player]}:#{state[:board].flatten.map { |piece| piece || "--" }.join}"
    end

    def compact_board_key(board)
      board.flatten.map { |piece| piece || "--" }.join
    end
  end
end

require_relative 'generated/rulebooks/checkers'
