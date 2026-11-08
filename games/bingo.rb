require_relative "base"
require_relative "base/round_tournament"
require_relative "bingo_ticket"
require_relative "../lib/game_bots"
require_relative "../lib/game_reduction"

module GameRoomGames
  using GameRoomLocalization::Translations

  class Bingo < Base
    include PublicHistoryAnnouncements
    include RoundTournament
    GameRoomServerRandom.register("bingo", %w[start draw])

    def id; "bingo"; end
    def name; _("Bingo"); end
    def short_description; _("Follow the called balls and complete your ticket in 30-, 75-, 80- or 90-ball bingo."); end
    def minimum_players; 1; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def notification_option_keys(_options); %w[variant marking pattern]; end

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: _("Variant"), kind: :choice, default: "90", choices: [
          OptionChoice.new(value: "90", label: _("90 balls: one line, two lines, full house")),
          OptionChoice.new(value: "75", label: _("75 balls: American bingo")),
          OptionChoice.new(value: "80", label: _("80 balls: four by four")),
          OptionChoice.new(value: "30", label: _("30 balls: speed bingo"))
        ]),
        OptionDefinition.new(key: "pattern", label: _("Winning pattern"), kind: :choice, default: "line",
          visible_if: {"variant" => %w[75 80]}, choices: [
            OptionChoice.new(value: "line", label: _("Any horizontal, vertical or diagonal line")),
            OptionChoice.new(value: "corners", label: _("Four corners")),
            OptionChoice.new(value: "full", label: _("Full house (all ticket numbers)"))
          ]),
        OptionDefinition.new(key: "marking", label: _("Marking numbers"), kind: :choice, default: "automatic", choices: [
          OptionChoice.new(value: "automatic", label: _("Automatic marking and bingo detection")),
          OptionChoice.new(value: "manual", label: _("Manual marking, bingo claim and ready confirmation"))
        ]),
        OptionDefinition.new(key: "ball_interval", label: _("Seconds between bingo balls (3-30)"), kind: :integer, default: 5,
          visible_if: {"marking" => "automatic"})
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("Choose a delay from 3 to 30 seconds.") unless values["ball_interval"].is_a?(Integer) && values["ball_interval"].between?(3, 30)
      nil
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = {players: players, options: options_from_json(session["options"]), phase: :initializing,
        tickets: {}, marks: players.to_h { |player| [player, []] }, remaining: [], called: [], stage: 0,
        awards: [], ready: [], claims: [], next_at: 0, current_player: players.first, winner: nil, draw: false}
      enable_round_tournament(state, session)
      GameRoomSessionClock.attach(state, session)
      accepted, history, seen = [], [starting_history(players)], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id = repository.event_id(event)
        next if seen[event_id]
        actor = repository.actor_of(event, session)
        next unless apply_bingo_event(state, event, actor, event_id, history, session)
        accepted << event
        seen[event_id] = true
      end
      Replay.new(players: players, board: nil, current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], state: state, history: history, accepted_events: accepted)
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      return {"kind" => "command", "action" => "start"} if replay.state[:phase] == :initializing
      {"kind" => "command", "action" => "draw"} if replay.state[:phase] == :drawing && draw_due?(replay.state, context&.now)
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def active_actors(replay)
      return [] unless replay.state[:phase] == :marking
      tournament_contenders(replay.state) - replay.state[:ready]
    end

    def required_decision_key(replay, viewer)
      return nil unless replay && !replay.finished? && GameRoomParticipants.includes?(active_actors(replay), viewer)
      [replay.state[:called].size, replay.state[:stage], viewer.to_s.downcase]
    end

    def concurrent_session_input?(before, after, selection)
      manual_action?(selection) && before.state[:phase] == :marking && after.state[:phase] == :marking &&
        before.state[:called] == after.state[:called] && before.state[:stage] == after.state[:stage]
    end

    def legal_actions(replay, actor, context: nil)
      return [] unless GameRoomParticipants.includes?(active_actors(replay), actor)
      state = replay.state
      player = player_key(state, actor)
      payload = {"kind" => "command", "call" => state[:called].size, "stage" => state[:stage]}
      available = state[:tickets][player].compact.select { |number| number > 0 && state[:called].include?(number) && !state[:marks][player].include?(number) }
      actions = available.map { |number| payload.merge("action" => "mark", "number" => number) }
      actions << payload.merge("action" => "claim") if ticket_wins?(state, player)
      actions << payload.merge("action" => "ready")
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      action = selection["action"].to_s
      if %w[start draw].include?(action)
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] unless automatic_action(replay, actor, context: context)&.fetch("action") == action && context&.random_source
        if action == "start"
          return [:ok, server_seed_plan("start")] if context.server_random
          seed = context.random_source.roll(count: 16, sides: 256).values.map { |number| (number - 1).to_s(16).rjust(2, "0") }.join
          return [:ok, event_plan("start", seed)]
        end
        sides = [state[:remaining].size, 2].max
        return [:ok, ActionPlan.new(events: [GameRoomServerRandom.command(action: "draw", count: 1, sides: sides)])] if context.server_random
        return [:ok, event_plan("draw", context.random_source.roll(count: 1, sides: sides).values.first.to_s)]
      end
      player = player_key(state, actor)
      return [:not_your_turn, nil] unless player && active_actors(replay).include?(player)
      if selection["kind"] == "grid" && action == "select"
        x, y = selection["x"], selection["y"]
        width, height = GameRoomBingo.size(state[:options]["variant"])
        return [:invalid_mark, nil] unless x.is_a?(Integer) && y.is_a?(Integer) && x.between?(0, width - 1) && y.between?(0, height - 1)
        number = state[:tickets][player][y * width + x]
        action = "mark"
      else
        return [:invalid, nil] unless selection["call"] == state[:called].size && selection["stage"] == state[:stage]
        number = selection["number"]
      end
      return [:invalid_mark, nil] if action == "mark" && !mark_allowed?(state, player, number)
      return [:invalid_claim, nil] if action == "claim" && !ticket_wins?(state, player)
      return [:invalid, nil] unless %w[mark claim ready].include?(action)
      value = "#{state[:called].size}|#{state[:stage]}"
      value += "|#{number}" if action == "mark"
      [:ok, event_plan(action, value)]
    end

    def bot_action_score(_replay, _actor, action, context: nil)
      {"claim" => 100, "mark" => 10, "ready" => 0}.fetch(action["action"], -1)
    end

    def turn_announcement(replay, viewer)
      nil
    end

    def turn_transition_history_entry(before_replay, after_replay, event_id:)
      nil
    end

    def current_turn_shortcut_text(replay, viewer)
      return result_text(replay) if replay.finished?
      return _("The bingo caller is drawing balls.") unless replay.state[:phase] == :marking
      if GameRoomParticipants.includes?(active_actors(replay), viewer)
        _("Mark the called number if it is on your ticket, then finish marking.")
      else
        _("Waiting for players to finish marking.")
      end
    end

    def participant_status(replay, participant, connected: true)
      player = player_key(replay.state, participant)
      return super unless player && replay.state[:tickets][player]
      _("Marked %{count} of %{total}") % {count: replay.state[:marks][player].size, total: replay.state[:tickets][player].compact.count(&:positive?)}
    end

    def surface_spec(replay, viewer)
      state = replay.state
      player = player_key(state, viewer)
      cells = state[:tickets][player]
      return GameSurfaces::PawnTrackSpec.new(id: "bingo_status", header: GameRoomContent.utf8(name),
        items: [GameSurfaces::PawnTrackItem.new(id: "status", label: GameRoomContent.utf8(current_turn_shortcut_text(replay, viewer)))]) unless cells
      width, height = GameRoomBingo.size(state[:options]["variant"])
      labels = cells.map do |number|
        if number.nil? then _("Blank")
        elsif number == 0 then _("Free centre")
        elsif state[:marks][player].include?(number) then _("%{number}, marked") % {number: number}
        elsif state[:called].include?(number) then _("%{number}, called, not marked") % {number: number}
        else _("%{number}, not called") % {number: number}
        end
      end
      header = _("Bingo %{variant}: %{goal}; last ball %{ball}; calls %{count} of %{total}.") % {
        variant: state[:options]["variant"], goal: goal_label(goal(state)),
        ball: state[:called].last ? ball_label(state, state[:called].last) : "-",
        count: state[:called].size, total: state[:options]["variant"]}
      grid = GameSurfaces::GridSpec.new(width: width, height: height, header: GameRoomContent.utf8(header),
        cells: labels.map { |label| GameRoomContent.utf8(label) }.each_slice(width).to_a, row_origin: :top)
      commands = []
      if active_actors(replay).include?(player)
        payload = {"kind" => "command", "call" => state[:called].size, "stage" => state[:stage]}
        if ticket_wins?(state, player)
          commands << GameSurfaces::PawnTrackItem.new(id: "claim", label: GameRoomContent.utf8(_("Claim bingo")),
            action: GameSurfaces::Action.new(kind: "command", name: "claim", payload: payload))
        end
        commands << GameSurfaces::PawnTrackItem.new(id: "ready", label: GameRoomContent.utf8(_("Ready for the next bingo call")),
          action: GameSurfaces::Action.new(kind: "command", name: "ready", payload: payload))
      end
      actions = GameSurfaces::PawnTrackSpec.new(id: "bingo_commands", header: GameRoomContent.utf8(_("Bingo actions")), items: commands,
        empty_label: GameRoomContent.utf8(current_turn_shortcut_text(replay, viewer)))
      GameSurfaces::CompositeSpec.new(parts: [GameSurfaces::SurfacePart.new(id: "ticket", surface: grid),
        GameSurfaces::SurfacePart.new(id: "actions", surface: actions)])
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      called = state[:called].map { |number| ShortcutChoice.new(value: nil, label: ball_label(state, number)) }
      called << ShortcutChoice.new(value: nil, label: _("No ball has been called yet.")) if called.empty?
      shortcuts = [announcement_shortcut(key: "l", label: _("read the last bingo ball"), message: state[:called].last ? ball_label(state, state[:called].last) : _("No ball has been called yet.")),
        GameShortcut.new(key: "d", label: _("browse called bingo numbers"), kind: :browse, prompt: _("Called bingo numbers"),
          choices: called)]
      return shortcuts unless GameRoomParticipants.includes?(active_actors(replay), viewer)
      payload = {"call" => state[:called].size, "stage" => state[:stage]}
      shortcuts << GameShortcut.new(key: "m", label: _("mark a called bingo number"), kind: :number_input, prompt: _("Number to mark"),
        action_kind: "command", action_name: "mark", value_key: "number", allowed_values: 1..state[:options]["variant"].to_i,
        default_value: state[:called].last, payload: payload)
      if ticket_wins?(state, player_key(state, viewer))
        shortcuts << GameShortcut.new(key: "b", label: _("claim bingo"), kind: :action, action_kind: "command", action_name: "claim", payload: payload)
      end
      shortcuts << GameShortcut.new(key: "r", label: _("finish marking this call"), kind: :action, action_kind: "command", action_name: "ready", payload: payload)
    end

    def move_error(status)
      return _("Mark a number on your ticket that has been called and is not marked yet.") if status == :invalid_mark
      return _("Your marked ticket does not complete the current bingo pattern.") if status == :invalid_claim
      super
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = []
      cues << "bingo_draw" if event["action"] == "draw" && after_replay.state[:called].size > before_replay.to_h.dig(:state, :called).to_a.size
      cues << "replay" if history.any? { |entry| entry.kind == :bingo_award && same_user?(entry.actor, viewer) }
      cues
    end

    private

    def player_key(state, actor); state[:players].find { |person| same_user?(person, actor) }; end
    def manual_action?(selection); %w[mark claim ready].include?(selection["action"]) || (selection["kind"] == "grid" && selection["action"] == "select"); end
    def goals(state); state[:options]["variant"] == "90" ? %w[line two_lines full] : [state[:options]["variant"] == "30" ? "full" : state[:options]["pattern"]]; end
    def goal(state); goals(state).fetch(state[:stage]); end
    def goal_label(value); {"line" => _("one line"), "two_lines" => _("two lines"), "full" => _("full bingo ticket"), "corners" => _("four corners")}.fetch(value); end
    def manual?(state); state[:options]["marking"] == "manual"; end
    def draw_due?(state, now); !state[:remaining].empty? && (state[:next_at] == 0 || (state[:next_at] != nil && now != nil && now >= state[:next_at])); end
    def ticket_wins?(state, player); GameRoomBingo.winning?(state[:options]["variant"], goal(state), state[:tickets][player], state[:marks][player]); end
    def mark_allowed?(state, player, number)
      number.is_a?(Integer) && number > 0 && state[:tickets][player].include?(number) && state[:called].include?(number) && !state[:marks][player].include?(number)
    end

    def add_history(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "#{kind}:#{event_id}:#{history.size}", event_id: event_id, actor: actor, kind: kind, text: text)
    end

    def schedule_draw(state, event, session)
      timestamp = GameRoomReduction.timestamp(event)
      time = timestamp && GameRoomSessionClock.from_server(session, timestamp, event: event)
      state.merge!(phase: :drawing, current_player: state[:players].first, ready: [], claims: [],
        next_at: manual?(state) ? 0 : time ? time + state[:options]["ball_interval"] : nil)
    end

    def apply_bingo_event(state, event, actor, event_id, history, session)
      action, value = event.values_at("action", "value")
      if action == "tournament_elimination"
        return apply_round_tournament_elimination(state, event, event_id, history) do |departed|
          state[:ready] -= departed
          state[:claims] -= departed
          resolve_marking(state, event, event_id, history, session) if state[:phase] == :marking
        end
      elsif action == "start"
        return false unless state[:phase] == :initializing && same_user?(actor, state[:players].first)
        seed = GameRoomServerRandom.text_seed_value(event, template: "{seed}")
        return false unless seed
        random = Random.new(seed.to_i(16))
        state[:tickets] = state[:players].to_h { |player| [player, GameRoomBingo.ticket(state[:options]["variant"], random)] }
        state[:remaining] = (1..state[:options]["variant"].to_i).to_a
        schedule_draw(state, event, session)
        add_history(history, event_id, "", :bingo_start, _("Bingo tickets are ready. Target: %{goal}.") % {goal: goal_label(goal(state))})
      elsif action == "draw"
        sides = [state[:remaining].size, 2].max
        return false unless state[:phase] == :drawing && !state[:remaining].empty? && same_user?(actor, state[:players].first) &&
          value.to_s.match?(/\A[1-9][0-9]*\z/) && value.to_i.between?(1, sides)
        return false unless GameRoomServerRandom.valid_dice_event?(event, count: 1, sides: sides)
        ball = state[:remaining].delete_at((value.to_i - 1) % state[:remaining].size)
        state[:called] << ball
        add_history(history, event_id, "", :bingo_ball, _("Ball %{number}.") % {number: ball_label(state, ball)})
        if manual?(state)
          state.merge!(phase: :marking, current_player: state[:players].first, ready: [], claims: [])
        else
          tournament_contenders(state).each { |player| state[:marks][player] << ball if state[:tickets][player].include?(ball) }
          resolve_automatic(state, event_id, history)
          schedule_draw(state, event, session) unless state[:phase] == :finished
        end
      else
        player = player_key(state, actor)
        return false unless player && state[:phase] == :marking && (tournament_contenders(state) - state[:ready]).include?(player)
        match = /\A([1-9][0-9]*)\|([0-2])(?:\|([1-9][0-9]*))?\z/.match(value.to_s)
        return false unless match && match[1].to_i == state[:called].size && match[2].to_i == state[:stage]
        if action == "mark"
          number = match[3]&.to_i
          return false unless mark_allowed?(state, player, number)
          state[:marks][player] << number
        elsif %w[ready claim].include?(action) && match[3] == nil
          return false if action == "claim" && !ticket_wins?(state, player)
          state[:claims] << player if action == "claim"
          state[:ready] << player
          resolve_marking(state, event, event_id, history, session)
        else
          return false
        end
      end
      true
    end

    def resolve_marking(state, event, event_id, history, session)
      active = tournament_contenders(state)
      pending = active - state[:ready]
      if !pending.empty?
        state[:current_player] = pending.first
      elsif !state[:claims].empty?
        award(state, state[:claims].dup, event_id, history)
        state.merge!(ready: [], claims: [], current_player: active.first) unless state[:phase] == :finished
      elsif state[:remaining].empty?
        finish(state, [], event_id, history)
      else
        schedule_draw(state, event, session)
      end
    end

    def resolve_automatic(state, event_id, history)
      loop do
        winners = tournament_contenders(state).select { |player| ticket_wins?(state, player) }
        break if winners.empty?
        award(state, winners, event_id, history)
        break if state[:phase] == :finished
      end
      finish(state, [], event_id, history) if state[:phase] != :finished && state[:remaining].empty?
    end

    def award(state, winners, event_id, history)
      target = goal(state)
      state[:awards] << {goal: target, players: winners.dup, call: state[:called].size}
      record_tournament_round(state, event_id, kind: 'bingo', index: state[:stage] + 1)
      winners.each do |player|
        add_history(history, event_id, player, :bingo_award, _("%{player}: bingo for %{goal}!") % {player: participant_name(player), goal: goal_label(target)})
      end
      if state[:stage] + 1 == goals(state).size
        finish(state, winners, event_id, history)
      else
        state[:stage] += 1
        add_history(history, event_id, "", :bingo_target, _("Next bingo target: %{goal}.") % {goal: goal_label(goal(state))})
      end
    end

    def finish(state, winners, event_id, history)
      record_tournament_winners(state, winners)
      state.merge!(phase: :finished, current_player: nil, winner: winners.one? ? winners.first : nil, draw: !winners.one?)
      history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
    end

    def tournament_round_scores(state)
      state[:players].to_h { |player| [player, state[:awards].count { |award| award[:players].include?(player) }] }
    end

    def ball_label(state, number)
      state[:options]["variant"] == "75" ? "#{%w[B I N G O][(number - 1) / 15]} #{number}" : number.to_s
    end
  end
end

require_relative "generated/rulebooks/bingo"
