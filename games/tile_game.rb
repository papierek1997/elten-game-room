# encoding: UTF-8
require_relative "base"
require_relative "../lib/game_round_cues"
require_relative "../lib/domino_tiles"
require_relative "../lib/game_bots"
require_relative "../lib/game_turn_clock"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class TileGame < Base
    def player_spatial_audio?; true; end
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      GameRoomRoundCues.for_event(history, after_replay, viewer,
        assets: %w[domino_refill domino_take_chip domino_move_tile])
    end

    include PublicHistoryAnnouncements
    Tiles = GameRoomDominoTiles
    def maximum_players; 8; end
    def tournament_winning_units_result(replay, options:)
      tournament_result_from_public_winners(replay, options: options, winners: replay.state[:winners])
    end
    def supports_bots?; true; end
    def thinking_time_range; 1..600; end
    def perfect_information?; false; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def bot_delay_revision(replay, _revision); [replay.state[:round], replay.state[:turn]]; end

    def initial_state(players, options)
      assignment = team_assignment(options, players: players)
      units = assignment ? assignment.team_ids.to_h { |team| [team, assignment.members_for(team)] } : players.to_h { |p| [p, [p]] }
      order = assignment ? (0...assignment.team_size).flat_map { |i| units.values.map { |members| members[i] } } : players.dup
      { players: players.dup, options: options, units: units, order: order,
        phase: :awaiting_deal, round: 0, turn: 0, current_player: nil,
        scores: units.to_h { |key, _| [key, 0] }, eliminated: {},
        hands: players.to_h { |p| [p, []] }, stock: [], chain: [],
        winner: nil, winners: [], draw: false, drawn: false, turn_deadline: 0,
        blocked: 0, voids: {}, round_winner: nil }
    end

    def replay(session, events, repository)
      state = initial_state(repository.players_for(session), options_from_json(session["options"]))
      GameRoomPrivateCardLedger.initialize_state(state, session) if GameRoomPrivateCards.enabled?(session)
      history, accepted, seen = [starting_history(state[:players])], [], {}
      events.each do |event|
        event_id = repository.event_id(event)
        next if seen[event_id] || state[:phase] == :finished
        # A refused rule move cannot undo an authenticated native disclosure.
        # Retain that knowledge before the transactional candidate is copied.
        GameRoomPrivateCardLedger.observe_reveal(state, event, repository.actor_of(event, session)) if state[:private_cards]
        candidate, additions = copy_state(state), []
        next unless apply_replay_event(candidate, event, session, repository, additions)
        state = candidate
        history.concat(additions)
        accepted << event
        seen[event_id] = true
      end
      GameRoomSessionClock.attach(state, session)
      Replay.new(board: nil, players: state[:players], current_player: state[:current_player],
        winner: state[:winner], draw: false, accepted_events: accepted, history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      input = selection.to_h.transform_keys(&:to_s)
      data = input.select { |key, _| %w[action tile target].include?(key) }
      data.merge!("round" => replay.state[:round], "turn" => replay.state[:turn], "time" => GameRoomTurnClock.logical_now(replay.state, context))
      if data["action"] == "deal"
        return [:invalid, nil] unless context&.random_source
        data["seed"] = context.server_random ? '0' * 32 :
          context.random_source.roll(count: 16, sides: 256).values.map { |v| (v - 1).to_s(16).rjust(2, "0") }.join
      end
      status = apply(copy_state(replay.state), data, actor, 0, [])
      return [status, nil] unless status == :ok
      if data['action'] == 'deal' && context.server_random
        return [:ok, server_seed_plan(id, template: encode(data.merge('seed' => '{seed}')))]
      end
      value = encode(data)
      return [:invalid, nil] if value.length > 64
      [:ok, event_plan(id, value)]
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if replay.finished? || !same_user?(actor, state[:players].first)
      return command("deal") if [:awaiting_deal, :round_complete].include?(state[:phase])
      return command("timeout") if deadline_reached?(state, context&.now)
      return command("pass") if placements(state, state[:current_player]).empty? && !can_draw?(state)
      nil
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] unless state[:phase] == :playing && same_user?(actor, state[:current_player])
      return [] if deadline_reached?(state, context&.now)
      actions = placements(state, state[:current_player])
      actions << command("draw") if can_draw?(state)
      actions
    end

    def participant_scores(replay)
      replay.players.to_h { |p| [p, replay.state[:scores][unit_for(replay.state, p)]] }
    end

    def eliminated_from_game?(replay, viewer)
      !!replay.state.fetch(:eliminated, {})[unit_for(replay.state, viewer)]
    end

    def participant_status(replay, participant, connected: true)
      return _("eliminated") if replay.state[:eliminated][unit_for(replay.state, participant)]
      super
    end

    def bot_allied?(replay, first, second); unit_for(replay.state, first) == unit_for(replay.state, second); end
    def bot_reward(replay, actor)
      return 0.0 unless replay.finished?
      replay.state[:winners].any? { |p| same_user?(p, actor) } ? 1.0 : -1.0
    end

    def result_text(replay)
      return nil unless replay.finished?
      _("Game winners: %{players}.") % { players: replay.state[:winners].map { |p| participant_name(p) }.join(", ") }
    end

    def hand(state, actor)
      player = state[:players].find { |p| same_user?(p, actor) }
      state[:hands].fetch(player, [])
    end

    def surface_spec(replay, viewer)
      state = replay.state
      legal = state[:phase] == :playing && same_user?(state[:current_player], viewer) ? placements(state, state[:current_player]) : []
      tiles = hand(state, viewer).map do |tile|
        moves = legal.select { |a| a["tile"] == tile }
        choices = moves.length > 1 ? moves.map { |a| GameSurfaces::TileChoice.new(id: a["target"], label: target_label(state, a["target"]), value: a) } : []
        GameSurfaces::Tile.new(id: tile, label: Tiles.label(tile),
          value: moves.first || command("play", tile: tile, target: ""), choices: choices, choice_header: _("Choose where to play %{tile}") % { tile: Tiles.label(tile) })
      end
      GameSurfaces::TileHandSpec.new(zones: [GameSurfaces::TileZoneSpec.new(id: "tiles", header: _("Your tiles"), cards: tiles,
        empty_label: _("Your hand is empty"), hand_order: hand(state, viewer).dup, hand_epoch: "#{viewer.to_s.downcase}:#{state[:round]}")],
        table_header: table_header(state), table: table_rows(state), table_epoch: "#{id}:#{state[:round]}")
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      actions = legal_actions(replay, viewer).select { |a| a["action"] == "play" }
      tiles = actions.map { |a| a["tile"] }.uniq
      automatic = auto_play_unique_tile? && actions.one? ? actions.first : nil
      payload = { "hand_id" => "tiles", "card_ids" => tiles, "auto_card_id" => automatic&.[]( "tile"),
        "auto_action" => automatic, "empty_message" => _("You have no playable tile."), "focus_surface" => true }
      [
        GameShortcut.new(key: "space", label: _("draw tiles"), kind: :action, action_kind: "tile", action_name: "draw", payload: {}),
        announcement_shortcut(key: "e", label: _("tile counts and boneyard"), message: tile_counts_text(state)),
        announcement_shortcut(key: "s", label: _("scores"), message: score_announcement_order(state[:units].keys, state[:scores], eliminated: state[:eliminated]).map { |unit| "#{unit_label(state, unit)}, #{state[:scores][unit]}" }.join("; ")),
        surface_shortcut(key: "z", label: _("next playable tile"), command: "navigate_playable_tile", payload: payload.merge("direction" => 1, "shortcut" => "z")),
        surface_shortcut(key: "z", modifiers: [:shift], label: _("previous playable tile"), command: "navigate_playable_tile", payload: payload.merge("direction" => -1, "shortcut" => "shift+z"))
      ]
    end

    def bot_observation(replay, actor)
      state = replay.state
      { "hand" => hand(state, actor).dup, "hand_counts" => state[:hands].transform_values(&:length),
        "boneyard" => state[:stock].length, "table" => copy_state(public_table(state)),
        "scores" => state[:scores].dup, "options" => copy_state(state[:options]), "units" => copy_state(state[:units]),
        "voids" => copy_state(state[:voids]), "current_player" => state[:current_player] }
    end

    protected

    def apply_replay_event(state, event, session, repository, history)
      return false unless event['action'] == id || (state[:private_cards] && event['action'] == 'deal')
      data = decode(event['value'].to_s)
      return false unless data
      if data['action'] == 'deal'
        return false unless GameRoomServerRandom.valid_text_seed_event?(event,
          template:encode(data.merge('seed'=>'{seed}')))
      elsif state[:private_cards]
        return private_apply_effect(state, event, session, repository, history)
      end
      apply(state, data, repository.actor_of(event, session), repository.event_id(event), history) == :ok
    end

    def has_placement?(state, player); !placements(state, player).empty?; end
    def automatic_move_actor(state); state[:players].first; end

    def auto_play_unique_tile?; true; end

    def command(action, **values); { "kind" => "tile", "action" => action }.merge(values.transform_keys(&:to_s)); end
    def copy_state(value)
      case value
      when Hash then value.to_h { |k, v| [k, copy_state(v)] }
      when Array then value.map { |v| copy_state(v) }
      else value
      end
    end
    def unit_for(state, player); state[:units].find { |_, members| members.any? { |p| same_user?(p, player) } }&.first; end
    def active_players(state); state[:order].reject { |p| state[:eliminated][unit_for(state, p)] }; end
    def waiting_players(state); active_players(state).reject { |p| state[:hands][p].empty? }; end
    def unit_label(state, unit)
      members = state[:units].fetch(unit)
      members.length == 1 ? participant_name(members.first) : _("Team %{number}: %{players}") % { number: state[:units].keys.index(unit) + 1, players: members.map { |p| participant_name(p) }.join(", ") }
    end
    def tile_counts_text(state)
      active_players(state).map { |p| "#{participant_name(p)}, #{state[:hands][p].length}" }.join("; ") + ". " +
        ((state[:options]["forbid_draw"] ? _("Boneyard unavailable: %{count}.") : _("Boneyard: %{count}.")) % { count: state[:stock].length })
    end
    def bot_elimination_risk(state, actor, remaining)
      # Only the bot's own remaining tiles and public cumulative score. Even
      # in teams, never inspect the partner's hidden pips to estimate safety.
      margin = state[:options]["score_limit"] - state[:scores].fetch(unit_for(state, actor), 0)
      exposure = hand_points(remaining) - margin + 1
      [[exposure * 2, 0].max, 100].min
    end
    def add_history(history, event_id, actor, kind, text, value = nil)
      history << HistoryEntry.new(key: "#{id}:#{event_id}:#{history.length}", event_id: event_id, actor: actor, kind: kind, text: text, value: value)
    end
    def deadline_reached?(state, now)
      state[:phase] == :playing && now != nil && state[:turn_deadline].to_i > 0 && now.to_i >= state[:turn_deadline]
    end
    def begin_turn(state, time)
      state[:turn] += 1
      state[:drawn] = false
      state[:turn_started] = time
      duration = state[:options]["thinking_time"].to_i
      state[:turn_deadline] = duration > 0 ? time + duration : 0
    end
    def next_turn(state, time)
      current_index = state[:order].index(state[:current_player])
      players = waiting_players(state)
      state[:current_player] = state[:order].rotate(current_index + 1).find { |p| players.include?(p) }
      begin_turn(state, time)
    end
    def draw_one(state, player)
      tile = state[:stock].shift
      state[:hands][player] << tile if tile
      state[:voids].delete(player) if tile
      tile
    end
    def encode(data)
      letter = { "deal" => "n", "play" => "p", "draw" => "d", "pass" => "s", "timeout" => "t" }.fetch(data["action"])
      extra = data["action"] == "deal" ? [data["seed"]] : data["action"] == "play" ? [data["tile"], data["target"]] : []
      [letter, data["round"].to_s(36), data["turn"].to_s(36), data["time"].to_s(36), *extra].join(":")
    end
    def decode(value)
      parts = value.split(":", -1)
      return nil if value.length > 64 || parts.length < 4 || parts[1..3].any? { |v| !/\A[0-9a-z]{1,10}\z/.match?(v) }
      action = { "n" => "deal", "p" => "play", "d" => "draw", "s" => "pass", "t" => "timeout" }[parts[0]]
      return nil unless action && parts.length == (action == "deal" ? 5 : action == "play" ? 6 : 4)
      data = { "action" => action, "round" => parts[1].to_i(36), "turn" => parts[2].to_i(36), "time" => parts[3].to_i(36) }
      data["seed"] = parts[4] if action == "deal"
      data.merge!("tile" => parts[4], "target" => parts[5]) if action == "play"
      data
    end

    def apply(state, data, actor, event_id, history)
      return :invalid unless data["round"] == state[:round] && data["turn"] == state[:turn] && data["time"].is_a?(Integer) && data["time"] >= state.fetch(:turn_started, 0)
      if data["action"] == "deal"
        return :not_your_turn unless same_user?(actor, state[:players].first)
        return :invalid unless [:awaiting_deal, :round_complete].include?(state[:phase]) && /\A[0-9a-f]{32}\z/.match?(data["seed"].to_s)
        return :invalid if validation_error(state[:options], player_count: state[:players].length)
        deal(state, data, event_id, history)
        return :ok
      end
      return :invalid unless state[:phase] == :playing
      auto = %w[timeout pass].include?(data["action"])
      return :not_your_turn unless same_user?(actor, auto ? automatic_move_actor(state) : state[:current_player])
      return :invalid if !auto && deadline_reached?(state, data["time"])
      return :invalid if data["action"] == "timeout" && !deadline_reached?(state, data["time"])
      return :invalid if data["action"] == "pass" && (has_placement?(state, state[:current_player]) || can_draw?(state))
      apply_move(state, data, event_id, history)
    end

    def finish_round(state, winner, event_id, history)
      unit = winner && unit_for(state, winner)
      state[:round_winner] = unit
      text = unit ? _("%{player} wins the round.") % { player: unit_label(state, unit) } : _("The round is blocked.")
      add_history(history, event_id, winner, :round_result, text, unit && state[:units][unit])
      amounts = state[:units].to_h { |key, members| [key, members.sum { |p| hand_points(state[:hands][p]) }] }
      round_units = state[:units].keys.reject { |key| state[:eliminated][key] }
      state[:units].each_key do |key|
        next if state[:eliminated][key]
        points = key == unit ? 0 : amounts[key] + (unit ? amounts[unit] : 0)
        state[:scores][key] += points
        add_history(history, event_id, nil, :score, _("%{player} receives %{points} points.") % { player: unit_label(state, key), points: points })
        state[:eliminated][key] = true if state[:scores][key] >= state[:options]["score_limit"]
      end
      survivors = state[:units].keys.reject { |key| state[:eliminated][key] }
      if survivors.length <= 1
        lowest = round_units.map { |key| state[:scores][key] }.min
        candidates = survivors.empty? ? round_units.select { |key| state[:scores][key] == lowest } : survivors
        state[:winners] = candidates.flat_map { |key| state[:units][key] }
        state[:winner] = state[:winners].first
        state[:phase] = :finished
        add_history(history, event_id, state[:winner], :result, _("Game winners: %{players}.") % { players: state[:winners].map { |p| participant_name(p) }.join(", ") })
      else
        state[:phase] = :round_complete
      end
      state[:current_player] = nil
      state[:turn_deadline] = 0
    end
  end
end
