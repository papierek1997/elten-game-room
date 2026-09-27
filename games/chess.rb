require_relative "../lib/game_bots"
require_relative "../lib/game_tree_search"
require_relative "board_game"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Chess < TurnBasedBoardGame
    SIZE = 8
    PIECE_NAMES = {
      "P" => "pawn", "N" => "knight", "B" => "bishop",
      "R" => "rook", "Q" => "queen", "K" => "king"
    }.freeze
    PIECE_VALUES = { "P" => 100, "N" => 320, "B" => 330, "R" => 500, "Q" => 900, "K" => 20_000 }.freeze
    KNIGHT_STEPS = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]].freeze
    KING_STEPS = [-1, 0, 1].product([-1, 0, 1]).reject { |dx, dy| dx == 0 && dy == 0 }.freeze
    BISHOP_STEPS = [[1, 1], [1, -1], [-1, 1], [-1, -1]].freeze
    ROOK_STEPS = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
    PROMOTIONS = %w[Q R B N].freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      action == "move" ? "play2" : nil
    end

    def id
      "chess"
    end

    def name
      _("Chess")
    end

    def supports_bots?
      true
    end

    def shareable_simulation_snapshot?
      true
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::AlphaBetaStrategy.new(max_depth: 3, node_limit: 30_000, optimize_transpositions: true)
    end

    def rule_sections
      # Generated from docs/rulebooks/chess.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:king, GameRoomRules.translate("The king is what you are protecting"),
          GameRoomRules.translate("Chess is a game for two players. White moves first, then the players alternate one move at a time. Each begins with a king, queen, two rooks, two bishops, two knights and eight pawns on an 8 by 8 board. Your aim is to attack the opposing king in a way your opponent cannot escape: this is checkmate. You do not actually capture the king."),
          GameRoomRules.translate("You capture an opposing piece by moving one of yours onto its square. You cannot land on a piece of your own colour. Nor may you make a move that exposes your king to attack, even if the move would otherwise be possible.")),
        rule_section(:pieces, GameRoomRules.translate("Getting to know the pieces"),
          GameRoomRules.translate("The rook moves any distance along a row or column. The bishop moves any distance diagonally. The queen combines both movements. None of these pieces can jump over another piece. For example, a rook blocked by your own pawn must wait for the pawn to move or choose another direction."),
          GameRoomRules.translate("The knight moves in an L: two squares along a row or column, then one square sideways. It can jump over pieces in between. The king normally moves one square in any direction, but never onto a square attacked by the opponent. Two kings therefore cannot stand next to each other."),
          GameRoomRules.translate("A pawn moves forward towards the opponent's starting side. It advances one square into an empty square. From its starting row it may instead advance two, provided both squares are empty. It captures differently: one square diagonally forward. A pawn cannot move backwards or capture straight ahead."),
          GameRoomRules.translate("A pawn reaching the farthest row is promoted. Choose a queen, rook, bishop or knight from the list. This choice is not limited to pieces that have already been captured: you can have two queens.")),
        rule_section(:special, GameRoomRules.translate("Two special moves"),
          GameRoomRules.translate("Castling moves the king and a rook in one turn. Move your king two squares towards the chosen rook; the program moves the rook to the square the king crossed. Both pieces must still have their original castling rights, and the squares between them must be empty. You cannot castle out of check, through an attacked square or into check. Both kingside and queenside castling are supported."),
          GameRoomRules.translate("En passant is a special pawn capture. If an opposing pawn advances two squares and finishes beside your pawn, you may capture it as though it had advanced only one. Move diagonally to the square it passed through. This opportunity exists only on your very next move; if you play something else, it is gone.")),
        rule_section(:mate, GameRoomRules.translate("Check, mate and the end of the game"),
          GameRoomRules.translate("Check means that your king is under attack. You must answer it by moving the king, capturing the attacker or blocking the attack, whichever is legal. If no legal reply exists, it is checkmate and you lose. If you have no legal move but your king is not attacked, it is stalemate and the game is drawn."),
          GameRoomRules.translate("Game Room also ends the game automatically on threefold repetition, after 50 moves by each side without a pawn move or capture, and in the insufficient-material positions recognised by the program. You do not have to claim these draws. There is no chess clock or alternative chess variant in the current game.")),
        rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
          GameRoomRules.translate("Arrows: browse squares."),
          GameRoomRules.translate("Enter: select your piece, then its destination; choose a promotion if needed."),
          GameRoomRules.translate("V: read legal destinations for the inspected piece."),
          GameRoomRules.translate("E: read pieces attacking the inspected square."),
          GameRoomRules.translate("C: read player colours."),
          GameRoomRules.translate("S: read each player's remaining pieces."),
          GameRoomRules.translate("Ctrl+Shift+H: rotate the board view."),
          GameRoomRules.translate("T: read whose turn it is."),
          GameRoomRules.translate("K: browse your kings."),
          GameRoomRules.translate("Shift+K: browse the opponent's kings."),
          GameRoomRules.translate("D: browse your queens."),
          GameRoomRules.translate("Shift+D: browse the opponent's queens."),
          GameRoomRules.translate("R: browse your rooks."),
          GameRoomRules.translate("Shift+R: browse the opponent's rooks."),
          GameRoomRules.translate("B: browse your bishops."),
          GameRoomRules.translate("Shift+B: browse the opponent's bishops."),
          GameRoomRules.translate("N: browse your knights."),
          GameRoomRules.translate("Shift+N: browse the opponent's knights."),
          GameRoomRules.translate("P: browse your pawns."),
          GameRoomRules.translate("Shift+P: browse the opponent's pawns."))
      ]
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players)
      accepted = []
      history = [starting_history(players)]
      apply_events!(state, events, repository, session, accepted, history)

      Replay.new(
        board: state[:board], players: players, current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], accepted_events: accepted, history: history, state: state
      )
    end

    def incremental_replay(replay, session, events, repository)
      return nil if replay == nil

      state = duplicate_state(replay.state)
      accepted = replay.accepted_events.dup
      history = replay.history.dup
      apply_events!(state, events, repository, session, accepted, history)
      Replay.new(
        board: state[:board], players: state[:players], current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], accepted_events: accepted, history: history, state: state
      )
    end

    def available_board_moves(replay, actor)
      return [] if replay.state[:pending_promotion] != nil

      legal_moves(replay.state, actor)
    end

    def legal_actions(replay, actor, context: nil)
      if replay.state[:pending_promotion] != nil
        return [] if replay.finished? || !same_user?(replay.current_player, actor)

        return PROMOTIONS.map { |piece| { "kind" => "card", "action" => "select", "zone" => "promotion", "card" => piece } }
      end
      super
    end

    def action_for(selection, replay, actor, context: nil)
      if replay.state[:pending_promotion] != nil
        return [:not_your_turn, nil] if !same_user?(replay.current_player, actor)
        return [:invalid, nil] if selection["kind"].to_s != "card" || selection["zone"].to_s != "promotion"
        piece = selection["card"].to_s.upcase
        return [:invalid, nil] if !PROMOTIONS.include?(piece)

        return [:ok, event_plan("promote", piece)]
      end
      super
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if state[:pending_promotion] != nil && same_user?(replay.current_player, viewer)
        cards = PROMOTIONS.map do |piece|
          GameSurfaces::Card.new(id: piece, label: translated_piece_name(piece), value: piece)
        end
        return GameSurfaces::CardTableSpec.new(
          zones: [GameSurfaces::CardZoneSpec.new(id: "promotion", header: _("Choose the promotion piece"), cards: cards, empty_label: "")]
        )
      end

      pieces = Array.new(SIZE) { Array.new(SIZE) }
      state[:board].each_with_index do |row, y|
        row.each_with_index do |code, x|
          next if code == nil
          owner = state[:players][code[0] == "w" ? 0 : 1]
          pieces[y][x] = GameSurfaces::Piece.new(
            id: "#{code}:#{x}:#{y}", label: chess_piece_label(code), owner: owner,
            kind: PIECE_NAMES[code[1]], value: code
          )
        end
      end
      moves = !replay.finished? && same_user?(replay.current_player, viewer) ? available_board_moves(replay, viewer) : []
      orientation = board_orientation(replay, viewer)
      build_piece_board(
        replay,
        viewer,
        width: SIZE,
        height: SIZE,
        pieces: pieces,
        moves: moves,
        default_orientation: orientation[:default],
        orientation_labels: orientation[:labels],
        square_details: square_threat_details(state, viewer)
      )
    end

    def board_origin_error(replay, actor, position, field:, piece:, labeler:)
      contextual = board_selection_context_error(replay, actor, field: field, piece: piece)
      return contextual if contextual != nil

      state = replay.state
      colour = colour_for(state, actor)
      pseudo = pseudo_moves(state, colour).select { |move| move.from == position }
      legal = available_board_moves(replay, actor).select { |move| move.from == position }
      if !pseudo.empty? && legal.empty?
        if in_check?(state, colour)
          return _("The %{piece} on %{field} has no move that resolves the check.") % {
            piece: piece.label.to_s,
            field: field
          }
        end
        return _("The %{piece} on %{field} cannot move because that would expose your king to check.") % {
          piece: piece.label.to_s,
          field: field
        }
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

      state = replay.state
      colour = colour_for(state, actor)
      pseudo = pseudo_moves(state, colour).select { |move| move.from == origin && move.to == destination }
      legal = available_board_moves(replay, actor).select { |move| move.from == origin && move.to == destination }
      if !pseudo.empty? && legal.empty?
        return in_check?(state, colour) ?
          _("This move does not resolve the check on your king.") :
          _("This move would leave your king in check.")
      end

      castling_error = chess_castling_error(state, colour, origin, destination)
      return castling_error if castling_error != nil

      code = state[:board][origin[1]][origin[0]]
      if chess_sliding_move?(code, origin, destination) &&
          !clear_chess_ray?(state[:board], origin[0], origin[1], destination[0], destination[1])
        return _("The path from %{from} to %{to} is blocked.") % {
          from: origin_field,
          to: destination_field
        }
      end
      if target != nil
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
      if code&.end_with?("P")
        return _("The pawn cannot move from %{from} to %{to} in this position.") % {
          from: origin_field,
          to: destination_field
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
      owner = replay.players[own_index]
      shortcuts = [
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
          key: "e",
          label: _("read what threatens the current field"),
          command: "announce_square_details"
        ),
        surface_shortcut(
          key: "h",
          modifiers: [:control, :shift],
          label: _("rotate the board"),
          command: "toggle_orientation"
        )
      ]
      {
        "k" => ["king", _("king")],
        "d" => ["queen", _("chess queen")],
        "r" => ["rook", _("rook")],
        "b" => ["bishop", _("bishop")],
        "n" => ["knight", _("knight")],
        "p" => ["pawn", _("pawn")]
      }.each do |key, (kind, piece_name)|
        shortcuts << surface_shortcut(
          key: key,
          label: _("go to your next %{piece}") % { piece: piece_name },
          command: "navigate_piece",
          payload: {
            "owner" => owner,
            "kind" => kind,
            "empty_message" => _("You have no %{piece}.") % { piece: piece_name }
          }
        )
      end
      shortcuts
    end

    def remaining_piece_counts(replay)
      pieces = replay.board.flatten.compact
      %w[w b].map do |colour|
        _("kings: %{kings}, queens: %{queens}, rooks: %{rooks}, bishops: %{bishops}, knights: %{knights}, pawns: %{pawns}") % {
          kings: pieces.count("#{colour}K"), queens: pieces.count("#{colour}Q"),
          rooks: pieces.count("#{colour}R"), bishops: pieces.count("#{colour}B"),
          knights: pieces.count("#{colour}N"), pawns: pieces.count("#{colour}P")
        }
      end
    end

    def bot_search_key(replay, actor)
      state = replay.state
      board = state[:board].flatten.map { |piece| piece || "--" }.join
      [colour_for(state, actor), colour_for(state, replay.current_player), state[:castling],
       state[:en_passant], state[:pending_promotion], board, state[:halfmove],
       state[:positions].sort]
    end

    def bot_forced_continuation?(replay)
      replay.state[:pending_promotion] != nil
    end

    def bot_tactical_actions(replay)
      state = replay.state
      actor = state[:current_player]
      checked = in_check?(state, colour_for(state, actor))
      return { actions: legal_actions(replay, actor), forced: true } if checked || state[:pending_promotion]
      # Only immediate recaptures, not another full search of quiet moves.
      event = replay.accepted_events.last
      previous = event && event["action"] == board_event_action ? parse_board_move(event["value"]) : nil
      return { actions: [], forced: false } unless previous && state[:halfmove].zero?
      actions = available_board_moves(replay, actor).select do |move|
        move.to == previous.to && state[:board][move.to[1]][move.to[0]] != nil
      end.map(&:action)
      { actions: actions, forced: false }
    end

    def bot_action_score(replay, actor, action, context: nil)
      if action["kind"].to_s == "card"
        return PIECE_VALUES.fetch(action["card"].to_s, 0).to_f
      end
      move = action_to_move(action)
      return -10_000.0 if move == nil
      state = replay.state
      moving = state[:board][move.from[1]][move.from[0]]
      captured = state[:board][move.to[1]][move.to[0]]
      captured ||= state[:board][move.from[1]][move.to[0]] if move.metadata["en_passant"] == "1"
      score = captured == nil ? 0.0 : PIECE_VALUES[captured[1]].to_f * 10 - PIECE_VALUES[moving[1]].to_f
      score += 180 if move.metadata["castle"] != nil
      score += 120 if moving&.end_with?("P") && [0, 7].include?(move.to[1])
      score
    end

    def bot_position_value(replay, actor)
      return bot_reward(replay, actor) * 1_000_000.0 if replay.finished?

      state = replay.state
      colour = colour_for(state, actor)
      opponent = colour == "w" ? "b" : "w"
      value = 0.0
      pieces = state[:board].flatten.compact
      phase = [pieces.sum { |code| { "N" => 1, "B" => 1, "R" => 2, "Q" => 4 }.fetch(code[1], 0) } / 24.0, 1.0].min
      pawns = { "w" => [], "b" => [] }
      state[:board].each_with_index { |row, y| row.each_with_index { |code, x| pawns[code[0]] << [x, y] if code && code[1] == "P" } }
      state[:board].each_with_index do |row, y|
        row.each_with_index do |code, x|
          next if code == nil
          sign = code[0] == colour ? 1 : -1
          center = (x.between?(2, 5) && y.between?(2, 5)) ? 12 : 0
          advancement = code[1] == "P" ? (code[0] == "w" ? y : 7 - y) * 4 : 0
          if code[1] == "K"
            edge_distance = [x, 7 - x].min + [y, 7 - y].min
            home_row = code[0] == "w" ? 0 : 7
            shield = pawns[code[0]].count { |px, py| (px - x).abs <= 1 && (py - y) == (code[0] == "w" ? 1 : -1) }
            center = (1 - phase) * edge_distance * 10 + phase * (shield * 12 - (y - home_row).abs * 12 - edge_distance * 6)
          elsif code[1] == "P"
            friendly = pawns[code[0]]
            enemies = pawns[code[0] == "w" ? "b" : "w"]
            advancement -= 12 if friendly.count { |px, _| px == x } > 1
            advancement -= 10 unless friendly.any? { |px, _| (px - x).abs == 1 }
            passed = enemies.none? { |px, py| (px - x).abs <= 1 && (code[0] == "w" ? py > y : py < y) }
            distance = code[0] == "w" ? 7 - y : y
            advancement += (7 - distance)**2 * (1.5 - phase) if passed
          end
          value += sign * (PIECE_VALUES[code[1]] + center + advancement)
        end
      end
      own_moves = pseudo_moves(state, colour).length
      other_moves = pseudo_moves(state, opponent).length
      value + (own_moves - other_moves) * 2.0 - (in_check?(state, colour) ? 45 : 0) + (in_check?(state, opponent) ? 45 : 0)
    end

    def describe_event(event, repository, replay, _viewer)
      replay.history.filter_map do |entry|
        entry.text if entry.event_id.to_i == repository.event_id(event).to_i && [:move, :promotion, :check].include?(entry.kind)
      end
    end

    def result_text(replay)
      return chess_draw_text(replay.state[:draw_reason]) if replay.draw && replay.state[:draw_reason]
      super
    end

    private

    def chess_draw_text(reason)
      case reason
      when :stalemate then _("Draw by stalemate.")
      when :repetition then _("Draw by threefold repetition.")
      when :fifty_moves then _("Draw after fifty moves without a pawn move or capture.")
      when :material then _("Draw because neither side has sufficient mating material.")
      else _("The game ended in a draw.")
      end
    end

    def chess_castling_error(state, colour, origin, destination)
      row = colour == "w" ? 0 : 7
      return nil if origin != [4, row] || destination[1] != row || ![2, 6].include?(destination[0])
      return _("You cannot castle while your king is in check.") if in_check?(state, colour)

      king_side = destination[0] == 6
      flag = if colour == "w"
        king_side ? "K" : "Q"
      else
        king_side ? "k" : "q"
      end
      rook_x = king_side ? 7 : 0
      if !state[:castling].include?(flag) || state[:board][row][rook_x] != "#{colour}R"
        return _("Castling is no longer available on this side.")
      end

      between = king_side ? [5, 6] : [1, 2, 3]
      return _("Castling is not possible because the path between the king and rook is blocked.") if between.any? { |x| state[:board][row][x] != nil }

      opponent = colour == "w" ? "b" : "w"
      crossed = king_side ? [5, 6] : [3, 2]
      if crossed.any? { |x| attacked?(state, x, row, opponent) }
        return _("Castling is not possible because the king would cross an attacked field.")
      end

      nil
    end

    def chess_sliding_move?(code, origin, destination)
      return false if code == nil || origin == destination

      dx = destination[0] - origin[0]
      dy = destination[1] - origin[1]
      case code[1]
      when "B" then dx.abs == dy.abs
      when "R" then dx == 0 || dy == 0
      when "Q" then dx.abs == dy.abs || dx == 0 || dy == 0
      else false
      end
    end

    def apply_events!(state, events, repository, session, accepted, history)
      events.each do |event|
        break if state[:winner] != nil || state[:draw]
        actor = repository.actor_of(event, session)
        next if !same_user?(actor, state[:current_player])

        if state[:pending_promotion] != nil
          next if event["action"].to_s != "promote"
          piece = event["value"].to_s.upcase
          next if !PROMOTIONS.include?(piece)

          x, y = state[:pending_promotion]
          state[:board][y][x] = "#{colour_for(state, actor)}#{piece}"
          state[:pending_promotion] = nil
          accepted << event
          event_id = repository.event_id(event)
          history << HistoryEntry.new(
            key: "promotion:#{event_id}",
            text: _("%{player} promoted the pawn to %{piece}.") % { player: participant_name(actor), piece: translated_piece_name(piece) },
            event_id: event_id, actor: actor, kind: :promotion, field: field_label(x, y), value: piece
          )
          finish_chess_turn!(state, actor, event_id, history)
          next
        end

        next if event["action"].to_s != board_event_action
        requested = parse_board_move(event["value"])
        move = legal_moves(state, actor).find { |candidate| same_board_move?(candidate, requested) }
        next if move == nil

        result = apply_chess_move!(state, move, actor)
        accepted << event
        event_id = repository.event_id(event)
        history << chess_move_history(event_id, actor, move, result)
        finish_chess_turn!(state, actor, event_id, history) if state[:pending_promotion] == nil
      end
    end

    def initial_state(players)
      board = Array.new(SIZE) { Array.new(SIZE) }
      order = %w[R N B Q K B N R]
      board[0] = order.map { |piece| "w#{piece}" }
      board[1] = Array.new(SIZE, "wP")
      board[6] = Array.new(SIZE, "bP")
      board[7] = order.map { |piece| "b#{piece}" }
      state = {
        board: board, players: players, current_player: players[0], castling: "KQkq",
        en_passant: nil, pending_promotion: nil, halfmove: 0, positions: Hash.new(0), winner: nil, draw: false
      }
      state[:positions][position_key(state)] = 1
      state
    end

    def legal_moves(state, actor)
      colour = colour_for(state, actor)
      key = [colour, state[:board], state[:castling], state[:en_passant], state[:pending_promotion]].inspect
      @chess_moves_cache ||= {}
      return @chess_moves_cache[key] if @chess_moves_cache.key?(key)
      @chess_moves_cache.clear if @chess_moves_cache.length >= 8_000
      return [] if colour == nil

      @chess_moves_cache[key] = pseudo_moves(state, colour).select do |move|
        copy = duplicate_state(state)
        apply_chess_move!(copy, move, actor, simulation: true)
        !in_check?(copy, colour)
      end
    end

    def pseudo_moves(state, colour)
      moves = []
      state[:board].each_with_index do |row, y|
        row.each_with_index do |code, x|
          next if code == nil || code[0] != colour
          case code[1]
          when "P" then add_pawn_moves(state, moves, x, y, colour)
          when "N" then add_step_moves(state, moves, x, y, colour, KNIGHT_STEPS)
          when "B" then add_slide_moves(state, moves, x, y, colour, BISHOP_STEPS)
          when "R" then add_slide_moves(state, moves, x, y, colour, ROOK_STEPS)
          when "Q" then add_slide_moves(state, moves, x, y, colour, BISHOP_STEPS + ROOK_STEPS)
          when "K"
            add_step_moves(state, moves, x, y, colour, KING_STEPS)
            add_castling_moves(state, moves, colour)
          end
        end
      end
      moves
    end

    def add_pawn_moves(state, moves, x, y, colour)
      direction = colour == "w" ? 1 : -1
      start = colour == "w" ? 1 : 6
      one = y + direction
      if inside?(x, one) && state[:board][one][x] == nil
        moves << BoardMove.new(from: [x, y], to: [x, one])
        two = y + direction * 2
        moves << BoardMove.new(from: [x, y], to: [x, two], metadata: { "double" => "1" }) if y == start && state[:board][two][x] == nil
      end
      [-1, 1].each do |dx|
        tx = x + dx
        ty = y + direction
        next if !inside?(tx, ty)
        target = state[:board][ty][tx]
        if enemy_piece?(target, colour) && target[1] != "K"
          moves << BoardMove.new(from: [x, y], to: [tx, ty])
        elsif state[:en_passant] == [tx, ty]
          moves << BoardMove.new(from: [x, y], to: [tx, ty], metadata: { "en_passant" => "1" })
        end
      end
    end

    def add_step_moves(state, moves, x, y, colour, steps)
      steps.each do |dx, dy|
        tx = x + dx
        ty = y + dy
        next if !inside?(tx, ty)
        target = state[:board][ty][tx]
        next if target != nil && (target[0] == colour || target[1] == "K")
        moves << BoardMove.new(from: [x, y], to: [tx, ty])
      end
    end

    def add_slide_moves(state, moves, x, y, colour, steps)
      steps.each do |dx, dy|
        tx = x + dx
        ty = y + dy
        while inside?(tx, ty)
          target = state[:board][ty][tx]
          if target == nil
            moves << BoardMove.new(from: [x, y], to: [tx, ty])
          else
            moves << BoardMove.new(from: [x, y], to: [tx, ty]) if target[0] != colour && target[1] != "K"
            break
          end
          tx += dx
          ty += dy
        end
      end
    end

    def add_castling_moves(state, moves, colour)
      row = colour == "w" ? 0 : 7
      king = state[:board][row][4]
      return if king != "#{colour}K" || in_check?(state, colour)
      opponent = colour == "w" ? "b" : "w"
      king_flag = colour == "w" ? "K" : "k"
      queen_flag = colour == "w" ? "Q" : "q"
      if state[:castling].include?(king_flag) && state[:board][row][5] == nil && state[:board][row][6] == nil &&
          state[:board][row][7] == "#{colour}R" && !attacked?(state, 5, row, opponent) && !attacked?(state, 6, row, opponent)
        moves << BoardMove.new(from: [4, row], to: [6, row], metadata: { "castle" => "king" })
      end
      if state[:castling].include?(queen_flag) && state[:board][row][1] == nil && state[:board][row][2] == nil && state[:board][row][3] == nil &&
          state[:board][row][0] == "#{colour}R" && !attacked?(state, 3, row, opponent) && !attacked?(state, 2, row, opponent)
        moves << BoardMove.new(from: [4, row], to: [2, row], metadata: { "castle" => "queen" })
      end
    end

    def apply_chess_move!(state, move, actor, simulation: false)
      board = state[:board]
      code = board[move.from[1]][move.from[0]]
      captured = board[move.to[1]][move.to[0]]
      if move.metadata["en_passant"] == "1"
        captured = board[move.from[1]][move.to[0]]
        board[move.from[1]][move.to[0]] = nil
      end
      update_castling_rights!(state, code, move, captured)
      board[move.from[1]][move.from[0]] = nil
      board[move.to[1]][move.to[0]] = code
      if move.metadata["castle"] == "king"
        board[move.to[1]][5] = board[move.to[1]][7]
        board[move.to[1]][7] = nil
      elsif move.metadata["castle"] == "queen"
        board[move.to[1]][3] = board[move.to[1]][0]
        board[move.to[1]][0] = nil
      end
      state[:en_passant] = if code[1] == "P" && (move.to[1] - move.from[1]).abs == 2
        [move.from[0], (move.from[1] + move.to[1]) / 2]
      end
      state[:halfmove] = code[1] == "P" || captured != nil ? 0 : state[:halfmove].to_i + 1
      if code[1] == "P" && [0, 7].include?(move.to[1])
        state[:pending_promotion] = move.to.dup
      end
      { piece: code, captured: captured, castle: move.metadata["castle"], simulation: simulation }
    end

    def finish_chess_turn!(state, actor, event_id, history)
      opponent = other_player(state[:players], actor)
      state[:current_player] = opponent
      colour = colour_for(state, opponent)
      moves = legal_moves(state, opponent)
      if moves.empty?
        state[:current_player] = nil
        if in_check?(state, colour)
          state[:winner] = actor
          history << result_history(event_id: event_id, winner: actor)
        else
          state[:draw] = true
          state[:draw_reason] = :stalemate
          entry = result_history(event_id: event_id, draw: true)
          entry.text = chess_draw_text(:stalemate)
          history << entry
        end
        return
      end
      key = position_key(state)
      state[:positions][key] += 1
      if state[:halfmove] >= 100 || state[:positions][key] >= 3 || insufficient_material?(state[:board])
        state[:draw] = true
        state[:current_player] = nil
        state[:draw_reason] = state[:halfmove] >= 100 ? :fifty_moves : state[:positions][key] >= 3 ? :repetition : :material
        entry = result_history(event_id: event_id, draw: true)
        entry.text = chess_draw_text(state[:draw_reason])
        history << entry
      elsif in_check?(state, colour)
        history << HistoryEntry.new(key: "check:#{event_id}", text: _("Check."), event_id: event_id, actor: actor, kind: :check)
      end
    end

    def in_check?(state, colour)
      king = nil
      state[:board].each_with_index do |row, y|
        x = row.index("#{colour}K")
        king = [x, y] if x != nil
      end
      king == nil || attacked?(state, king[0], king[1], colour == "w" ? "b" : "w")
    end

    def attacked?(state, x, y, by_colour)
      board = state[:board]
      pawn_direction = by_colour == "w" ? 1 : -1
      return true if [-1, 1].any? { |dx| inside?(x - dx, y - pawn_direction) && board[y - pawn_direction][x - dx] == "#{by_colour}P" }
      return true if KNIGHT_STEPS.any? { |dx, dy| inside?(x + dx, y + dy) && board[y + dy][x + dx] == "#{by_colour}N" }
      return true if KING_STEPS.any? { |dx, dy| inside?(x + dx, y + dy) && board[y + dy][x + dx] == "#{by_colour}K" }
      return true if ray_attacked?(board, x, y, by_colour, BISHOP_STEPS, %w[B Q])
      ray_attacked?(board, x, y, by_colour, ROOK_STEPS, %w[R Q])
    end

    def attackers_of(state, x, y, colours)
      result = []
      state[:board].each_with_index do |row, source_y|
        row.each_with_index do |code, source_x|
          next if code == nil || !colours.include?(code[0])
          next if !piece_attacks_square?(state[:board], code, source_x, source_y, x, y)

          result << [code, source_x, source_y]
        end
      end
      result
    end

    def piece_attacks_square?(board, code, source_x, source_y, target_x, target_y)
      dx = target_x - source_x
      dy = target_y - source_y
      case code[1]
      when "P"
        direction = code[0] == "w" ? 1 : -1
        dy == direction && dx.abs == 1
      when "N"
        KNIGHT_STEPS.include?([dx, dy])
      when "K"
        KING_STEPS.include?([dx, dy])
      when "B"
        dx.abs == dy.abs && clear_chess_ray?(board, source_x, source_y, target_x, target_y)
      when "R"
        (dx == 0 || dy == 0) && clear_chess_ray?(board, source_x, source_y, target_x, target_y)
      when "Q"
        (dx.abs == dy.abs || dx == 0 || dy == 0) && clear_chess_ray?(board, source_x, source_y, target_x, target_y)
      else
        false
      end
    end

    def clear_chess_ray?(board, source_x, source_y, target_x, target_y)
      return false if source_x == target_x && source_y == target_y

      step_x = target_x <=> source_x
      step_y = target_y <=> source_y
      x = source_x + step_x
      y = source_y + step_y
      while x != target_x || y != target_y
        return false if board[y][x] != nil
        x += step_x
        y += step_y
      end
      true
    end

    def ray_attacked?(board, x, y, colour, directions, kinds)
      directions.any? do |dx, dy|
        cx = x + dx
        cy = y + dy
        cx, cy = cx + dx, cy + dy while inside?(cx, cy) && board[cy][cx] == nil
        inside?(cx, cy) && board[cy][cx] != nil && board[cy][cx][0] == colour && kinds.include?(board[cy][cx][1])
      end
    end

    def update_castling_rights!(state, code, move, captured)
      rights = state[:castling]
      rights = rights.delete(code[0] == "w" ? "KQ" : "kq") if code[1] == "K"
      rights = rights.delete("Q") if code == "wR" && move.from == [0, 0]
      rights = rights.delete("K") if code == "wR" && move.from == [7, 0]
      rights = rights.delete("q") if code == "bR" && move.from == [0, 7]
      rights = rights.delete("k") if code == "bR" && move.from == [7, 7]
      rights = rights.delete("Q") if captured == "wR" && move.to == [0, 0]
      rights = rights.delete("K") if captured == "wR" && move.to == [7, 0]
      rights = rights.delete("q") if captured == "bR" && move.to == [0, 7]
      rights = rights.delete("k") if captured == "bR" && move.to == [7, 7]
      state[:castling] = rights
    end

    def insufficient_material?(board)
      pieces = board.flatten.compact.reject { |piece| piece[1] == "K" }
      return true if pieces.empty?
      return false if pieces.any? { |piece| %w[P R Q].include?(piece[1]) }
      return true if pieces.length == 1
      if pieces.all? { |piece| piece[1] == "B" }
        colours = []
        board.each_with_index do |row, y|
          row.each_with_index { |piece, x| colours << (x + y) % 2 if piece != nil && piece[1] == "B" }
        end
        return true if colours.uniq.length == 1
      end
      false
    end

    def chess_move_history(event_id, actor, move, result)
      from = field_label(move.from[0], move.from[1])
      to = field_label(move.to[0], move.to[1])
      piece = chess_piece_label(result[:piece])
      text = if result[:castle] != nil
        _("%{piece} castles %{side}.") % { piece: piece, side: result[:castle] == "king" ? _("king-side") : _("queen-side") }
      elsif result[:captured] != nil
        _("%{piece} from %{from} to %{to}, captures %{captured}.") % {
          piece: piece, from: from, to: to,
          captured: chess_piece_label(result[:captured])
        }
      else
        _("%{piece} from %{from} to %{to}.") % {
          piece: piece, from: from, to: to
        }
      end
      HistoryEntry.new(key: "move:#{event_id}", text: text, event_id: event_id, actor: actor, kind: :move, field: to)
    end

    def chess_piece_label(code)
      case code.to_s
      when "wP" then _("white pawn")
      when "wN" then _("white knight")
      when "wB" then _("white bishop")
      when "wR" then _("white rook")
      when "wQ" then _("white queen")
      when "wK" then _("white king")
      when "bP" then _("black pawn")
      when "bN" then _("black knight")
      when "bB" then _("black bishop")
      when "bR" then _("black rook")
      when "bQ" then _("black queen")
      when "bK" then _("black king")
      else code.to_s
      end
    end

    def colour_assignments(replay)
      _("White: %{white}. Black: %{black}.") % {
        white: participant_name(replay.players[0]),
        black: participant_name(replay.players[1])
      }
    end

    def board_orientation(replay, viewer)
      index = player_index(replay.players, viewer)
      if index == nil
        return {
          default: "normal",
          labels: {
            "normal" => _("The first player's pieces are at the bottom."),
            "rotated" => _("The second player's pieces are at the bottom.")
          }
        }
      end

      own_orientation = index == 0 ? "normal" : "rotated"
      other_orientation = own_orientation == "normal" ? "rotated" : "normal"
      {
        default: own_orientation,
        labels: {
          own_orientation => _("Your pieces are at the bottom."),
          other_orientation => _("The opponent's pieces are at the bottom.")
        }
      }
    end

    def square_threat_details(state, viewer)
      viewer_colour = colour_for(state, viewer)
      colours = if viewer_colour == nil
        %w[w b]
      else
        [viewer_colour == "w" ? "b" : "w"]
      end
      Array.new(SIZE) do |y|
        Array.new(SIZE) do |x|
          field = field_label(x, y)
          attackers = attackers_of(state, x, y, colours)
          if attackers.empty?
            viewer_colour == nil ?
              _("No piece attacks %{field}.") % { field: field } :
              _("No opposing piece attacks %{field}.") % { field: field }
          else
            descriptions = attackers.map do |code, source_x, source_y|
              _("%{piece} from %{field}") % {
                piece: chess_piece_label(code),
                field: field_label(source_x, source_y)
              }
            end
            _("%{field} is attacked by %{pieces}.") % { field: field, pieces: descriptions.join(", ") }
          end
        end
      end
    end

    def translated_piece_name(kind)
      case kind
      when "P" then _("pawn")
      when "N" then _("knight")
      when "B" then _("bishop")
      when "R" then _("rook")
      when "Q" then _("chess queen")
      when "K" then _("king")
      else kind.to_s
      end
    end

    def action_to_move(action)
      metadata = {}
      %w[castle en_passant double].each { |key| metadata[key] = action[key].to_s if !action[key].to_s.empty? }
      BoardMove.new(
        from: [selection_value(action, "from_x"), selection_value(action, "from_y")],
        to: [selection_value(action, "to_x"), selection_value(action, "to_y")], metadata: metadata
      )
    rescue StandardError
      nil
    end

    def colour_for(state, actor)
      index = player_index(state[:players], actor)
      index == 0 ? "w" : (index == 1 ? "b" : nil)
    end

    def enemy_piece?(piece, colour)
      piece != nil && piece[0] != colour
    end

    def inside?(x, y)
      x.between?(0, 7) && y.between?(0, 7)
    end

    def duplicate_state(state)
      state.merge(
        board: state[:board].map(&:dup), castling: state[:castling].dup,
        en_passant: state[:en_passant]&.dup, pending_promotion: state[:pending_promotion]&.dup,
        positions: state[:positions].dup
      )
    end

    def position_key(state)
      ep = state[:en_passant]
      if ep != nil
        # A nominal target changes repetition rights only if a legal capture
        # exists. In particular a pinned pawn must not distinguish positions.
        ep = nil unless legal_moves(state, state[:current_player]).any? { |move| move.metadata["en_passant"] == "1" }
      end
      [state[:board].flatten.map { |piece| piece || "--" }.join, colour_for(state, state[:current_player]), state[:castling], ep].join(":")
    end
  end
end
