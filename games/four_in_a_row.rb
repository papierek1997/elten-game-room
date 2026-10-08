require_relative "base"
require_relative "../lib/game_bots"
require_relative "../lib/game_tree_search"
require_relative "../lib/board_presentation"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class FourInARow < Base
    include GameRoomBoardPresentation
    ROWS = 6
    COLUMNS = 7
    CONNECT = 4

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      action == "drop" ? "play2" : nil
    end

    def id
      "four_in_a_row"
    end

    def name
      _("Four in a row")
    end

    def short_description
      _("Drop pieces into columns and be the first to line up four.")
    end

    def rule_sections
      generated_rule_sections
    end

    def supports_bots?
      true
    end

    def shareable_simulation_snapshot?
      true
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::AlphaBetaStrategy.new(max_depth: 8, node_limit: 70_000)
    end

    def bot_search_key(replay, actor)
      marker = player_index(replay.players, actor)
      rows = replay.board.map do |row|
        row.map { |value| value == nil ? "-" : value.to_i.to_s }.join
      end
      board = rows.join
      mirrored_board = rows.map(&:reverse).join
      canonical_board = board < mirrored_board ? board : mirrored_board
      "#{marker}:#{player_index(replay.players, replay.current_player)}:#{canonical_board}"
    end

    def bot_position_value(replay, actor)
      return bot_reward(replay, actor) * 1_000_000.0 if replay.finished?

      marker = player_index(replay.players, actor)
      return 0.0 if marker == nil

      opponent = marker == 0 ? 1 : 0
      board = replay.board
      center = COLUMNS / 2
      value = board.sum do |row|
        row[center] == marker ? 8.0 : (row[center] == opponent ? -8.0 : 0.0)
      end
      immediate = [[], []]
      four_windows.each do |window|
        cells = window.map { |row, column| board[row][column] }
        own = cells.count(marker)
        other = cells.count(opponent)
        next if own > 0 && other > 0

        empty_index = cells.index(nil)
        playable = false
        if empty_index != nil
          row, column = window[empty_index]
          playable = first_empty_row(board, column) == row
        end
        if other == 0
          value += 18.0 if own == 2
          value += playable ? 520.0 : 150.0 if own == 3
          immediate[marker] << window[empty_index] if own == 3 && playable
        elsif own == 0
          value -= 22.0 if other == 2
          value -= playable ? 620.0 : 180.0 if other == 3
          immediate[opponent] << window[empty_index] if other == 3 && playable
        end
      end
      moving = player_index(replay.players, replay.current_player)
      if moving != nil
        return moving == marker ? 900_000.0 : -900_000.0 unless immediate[moving].empty?
        rival = 1 - moving
        return rival == marker ? 850_000.0 : -850_000.0 if immediate[rival].uniq.length >= 2
      end
      value
    end

    def bot_action_score(replay, actor, action, context: nil)
      column = selection_value(action, "x")
      row = first_empty_row(replay.board, column)
      marker = player_index(replay.players, actor)
      return -10_000.0 if row == nil || marker == nil

      board = replay.board.map(&:dup)
      board[row][column] = marker
      return 10_000.0 if winning_move?(board, row, column, marker)

      opponent = marker == 0 ? 1 : 0
      blocking_board = replay.board.map(&:dup)
      blocking_board[row][column] = opponent
      return 8_000.0 if winning_move?(blocking_board, row, column, opponent)

      20.0 - (column - COLUMNS / 2).abs * 3.0
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      position = Replay.new(
        board: Array.new(ROWS) { Array.new(COLUMNS) },
        players: players,
        current_player: players[0],
        winner: nil,
        draw: false,
        accepted_events: [],
        history: [starting_history(players)]
      )
      apply_events!(position, session, events, repository)
    end

    # Alpha-beta appends one hypothetical move at a time. Extend the immutable
    # parent position instead of replaying the complete move history at every
    # search node. The returned replay owns its board, event list and history,
    # so sibling branches cannot affect one another.
    def incremental_replay(replay, session, events, repository)
      return nil if replay == nil || replay.board == nil

      position = Replay.new(
        board: replay.board.map(&:dup),
        players: replay.players,
        current_player: replay.current_player,
        winner: replay.winner,
        draw: replay.draw == true,
        accepted_events: replay.accepted_events.dup,
        history: replay.history.dup
      )
      apply_events!(position, session, events, repository)
    end

    def surface_spec(replay, viewer)
      cells = replay.board.map do |row|
        row.map do |marker|
          board_owner_label(replay, marker)
        end
      end
      GameSurfaces::GridSpec.new(
        width: COLUMNS,
        height: ROWS,
        header: game_field_header(replay, viewer),
        cells: cells,
        row_origin: :bottom
      )
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] if !same_user?(replay.current_player, actor)
      return [:invalid, nil] if selection["kind"].to_s != "grid"
      return [:invalid, nil] if selection["action"].to_s != "select"

      column = selection_value(selection, "x")
      return [:invalid, nil] if column < 0 || column >= COLUMNS
      return [:column_full, nil] if !available_columns(replay).include?(column)

      [:ok, event_plan("drop", (column + 1).to_s)]
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)

      available_columns(replay).map do |column|
        {
          "kind" => "grid",
          "action" => "select",
          "x" => column,
          "y" => 0
        }
      end
    end

    def move_error(status)
      return _("This column is full.") if status == :column_full

      super
    end

    private

    def apply_events!(replay, session, events, repository)
      players, board = replay.players, replay.board
      accepted, history = replay.accepted_events, replay.history
      current_player, winner, draw = replay.current_player, replay.winner, replay.draw
      events.each do |event|
        break if winner != nil || draw

        actor = repository.actor_of(event, session)
        column = event["value"].to_i - 1
        next if event["action"].to_s != "drop"
        next if current_player == nil || !same_user?(actor, current_player)
        next if column < 0 || column >= COLUMNS

        row = first_empty_row(board, column)
        next if row == nil

        marker = player_index(players, actor)
        next if marker == nil

        board[row][column] = marker
        accepted << event
        event_id = repository.event_id(event)
        field = field_label(column, row)
        history << HistoryEntry.new(
          key: "move:#{event_id}",
          text: describe_move(actor, field),
          event_id: event_id,
          actor: actor,
          kind: :move,
          field: field
        )

        if winning_move?(board, row, column, marker)
          winner = actor
          history << result_history(event_id: event_id, winner: actor)
        elsif board_full?(board)
          draw = true
          history << result_history(event_id: event_id, draw: true)
        else
          current_player = other_player(players, actor)
        end
      end
      replay.current_player, replay.winner, replay.draw = current_player, winner, draw
      replay
    end

    def four_windows
      @four_windows ||= begin
        windows = []
        (0...ROWS).each do |row|
          (0..(COLUMNS - 4)).each do |column|
            windows << 4.times.map { |offset| [row, column + offset] }
          end
        end
        (0...COLUMNS).each do |column|
          (0..(ROWS - 4)).each do |row|
            windows << 4.times.map { |offset| [row + offset, column] }
          end
        end
        (0..(ROWS - 4)).each do |row|
          (0..(COLUMNS - 4)).each do |column|
            windows << 4.times.map { |offset| [row + offset, column + offset] }
            windows << 4.times.map { |offset| [row + 3 - offset, column + offset] }
          end
        end
        windows.freeze
      end
    end

    def available_columns(replay)
      (0...COLUMNS).select { |column| first_empty_row(replay.board, column) != nil }
    end

    def describe_move(actor, field)
      board_move_text(actor, field)
    end

    def first_empty_row(board, column)
      (0...ROWS).find { |row| board[row][column] == nil }
    end

    def board_full?(board)
      board.all? { |row| row.none?(&:nil?) }
    end

    def winning_move?(board, row, column, marker)
      [[1, 0], [0, 1], [1, 1], [1, -1]].any? do |row_step, column_step|
        connected = 1
        connected += count_direction(board, row, column, marker, row_step, column_step)
        connected += count_direction(board, row, column, marker, -row_step, -column_step)
        connected >= CONNECT
      end
    end

    def count_direction(board, row, column, marker, row_step, column_step)
      count = 0
      current_row = row + row_step
      current_column = column + column_step
      while current_row.between?(0, ROWS - 1) && current_column.between?(0, COLUMNS - 1)
        break if board[current_row][current_column] != marker

        count += 1
        current_row += row_step
        current_column += column_step
      end
      count
    end
  end
end

require_relative 'generated/rulebooks/four_in_a_row'
