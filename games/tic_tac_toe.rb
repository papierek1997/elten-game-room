require_relative "base"
require_relative "../lib/game_bots"
require_relative "../lib/game_tree_search"
require_relative "../lib/board_presentation"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class TicTacToe < Base
    include GameRoomBoardPresentation
    SIZE = 3
    MARKS = ["X", "O"].freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      action == "place" ? "play2" : nil
    end

    def id
      "tic_tac_toe"
    end

    def name
      _("Tic-tac-toe")
    end

    def short_description
      _("Place three of your marks in a line before your opponent does.")
    end

    def rule_sections
      generated_rule_sections
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::AlphaBetaStrategy.new(max_depth: 9, node_limit: 80_000)
    end

    def bot_search_key(replay, actor)
      marker = player_index(replay.players, actor)
      board = replay.board.flatten.map { |value| value == nil ? "-" : value.to_i.to_s }.join
      "#{marker}:#{player_index(replay.players, replay.current_player)}:#{board}"
    end

    def bot_action_score(replay, actor, action, context: nil)
      column = selection_value(action, "x")
      row = selection_value(action, "y")
      marker = player_index(replay.players, actor)
      return -1_000.0 if marker == nil || replay.board[row][column] != nil

      board = replay.board.map(&:dup)
      board[row][column] = marker
      return 1_000.0 if winning_move?(board, row, column, marker)

      opponent = marker == 0 ? 1 : 0
      blocking_board = replay.board.map(&:dup)
      blocking_board[row][column] = opponent
      return 800.0 if winning_move?(blocking_board, row, column, opponent)
      return 30.0 if column == 1 && row == 1
      return 15.0 if [0, 2].include?(column) && [0, 2].include?(row)

      5.0
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      board = Array.new(SIZE) { Array.new(SIZE) }
      accepted = []
      history = [starting_history(players)]
      current_player = players[0]
      winner = nil
      draw = false

      events.each do |event|
        break if winner != nil || draw
        next if event["action"].to_s != "place"

        actor = repository.actor_of(event, session)
        next if current_player == nil || !same_user?(actor, current_player)

        coordinates = parse_coordinates(event["value"])
        next if coordinates == nil

        column, row = coordinates
        next if board[row][column] != nil

        marker = player_index(players, actor)
        next if marker == nil || marker >= MARKS.length

        board[row][column] = marker
        accepted << event
        event_id = repository.event_id(event)
        field = field_label(column, row)
        mark = MARKS[marker]
        history << HistoryEntry.new(
          key: "move:#{event_id}",
          text: board_move_text(actor, field),
          event_id: event_id,
          actor: actor,
          kind: :move,
          field: field,
          value: mark
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

      Replay.new(
        board: board,
        players: players,
        current_player: current_player,
        winner: winner,
        draw: draw,
        accepted_events: accepted,
        history: history
      )
    end

    def surface_spec(replay, viewer)
      cells = replay.board.map do |row|
        row.map do |marker|
          board_owner_label(replay, marker)
        end
      end
      GameSurfaces::GridSpec.new(
        width: SIZE,
        height: SIZE,
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
      row = selection_value(selection, "y")
      return [:invalid, nil] if !column.between?(0, SIZE - 1) || !row.between?(0, SIZE - 1)
      return [:occupied, nil] if !available_fields(replay).include?([column, row])

      [:ok, event_plan("place", "#{column + 1},#{row + 1}")]
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)

      available_fields(replay).map do |column, row|
        {
          "kind" => "grid",
          "action" => "select",
          "x" => column,
          "y" => row
        }
      end
    end

    def move_error(status)
      return _("This field is already occupied.") if status == :occupied

      super
    end

    private

    def available_fields(replay)
      fields = []
      (0...SIZE).each do |row|
        (0...SIZE).each do |column|
          fields << [column, row] if replay.board[row][column] == nil
        end
      end
      fields
    end

    def parse_coordinates(value)
      match = /\A([1-3]),([1-3])\z/.match(value.to_s)
      match == nil ? nil : [match[1].to_i - 1, match[2].to_i - 1]
    end

    def board_full?(board)
      board.all? { |row| row.none?(&:nil?) }
    end

    def winning_move?(board, row, column, marker)
      board[row].all? { |value| value == marker } ||
        board.all? { |candidate| candidate[column] == marker } ||
        (row == column && (0...SIZE).all? { |index| board[index][index] == marker }) ||
        (row + column == SIZE - 1 && (0...SIZE).all? { |index| board[index][SIZE - index - 1] == marker })
    end
  end
end

require_relative 'generated/rulebooks/tic_tac_toe'
