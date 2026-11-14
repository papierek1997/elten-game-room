require_relative "base"
require_relative "backgammon_support/backgammon_rules"
require_relative "../lib/server_random"
require_relative "../lib/game_bots"
require_relative "../lib/game_replay_cache"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Backgammon < Base
    include PublicHistoryAnnouncements
    GameRoomServerRandom.register("backgammon", %w[opening roll])

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return 'roll' if %w[opening roll].include?(event['action'])
      return {'double' => 'poker_raise', 'take' => 'poker_call', 'drop' => 'poker_fold'}[event['action']] if %w[double take drop].include?(event['action'])
      return unless event["action"] == "move"

      history.find { |entry| entry.kind == :move }&.value
    end

    def id; "backgammon"; end
    def name; _("Backgammon"); end
    def short_description; _("Move your checkers home and bear them all off before your opponent."); end
    def notification_option_keys(options)
      ['variant', *(options['score_limit'].to_i.positive? ? ['score_limit'] : []), *(options['doubling_cube'] ? ['doubling_cube'] : [])]
    end
    def notification_variant(options)
      [notification_choice(options, 'variant'), notification_points(options, 'score_limit'),
        (options['doubling_cube'] == true ? _("Doubling cube") : nil)].compact.join(', ')
    end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def tournament_capabilities(options: {}); super.merge(player_counts: [].freeze).freeze; end

    def rule_sections; generated_rule_sections; end

    def option_definitions
      [OptionDefinition.new(key: "variant", label: _("Variant"), kind: :choice, default: "classic", choices: [
        OptionChoice.new(value: "classic", label: p_("Backgammon variant", "Classic")),
        OptionChoice.new(value: "nack", label: _("Nackgammon")),
        OptionChoice.new(value: "hyper", label: _("Hypergammon")),
        OptionChoice.new(value: "long", label: _("LongGammon")),
        OptionChoice.new(value: "egyptian", label: _("Egyptian rule"))
      ]),
        OptionDefinition.new(key: "score_limit", label: _("Match score limit (0 for one game)"), kind: :integer, default: 0),
        OptionDefinition.new(key: "doubling_cube", label: _("Doubling cube"), kind: :boolean, default: false)]
    end

    def options_error(options, player_count: nil)
      limit = normalize_options(options)["score_limit"]
      _("Enter a non-negative match score limit.") unless limit.is_a?(Integer) && limit >= 0
    end

    def replay(session, events, repository)
      input = GameRoomReplayCache::Input.new(session, events, repository)
      players = input.players
      options = options_from_json(session["options"])
      variant = options["variant"]
      @backgammon_cache ||= GameRoomReplayCache.new
      state, accepted, history = @backgammon_cache.reduce(input, context: options) do |checkpoint, prefix|
        state, accepted, history = checkpoint || [initial_game_state(options), [], [starting_history(players)]]
        seen = state[:seen]
        input.events.drop(prefix).each_with_index do |event, offset|
          break if state[:winner]
          key = input.event_id(event)
          actor = players[state[:turn]]
          next if seen[key] || !same_user?(actor, input.actor_of(event))
          phase = state[:phase]
          action = event["action"]
          if action == "double" && can_double?(state) && event["value"] == ""
            history << HistoryEntry.new(key: "cube:#{key}", event_id: key, actor: actor, kind: :notice,
              text: _("%{player} offers to double the stake to %{stake}.") % {player: participant_name(actor), stake: state[:cube] * 2})
            state[:phase], state[:turn] = :cube_reply, 1 - state[:turn]
          elsif phase == :cube_reply && %w[take drop].include?(action) && event["value"] == ""
            responder = state[:turn]
            state[:turn] = 1 - responder
            if action == "take"
              history << HistoryEntry.new(key: "cube:#{key}", event_id: key, actor: actor, kind: :notice,
                text: _("%{player} accepts the double.") % {player: participant_name(actor)})
              state[:cube] *= 2
              state[:cube_owner] = responder
              state[:phase] = :roll
            else
              history << HistoryEntry.new(key: "cube:#{key}", event_id: key, actor: actor, kind: :notice,
                text: _("%{player} declines the double.") % {player: participant_name(actor)})
              settle_game(state, players, variant, state[:cube], history, key)
            end
          elsif (phase == :opening && event["action"] == "opening") || (phase == :roll && event["action"] == "roll")
            next unless event["value"].to_s.match?(/\A[1-6],[1-6]\z/)
            if event["__server_random"]
              next unless GameRoomServerRandom.valid_dice_event?(event, count: 2, sides: 6)
            end
            dice = event["value"].split(",").map(&:to_i)
            if phase == :opening
              state[:turn] = dice[0] > dice[1] ? 0 : 1 unless dice.uniq.one?
            end
            history << HistoryEntry.new(key: "roll:#{key}", event_id: key, actor: actor, kind: :roll,
              text: roll_history_text(phase, players, dice, actor, state[:turn]))
            unless phase == :opening && dice.uniq.one?
              state[:dice] = dice.uniq.one? ? dice * 2 : dice
              advance(state)
            end
          elsif phase == :move && event["action"] == "move"
            move = choices(state).find { |candidate| candidate.join(",") == event["value"] }
            next unless move
            destination = move[1]
            hit = destination.positive? && state[:board][1 - state[:turn]].fetch(25 - destination, 0) == 1
            state[:board] = BackgammonRules.apply(state[:board], state[:turn], move)
            state[:dice].delete_at(state[:dice].index(move.last))
            history << HistoryEntry.new(key: "move:#{key}", event_id: key, actor: actor, kind: :move,
              value: hit ? "play2" : (destination.zero? ? "domino_take_chip" : 'play'),
              text: _("%{player}: %{move}.") % {player: participant_name(actor), move: move_label(move)} + (hit ? ' ' + _("The opponent's checker goes to the bar.") : ''))
            if state[:board][state[:turn]].fetch(0, 0) == state[:checker_count]
              settle_game(state, players, variant, BackgammonRules.stake(state[:board], state[:turn]) * state[:cube], history, key)
            else
              advance(state)
            end
          else
            next
          end
          seen[key] = true
          accepted << prefix + offset
        end
        [state, accepted, history]
      end
      Replay.new(players: players, board: state[:board], current_player: state[:winner] ? nil : players[state[:turn]],
        winner: state[:winner], draw: false, state: state, accepted_events: accepted.map { |position| input.events.fetch(position) }, history: history)
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      state = replay.state
      if state[:phase] == :cube_reply
        return %w[take drop].map { |action| {"kind" => "command", "action" => action} }
      end
      unless state[:phase] == :move
        actions = [{"kind" => "dice", "action" => state[:phase].to_s}]
        actions << {"kind" => "command", "action" => "double"} if can_double?(state)
        return actions
      end
      choices(state).map { |move| {"kind" => "pawn", "action" => "move", "move" => move.join(",")} }
    end

    def action_for(selection, replay, actor, context: nil)
      action = legal_actions(replay, actor).find do |candidate|
        candidate["action"] == selection["action"] && candidate["move"] == selection["move"]
      end
      return [:invalid, nil] unless action
      name = action["action"]
      return [:ok, event_plan(name, action["move"])] if name == "move"
      return [:ok, event_plan(name, "")] if action["kind"] == "command"
      return [:invalid, nil] unless context&.random_source
      if context.server_random
        command = GameRoomServerRandom.command(action: name, count: 2, sides: 6)
        [:ok, ActionPlan.new(events: [command])]
      else
        [:ok, event_plan(name, context.random_source.roll(count: 2, sides: 6).values.join(","))]
      end
    end

    def surface_spec(replay, viewer)
      actions = legal_actions(replay, viewer)
      if replay.state[:phase] == :move && !actions.empty?
        return board_grid(replay, viewer, point_moves: choices(replay.state))
      end
      if actions.any? { |action| action["kind"] == "command" }
        labels = {"roll" => _("Roll the dice"), "double" => _("Offer a double"),
          "take" => _("Accept the double"), "drop" => _("Decline and concede this game")}
        items = actions.map do |action|
          name = action.fetch("action")
          GameSurfaces::PawnTrackItem.new(id: name, label: labels.fetch(name),
            action: GameSurfaces::Action.new(kind: action.fetch("kind"), name: name, source: id))
        end
        stake = replay.state[:cube]
        header = replay.state[:phase] == :cube_reply ? _("Double the stake from %{from} to %{to}.") % {from: stake, to: stake * 2} : _("Stake: %{stake}.") % {stake: stake}
        return GameSurfaces::PawnTrackSpec.new(id: id, header: header, items: items)
      end
      items = []
      if items.empty?
        label = replay.finished? ? result_text(replay) : actions.empty? ? current_turn_shortcut_text(replay, viewer) : _("Roll the dice")
        items << GameSurfaces::PawnTrackItem.new(id: "status", label: label)
      end
      activation = actions.first
      activation = if activation && !activation["move"]
        GameSurfaces::Action.new(kind: "dice", name: activation["action"], source: id)
      end
      GameSurfaces::PawnTrackSpec.new(id: id, header: name,
        items: items, activation_action: activation)
    end

    def board_grid(replay, viewer, point_moves: nil)
      side = replay.players.index { |player| same_user?(player, viewer) } || 0
      own, opponent = replay.board.values_at(side, 1 - side)
      names = replay.players.values_at(side, 1 - side).map { |player| GameRoomContent.utf8(participant_name(player)) }
      rows = [24.downto(13).to_a, (1..12).to_a].map do |points|
        points.map do |point|
          occupants = [own.fetch(point, 0), opponent.fetch(25 - point, 0)]
          pieces = occupants.each_with_index.filter_map { |count, index| "#{names[index]}, #{count}" if count.positive? }
          _("Point %{point}: %{pieces}") % {point: point, pieces: pieces.empty? ? _("empty") : pieces.join('. ')}
        end
      end
      bar = _("Bar. %{first}: %{one}. %{second}: %{two}.") % {first: names[0], one: own.fetch(25, 0), second: names[1], two: opponent.fetch(25, 0)}
      off = _("Borne off. %{first}: %{one}. %{second}: %{two}.") % {first: names[0], one: own.fetch(0, 0), second: names[1], two: opponent.fetch(0, 0)}
      rows[0].unshift(bar)
      rows[1].unshift(off)
      moves = point_moves&.group_by { |from, to, _die| [from, to] }&.values&.map do |alternatives|
        move = alternatives.max_by(&:last)
        GameSurfaces::GridMove.new(origin: board_cell(move[0]), destination: board_cell(move[1]),
          action: GameSurfaces::Action.new(kind: 'pawn', name: 'move', payload: {'move' => move.join(',')}))
      end
      GameSurfaces::GridSpec.new(width: 13, height: 2,
        header: _("Dice: %{dice}. Board.") % {dice: replay.state[:dice].join(', ')},
        cells: rows, row_origin: :top, hide_coordinates: true, move_actions: moves,
        selection_epoch: replay.accepted_events.length,
        forced_origin: point_moves&.any? { |from, _, _| from == 25 } ? board_cell(25) : nil,
        shortcuts: replay.state[:dice].empty? ? [] : [GameShortcut.new(key: "space", kind: :announcement,
          label: _("Read the dice"), message: replay.state[:dice].join(", "))])
    end

    def custom_game_shortcuts(replay, viewer)
      counts = [25, 0].map do |point|
        replay.players.zip(replay.board).map do |player, board|
          "#{GameRoomContent.utf8(participant_name(player))}, #{board.fetch(point, 0)}"
        end.join(". ")
      end
      [announcement_shortcut(key: "s", label: _("Read scores"), message: score_text(replay.players, replay.state)),
        announcement_shortcut(key: "b", label: _("Read the bar"), message: _("Bar: %{counts}.") % {counts: counts[0]}),
        announcement_shortcut(key: "z", label: _("Read borne-off checkers"), message: _("Borne off: %{counts}.") % {counts: counts[1]}),
        GameShortcut.new(key: "v", kind: :grid_preview, label: _("Inspect the board"), default_value: board_grid(replay, viewer)),
        announcement_shortcut(key: "d", label: _("Read the dice"), message: replay.state[:dice].empty? ?
          _("No dice remain to be played.") : replay.state[:dice].join(", "))]
    end

    def bot_action_score(replay, _actor, action, context: nil)
      probability = bot_winning_chance(replay.board, replay.state[:turn])
      case action['action']
      when 'double' then return probability > 0.67 ? 5 : -5
      when 'take' then return probability >= 0.25 ? 2 : -2
      when 'drop' then return probability < 0.25 ? 2 : -2
      end
      return 0 unless action["move"]
      from, to, die = action["move"].split(",").map(&:to_i)
      other = replay.board[1 - replay.state[:turn]]
      own = replay.board[replay.state[:turn]]
      rear = own.keys.max
      after = BackgammonRules.apply(replay.board, replay.state[:turn], [from, to, die])
      risk = bot_blot_risk(after, replay.state[:turn]) - bot_blot_risk(replay.board, replay.state[:turn])
      die + (to.zero? ? 30 : 0) + (from == rear ? 3 : 0) +
        (from == 25 ? 15 : 0) + (to.positive? && other.fetch(25 - to, 0) == 1 ? 12 : 0) +
        (to.positive? && own.fetch(to, 0) == 1 ? 8 : 0) - 12 * risk
    end

    def participant_scores(replay)
      replay.players.zip(replay.state[:scores]).to_h
    end

    private

    def initial_game_state(options)
      variant = options['variant']
      board = BackgammonRules.initial(variant)
      {board: board, point_limit: variant == 'egyptian' ? 5 : nil, checker_count: board.first.values.sum,
        turn: 0, phase: :opening, dice: [], winner: nil, points: 0, scores: [0, 0],
        target: options['score_limit'], doubling: options['doubling_cube'], cube: 1,
        cube_owner: nil, crawford: false, crawford_played: false, seen: {}}
    end

    def roll_history_text(phase, players, dice, actor, turn)
      return _("%{player} rolled %{dice}.") % {player: participant_name(actor), dice: dice.join(', ')} unless phase == :opening

      opening = players.zip(dice).map { |player, die| _("%{player} rolls %{die}.") % {player: participant_name(player), die: die} }
      opening << (dice.uniq.one? ? _("Tie. Roll again.") : _("%{player} starts.") % {player: participant_name(players[turn])})
      opening.join("\n")
    end

    def bot_winning_chance(board, side)
      pips = board.map { |pieces| pieces.sum { |point, count| point * count } }
      scale = [Math.sqrt(pips.sum) * 2, 10].max
      (0.5 + (pips[1 - side] - pips[side]) / (2.0 * scale)).clamp(0.01, 0.99)
    end

    def bot_blot_risk(board, side)
      own, other = board.values_at(side, 1 - side)
      own.sum do |point, count|
        next 0.0 unless point.between?(1, 24) && count == 1
        origins = other.fetch(25, 0).positive? ? [25] : other.keys.select(&:positive?)
        faces = origins.map { |origin| origin + point - 25 }.select { |distance| distance.between?(1, 6) }.uniq.length
        1.0 - ((6 - faces) / 6.0) ** 2
      end
    end

    def board_cell(point)
      return [0, 0] if point == 25
      return [0, 1] if point.zero?
      point >= 13 ? [25 - point, 0] : [point, 1]
    end

    def score_text(players, state)
      players.zip(state[:scores]).map { |player, points| "#{GameRoomContent.utf8(participant_name(player))}, #{points}" }.join(". ")
    end

    def can_double?(state)
      state[:phase] == :roll && state[:doubling] && !state[:crawford] && state[:cube] < 64 &&
        (state[:cube_owner].nil? || state[:cube_owner] == state[:turn])
    end

    def settle_game(state, players, variant, points, history, event_id)
      winner = state[:turn]
      state[:scores][winner] += points
      state[:points] = points
      actor = players[winner]
      message = n_("%{player} wins this game for %{points} point.", "%{player} wins this game for %{points} points.", points) % {player: participant_name(actor), points: points}
      message += "\n" + score_text(players, state) + '.'
      if state[:target].zero? || state[:scores][winner] >= state[:target]
        state[:winner] = actor
      else
        state[:crawford_played] ||= state[:crawford]
        state[:crawford] = state[:doubling] && !state[:crawford_played] && state[:scores].include?(state[:target] - 1)
        state.merge!(board: BackgammonRules.initial(variant), turn: 0, phase: :opening, dice: [], cube: 1, cube_owner: nil)
        message += "\n" + _("Crawford game. Doubling is disabled.") if state[:crawford]
      end
      history << HistoryEntry.new(key: "game:#{event_id}", event_id: event_id, actor: actor, kind: :notice, text: message)
    end

    def choices(state)
      BackgammonRules.legal(state[:board], state[:turn], state[:dice], point_limit: state[:point_limit])
    end

    def advance(state)
      if choices(state).empty?
        state[:turn] = 1 - state[:turn]
        state[:dice] = []
        state[:phase] = :roll
      else
        state[:phase] = :move
      end
    end

    def point_label(point)
      return _("bar") if point == 25
      return _("borne off") if point.zero?
      _("point %{point}") % {point: point}
    end

    def move_label(move)
      from, to, die = move
      _("%{from} to %{to}, die %{die}") % {from: point_label(from), to: point_label(to), die: die}
    end
  end
end

require_relative 'generated/rulebooks/backgammon'
