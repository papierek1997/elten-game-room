require_relative '../lib/board_preference_definition'
require_relative "../lib/game_bots"
require_relative "base"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Ludo < Base
    PAWNS_PER_PLAYER = 4
    OUTER_LENGTH = 52
    FINISH_PROGRESS = 57
    HOME_LANE_LENGTH = FINISH_PROGRESS - OUTER_LENGTH + 1
    ENTRY_INDICES = [0, 13, 26, 39].freeze
    SAFE_TRACK_INDICES = ENTRY_INDICES.freeze
    PAWN_MOVE_ACTION = "move_pawn"

    def board_preference_definitions
      [GameRoomBoardPreference::Definition.new(key: 'player_labels', values: %w[names colours],
        command: 'toggle_player_labels', state_key: 'player_labels')]
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      if action == "roll"
        moved_automatically = history.any? { |entry| entry.kind == :move }
        return moved_automatically ? ["roll", "play2"] : "roll"
      end

      ["move", "move_pawn"].include?(action) ? "play2" : nil
    end

    def id
      "ludo"
    end

    def name
      _("Ludo")
    end

    def short_description
      _("Race your four pieces to the finish, sending your opponents' pieces back to base along the way.")
    end

    def minimum_players
      2
    end

    def maximum_players
      4
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def option_definitions
      [
        OptionDefinition.new(key: "enter_on_six", label: _("A 6 allows leaving the base"), kind: :boolean, default: true),
        OptionDefinition.new(key: "enter_on_one", label: _("A 1 allows leaving the base"), kind: :boolean, default: true),
        OptionDefinition.new(key: "extra_on_six", label: _("Roll again after a 6"), kind: :boolean, default: true),
        OptionDefinition.new(key: "exact_finish", label: _("An exact roll is required to reach the finish"), kind: :boolean, default: true),
        OptionDefinition.new(key: "three_sixes", label: _("Three consecutive sixes lose the turn"), kind: :boolean, default: true),
        OptionDefinition.new(key: "blockades", label: _("Two pawns of one player form a blockade"), kind: :boolean, default: true)
      ]
    end

    def options_summary(options)
      normalize_options(options) == default_options ? _("classic rules; four pawns per player") : _("custom rules; four pawns per player")
    end

    def options_from_json(value)
      parsed = value.to_s.empty? ? {} : JSON.parse(value.to_s)
      parsed = {} unless parsed.is_a?(Hash)
      normalize_options({"enter_on_one" => false}.merge(parsed))
    rescue JSON::ParserError
      normalize_options("enter_on_one" => false)
    end

    def rule_sections
      generated_rule_sections
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = initial_state(players, options)
      accepted = []
      history = [starting_history(players)]

      events.each do |event|
        break if state[:winner] != nil
        actor = repository.actor_of(event, session)
        next if !same_user?(actor, state[:current_player])

        applied = case event["action"].to_s
        when "roll"
          apply_roll!(state, event, actor, repository, history)
        when PAWN_MOVE_ACTION
          apply_pawn_move!(state, event, actor, repository, history)
        when "move"
          apply_legacy_pawn_move!(state, event, actor, repository, history)
        else
          false
        end
        accepted << event if applied
      end

      Replay.new(
        board: board_snapshot(state), players: players, current_player: state[:current_player], winner: state[:winner],
        draw: false, accepted_events: accepted, history: history, state: state
      )
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      return [{ "kind" => "dice", "action" => "roll" }] if replay.state[:phase] == :awaiting_roll

      player = player_index(replay.state[:players], actor)
      legal_pawn_indices(replay.state, player).map do |pawn|
        { "kind" => "pawn", "action" => "move", "pawn" => pawn.to_s }
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      player = player_index(state[:players], viewer)
      own_turn = !replay.finished? && same_user?(state[:current_player], viewer)
      choosing = own_turn && state[:phase] == :moving
      items = if choosing
        move_choice_items(state, player)
      else
        main_status_items(replay, viewer)
      end
      activation_action = if own_turn && state[:phase] == :awaiting_roll
        GameSurfaces::Action.new(kind: "dice", name: "roll", source: "ludo_pawns")
      end
      GameSurfaces::PawnTrackSpec.new(
        id: "ludo_pawns",
        header: pawn_track_header(replay, viewer),
        items: items,
        empty_label: _("No pawns to display"),
        activation_action: activation_action,
        player_labels: board_presentation_preferences.to_h.fetch("player_labels", "names")
      )
    end

    def describe_event(event, repository, replay, _viewer)
      event_id = repository.event_id(event).to_i
      spoken_kinds = [:roll, :move, :capture, :pass, :turn_end]
      replay.history.filter_map do |entry|
        entry.text if entry.event_id.to_i == event_id && spoken_kinds.include?(entry.kind)
      end
    end

    def history_presentation_depends_on_surface_state?; true; end

    def history_entries_for_display(replay, _viewer, surface_state: {})
      replay.history.map do |entry|
        data = entry.value
        next entry unless data.is_a?(Hash) && data.key?(:ludo_seat)
        copy = entry.dup
        copy.text = display_history_entry(entry, data, surface_state)
        copy
      end
    end

    def describe_event_for_display(event, repository, replay, viewer, surface_state: {})
      event_id = repository.event_id(event).to_i
      history_entries_for_display(replay, viewer, surface_state: surface_state).filter_map do |entry|
        entry.text if entry.event_id.to_i == event_id && [:roll, :move, :capture, :pass, :turn_end].include?(entry.kind)
      end
    end

    def turn_announcement(replay, viewer)
      return if replay == nil || replay.finished? || replay.current_player == nil
      return _("It is your turn.") if same_user?(replay.current_player, viewer)
      _("Turn: %{player}.") % {player: display_player(replay.state, replay.current_player)}
    end

    def turn_transition_history_entry(before_replay, after_replay, event_id:)
      entry = super
      entry.value = {ludo_seat: player_index(after_replay.players, entry.actor)}.freeze if entry
      entry
    end

    def result_text(replay)
      return super unless replay.winner
      _("%{player} won the game.") % {player: display_player(replay.state, replay.winner)}
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] if !same_user?(replay.current_player, actor)
      if ["dice", "command"].include?(selection["kind"].to_s) && selection["action"].to_s == "roll"
        return [:invalid, nil] if state[:phase] != :awaiting_roll || context == nil || context.random_source == nil

        value = context.random_source.roll(count: 1, sides: 6).values.first.to_i
        return [:ok, event_plan("roll", value.to_s)]
      end
      return [:invalid, nil] if state[:phase] != :moving
      return [:invalid, nil] if selection["kind"].to_s != "pawn" || selection["action"].to_s != "move"

      player = player_index(state[:players], actor)
      pawn_value = selection["pawn"].to_s
      return [:invalid_move, nil] if !/\A\d+\z/.match?(pawn_value)
      pawn = pawn_value.to_i
      return [:invalid_move, nil] if !legal_pawn_indices(state, player).include?(pawn)

      [:ok, event_plan(PAWN_MOVE_ACTION, pawn.to_s)]
    end

    def move_error(status)
      return _("This pawn cannot move after the current roll.") if status == :invalid_move

      super
    end

    def bot_action_score(replay, actor, action, context: nil)
      return 0.0 if action["action"].to_s == "roll"

      state = replay.state
      player = player_index(state[:players], actor)
      pawn = action["pawn"].to_i
      return -10_000.0 if !legal_pawn_indices(state, player).include?(pawn)

      before = state[:pawns][player][pawn]
      after = destination_progress(state, player, pawn)
      score = after - before
      score += 1_000 if after == FINISH_PROGRESS
      score += 240 if before < 0
      captures = capture_targets(state, player, after)
      score += captures.sum { |other, index| 180 + state[:pawns][other][index] * 6 }
      score += 80 if safe_progress?(player, after)
      moved = state.merge(pawns: state[:pawns].map(&:dup))
      moved[:pawns][player][pawn] = after
      captures.each { |other, index| moved[:pawns][other][index] = -1 }
      score -= exposure_risk(moved, player, after) * (35 + after * 3)
      score
    end

    def bot_position_value(replay, actor)
      return bot_reward(replay, actor) * 1_000_000.0 if replay.finished?
      player = player_index(replay.players, actor)
      own = replay.state[:pawns][player].sum { |progress| progress < 0 ? -8 : progress }
      others = replay.state[:pawns].each_with_index.reject { |_pawns, index| index == player }
        .sum { |pawns, _index| pawns.sum { |progress| progress < 0 ? -8 : progress } }
      own * 5.0 - others * 2.0
    end

    def bot_search_key(replay, actor)
      state = replay.state
      "#{player_index(replay.players, actor)}:#{player_index(replay.players, replay.current_player)}:#{state[:phase]}:#{state[:roll]}:#{state[:pawns].flatten.join(',')}"
    end

    def custom_game_shortcuts(replay, viewer)
      player = player_index(replay.state[:players], viewer)
      ordered = replay.state[:players].rotate(player || 0)
      shortcuts = ordered.each_with_index.map do |owner, index|
        announcement_shortcut(key: (index + 1).to_s,
          label: _("read positions: %{player}") % { player: display_player(replay.state, owner) },
          message: _("%{player}: %{positions}.") % {
            player: display_player(replay.state, owner),
            positions: pawn_status_labels(replay.state, player_index(replay.state[:players], owner)).join("; ")
          })
      end
      shortcuts + [
        announcement_shortcut(key: "c", label: _("read players' colours"),
          message: replay.players.each_with_index.map { |name, index| "#{participant_name(name)}, #{player_colour(index)}" }.join("; ")),
        surface_shortcut(key: "c", modifiers: [:control], label: _("switch between player names and colours"),
          command: "toggle_player_labels", payload: {"names" => _("Player names."), "colours" => _("Player colours.")}),
        announcement_shortcut(
          key: "p",
          label: _("read your pawn positions"),
          message: pawn_positions_text(replay.state, viewer)
        ),
        GameShortcut.new(
          key: "p",
          modifiers: [:shift],
          label: _("read the opponents' pawn positions"),
          kind: :announcement,
          message: opponents_pawn_positions_text(replay.state, viewer)
        ),
        browse_shortcut(
          key: "v",
          label: _("browse your pawns"),
          prompt: _("Your pawns"),
          choices: own_pawn_browse_choices(replay.state, viewer)
        ),
        browse_shortcut(
          key: "v",
          modifiers: [:shift],
          label: _("browse all pawns"),
          prompt: _("All pawns"),
          choices: all_pawn_browse_choices(replay.state)
        )
      ]
    end

    def shortcut_features; super + [:last_roll]; end
    def shortcut_feature_data(feature, replay, viewer)
      if feature == :turn && replay.finished? && replay.winner
        return {message: _("%{player} wins the game.") % {player: display_player(replay.state, replay.winner)}}
      end
      if feature == :turn && !replay.finished?
        return {message: _("Turn: %{player}.") % {player: display_player(replay.state, replay.current_player)}}
      end
      if feature == :material
        return {message: replay.players.each_with_index.map { |name, index|
          _("%{player}: %{count} at the finish") % {player: display_player(replay.state, name), count: replay.state[:pawns][index].count(FINISH_PROGRESS)}
        }.join("; ")}
      end
      return super unless feature == :last_roll
      roll = replay.state[:last_roll]
      { message: roll == nil ? _("The dice have not been rolled.") : _("%{player}, %{dice}.") % {
        player: display_player(replay.state, replay.state[:last_roll_player]), dice: roll } }
    end

    private

    def player_colour(index)
      # Explicit calls keep these translated in source extraction, too.
      [_("red"), _("blue"), _("yellow"), _("green")][index]
    end

    def display_player(state, name)
      index = player_index(state[:players], name)
      historical_player(name, index)
    end

    def historical_player(name, index, presentation = {})
      mode = presentation.to_h.fetch("player_labels", board_presentation_preferences.to_h["player_labels"])
      mode == "colours" && index != nil ? player_colour(index) : participant_name(name)
    end

    def starting_history(players)
      entry = super
      entry.value = {ludo_seat: nil, players: players.dup.freeze}.freeze
      entry
    end

    def display_history_entry(entry, data, presentation)
      player = historical_player(entry.actor, data[:ludo_seat], presentation)
      case entry.kind
      when :start
        _("Game started: %{players}.") % {players: data[:players].each_with_index.map { |name, i| historical_player(name, i, presentation) }.join(", ")}
      when :roll
        _("%{player} rolled %{value}.") % {player: player, value: data[:roll]}
      when :turn_end
        _("%{player}: three consecutive sixes; end of turn.") % {player: player}
      when :pass
        _("%{player}: no legal move.") % {player: player}
      when :move
        _("%{player}, %{from} %{to}.") % {player: player,
          from: progress_from(data[:ludo_seat], data[:from]), to: progress_to(data[:ludo_seat], data[:to])}
      when :capture
        text = _("%{player}: captured %{opponent}, %{from}; back to the base.") % {
          player: player, opponent: historical_player(data[:opponent], data[:opponent_seat], presentation),
          from: progress_from(data[:ludo_seat], data[:to])}
        data[:count] > 1 ? _("%{text} Capture %{index} of %{count}.") % {text: text, index: data[:index], count: data[:count]} : text
      when :turn
        _("Turn: %{player}.") % {player: player}
      when :result
        _("%{player} won the game.") % {player: player}
      else
        entry.text
      end
    end

    def progress_from(player, progress)
      return _("from the base") if progress < 0
      return _("from the finish") if progress == FINISH_PROGRESS
      return _("from home lane %{position}") % {position: progress - OUTER_LENGTH + 1} if progress >= OUTER_LENGTH
      _("from track %{position}") % {position: global_track_index(player, progress) + 1}
    end

    def progress_to(player, progress)
      return _("to the base") if progress < 0
      return _("to the finish") if progress == FINISH_PROGRESS
      return _("to home lane %{position}") % {position: progress - OUTER_LENGTH + 1} if progress >= OUTER_LENGTH
      _("to track %{position}") % {position: global_track_index(player, progress) + 1}
    end

    def main_status_items(replay, viewer)
      label = if replay.finished?
        result_text(replay) || _("The game is finished.")
      elsif same_user?(replay.state[:current_player], viewer) && replay.state[:phase] == :awaiting_roll
        _("Roll the die")
      else
        _("Waiting for a move: %{player}") % { player: display_player(replay.state, replay.state[:current_player]) }
      end
      [GameSurfaces::PawnTrackItem.new(id: "status", label: label)]
    end

    def pawn_track_header(replay, viewer)
      state = replay.state
      if !replay.finished? && same_user?(state[:current_player], viewer) && state[:phase] == :moving
        _("You rolled %{value}. Choose a pawn to move") % { value: state[:roll] }
      else
        name
      end
    end

    def move_choice_items(state, player)
      legal_pawn_indices(state, player).map do |pawn|
        GameSurfaces::PawnTrackItem.new(
          id: "move:#{pawn}",
          label: move_choice_label(state, player, pawn),
          action: GameSurfaces::Action.new(
            kind: "pawn", name: "move", payload: { "pawn" => pawn.to_s }, source: "ludo_pawns"
          )
        )
      end
    end

    def move_choice_label(state, player, pawn)
      before = state[:pawns][player][pawn]
      after = destination_progress(state, player, pawn)
      label = _("%{player}, %{from}; will move to %{to}") % {
        player: display_player(state, state[:players][player]),
        from: progress_label(player, before),
        to: progress_label(player, after)
      }
      captures = capture_targets(state, player, after).length
      if captures == 1
        label = _("%{move}; captures an opposing pawn") % { move: label }
      elsif captures > 1
        label = _("%{move}; opposing pawns captured: %{count}") % { move: label, count: captures }
      end
      label = _("%{move}; safe field") % { move: label } if after < OUTER_LENGTH && safe_progress?(player, after)
      label
    end

    def pawn_status_labels(state, player)
      pawns = state[:pawns][player]
      labels = []
      base_pawns = pawns.each_index.select { |pawn| pawns[pawn] < 0 }.map { |pawn| pawn + 1 }
      labels << _("In base: %{count}") % { count: base_pawns.length } if !base_pawns.empty?
      pawns.each_with_index do |progress, pawn|
        next if progress < 0 || progress == FINISH_PROGRESS

        labels << progress_label(player, progress)
      end
      finished = pawns.count { |progress| progress == FINISH_PROGRESS }
      if finished > 0
        labels << _("At the finish: %{count} of %{total} pawns") % { count: finished, total: PAWNS_PER_PLAYER }
      end
      labels
    end

    def own_pawn_browse_choices(state, viewer)
      player = player_index(state[:players], viewer)
      labels = if player == nil
        [_("You are not a player in this game.")]
      else
        state[:pawns][player].each_with_index.map do |progress, pawn|
          _("%{player}, %{position}") % {
            player: display_player(state, state[:players][player]),
            position: progress_label(player, progress)
          }
        end
      end
      shortcut_choices(labels)
    end

    def all_pawn_browse_choices(state)
      rows = state[:players].each_index.flat_map do |player|
        state[:pawns][player].each_with_index.map do |progress, pawn|
          [player, pawn, progress]
        end
      end
      # Shared field numbers expose neighbours across owners. Private home
      # lanes, bases and finished pawns follow the common track, without loss.
      rows.sort_by! do |player, pawn, progress|
        if progress.between?(0, OUTER_LENGTH - 1)
          [0, global_track_index(player, progress), player, pawn]
        else
          zone = progress < 0 ? 2 : progress == FINISH_PROGRESS ? 3 : 1
          [zone, player, progress, pawn]
        end
      end
      labels = rows.map do |player, pawn, progress|
        _("%{player}, %{position}") % {
          position: progress_label(player, progress),
          player: display_player(state, state[:players][player])
        }
      end
      shortcut_choices(labels)
    end

    def shortcut_choices(labels)
      labels.each_with_index.map do |label, index|
        ShortcutChoice.new(value: index, label: label)
      end
    end

    def pawn_positions_text(state, viewer)
      player = player_index(state[:players], viewer)
      return _("You are not a player in this game.") if player == nil

      _("%{player}: %{positions}.") % { player: display_player(state, viewer), positions: pawn_status_labels(state, player).join("; ") }
    end

    def opponents_pawn_positions_text(state, viewer)
      viewer_index = player_index(state[:players], viewer)
      positions = state[:players].each_index.filter_map do |player|
        next if player == viewer_index

        _("%{player}: %{positions}") % {
          player: display_player(state, state[:players][player]),
          positions: pawn_status_labels(state, player).join("; ")
        }
      end
      positions.join("; ")
    end

    def initial_state(players, options)
      {
        players: players, options: options, current_player: players[0], phase: :awaiting_roll, roll: nil, last_roll: nil,
        consecutive_sixes: 0, pawns: Array.new(players.length) { Array.new(PAWNS_PER_PLAYER, -1) }, winner: nil
      }
    end

    def apply_roll!(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_roll
      value = event["value"].to_i
      return false if !value.between?(1, 6)

      state[:roll] = value
      state[:last_roll] = value
      state[:last_roll_player] = actor
      state[:consecutive_sixes] = value == 6 ? state[:consecutive_sixes] + 1 : 0
      event_id = repository.event_id(event)
      player = player_index(state[:players], actor)
      history << HistoryEntry.new(
        key: "roll:#{event_id}", text: _("%{player} rolled %{value}.") % { player: participant_name(actor), value: value },
        event_id: event_id, actor: actor, kind: :roll, value: {ludo_seat: player, roll: value}.freeze
      )
      if state[:options]["three_sixes"] && state[:consecutive_sixes] >= 3
        history << HistoryEntry.new(
          key: "three_sixes:#{event_id}", text: _("Three consecutive sixes; %{player}'s turn ends.") % { player: participant_name(actor) },
          event_id: event_id, actor: actor, kind: :turn_end, value: {ludo_seat: player}.freeze
        )
        advance_turn!(state, actor)
        return true
      end

      choices = legal_pawn_indices(state, player)
      if choices.empty?
        history << HistoryEntry.new(
          key: "no_move:#{event_id}", text: _("%{player} has no legal pawn move.") % { player: participant_name(actor) },
          event_id: event_id, actor: actor, kind: :pass, value: {ludo_seat: player}.freeze
        )
        if value == 6 && state[:options]["extra_on_six"]
          state[:phase] = :awaiting_roll
          state[:roll] = nil
        else
          advance_turn!(state, actor)
        end
      elsif choices.length == 1
        state[:phase] = :moving
        apply_pawn_move_index!(state, actor, player, choices.first, event_id, history)
      else
        state[:phase] = :moving
      end
      true
    end

    def apply_pawn_move!(state, event, actor, repository, history)
      return false if state[:phase] != :moving
      player = player_index(state[:players], actor)
      pawn = Integer(event["value"].to_s, 10)
      return false if !legal_pawn_indices(state, player).include?(pawn)

      apply_pawn_move_index!(state, actor, player, pawn, repository.event_id(event), history)
      true
    rescue ArgumentError
      false
    end

    def apply_legacy_pawn_move!(state, event, actor, repository, history)
      pawn_field = event["value"].to_s.split(";").find { |field| field.start_with?("pawn=") }
      return false if pawn_field == nil

      legacy_event = event.merge("value" => pawn_field.split("=", 2)[1])
      apply_pawn_move!(state, legacy_event, actor, repository, history)
    end

    def apply_pawn_move_index!(state, actor, player, pawn, event_id, history)
      previous = state[:pawns][player][pawn]
      destination = destination_progress(state, player, pawn)
      captured = capture_targets(state, player, destination)
      state[:pawns][player][pawn] = destination
      captured.each { |other, index| state[:pawns][other][index] = -1 }
      text = _("%{player} moved pawn %{pawn} from %{from} to %{to}.") % {
        player: participant_name(actor), pawn: pawn + 1,
        from: progress_label(player, previous), to: progress_label(player, destination)
      }
      history << HistoryEntry.new(
        key: "move:#{event_id}", text: text, event_id: event_id, actor: actor,
        kind: :move, field: progress_label(player, destination),
        value: {ludo_seat: player, from: previous, to: destination}.freeze
      )
      captured.each_with_index do |(other, captured_pawn), index|
        history << HistoryEntry.new(
          key: "capture:#{event_id}:#{other}:#{captured_pawn}",
          text: _("%{player} sent pawn %{pawn} belonging to %{opponent} back to the base.") % {
            player: participant_name(actor),
            pawn: captured_pawn + 1,
            opponent: participant_name(state[:players][other])
          },
          event_id: event_id, actor: actor, kind: :capture,
          value: {ludo_seat: player, opponent: state[:players][other], opponent_seat: other,
            to: destination, index: index + 1, count: captured.length}.freeze
        )
      end
      if state[:pawns][player].all? { |progress| progress == FINISH_PROGRESS }
        state[:winner] = actor
        state[:current_player] = nil
        state[:phase] = :finished
        result = result_history(event_id: event_id, winner: actor)
        result.value = {ludo_seat: player}.freeze
        history << result
      elsif state[:roll] == 6 && state[:options]["extra_on_six"]
        state[:phase] = :awaiting_roll
        state[:roll] = nil
      else
        advance_turn!(state, actor)
      end
    end

    def legal_pawn_indices(state, player)
      return [] if player == nil || state[:roll] == nil
      roll = state[:roll].to_i
      state[:pawns][player].each_index.filter_map do |pawn|
        current = state[:pawns][player][pawn]
        next if current == FINISH_PROGRESS

        destination = if current < 0
          next if state[:options]["enter_on_six"] && roll != 6 && !(roll == 1 && state[:options]["enter_on_one"])
          0
        else
          current + roll
        end
        if destination > FINISH_PROGRESS
          next if state[:options]["exact_finish"]
          destination = FINISH_PROGRESS
        end
        next if blocked_path?(state, player, current, destination)

        pawn
      end
    end

    def destination_progress(state, player, pawn)
      current = state[:pawns][player][pawn]
      current < 0 ? 0 : [current + state[:roll].to_i, FINISH_PROGRESS].min
    end

    def blocked_path?(state, player, current, destination)
      return false if !state[:options]["blockades"] || current < 0
      ((current + 1)..destination).any? do |progress|
        next false if progress >= OUTER_LENGTH
        global = global_track_index(player, progress)
        state[:pawns].each_with_index.any? do |pawns, other|
          other != player && pawns.count { |value| value.between?(0, OUTER_LENGTH - 1) && global_track_index(other, value) == global } >= 2
        end
      end
    end

    def capture_targets(state, player, progress)
      return [] if progress < 0 || progress >= OUTER_LENGTH
      global = global_track_index(player, progress)
      return [] if SAFE_TRACK_INDICES.include?(global)
      result = []
      state[:pawns].each_with_index do |pawns, other|
        next if other == player
        pawns.each_with_index do |candidate, index|
          result << [other, index] if candidate.between?(0, OUTER_LENGTH - 1) && global_track_index(other, candidate) == global
        end
      end
      result
    end

    def exposure_risk(state, player, progress)
      return 0 if progress < 0 || progress >= OUTER_LENGTH || safe_progress?(player, progress)
      global = global_track_index(player, progress)
      key = [player, state[:pawns], state[:options]].inspect
      @ludo_threats ||= {}
      unless @ludo_threats.key?(key)
        @ludo_threats.clear if @ludo_threats.length >= 64
        threats = Hash.new(0)
        state[:pawns].each_index do |other|
          next if other == player
          (1..6).each do |roll|
            possible = state.merge(roll: roll)
            destinations = legal_pawn_indices(possible, other).filter_map do |pawn|
              destination = destination_progress(possible, other, pawn)
              global_track_index(other, destination) if destination < OUTER_LENGTH
            end
            destinations.uniq.each { |field| threats[field] += 1 }
          end
        end
        @ludo_threats[key] = threats
      end
      @ludo_threats[key][global]
    end

    def safe_progress?(player, progress)
      progress >= OUTER_LENGTH || SAFE_TRACK_INDICES.include?(global_track_index(player, progress))
    end

    def advance_turn!(state, actor)
      index = player_index(state[:players], actor)
      state[:current_player] = state[:players][(index + 1) % state[:players].length]
      state[:phase] = :awaiting_roll
      state[:roll] = nil
      state[:consecutive_sixes] = 0
    end

    def board_snapshot(state)
      state[:pawns].map(&:dup)
    end

    def progress_label(player, progress)
      return _("base") if progress < 0
      return _("finish") if progress == FINISH_PROGRESS
      if progress >= OUTER_LENGTH
        return _("home lane %{position} of %{total}") % {
          position: progress - OUTER_LENGTH + 1,
          total: HOME_LANE_LENGTH
        }
      end

      _("track %{position}") % { position: global_track_index(player, progress) + 1 }
    end

    def global_track_index(player, progress)
      (ENTRY_INDICES[player] + progress) % OUTER_LENGTH
    end
  end
end

require_relative 'generated/rulebooks/ludo'
