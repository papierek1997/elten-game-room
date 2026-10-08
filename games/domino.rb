# encoding: UTF-8
require_relative "tile_game"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Domino < TileGame
    SETS = {
      "d6" => [6, 1, 7, 4], "d9" => [9, 1, 10, 5], "d12" => [12, 1, 10, 8],
      "2d6" => [6, 2, 10, 5], "2d9" => [9, 2, 10, 8], "2d12" => [12, 2, 10, 8],
      "4d6" => [6, 4, 10, 8], "4d9" => [9, 4, 10, 8], "4d12" => [12, 4, 10, 8],
      "d15" => [15, 1, 10, 8], "d18" => [18, 1, 10, 8]
    }.freeze

    def id; "domino"; end
    def notification_option_keys(_options); %w[tile_set teams]; end
    def notification_variant(options)
      setting = SETS[options["tile_set"]]
      if setting
        max, copies = setting
        set = {6 => _("Double 6"), 9 => _("Double 9"), 12 => _("Double 12"), 15 => _("Double 15"), 18 => _("Double 18")}.fetch(max)
        set = GameRoomContent.utf8("%{copies} × %{set}") % {copies: copies, set: set} if copies > 1
      end
      [set, notification_flag(options, "teams", _("Team play"), _("Individual play"))].compact.join(", ")
    end
    def name; _("Domino"); end

    def short_description
      _("Match the numbers on dominoes and play all your tiles before anyone else to avoid penalty points.")
    end

    def option_definitions
      [
        OptionDefinition.new(key: "tile_set", label: _("Domino set"), kind: :choice, default: "d6", choices: SETS.map do |key, (max, copies, _, limit)|
          count = (max + 1) * (max + 2) / 2 * copies
          names = { 6 => _("Double 6"), 9 => _("Double 9"), 12 => _("Double 12"), 15 => _("Double 15"), 18 => _("Double 18") }
          set = GameRoomContent.utf8(names.fetch(max))
          set = GameRoomContent.utf8("%{copies} × %{set}") % { copies: copies, set: set } if copies > 1
          label = _("%{set}, %{count} tiles, up to %{players} players") % { set: set, count: count, players: limit }
          OptionChoice.new(value: key, label: label)
        end),
        OptionDefinition.new(key: "teams", label: _("Play in teams"), kind: :boolean, default: false),
        OptionDefinition.new(key: "team_count", label: _("Number of teams"), kind: :choice, default: "2", choices: [2, 3, 4].map { |n| OptionChoice.new(value: n.to_s, label: n.to_s) }, visible_if: { "teams" => true }),
        OptionDefinition.new(key: "forbid_draw", label: _("Forbid drawing from the boneyard"), kind: :boolean, default: false),
        OptionDefinition.new(key: "allow_playable_draw", label: _("Allow drawing with a playable tile"), kind: :boolean, default: true, visible_if: { "forbid_draw" => false }),
        OptionDefinition.new(key: "draw_until", label: _("Draw until finding a playable tile"), kind: :boolean, default: false, visible_if: { "forbid_draw" => false }),
        OptionDefinition.new(key: "whole_team", label: _("The whole team must finish"), kind: :boolean, default: false, visible_if: { "teams" => true }),
        thinking_time_option,
        OptionDefinition.new(key: "score_limit", label: _("Score limit"), kind: :integer, default: 100)
      ]
    end

    def normalize_options(values)
      result = super
      result["allow_playable_draw"] = result["draw_until"] = false if result["forbid_draw"]
      result["whole_team"] = false unless result["teams"]
      result
    end

    def team_size(options, player_count:)
      options = normalize_options(options)
      count = options["team_count"].to_i
      return 0 unless options["teams"] && count >= 2 && player_count % count == 0 && player_count / count >= 2
      player_count / count
    end

    def options_error(values, player_count: nil)
      options = normalize_options(values)
      return _("Unknown domino set.") unless SETS.key?(options["tile_set"])
      return _("The score limit must be a positive number, at most 100000.") unless options["score_limit"].between?(1, 100_000)
      return thinking_time_options_error(options) if thinking_time_options_error(options)
      if player_count
        maximum = SETS[options["tile_set"]][3]
        return _("This domino set supports from 2 to %{count} players.") % { count: maximum } unless player_count.between?(2, maximum)
        return _("Choose equal teams with at least two players each.") if options["teams"] && team_size(options, player_count: player_count) == 0
        seats = options[GameRoomTeams::OPTION_KEY]
        if options["teams"] && seats
          expected = team_size(options, player_count: player_count)
          return _("Choose equal teams with at least two players each.") unless seats.length == player_count && (0...options["team_count"].to_i).all? { |t| seats.count(t) == expected }
        end
      end
      nil
    end

    def custom_game_shortcuts(replay, viewer)
      super + [
        announcement_shortcut(key: "c", label: _("chain ends"), message: ends_text(replay.state)),
        surface_shortcut(key: "v", label: _("browse the domino chain"), command: "tile_table"),
        surface_shortcut(key: "g", label: _("prefer playing on the left"), command: "tile_side", payload: { "target" => "l" }),
        surface_shortcut(key: "d", label: _("prefer playing on the right"), command: "tile_side", payload: { "target" => "r" })
      ]
    end

    def surface_spec(replay, viewer)
      spec = super
      spec.default_target = "r"
      spec
    end

    def placements(state, player)
      return [] if state[:phase] != :playing
      hand(state, player).flat_map do |tile|
        targets_for(state, tile).map { |side| command("play", tile: tile, target: side) }
      end
    end

    def can_draw?(state)
      return false if state[:drawn] || state[:options]["forbid_draw"] || state[:stock].empty? || hand(state, state[:current_player]).empty?
      state[:options]["allow_playable_draw"] || placements(state, state[:current_player]).empty?
    end

    def bot_action_score(replay, actor, action, context: nil)
      return -1000 if action["action"] == "draw"
      state, tile = replay.state, action["tile"]
      own = hand(state, actor)
      if own.one?
        partners = state[:units].fetch(unit_for(state, actor)).reject { |p| same_user?(p, actor) }
        return 100_000 unless state[:options]["whole_team"] && partners.any? { |p| !state[:hands][p].empty? }
      end
      rest = own.reject { |t| t == tile }
      left, right = ends_after(state, tile, action["target"])
      links = rest.count { |t| Tiles.fits?(t, left) || Tiles.fits?(t, right) }
      # Bound work by hand + public chain, not by hidden worlds or rollouts.
      score = Tiles.pips(tile) * 2 + (Tiles.double?(tile) ? 4 : 0) + links * 7
      # An empty own hand is not a round win in whole-team mode. Still compare
      # the two ends using public information about the remaining partners.
      score += 1000 if rest.empty?
      score -= 18 if links == 0 && rest.length > 1
      score -= 20 if rest.one? && Tiles.pips(rest.first) == 0
      score -= bot_elimination_risk(state, actor, rest)
      maximum, copies = SETS.fetch(state[:options]["tile_set"])[0..1]
      public_tiles = state[:chain].map { |item| item[:tile] } + own
      unseen = [left, right].uniq.sum do |pip|
        (maximum + 1) * copies - public_tiles.count { |t| Tiles.fits?(t, pip) }
      end
      peers = waiting_players(state).reject { |p| same_user?(actor, p) }
      peers.each do |p|
        void = state[:voids].fetch(p, [])
        known_blocked = void.include?(left) && void.include?(right)
        allied = bot_allied?(replay, actor, p)
        urgency = state[:hands][p].length <= 2 ? 20 : 4
        score += (allied ? -urgency : urgency) if known_blocked
      end
      # Locking low-pip hands is attractive; do not force a block with a costly hand.
      if links == 0 && (state[:stock].empty? || state[:options]["forbid_draw"])
        average = rest.sum { |t| Tiles.pips(t) }.to_f / [rest.length, 1].max
        score += [12 - average * 3, -30].max if unseen <= 2
      end
      score
    end

    def rule_sections
      generated_rule_sections
    end

    protected

    def targets_for(state, tile)
      return ["r"] if state[:chain].empty?
      result = []
      result << "l" if Tiles.fits?(tile, state[:chain].first[:left])
      result << "r" if Tiles.fits?(tile, state[:chain].last[:right])
      result
    end
    def ends_after(state, tile, side)
      return Tiles.faces(tile) if state[:chain].empty?
      left, right = state[:chain].first[:left], state[:chain].last[:right]
      side == "l" ? [Tiles.other(tile, left), right] : [left, Tiles.other(tile, right)]
    end
    def ends_text(state)
      return _("The table is empty.") if state[:chain].empty?
      _("Left %{left}, right %{right}.") % { left: state[:chain].first[:left], right: state[:chain].last[:right] }
    end
    def target_label(_state, target); target == "l" ? _("Left") : _("Right"); end
    def table_header(_state); _("Domino chain"); end
    def table_rows(state)
      state[:chain].map { |item| { id: item[:tile], label: "#{item[:left]}–#{item[:right]}", detail: "#{item[:left]}–#{item[:right]}" } }
    end
    def public_table(state); state[:chain]; end
    def hand_points(tiles); tiles.one? && Tiles.pips(tiles.first) == 0 ? 10 : tiles.sum { |t| Tiles.pips(t) }; end

    def deal(state, data, event_id, history)
      maximum, copies, count, = SETS.fetch(state[:options]["tile_set"])
      players = active_players(state)
      state[:stock] = Tiles.shuffle(Tiles.deck(maximum, copies), data["seed"])
      state[:hands] = state[:players].to_h { |p| [p, []] }
      count.times { players.each { |p| state[:hands][p] << state[:stock].shift } }
      # Rotate tie priority without biasing the common high-double rule.
      priority = players.rotate(state[:round] % players.length)
      starter = priority.max_by do |p|
        doubles = state[:hands][p].select { |t| Tiles.double?(t) }
        doubles.empty? ? [-1, state[:hands][p].map { |t| Tiles.pips(t) }.max] : [doubles.map { |t| Tiles.faces(t).first }.max, 0]
      end
      state.merge!(phase: :playing, round: state[:round] + 1, current_player: starter,
        chain: [], blocked: 0, voids: {}, round_winner: nil)
      begin_turn(state, data["time"])
      add_history(history, event_id, starter, :deal, _("Round %{round}. Tiles dealt.") % { round: state[:round] })
    end

    def apply_move(state, data, event_id, history)
      player = state[:current_player]
      case data["action"]
      when "play"
        tile, side = data["tile"], data["target"]
        return :invalid unless state[:hands][player].include?(tile) && %w[l r].include?(side)
        return :invalid unless state[:chain].empty? || targets_for(state, tile).include?(side)
        if state[:chain].empty?
          a, b = Tiles.faces(tile)
          state[:chain] << { tile: tile, left: a, right: b }
        elsif side == "l"
          right = state[:chain].first[:left]
          state[:chain].unshift(tile: tile, left: Tiles.other(tile, right), right: right)
        else
          left = state[:chain].last[:right]
          state[:chain] << { tile: tile, left: left, right: Tiles.other(tile, left) }
        end
        state[:hands][player].delete(tile)
        state[:blocked] = 0
        add_history(history, event_id, player, :play, (side == "l" ? _("%{player} plays %{tile} on the left.") : _("%{player} plays %{tile} on the right.")) % { player: participant_name(player), tile: Tiles.label(tile) })
        members = state[:units][unit_for(state, player)]
        finished = state[:options]["whole_team"] ? members.all? { |p| state[:hands][p].empty? } : state[:hands][player].empty?
        finished ? finish_round(state, player, event_id, history) : next_turn(state, data["time"])
      when "draw"
        return :invalid unless can_draw?(state)
        state[:drawn] = true
        count = 0
        loop do
          tile = draw_one(state, player)
          break unless tile
          count += 1
          break unless state[:options]["draw_until"] && targets_for(state, tile).empty?
        end
        state[:blocked] = 0
        add_history(history, event_id, player, :draw, n_("%{player} draws %{count} tile.", "%{player} draws %{count} tiles.", count) % { player: participant_name(player), count: count })
        pass(state, data, event_id, history, announce: false) if placements(state, player).empty?
      when "pass", "timeout"
        if data["action"] == "timeout" && !state[:drawn] && !state[:options]["forbid_draw"] && !state[:stock].empty?
          draw_one(state, player)
          add_history(history, event_id, player, :draw, _("%{player} draws a tile.") % { player: participant_name(player) })
        end
        pass(state, data, event_id, history)
      else return :invalid
      end
      :ok
    end

    def pass(state, data, event_id, history, announce: true)
      player = state[:current_player]
      unless state[:chain].empty? || !placements(state, player).empty?
        state[:voids][player] = (state[:voids].fetch(player, []) + [state[:chain].first[:left], state[:chain].last[:right]]).uniq
      end
      add_history(history, event_id, player, :pass, _("%{player} passes.") % { player: participant_name(player) }) if announce
      state[:blocked] += 1
      blocked = (state[:stock].empty? || state[:options]["forbid_draw"]) &&
        state[:blocked] >= waiting_players(state).length && waiting_players(state).all? { |p| placements(state, p).empty? }
      blocked ? finish_round(state, nil, event_id, history) : next_turn(state, data["time"])
    end
  end
end

require_relative 'generated/rulebooks/domino'
