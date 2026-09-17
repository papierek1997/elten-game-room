require_relative "base"
require_relative "../lib/game_bots"
require_relative "../lib/farkle_strategy"

module GameRoomGames
  class Farkle < Base
    DIE_COUNT = 6

    def id
      "farkle"
    end

    def name
      _("Farkle")
    end

    def rule_sections
      [
        rule_section(:risk, _("Keep points or risk another roll"),
          _("Farkle is played by 2 to 8 players with six dice. Everyone starts with zero banked points. The table master may configure the winning score, the minimum score for an ordinary bank and the minimum required for a player's first bank."),
          _("The default values are 1000 points to win, 30 points to bank a turn and 50 points for the first bank."),
          _("Start your turn by rolling all six dice. Use the Arrow keys to choose one of the complete scoring combinations offered from that roll and press Enter. Its dice are kept and its points are added to the current turn."),
          _("After keeping a combination, choose either Roll N dice or, once the required minimum has been reached, Bank X points. Rolling continues the same turn with the remaining dice; banking makes the turn points permanent and passes play to the next player."),
          _("Kept dice from separate rolls cannot be combined into a new scoring set. If all six dice score, you have hot dice and may roll all six again while keeping the accumulated turn points. A roll with no scoring combination is a Farkle: the entire unbanked turn score is lost and the turn ends.")),
        rule_section(:scoring, _("Scoring combinations in this implementation"),
          _("A single one scores 10 and a single five scores 5. Three ones score 75; triples of 2, 3, 4, 5 and 6 score 20, 30, 40, 50 and 60 respectively. Four equal dice score 100 plus ten times their face (110–160). Five equal dice score 300 plus twenty times their face (320–420). Six equal dice score 600 plus twenty-five times their face (625–750)."),
          _("Five consecutive values, 1–5 or 2–6, score 100. All six different values score 200. Three pairs of different values score 150. Four of one value plus two of another, or two different triples, score 250. The four-plus-two combination is not the five-dice full house from Yahtzee."),
          _("A selection must use every chosen die in a scoring group; stray twos, threes, fours or sixes cannot be attached for free. Several scoring groups from the same roll can be combined. When more than one interpretation uses the selected dice, the program awards the highest valid score. Previously kept dice do not help form a group in a later roll.")),
        rule_section(:banking, _("Banking thresholds and the winning score"),
          _("Score limit changes the winning total. Minimum score to bank a turn controls later banks. Minimum score to enter the game applies while a player's banked score is still zero. All three values are entered when the table is created."),
          _("The scoring combinations themselves do not change between table configurations."),
          _("When a player's banked total reaches or exceeds the selected score limit, the round is played to its end, so that every player has taken the same number of turns. The highest banked total then wins, and equal totals end the game in a draw."),
          _("Reaching the target with unbanked turn points is not enough: you must bank them. A Farkle loses only the current turn's unbanked points, not points saved in earlier turns. The first-bank minimum applies while your saved score is zero; after a successful first bank the ordinary minimum applies.")),
        rule_section(:controls, _("Selecting combinations, rolling and banking"),
          _("Use the Up and Down Arrow keys to browse available scoring combinations, Roll and Bank. Press Enter to choose the current item. Roll and Bank appear next to each other in the same list rather than as separate Tab fields."),
          _("T reads the turn, S all scores, C the current turn total and required minimum, and D the last roll. Outside your own turn the game field is informational; the other player's dice are not choices for you to play."))
      ]
    end

    def minimum_players
      2
    end

    def maximum_players
      8
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= FarklePlanning::Strategy.new
    end

    def bot_keep_details(replay, action)
      return nil if action["action"].to_s != "keep"

      indices = parse_indices(action["indices"])
      points = score_for_indices(replay.state[:last_roll], indices)
      return nil if points == nil

      remaining = replay.state[:dice_to_roll].to_i - indices.length
      remaining = DIE_COUNT if remaining == 0
      { points: points.to_i, dice_to_roll: remaining }
    end

    def bot_observation(replay, actor)
      state = replay.state
      {
        "players" => state[:players],
        "scores" => state[:scores],
        "phase" => state[:phase],
        "current_player" => state[:current_player],
        "turn_points" => state[:turn_points],
        "dice_to_roll" => state[:dice_to_roll],
        "last_roll" => state[:last_roll],
        "winner" => state[:winner],
        "viewer" => actor.to_s
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      case action["action"].to_s
      when "keep"
        indices = parse_indices(action["indices"])
        points = score_for_indices(state[:last_roll], indices).to_i
        remaining = state[:dice_to_roll].to_i - indices.length
        remaining = DIE_COUNT if remaining == 0
        points * 10.0 + remaining
      when "bank"
        player = player_key(state, actor)
        total = state[:scores].fetch(player, 0).to_i + state[:turn_points].to_i
        return 100_000.0 if total >= state[:options]["score_limit"].to_i

        state[:turn_points].to_i * 12.0
      when "roll"
        risk_discount = state[:turn_points].to_i * (DIE_COUNT - state[:dice_to_roll].to_i + 1) / 8.0
        450.0 - risk_discount
      else
        -1_000.0
      end
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "score_limit",
          label: _("Score limit"),
          kind: :integer,
          default: 1_000
        ),
        OptionDefinition.new(
          key: "turn_minimum",
          label: _("Minimum score to bank a turn"),
          kind: :integer,
          default: 30
        ),
        OptionDefinition.new(
          key: "entry_minimum",
          label: _("Minimum score to enter the game"),
          kind: :integer,
          default: 50
        )
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("The score limit must be greater than zero.") if values["score_limit"].to_i <= 0
      return _("The minimum turn score cannot be negative.") if values["turn_minimum"].to_i < 0
      return _("The minimum entry score cannot be negative.") if values["entry_minimum"].to_i < 0

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      _("to %{limit} points; bank from %{turn}; first bank from %{entry}") % {
        limit: values["score_limit"],
        turn: values["turn_minimum"],
        entry: values["entry_minimum"]
      }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]

      events.each do |event|
        break if state[:phase] == :finished

        actor = repository.actor_of(event, session)
        applied = case event["action"].to_s
        when "roll"
          apply_roll(state, event, actor, repository, history)
        when "select"
          apply_select(state, event, actor)
        when "keep"
          apply_keep(state, event, actor, repository, history)
        when "bank"
          apply_bank(state, event, actor, repository, history)
        else
          false
        end
        accepted << event if applied
      end

      Replay.new(
        board: nil,
        players: players,
        current_player: state[:current_player],
        winner: state[:winner],
        draw: state[:draw],
        accepted_events: accepted,
        history: history,
        state: state
      )
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:phase] == :finished
      return [] if !same_user?(state[:current_player], actor)

      if state[:phase] == :selecting
        scoring_selections(state[:last_roll]).map do |indices|
          {
            "kind" => "command",
            "action" => "keep",
            "indices" => indices.join(",")
          }
        end
      elsif state[:phase] == :awaiting_roll
        actions = [{ "kind" => "dice", "action" => "roll" }]
        actions << { "kind" => "dice", "action" => "bank" } if can_bank?(state, actor)
        actions
      else
        []
      end
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)

      action = selection["action"].to_s
      if selection["kind"].to_s == "card" && action == "select" && selection["zone"].to_s == "actions"
        action = selection["card"].to_s
      end
      case action
      when "roll"
        return [:invalid, nil] if state[:phase] != :awaiting_roll
        return [:invalid, nil] if context == nil || context.random_source == nil

        count = state[:dice_to_roll].to_i
        values = context.random_source.roll(count: count, sides: 6).values
        [:ok, event_plan("roll", values.join(","))]
      when "toggle"
        return [:invalid, nil] if state[:phase] != :selecting
        index = selection_value(selection, "index")
        return [:invalid, nil] if !index.between?(0, state[:last_roll].length - 1)

        [:ok, event_plan("select", index.to_s)]
      when "select"
        return [:invalid, nil] if state[:phase] != :selecting
        return [:invalid, nil] if selection["kind"].to_s != "card"
        return [:invalid, nil] if selection["zone"].to_s != "combinations"

        indices = parse_indices(selection["card"])
        score = score_for_indices(state[:last_roll], indices)
        return [:invalid_selection, nil] if score == nil

        [:ok, event_plan("keep", indices.join(","))]
      when "keep"
        return [:invalid, nil] if state[:phase] != :selecting
        indices = parse_indices(selection["indices"])
        indices = state[:selected_indices].sort if indices.empty?
        score = score_for_indices(state[:last_roll], indices)
        return [:invalid_selection, nil] if score == nil

        [:ok, event_plan("keep", indices.join(","))]
      when "bank"
        return [:invalid, nil] if state[:phase] != :awaiting_roll
        return [:minimum_not_reached, nil] if !can_bank?(state, actor)

        [:ok, event_plan("bank", "")]
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if !replay.finished? && !same_user?(state[:current_player], viewer)
        waiting_label = current_turn_shortcut_text(replay, viewer)
        return GameSurfaces::CardTableSpec.new(
          zones: [
            GameSurfaces::CardZoneSpec.new(
              id: "actions",
              header: waiting_label,
              cards: [],
              empty_label: waiting_label
            )
          ]
        )
      end

      if state[:phase] == :selecting
        combinations = scoring_selections(state[:last_roll]).map do |indices|
          values = indices.map { |index| state[:last_roll][index] }
          score = score_for_indices(state[:last_roll], indices)
          GameSurfaces::Card.new(
            id: indices.join(","),
            label: _("Keep %{dice}; %{points} points") % {
              dice: values.join(", "),
              points: score
            },
            value: indices.join(",")
          )
        end
        return GameSurfaces::CardTableSpec.new(
          zones: [
            GameSurfaces::CardZoneSpec.new(
              id: "combinations",
              header: _("Scoring combinations from the last roll: %{dice}") % {
                dice: state[:last_roll].join(", ")
              },
              cards: combinations,
              empty_label: _("No scoring combinations")
            )
          ]
        )
      end

      actions = [
        GameSurfaces::Card.new(
          id: "roll",
          label: _("Roll %{count} dice") % { count: state[:dice_to_roll] },
          value: "roll"
        )
      ]
      actions << GameSurfaces::Card.new(
        id: "bank",
        label: _("Bank %{points} points") % { points: state[:turn_points] },
        value: "bank"
      ) if can_bank?(state, state[:current_player])
      GameSurfaces::CardTableSpec.new(
        zones: [
          GameSurfaces::CardZoneSpec.new(
            id: "actions",
            header: _("Actions. Use the arrow keys and press Enter"),
            cards: actions,
            empty_label: _("No actions are available")
          )
        ]
      )
    end

    def participant_scores(replay)
      replay.state[:scores].dup
    end

    def shortcut_features
      super + [:scores, :current_total, :last_roll]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :scores
        { message: scores_text(state) }
      when :current_total
        { message: current_total_text(state, viewer) }
      when :last_roll
        { message: last_roll_text(state) }
      else
        super
      end
    end

    def move_error(status)
      case status
      when :invalid_selection
        _("The selected dice do not form a scoring combination.")
      when :minimum_not_reached
        _("You have not reached the minimum score required to bank this turn.")
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id.to_i }
      entries.empty? ? nil : entries.map(&:text)
    end

    # Returns the best legal score using every supplied die, or nil when at
    # least one die cannot belong to a scoring combination from the same roll.
    def score_selection(values)
      dice = values.to_a.map(&:to_i)
      return nil if dice.empty? || dice.any? { |value| !value.between?(1, 6) }

      counts = (1..6).map { |face| dice.count(face) }
      scores = []
      ordinary = counts.each_with_index.sum do |count, index|
        score_for_face(index + 1, count) || -100_000
      end
      scores << ordinary if ordinary >= 0
      if dice.length == 5 && ([1, 2, 3, 4, 5] - dice).empty?
        scores << 100
      end
      if dice.length == 5 && ([2, 3, 4, 5, 6] - dice).empty?
        scores << 100
      end
      scores << 200 if dice.length == 6 && counts.all? { |count| count == 1 }
      scores << 150 if dice.length == 6 && counts.count(2) == 3
      scores << 250 if dice.length == 6 && counts.sort == [0, 0, 0, 0, 2, 4]
      scores << 250 if dice.length == 6 && counts.count(3) == 2
      scores.empty? ? nil : scores.max
    end

    private

    def initial_state(players, options)
      {
        players: players,
        options: options,
        scores: players.each_with_object({}) { |player, result| result[player] = 0 },
        phase: :awaiting_roll,
        current_player: players.first,
        turn_points: 0,
        dice_to_roll: DIE_COUNT,
        last_roll: [],
        selected_indices: [],
        final_round: false,
        winner: nil,
        draw: false
      }
    end

    def apply_roll(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_roll
      return false if !same_user?(state[:current_player], actor)

      values = parse_roll(event["value"])
      return false if values.length != state[:dice_to_roll].to_i

      state[:last_roll] = values
      state[:selected_indices] = []
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "roll:#{event_id}",
        text: _("%{player} rolled: %{dice}.") % {
          player: participant_name(actor),
          dice: values.join(", ")
        },
        event_id: event_id,
        actor: actor,
        kind: :roll,
        value: values.join(",")
      )
      if scoring_selections(values).empty?
        history << HistoryEntry.new(
          key: "farkle:#{event_id}",
          text: _("Farkle. %{player} lost %{points} points from this turn.") % {
            player: participant_name(actor),
            points: state[:turn_points]
          },
          event_id: event_id,
          actor: actor,
          kind: :farkle
        )
        finish_turn(state, actor, event_id, history)
      else
        state[:phase] = :selecting
      end
      true
    rescue ArgumentError
      false
    end

    def apply_select(state, event, actor)
      return false if state[:phase] != :selecting
      return false if !same_user?(state[:current_player], actor)

      index = Integer(event["value"].to_s, 10)
      return false if !index.between?(0, state[:last_roll].length - 1)

      if state[:selected_indices].include?(index)
        state[:selected_indices].delete(index)
      else
        state[:selected_indices] << index
        state[:selected_indices].sort!
      end
      true
    rescue ArgumentError
      false
    end

    def apply_keep(state, event, actor, repository, history)
      return false if state[:phase] != :selecting
      return false if !same_user?(state[:current_player], actor)

      indices = parse_indices(event["value"])
      score = score_for_indices(state[:last_roll], indices)
      return false if score == nil

      dice = indices.map { |index| state[:last_roll][index] }
      state[:turn_points] += score
      state[:dice_to_roll] -= indices.length
      hot_dice = state[:dice_to_roll] == 0
      state[:dice_to_roll] = DIE_COUNT if hot_dice
      state[:phase] = :awaiting_roll
      state[:selected_indices] = []
      event_id = repository.event_id(event)
      text = _("%{player} kept %{dice} for %{score} points; turn total %{total}.") % {
        player: participant_name(actor),
        dice: dice.join(", "),
        score: score,
        total: state[:turn_points]
      }
      text += " " + _("All six dice scored; hot dice.") if hot_dice
      history << HistoryEntry.new(
        key: "keep:#{event_id}",
        text: text,
        event_id: event_id,
        actor: actor,
        kind: :keep,
        value: score
      )
      true
    end

    def apply_bank(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_roll
      return false if !same_user?(state[:current_player], actor)
      return false if !can_bank?(state, actor)

      player = player_key(state, actor)
      points = state[:turn_points]
      state[:scores][player] += points
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "bank:#{event_id}",
        text: _("%{player} banked %{points} points and now has %{total}.") % {
          player: participant_name(player),
          points: points,
          total: state[:scores][player]
        },
        event_id: event_id,
        actor: actor,
        kind: :bank,
        value: points
      )
      if !state[:final_round] && state[:scores][player] >= state[:options]["score_limit"].to_i
        state[:final_round] = true
        history << HistoryEntry.new(
          key: "final:#{event_id}",
          text: _("%{player} reached %{limit} points. The current round is played to its end.") % {
            player: participant_name(player),
            limit: state[:options]["score_limit"]
          },
          event_id: event_id,
          actor: actor,
          kind: :final_round
        )
      end
      finish_turn(state, actor, event_id, history)
      true
    end

    def finish_turn(state, actor, event_id, history)
      following = next_player(state[:players], actor)
      return conclude_game(state, event_id, history) if final_round_complete?(state, following)

      state[:phase] = :awaiting_roll
      state[:current_player] = following
      state[:turn_points] = 0
      state[:dice_to_roll] = DIE_COUNT
      state[:last_roll] = []
      state[:selected_indices] = []
    end

    def final_round_complete?(state, following)
      state[:final_round] && same_user?(following, state[:players].first)
    end

    def conclude_game(state, event_id, history)
      maximum = state[:scores].values.max
      winners = state[:players].select { |player| state[:scores][player] == maximum }
      state[:winner] = winners.one? ? winners.first : nil
      state[:draw] = winners.length > 1
      state[:phase] = :finished
      state[:current_player] = nil
      history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
    end

    def can_bank?(state, actor)
      return false if state[:turn_points].to_i <= 0
      player = player_key(state, actor)
      return false if player == nil

      minimum = if state[:scores].fetch(player, 0).to_i == 0
        state[:options]["entry_minimum"].to_i
      else
        state[:options]["turn_minimum"].to_i
      end
      state[:turn_points].to_i >= minimum
    end

    def scoring_selections(values)
      dice = values.to_a
      unique = {}
      (1...(1 << dice.length)).each do |mask|
        indices = dice.each_index.select { |index| (mask & (1 << index)) != 0 }
        score = score_for_indices(dice, indices)
        next if score == nil

        key = indices.map { |index| dice[index] }.sort.join(",")
        unique[key] ||= indices
      end
      unique.values.sort_by do |indices|
        values_for_selection = indices.map { |index| dice[index] }
        [-score_for_indices(dice, indices).to_i, -indices.length, values_for_selection.sort]
      end
    end

    def score_for_indices(values, indices)
      positions = indices.to_a.map(&:to_i)
      return nil if positions.empty? || positions.uniq.length != positions.length
      return nil if positions.any? { |index| !index.between?(0, values.length - 1) }

      score_selection(positions.map { |index| values[index] })
    end

    def score_for_face(face, count)
      return 0 if count == 0

      groups = []
      groups << [1, face == 1 ? 10 : 5] if [1, 5].include?(face)
      groups << [3, face == 1 ? 75 : face * 10]
      groups << [4, 100 + face * 10]
      groups << [5, 300 + face * 20]
      groups << [6, 600 + face * 25]
      best = Array.new(count + 1)
      best[0] = 0
      (1..count).each do |used|
        candidates = groups.filter_map do |size, points|
          previous = used >= size ? best[used - size] : nil
          previous == nil ? nil : previous + points
        end
        best[used] = candidates.max
      end
      best[count]
    end

    def parse_roll(value)
      fields = value.to_s.split(",", -1)
      raise ArgumentError, "invalid roll" if fields.empty?

      fields.map do |field|
        number = Integer(field, 10)
        raise ArgumentError, "invalid die" if !number.between?(1, 6)
        number
      end
    end

    def parse_indices(value)
      return [] if value == nil || value.to_s.empty?

      value.to_s.split(",", -1).map { |field| Integer(field, 10) }
    rescue ArgumentError
      []
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def next_player(players, actor)
      index = players.index { |player| same_user?(player, actor) }
      index == nil ? nil : players[(index + 1) % players.length]
    end

    def scores_text(state)
      values = state[:players].map do |player|
        _("%{player}: %{score}") % {
          player: participant_name(player),
          score: state[:scores].fetch(player, 0)
        }
      end
      _("Scores: %{scores}.") % { scores: values.join("; ") }
    end

    def current_total_text(state, viewer)
      minimum = if same_user?(state[:current_player], viewer)
        player = player_key(state, viewer)
        state[:scores].fetch(player, 0).to_i == 0 ?
          state[:options]["entry_minimum"] : state[:options]["turn_minimum"]
      end
      text = _("Current turn: %{points} points.") % { points: state[:turn_points] }
      text += " " + _("You may bank from %{minimum} points.") % { minimum: minimum } if minimum != nil
      text
    end

    def last_roll_text(state)
      return _("No dice have been rolled in this turn.") if state[:last_roll].empty?

      _("Last roll: %{dice}.") % { dice: state[:last_roll].join(", ") }
    end
  end
end
