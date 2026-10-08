# encoding: UTF-8
require_relative "tile_game"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class MexicanTrain < TileGame
    def id; "mexican_train"; end
    def name; _("Mexican Train"); end

    def short_description
      _("Build several trains of dominoes and try to play all your tiles before anyone else.")
    end

    def option_definitions
      [
        OptionDefinition.new(key: "allow_playable_draw", label: _("Allow drawing with a playable tile"), kind: :boolean, default: false),
        OptionDefinition.new(key: "score_limit", label: _("Score limit"), kind: :integer, default: 100)
      ]
    end

    def options_error(values, player_count: nil)
      options = normalize_options(values)
      return _("The score limit must be a positive number, at most 100000.") unless options["score_limit"].between?(1, 100_000)
      return _("Mexican Train supports from 2 to 8 players.") if player_count && !player_count.between?(2, 8)
      nil
    end

    def initial_state(players, options)
      super.merge(trains: {}, pending: [], series: false, station: 12, starter: nil)
    end

    def placements(state, player)
      return [] unless state[:phase] == :playing
      targets = accessible_trains(state, player)
      hand(state, player).flat_map do |tile|
        targets.filter_map do |target|
          command("play", tile: tile, target: target) if Tiles.fits?(tile, state[:trains][target][:end])
        end
      end
    end

    def can_draw?(state)
      return false if state[:drawn] || state[:stock].empty? || hand(state, state[:current_player]).empty?
      state[:options]["allow_playable_draw"] || placements(state, state[:current_player]).empty?
    end

    def custom_game_shortcuts(replay, viewer)
      super + [surface_shortcut(key: "c", label: _("browse trains"), command: "tile_table")]
    end

    def current_turn_shortcut_text(replay, viewer)
      text = super
      required = required_text(replay.state)
      required.empty? ? text : "#{text} #{required}"
    end

    def bot_action_score(replay, actor, action, context: nil)
      return -1000 if action["action"] == "draw"
      state, tile, target = replay.state, action["tile"], action["target"]
      own = hand(state, actor)
      return 100_000 if own.one?
      rest = own.reject { |t| t == tile }
      ending = Tiles.other(tile, state[:trains][target][:end])
      points = Tiles.pips(tile) == 0 ? 10 : Tiles.pips(tile)
      score = points * 2
      score -= bot_elimination_risk(state, actor, rest)
      self_id = train_id(state, actor)
      score += 9 if target == self_id && state[:trains][self_id][:open]
      # Follow only public ends and one's own tiles. A two-step continuation is
      # enough to avoid obvious dead-end doubles, without a permutation search.
      ends = accessible_trains(state, actor).map { |key| key == target ? ending : state[:trains][key][:end] }
      connected = rest.count { |t| ends.any? { |value| Tiles.fits?(t, value) } }
      score += connected * 5
      if Tiles.double?(tile)
        score += connected > 0 ? 22 : -20
        score += 1000 if rest.one? && ends.any? { |value| Tiles.fits?(rest.first, value) }
      else
        score -= 12 if connected == 0
      end
      pending = state[:pending].reject { |key| key == target }
      pending << target if Tiles.double?(tile)
      next_player = state[:order].rotate(state[:order].index(state[:current_player]) + 1).find { |p| active_players(state).include?(p) }
      if next_player && state[:hands][next_player].length <= 2 && !Tiles.double?(tile)
        void = state[:voids].fetch(next_player, [])
        exposed = if pending.empty?
          [state[:trains]["m"][:end], state[:trains][train_id(state, next_player)][:end], ending].uniq
        else
          [pending.last == target ? ending : state[:trains][pending.last][:end]]
        end
        score += 25 if exposed.all? { |value| void.include?(value) }
        score -= 6 if target == "m" && exposed.any? { |value| !void.include?(value) }
      end
      if state[:stock].empty? && !Tiles.double?(tile) && connected == 0
        # A conservative possible-block estimate from public passes only.
        # Include closed personal ends: failed players may open them before
        # a complete circuit, potentially making the position playable again.
        all_ends = state[:trains].map { |key, train| key == target ? ending : train[:end] }.uniq
        exposed = pending.empty? ? all_ends : [state[:trains][pending.last][:end]]
        peers = active_players(state).reject { |p| same_user?(p, actor) }
        if peers.all? { |p| (exposed - state[:voids].fetch(p, [])).empty? }
          score += [20 - hand_points(rest) * 2, -60].max
        end
      end
      score
    end

    def rule_sections
      generated_rule_sections
    end

    def surface_spec(replay, viewer)
      spec = super
      state = replay.state
      own = train_id(state, viewer)
      targets = [own, "m", *state[:trains].keys].uniq.select { |key| state[:trains].key?(key) }
      spec.zones.first.cards.each do |tile|
        tile.choices = targets.map do |target|
          GameSurfaces::TileChoice.new(id: target, label: target_label(state, target),
            value: command("play", tile: tile.id, target: target))
        end
      end
      spec.selection_error = ->(tile, target) { destination_error(state, viewer, tile, target) }
      spec
    end

    protected

    def auto_play_unique_tile?; false; end

    def destination_error(state, viewer, tile, target)
      return _("This move is not available.") unless state[:phase] == :playing &&
        same_user?(viewer, state[:current_player]) && hand(state, viewer).include?(tile)
      required = state[:pending].last unless state[:series]
      obligation = if required
        number = state[:trains].fetch(required)[:end]
        if required == "m"
          _("You must cover double %{number} on the Mexican train.") % { number: number }
        else
          _("You must cover double %{number} on %{player}'s train.") % { number: number, player: train_name(state, required) }
        end
      end
      if target == nil
        return nil if placements(state, viewer).any? { |move| move["tile"] == tile }
        return obligation + " " + _("This tile does not fit.") if obligation
        return _("This tile does not fit any train.")
      end
      return obligation if required && (target != required || !Tiles.fits?(tile, state[:trains][required][:end]))
      train = state[:trains][target]
      return _("This move is not available.") unless train
      unless accessible_trains(state, viewer).include?(target)
        return _("%{player}'s train is closed.") % { player: train_name(state, target) }
      end
      _("This tile does not fit this train.") unless Tiles.fits?(tile, train[:end])
    end

    def train_id(state, player); "p#{state[:players].index { |p| same_user?(p, player) }}"; end
    def accessible_trains(state, player)
      own_series = same_user?(state[:current_player], player) && state[:series]
      return [state[:pending].last] unless state[:pending].empty? || own_series
      own = train_id(state, player)
      [own, "m", *state[:trains].keys.reject { |key| [own, "m"].include?(key) }].select do |key|
        train = state[:trains][key]
        train && (key == own || key == "m" || train[:open])
      end
    end
    def train_name(state, target)
      return _("Mexican train") if target == "m"
      participant_name(state[:trains].fetch(target)[:owner])
    end
    def target_label(state, target)
      _("%{train}, %{value}") % { train: train_name(state, target), value: state[:trains][target][:end] }
    end
    def table_header(_state); _("Trains"); end
    def table_rows(state)
      state[:trains].map do |key, train|
        label = target_label(state, key)
        label += ", " + (train[:open] ? _("open") : _("closed")) unless key == "m"
        label += ", " + _("unfinished double") if state[:pending].include?(key)
        chain = ["#{state[:station]}–#{state[:station]}", *train[:chain].map { |item| "#{item[:left]}–#{item[:right]}" }]
        { id: key, label: label, detail: "#{train_name(state, key)}: #{chain.join(', ')}", items: chain,
          item_ids: ["station", *train[:chain].map { |item| item[:tile] }] }
      end
    end
    def public_table(state); { station: state[:station], trains: state[:trains], pending: state[:pending], series: state[:series] }; end
    def required_text(state)
      return "" if state[:pending].empty? || state[:series]
      key = state[:pending].last
      _("Cover %{double} on %{train}.") % { double: "#{state[:trains][key][:end]}–#{state[:trains][key][:end]}", train: train_name(state, key) }
    end
    def hand_points(tiles); tiles.sum { |tile| Tiles.pips(tile) == 0 ? 10 : Tiles.pips(tile) }; end

    def begin_turn(state, time)
      super
      state[:series] = false
    end

    def deal(state, data, event_id, history)
      players = active_players(state)
      station = 12 - state[:round] % 13
      deck = Tiles.deck(12).reject { |tile| tile == Tiles.tile(station, station) }
      state[:stock] = Tiles.shuffle(deck, data["seed"])
      count = players.length <= 5 ? 15 : players.length <= 7 ? 12 : 10
      state[:hands] = state[:players].to_h { |p| [p, []] }
      count.times { players.each { |p| state[:hands][p] << state[:stock].shift } }
      starter = if state[:starter]
        state[:order].rotate(state[:order].index(state[:starter]) + 1).find { |p| players.include?(p) }
      else
        players[Random.new(data["seed"].to_i(16)).rand(players.length)]
      end
      trains = players.to_h do |player|
        [train_id(state, player), { owner: player, open: false, end: station, chain: [] }]
      end
      trains["m"] = { owner: nil, open: true, end: station, chain: [] }
      state.merge!(phase: :playing, round: state[:round] + 1, station: station, trains: trains,
        pending: [], announced_obligation: nil, series: false, starter: starter, current_player: starter, blocked: 0, voids: {}, round_winner: nil)
      begin_turn(state, data["time"])
      add_history(history, event_id, starter, :deal, _("Round %{round}. Station %{station}. Tiles dealt.") % { round: state[:round], station: "#{station}–#{station}" })
    end

    def apply_move(state, data, event_id, history)
      player = state[:current_player]
      case data["action"]
      when "timeout"
        if !state[:drawn] && !state[:stock].empty?
          draw_one(state, player)
          add_history(history, event_id, player, :draw, _("%{player} draws a tile.") % { player: participant_name(player) })
        end
        # A timeout is not evidence that this player lacks a matching tile.
        pass(state, data, event_id, history, record_void: false)
      when "play"
        tile, target = data["tile"], data["target"]
        return :invalid unless state[:hands][player].include?(tile) && accessible_trains(state, player).include?(target)
        train = state[:trains][target]
        return :invalid unless Tiles.fits?(tile, train[:end])
        ending = Tiles.other(tile, train[:end])
        train[:chain] << { tile: tile, left: train[:end], right: ending }
        train[:end] = ending
        state[:pending].delete(target)
        state[:pending] << target if Tiles.double?(tile)
        state[:hands][player].delete(tile)
        closed = train[:open] && target == train_id(state, player)
        train[:open] = false if target == train_id(state, player)
        state[:blocked] = 0
        message = if target == "m"
          _("%{player} plays %{tile} on the Mexican train.") % { player: participant_name(player), tile: Tiles.label(tile) }
        elsif target == train_id(state, player)
          _("%{player} plays %{tile} on their own train.") % { player: participant_name(player), tile: Tiles.label(tile) }
        else
          _("%{player} plays %{tile} on %{owner}'s train.") % { player: participant_name(player), tile: Tiles.label(tile), owner: train_name(state, target) }
        end
        add_history(history, event_id, player, :play, message)
        add_history(history, event_id, player, :game, _("%{player}'s train is closed.") % { player: participant_name(player) }) if closed
        if state[:hands][player].empty?
          finish_round(state, player, event_id, history)
        elsif Tiles.double?(tile)
          state[:series] = true
          state[:turn] += 1 # A new decision: old retries cannot draw twice here.
          state[:drawn] = false
          state[:turn_started] = data["time"]
        else
          end_turn(state, data["time"], event_id, history)
        end
      when "draw"
        return :invalid unless can_draw?(state)
        state[:drawn] = true
        draw_one(state, player)
        state[:blocked] = 0
        add_history(history, event_id, player, :draw, _("%{player} draws a tile.") % { player: participant_name(player) })
        pass(state, data, event_id, history) if placements(state, player).empty?
      when "pass"
        pass(state, data, event_id, history)
      else return :invalid
      end
      :ok
    end

    def end_turn(state, time, event_id, history)
      next_turn(state, time)
      text = required_text(state)
      key = state[:pending].last
      obligation = key && [key, state[:trains][key][:end]]
      if obligation != state[:announced_obligation] && !text.empty?
        add_history(history, event_id, nil, :game, text)
      end
      state[:announced_obligation] = obligation
    end

    def pass(state, data, event_id, history, record_void: true)
      player = state[:current_player]
      targets = accessible_trains(state, player)
      if record_void
        state[:voids][player] = (state[:voids].fetch(player, []) + targets.map { |key| state[:trains][key][:end] }).uniq
      end
      own = state[:trains][train_id(state, player)]
      opened = !own[:open]
      own[:open] = true
      add_history(history, event_id, player, :pass, (opened ? _("%{player}'s train opens; turn passed.") : _("%{player} passes.")) % { player: participant_name(player) })
      state[:series] = false
      state[:blocked] += 1
      blocked = state[:stock].empty? && state[:blocked] >= waiting_players(state).length && waiting_players(state).all? { |p| placements(state, p).empty? }
      blocked ? finish_round(state, nil, event_id, history) : end_turn(state, data["time"], event_id, history)
    end
  end
end

require_relative 'generated/rulebooks/mexican_train'
