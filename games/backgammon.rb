require_relative "base"
require_relative "backgammon_support/backgammon_rules"
require_relative "../lib/server_random"
require_relative "../lib/game_bots"

module GameRoomGames
  class Backgammon < Base
    include PublicHistoryAnnouncements
    GameRoomServerRandom.register("backgammon", %w[opening roll])

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return unless event["action"] == "move"

      history.find { |entry| entry.kind == :move }&.value
    end

    def id; "backgammon"; end
    def name; "Tryktrak"; end
    def short_description; "Przeprowad\u017a wszystkie pionki do domu i zdejmij je przed przeciwnikiem."; end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def tournament_capabilities(options: {}); super.merge(player_counts: [].freeze).freeze; end

    def rule_sections; generated_rule_sections; end

    def option_definitions
      [OptionDefinition.new(key: "variant", label: "Wariant", kind: :choice, default: "classic", choices: [
        OptionChoice.new(value: "classic", label: "Klasyczny"),
        OptionChoice.new(value: "nack", label: "Nackgammon"),
        OptionChoice.new(value: "hyper", label: "Hypergammon"),
        OptionChoice.new(value: "long", label: "LongGammon"),
        OptionChoice.new(value: "egyptian", label: "Regu\u0142a egipska")
      ]),
        OptionDefinition.new(key: "score_limit", label: "Cel punktowy (0 = jedna partia)", kind: :integer, default: 0),
        OptionDefinition.new(key: "doubling_cube", label: "Kostka dubluj\u0105ca", kind: :boolean, default: false)]
    end

    def options_error(options, player_count: nil)
      limit = normalize_options(options)["score_limit"]
      "Podaj nieujemny cel punktowy." unless limit.is_a?(Integer) && limit >= 0
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      variant = options["variant"]
      board = BackgammonRules.initial(variant)
      state = {board: board, point_limit: variant == "egyptian" ? 5 : nil, checker_count: board.first.values.sum, turn: 0, phase: :opening, dice: [], winner: nil, points: 0,
        scores: [0, 0], target: options["score_limit"], doubling: options["doubling_cube"],
        cube: 1, cube_owner: nil, crawford: false, crawford_played: false}
      history, accepted, seen = [starting_history(players)], [], {}
      events.each do |event|
        break if state[:winner]
        key = repository.event_id(event)
        actor = players[state[:turn]]
        next if seen[key] || !same_user?(actor, repository.actor_of(event, session))
        phase = state[:phase]
        action = event["action"]
        if action == "double" && can_double?(state) && event["value"] == ""
          state[:phase], state[:turn] = :cube_reply, 1 - state[:turn]
        elsif phase == :cube_reply && %w[take drop].include?(action) && event["value"] == ""
          responder = state[:turn]
          state[:turn] = 1 - responder
          if action == "take"
            state[:cube] *= 2
            state[:cube_owner] = responder
            state[:phase] = :roll
          else
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
          roll_text = if phase == :opening
            opening = players.zip(dice).map { |player, die| "#{GameRoomContent.utf8(participant_name(player))} wyrzuca #{die}." }
            opening << (dice.uniq.one? ? "Remis. Powt\u00f3rzcie rzut." : "Zaczyna #{GameRoomContent.utf8(participant_name(players[state[:turn]]))}.")
            opening.join(" ")
          else
            "#{GameRoomContent.utf8(participant_name(actor))} wyrzuca #{dice.join(", ")}."
          end
          history << HistoryEntry.new(key: "roll:#{key}", event_id: key, actor: actor, kind: :roll,
            text: roll_text)
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
            value: hit ? "play2" : (destination.zero? ? "domino_take_chip" : nil),
            text: "#{GameRoomContent.utf8(participant_name(actor))}. #{move_label(move)}.#{hit ? " Zbija pionek przeciwnika." : ""}")
          if state[:board][state[:turn]].fetch(0, 0) == state[:checker_count]
            settle_game(state, players, variant, BackgammonRules.stake(state[:board], state[:turn]) * state[:cube], history, key)
          else
            advance(state)
          end
        else
          next
        end
        seen[key] = true
        accepted << event
      end
      Replay.new(players: players, board: state[:board], current_player: state[:winner] ? nil : players[state[:turn]],
        winner: state[:winner], draw: false, state: state, accepted_events: accepted, history: history)
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
        labels = {"roll" => "Rzu\u0107 ko\u015b\u0107mi", "double" => "Zaproponuj podwojenie",
          "take" => "Przyjmij podwojenie", "drop" => "Odrzu\u0107 i oddaj parti\u0119"}
        items = actions.map do |action|
          name = action.fetch("action")
          GameSurfaces::PawnTrackItem.new(id: name, label: labels.fetch(name),
            action: GameSurfaces::Action.new(kind: action.fetch("kind"), name: name, source: id))
        end
        stake = replay.state[:cube]
        header = replay.state[:phase] == :cube_reply ? "Podwojenie z #{stake} do #{stake * 2}." : "Stawka #{stake}."
        return GameSurfaces::PawnTrackSpec.new(id: id, header: header, items: items)
      end
      items = []
      if items.empty?
        label = replay.finished? ? result_text(replay) : actions.empty? ? current_turn_shortcut_text(replay, viewer) : "Rzu\u0107 ko\u015b\u0107mi"
        items << GameSurfaces::PawnTrackItem.new(id: "status", label: label)
      end
      activation = actions.first
      activation = if activation && !activation["move"]
        GameSurfaces::Action.new(kind: "dice", name: activation["action"], source: id)
      end
      GameSurfaces::PawnTrackSpec.new(id: id, header: "#{name}. Ko\u015bci: #{replay.state[:dice].join(', ')}",
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
          "Pole #{point}, #{pieces.empty? ? 'puste' : pieces.join('. ')}"
        end
      end
      rows[0].unshift("Banda. #{names[0]}, #{own.fetch(25, 0)}. #{names[1]}, #{opponent.fetch(25, 0)}.")
      rows[1].unshift("Zdj\u0119te pionki. #{names[0]}, #{own.fetch(0, 0)}. #{names[1]}, #{opponent.fetch(0, 0)}.")
      GameSurfaces::GridSpec.new(width: 13, height: 2,
        header: "Ko\u015bci: #{replay.state[:dice].join(", ")}. Plansza. Banda. #{names[0]}, #{own.fetch(25, 0)}. #{names[1]}, #{opponent.fetch(25, 0)}. " \
          "Zdj\u0119te pionki. #{names[0]}, #{own.fetch(0, 0)}. #{names[1]}, #{opponent.fetch(0, 0)}.",
        cells: rows, row_origin: :top, hide_coordinates: true, point_moves: point_moves,
        shortcuts: replay.state[:dice].empty? ? [] : [GameShortcut.new(key: "space", kind: :announcement,
          label: "Odczytaj ko\u015bci", message: replay.state[:dice].join(", "))])
    end

    def custom_game_shortcuts(replay, viewer)
      counts = [25, 0].map do |point|
        replay.players.zip(replay.board).map do |player, board|
          "#{GameRoomContent.utf8(participant_name(player))}, #{board.fetch(point, 0)}"
        end.join(". ")
      end
      [announcement_shortcut(key: "s", label: "Odczytaj wynik", message: score_text(replay.players, replay.state)),
        announcement_shortcut(key: "b", label: "Odczytaj band\u0119", message: "Banda. #{counts[0]}."),
        announcement_shortcut(key: "z", label: "Odczytaj zdj\u0119te pionki", message: "Zdj\u0119te pionki. #{counts[1]}."),
        GameShortcut.new(key: "v", kind: :grid_preview, label: "Przejrzyj plansz\u0119", default_value: board_grid(replay, viewer)),
        announcement_shortcut(key: "d", label: "Odczytaj ko\u015bci", message: replay.state[:dice].empty? ?
          "Brak ko\u015bci do wykorzystania." : replay.state[:dice].join(", "))]
    end

    def bot_action_score(replay, _actor, action, context: nil)
      return -1 if %w[double drop].include?(action["action"])
      return 0 unless action["move"]
      from, to, die = action["move"].split(",").map(&:to_i)
      other = replay.board[1 - replay.state[:turn]]
      own = replay.board[replay.state[:turn]]
      rear = own.keys.max
      die + (to.zero? ? 24 : 0) + (from == rear ? 9 : 0) +
        (from == 25 ? 12 : 0) + (to.positive? && other.fetch(25 - to, 0) == 1 ? 1 : 0)
    end

    def participant_scores(replay)
      replay.players.zip(replay.state[:scores]).to_h
    end

    private

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
      message = "#{GameRoomContent.utf8(participant_name(actor))} wygrywa parti\u0119 za #{points}. #{score_text(players, state)}."
      if state[:target].zero? || state[:scores][winner] >= state[:target]
        state[:winner] = actor
      else
        state[:crawford_played] ||= state[:crawford]
        state[:crawford] = state[:doubling] && !state[:crawford_played] && state[:scores].include?(state[:target] - 1)
        state.merge!(board: BackgammonRules.initial(variant), turn: 0, phase: :opening, dice: [], cube: 1, cube_owner: nil)
        message += " Partia Crawforda. Podwajanie wy\u0142\u0105czone." if state[:crawford]
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
      return "banda" if point == 25
      return "zdj\u0119te" if point.zero?
      "pole #{point}"
    end

    def move_label(move)
      from, to, die = move
      "#{point_label(from)} do #{point_label(to)}, ko\u015b\u0107 #{die}"
    end
  end
end

require_relative 'generated/rulebooks/backgammon'
