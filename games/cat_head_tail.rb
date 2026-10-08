require_relative "base"
require_relative "../lib/cat_head_tail_strategy"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class CatHeadTail < Base
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      entries = history
      if action == "bank"
        return "cht-bank" if entries.any? { |entry| entry.kind == :bank }
        return nil
      end
      return nil if action != "roll"

      cues = ["cht-roll-dice"]
      cues << "cht-lost-points" if entries.any? { |entry| entry.kind == :lost_points }
      cues << "cht-cat-minus-8" if entries.any? { |entry| entry.kind == :cat_minus }
      cues << "cht-cat-plus-8" if entries.any? { |entry| entry.kind == :cat_plus }
      cues
    end

    def id
      "cat_head_tail"
    end

    def notification_option_keys(_options); %w[score_limit]; end
    def notification_variant(options)
      value = options["score_limit"]
      value.is_a?(Integer) && value.positive? ? (_("Score limit: %{points}") % {points: value}) : ""
    end

    def name
      "Cat, head, tail"
    end

    def short_description
      _("Roll the die and decide when to bank your points before an unlucky one wipes out your turn's score.")
    end

    def rule_sections
      generated_rule_sections
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
      @bot_strategy ||= CatHeadTailPlanning::Strategy.new
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "score_limit",
          label: _("Score limit"),
          kind: :integer,
          default: 100
        )
      ]
    end

    def options_error(options, player_count: nil)
      return _("The score limit must be greater than zero.") if normalize_options(options)["score_limit"].to_i <= 0

      nil
    end

    def options_summary(options)
      _("to %{limit} points") % { limit: normalize_options(options)["score_limit"] }
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

      [
        { "kind" => "dice", "action" => "roll" },
        { "kind" => "dice", "action" => "bank" }
      ]
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
        return [:invalid, nil] if context == nil || context.random_source == nil

        roll = context.random_source.roll(count: 1, sides: 8).values.first.to_i
        value = if roll == 8
          tail = context.random_source.roll(count: 1, sides: 2).values.first.to_i == 1 ? "minus" : "plus"
          "8|#{tail}"
        else
          roll.to_s
        end
        [:ok, event_plan("roll", value)]
      when "bank"
        [:ok, event_plan("bank", "")]
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if replay.finished? || !same_user?(state[:current_player], viewer)
        label = replay.finished? ? result_text(replay) : current_turn_shortcut_text(replay, viewer)
        return action_surface([], label)
      end

      action_surface([
        GameSurfaces::Card.new(id: "roll", label: _("Roll"), value: "roll"),
        GameSurfaces::Card.new(
          id: "bank",
          label: _("Bank %{points} points") % { points: state[:turn_points] },
          value: "bank"
        )
      ], _("Actions. Use the arrow keys and press Enter"))
    end

    def participant_scores(replay)
      replay.state[:scores].dup
    end

    def shortcut_features
      super + [:scores, :current_total, :last_roll]
    end

    def shortcut_feature_data(feature, replay, viewer)
      case feature.to_sym
      when :scores
        { message: scores_text(replay.state) }
      when :current_total
        { message: _("Current turn: %{points} points.") % { points: replay.state[:turn_points] } }
      when :last_roll
        { message: last_roll_text(replay.state) }
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id.to_i }
      entries.empty? ? nil : entries.map(&:text)
    end

    private

    # The author's original catalogue is scoped to this game. In particular,
    # its Roll and Bank translations must not overwrite those used by Farkle.
    # Use the shared dictionary for texts added by the Game Room framework.
    def _(source)
      GameRoomLocalization.translate(source, context: "cat_head_tail", fallback_to_common: true)
    end

    def initial_state(players, options)
      {
        players: players,
        options: options,
        scores: players.each_with_object({}) { |player, result| result[player] = 0 },
        phase: :playing,
        current_player: players.first,
        turn_points: 0,
        last_roll: nil,
        last_roll_player: nil,
        last_tail: nil,
        final_round: false,
        winner: nil,
        draw: false
      }
    end

    def apply_roll(state, event, actor, repository, history)
      return false if state[:phase] != :playing
      return false if !same_user?(state[:current_player], actor)

      roll, tail = parse_roll(event["value"])
      return false if roll == nil

      event_id = repository.event_id(event)
      player = player_key(state, actor)
      state[:last_roll] = roll
      state[:last_roll_player] = player
      state[:last_tail] = tail
      case roll
      when 1
        previous = state[:turn_points]
        state[:turn_points] = 0
        text = if previous < 0
          _("%{player} rolled 1. The negative turn total was cleared and the turn ends.") % { player: participant_name(player) }
        else
          _("%{player} rolled 1 and lost %{points} points from this turn.") % {
            player: participant_name(player), points: previous
          }
        end
        history << roll_history(event_id, player, :lost_points, text, roll)
        finish_turn(state, player, event_id, history)
      when 2
        state[:scores][player] += 2
        history << roll_history(
          event_id,
          player,
          :automatic_bank,
          _("%{player} rolled 2. Two points were added directly to the bank.") % {
            player: participant_name(player)
          },
          roll
        )
      when 3, 4, 5, 6
        state[:turn_points] += roll
        history << roll_history(
          event_id,
          player,
          :roll,
          _("%{player} rolled %{roll} and now has %{points} points in this turn.") % {
            player: participant_name(player), roll: roll, points: state[:turn_points]
          },
          roll
        )
      when 7
        history << roll_history(
          event_id,
          player,
          :cat_head,
          _("%{player} rolled 7, the cat's head. Nothing happened.") % { player: participant_name(player) },
          roll
        )
      when 8
        change = tail == "plus" ? 8 : -8
        state[:turn_points] += change
        kind = change.positive? ? :cat_plus : :cat_minus
        text = if change.positive?
          _("%{player} rolled 8, the cat's tail, and gained 8 points.") % {
            player: participant_name(player)
          }
        else
          _("%{player} rolled 8, the cat's tail, and lost 8 points.") % {
            player: participant_name(player)
          }
        end
        history << roll_history(event_id, player, kind, text, tail)
      end
      true
    end

    def apply_bank(state, event, actor, repository, history)
      return false if state[:phase] != :playing
      return false if !same_user?(state[:current_player], actor)

      player = player_key(state, actor)
      points = state[:turn_points]
      state[:scores][player] += points
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "bank:#{event_id}",
        text: _("%{player} banked %{points} points and now has %{total}.") % {
          player: participant_name(player), points: points, total: state[:scores][player]
        },
        event_id: event_id,
        actor: player,
        kind: :bank,
        value: points
      )
      finish_turn(state, player, event_id, history)
      true
    end

    def finish_turn(state, actor, event_id, history)
      state[:turn_points] = 0
      next_actor = next_player(state[:players], actor)
      if !state[:final_round] && state[:scores].fetch(actor, 0).to_i >= state[:options]["score_limit"].to_i
        state[:final_round] = true
        if !same_user?(next_actor, state[:players].first)
          history << HistoryEntry.new(
            key: "final_round:#{event_id}",
            text: _("%{player} reached the score limit. Finish the current round of turns.") % {
              player: participant_name(actor)
            },
            event_id: event_id,
            actor: actor,
            kind: :game
          )
        end
      end
      if state[:final_round] && same_user?(next_actor, state[:players].first)
        winners = state[:players].select { |player| state[:scores][player] == state[:scores].values.max }
        state[:winner] = winners.first if winners.length == 1
        state[:draw] = winners.length > 1
        state[:phase] = :finished
        state[:current_player] = nil
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
      else
        state[:current_player] = next_actor
      end
    end

    def parse_roll(value)
      parts = value.to_s.split("|", -1)
      roll = Integer(parts[0], 10)
      return [nil, nil] if !roll.between?(1, 8)
      if roll == 8
        return [nil, nil] if parts.length != 2 || !["minus", "plus"].include?(parts[1])
        return [roll, parts[1]]
      end
      return [nil, nil] if parts.length != 1

      [roll, nil]
    rescue ArgumentError
      [nil, nil]
    end

    def roll_history(event_id, player, kind, text, value)
      HistoryEntry.new(
        key: "roll:#{event_id}",
        text: text,
        event_id: event_id,
        actor: player,
        kind: kind,
        value: value
      )
    end

    def action_surface(cards, label)
      GameSurfaces::CardTableSpec.new(
        zones: [
          GameSurfaces::CardZoneSpec.new(
            id: "actions",
            header: label,
            cards: cards,
            empty_label: label
          )
        ]
      )
    end

    def scores_text(state)
      players = score_announcement_order(state[:players], state[:scores])
      values = players.map do |player|
        _("%{player}: %{score}") % {
          player: participant_name(player),
          score: state[:scores].fetch(player, 0)
        }
      end
      _("Scores: %{scores}.") % { scores: values.join("; ") }
    end

    def last_roll_text(state)
      return _("The dice have not been rolled.") if state[:last_roll] == nil

      player = participant_name(state[:last_roll_player])
      if state[:last_roll] == 8
        _("%{player}, %{dice}, %{points} points.") % {
          player: player, dice: 8, points: state[:last_tail] == "plus" ? "+8" : "-8"
        }
      else
        _("%{player}, %{dice}.") % { player: player, dice: state[:last_roll] }
      end
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def next_player(players, actor)
      index = players.index { |player| same_user?(player, actor) }
      index == nil ? nil : players[(index + 1) % players.length]
    end
  end
end

require_relative 'generated/rulebooks/cat_head_tail'
