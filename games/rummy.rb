# encoding: UTF-8
require_relative "card_game"
require_relative "../lib/game_round_cues"
require_relative "../lib/game_action_payload"
require_relative "../lib/rummy_rules"
require_relative "../lib/game_bots"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Rummy < CardGame
    include PublicHistoryAnnouncements
    Rules = GameRoomRummyRules
    DISCARDS = [
      OptionChoice.new(value: "none", label: _("No discard pile")),
      OptionChoice.new(value: "discard", label: _("Discarding without taking discards")),
      OptionChoice.new(value: "single", label: _("Take the top discard")),
      OptionChoice.new(value: "multiple", label: _("Take a discard and all cards above it"))
    ].freeze

    def id; "rummy"; end
    def notification_option_keys(_options); %w[elimination manipulation]; end
    def notification_variant(options)
      [notification_flag(options, "elimination", _("Elimination mode"), _("Normal scoring")),
        notification_flag(options, "manipulation", _("with combination manipulation"), _("without combination manipulation"))].compact.join(", ")
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      GameRoomRoundCues.for_event(history, after_replay, viewer, assets: %w[shuffle draw play])
    end
    def eliminated_from_game?(replay, viewer)
      replay.state.fetch(:eliminated, {}).any? { |player, out| out && same_user?(player, viewer) }
    end

    def name; _("Rummy"); end

    def short_description
      _("Make scoring combinations of cards and add to those on the table, trying to empty your hand first.")
    end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def thinking_time_range; 20..600; end

    def option_definitions
      [
        OptionDefinition.new(key: "discard_mode", label: _("Discard mode"), kind: :choice, default: "single", choices: DISCARDS),
        OptionDefinition.new(key: "elimination", label: _("Elimination mode — fewer points is better"), kind: :boolean, default: false),
        OptionDefinition.new(key: "rounded", label: _("Round card values to five-point units"), kind: :boolean, default: true),
        OptionDefinition.new(key: "manipulation", label: _("Combination manipulation — take and rearrange melds"), kind: :boolean, default: false),
        OptionDefinition.new(key: "identities", label: _("Identities — identical cards may form a meld"), kind: :boolean, default: false),
        OptionDefinition.new(key: "first_meld", label: _("First meld minimum score"), kind: :integer, default: 30),
        OptionDefinition.new(key: "score_limit", label: _("Score limit"), kind: :integer, default: 1000),
        thinking_time_option
      ]
    end

    def normalize_options(values)
      result = super
      if result["elimination"] && !(values.respond_to?(:key?) && (values.key?("score_limit") || values.key?(:score_limit)))
        result["score_limit"] = 500
      end
      result
    end

    def options_error(options, player_count: nil)
      options = normalize_options(options)
      return _("The first meld minimum must be from 15 to 90.") unless options["first_meld"].between?(15, 90)
      return _("The score limit must be a positive number, at most 100000.") unless options["score_limit"].between?(1, 100_000)
      return thinking_time_options_error(options) if thinking_time_options_error(options)
      nil
    end

    def option_editor_changes(previous, current)
      return {} if previous["elimination"] == current["elimination"]
      old_default = previous["elimination"] ? 500 : 1000
      current["score_limit"] == old_default ? { "score_limit" => current["elimination"] ? 500 : 1000 } : {}
    end

    def initial_state(players, options)
      { players: players.dup, options: options, phase: :awaiting_deal, round: 0,
        turn: 0, current_player: nil, scores: players.to_h { |p| [p, 0] },
        eliminated: {}, hands: players.to_h { |p| [p, []] }, melds: [],
        stock: [], discard: [], first_meld: {}, winner: nil, draw: false,
        winners: [], debts: [], drawn: false, acted: false, next_meld_id: 1,
        blocked_turns: 0, turn_deadline: 0 }
    end

    def replay(session, events, repository)
      state = initial_state(repository.players_for(session), options_from_json(session["options"]))
      accepted = []
      history = [starting_history(state[:players])]
      seen = {}
      GameRoomActionPayload.each(events, "rummy", repository, session) do |data, actor, batch|
        next if state[:phase] == :finished || batch.any? { |e| seen[repository.event_id(e)] }
        copy = copy_state(state)
        additions = []
        event_id = repository.event_id(batch.last)
        next unless apply(copy, data, actor, event_id, additions) == :ok
        record_deck_reshuffle(additions, state[:recycle], copy[:recycle], event_id)
        state = copy
        history.concat(additions)
        accepted.concat(batch)
        batch.each { |e| seen[repository.event_id(e)] = true }
      end
      GameRoomSessionClock.attach(state, session)
      Replay.new(board: nil, players: state[:players], current_player: state[:current_player],
        winner: state[:winner], draw: state[:draw], accepted_events: accepted, history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      data = selection.to_h.transform_keys(&:to_s)
      # A hand choice contains an action descriptor, not a trusted move.
      if data["kind"] == "card" && data["card"].to_s.start_with?("{")
        data = JSON.parse(data["card"])
      end
      data = data.select { |key, _| %w[action card target mode groups second depth].include?(key) }
      %w[groups].each { |key| data[key] = JSON.parse(data[key]) if data[key].is_a?(String) }
      data["round"] = replay.state[:round]
      data["turn"] = replay.state[:turn]
      data["time"] = (context&.now || GameRoomSessionClock.for_state(replay.state)).to_i
      if data["action"] == "deal"
        return [:invalid, nil] unless context&.random_source
        data["seed"] = card_seed(context.random_source)
      end
      status = apply(copy_state(replay.state), data, actor, 0, [])
      return [status, nil] unless status == :ok
      [:ok, ActionPlan.new(events: GameRoomActionPayload.commands("rummy", data))]
    rescue JSON::ParserError, TypeError
      [:invalid, nil]
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      state = replay.state
      return command("deal") if [:awaiting_deal, :round_complete].include?(state[:phase])
      return command("timeout") if deadline_reached?(state, context&.now)
      nil
    end

    def automatic_action_due?(replay, actor, context: nil)
      same_user?(actor, replay.players.first) && deadline_reached?(replay.state, context&.now)
    end

    def bot_delay_revision(replay, _revision)
      [replay.state[:round], replay.state[:turn]]
    end

    def participant_scores(replay); replay.state[:scores].dup; end

    def participant_status(replay, participant, connected: true)
      return _("eliminated") if replay.state[:eliminated].keys.any? { |p| same_user?(p, participant) }
      super
    end

    def save_game_error(replay)
      error = super
      return error if error
      state = replay.state
      return _("Save Rummy at the beginning of a turn, before drawing or manipulating cards.") if state[:drawn] || state[:acted] || !state[:debts].empty?
      nil
    end

    def result_text(replay)
      return _("Shared victory: %{players}.") % { players: replay.state[:winners].map { |p| participant_name(p) }.join(", ") } if replay.state[:winners].length > 1
      super
    end

    def move_error(status)
      return _("The prepared melds do not reach the first meld minimum.") if status == :first_meld_too_small
      super
    end

    def hand(state, actor)
      player = state[:players].find { |p| same_user?(p, actor) }
      state[:hands].fetch(player, [])
    end

    def ready?(state)
      state[:drawn] || !draw_possible?(state)
    end

    def draw_possible?(state)
      !state[:stock].empty? || state[:discard].length > 1 ||
        (state[:first_meld][state[:current_player]] && %w[single multiple].include?(state[:options]["discard_mode"]) && !state[:discard].empty?)
    end

    def additions_for(state, card)
      return [] unless state[:phase] == :playing && ready?(state) && state[:first_meld][state[:current_player]]
      state[:melds].flat_map do |meld|
        Rules.additions(meld, card, identities: state[:options]["identities"]).map { |item| item.merge(target: meld[:id]) }
      end
    end

    def meld_preview(groups, state)
      return nil unless groups.is_a?(Array) && !groups.empty? && groups.length <= 72
      all = groups.flatten
      return nil unless all.length <= 216 && all.uniq.length == all.length
      return nil unless all.all? { |card| hand(state, state[:current_player]).include?(card) }
      melds = groups.map { |cards| Rules.validate(cards, identities: state[:options]["identities"]) }
      return nil if melds.any?(&:nil?)
      points = melds.sum { |meld| Rules.points(meld, rounded: state[:options]["rounded"]) }
      { melds: melds, points: points }
    end

    protected

    def copy_state(value)
      case value
      when Hash then value.to_h { |key, item| [key, copy_state(item)] }
      when Array then value.map { |item| copy_state(item) }
      else value
      end
    end

    def active_players(state)
      state[:players].reject { |p| state[:eliminated][p] }
    end

    def command(action, **extra)
      { "kind" => "command", "action" => action }.merge(extra.transform_keys(&:to_s))
    end

    def deadline_reached?(state, now)
      state[:phase] == :playing && state[:turn_deadline].to_i > 0 && now != nil && now.to_i >= state[:turn_deadline]
    end

    def add_history(history, id, actor, kind, text, value = nil)
      history << HistoryEntry.new(key: "rummy:#{id}:#{history.length}", text: text,
        event_id: id, actor: actor, kind: kind, value: value)
    end

    def apply(state, data, actor, id, history)
      return :invalid unless data["round"] == state[:round] && data["turn"] == state[:turn]
      return :invalid unless data["time"].is_a?(Integer) && data["time"] >= 0
      if data["action"] == "deal"
        return :not_your_turn unless same_user?(actor, state[:players].first)
        return :invalid unless [:awaiting_deal, :round_complete].include?(state[:phase]) && /\A[0-9a-f]{32}\z/.match?(data["seed"].to_s)
        deal(state, data, id, history)
        return :ok
      end
      return :invalid unless state[:phase] == :playing
      if data["action"] == "timeout"
        return :not_your_turn unless same_user?(actor, state[:players].first)
        return :invalid unless deadline_reached?(state, data["time"])
        player = state[:current_player]
        penalty(state, player, 50)
        add_history(history, id, player, :game, _("%{player}'s time expired. 50 penalty points.") % { player: participant_name(player) })
        if !state[:drawn] && draw_stock(state, player)
          add_history(history, id, player, :draw, _("%{player} draws a card.") % { player: participant_name(player) })
        end
        end_turn(state, data, id, history)
        return :ok
      end
      return :not_your_turn unless same_user?(actor, state[:current_player])
      return :invalid if deadline_reached?(state, data["time"])
      player = state[:current_player]
      before_count = state[:hands][player].length
      result = case data["action"]
      when "draw" then apply_draw(state, data, player, id, history)
      when "meld" then apply_meld(state, data, player, id, history)
      when "add" then apply_add(state, data, player, id, history)
      when "take" then apply_take(state, data, player, id, history)
      when "merge" then apply_merge(state, data, player, id, history)
      when "discard"
        if ready?(state) && state[:options]["discard_mode"] != "none" && state[:hands][player].include?(data["card"])
          state[:hands][player].delete(data["card"])
          state[:discard] << data["card"]
          add_history(history, id, player, :play, _("%{player} discards %{card}.") % { player: participant_name(player), card: playing_card_label(data["card"]) })
          end_turn(state, data, id, history)
          :ok
        else :invalid
        end
      when "end"
        if ready?(state) && state[:options]["discard_mode"] == "none"
          end_turn(state, data, id, history)
          :ok
        else :invalid
        end
      else :invalid
      end
      return result unless result == :ok
      if state[:hands][player].empty? && state[:phase] == :playing
        settle_debts(state, player, id, history)
        finish_round(state, player, id, history)
      end
      count = state[:hands][player].length
      if count.between?(1, 3) && count != before_count
        add_history(history, id, player, :game, n_("%{player} has %{count} card.", "%{player} has %{count} cards.", count) % { player: participant_name(player), count: count })
      end
      :ok
    end

    def deal(state, data, id, history)
      players = active_players(state)
      copies = state[:options]["identities"] ? 4 : players.length <= 4 ? 2 : players.length <= 6 ? 3 : 4
      state[:stock] = shuffled_cards(Rules.deck(copies), data["seed"])
      state[:hands] = state[:players].to_h { |p| [p, []] }
      14.times { players.each { |p| state[:hands][p] << state[:stock].shift } }
      previous = state[:starter]
      index = previous ? state[:players].index(previous) : -1
      begin
        index = (index + 1) % state[:players].length
      end until players.include?(state[:players][index])
      state.merge!(starter: state[:players][index], current_player: state[:players][index],
        discard: [], melds: [], first_meld: {}, meld_turn: {}, first_pure: {},
        phase: :playing, round: state[:round] + 1, seed: data["seed"], recycle: 0,
        blocked_turns: 0, next_meld_id: 1, borrowed_this_turn: false, used_other_meld: false)
      begin_turn(state, data["time"])
      add_history(history, id, state[:current_player], :deal, _("Round %{round}. Cards dealt.") % { round: state[:round] })
    end

    def begin_turn(state, time)
      state[:turn] += 1
      state[:drawn] = false
      state[:acted] = false
      state[:debts] = []
      state[:borrowed_this_turn] = false
      state[:used_other_meld] = false
      state[:turn_initial_hand] = state[:hands][state[:current_player]].dup
      duration = state[:options]["thinking_time"].to_i
      state[:turn_deadline] = duration > 0 ? time + duration : 0
    end

    def recycle(state)
      return unless state[:stock].empty? && state[:discard].length > 1
      top = state[:discard].pop
      state[:recycle] += 1
      state[:stock] = shuffled_cards(state[:discard], "#{state[:seed]}:#{state[:recycle]}")
      state[:discard] = [top]
    end

    def draw_stock(state, player)
      recycle(state)
      card = state[:stock].shift
      return nil unless card
      state[:hands][player] << card
      state[:drawn] = true
      state[:blocked_turns] = 0
      card
    end

    def apply_draw(state, data, player, id, history)
      return :invalid if state[:drawn] || state[:acted]
      depth = data.fetch("depth", 0)
      return :invalid unless depth.is_a?(Integer) && depth >= 0
      if depth == 0
        return :invalid unless draw_stock(state, player)
        text = _("%{player} draws a card.") % { player: participant_name(player) }
      else
        mode = state[:options]["discard_mode"]
        return :invalid unless state[:first_meld][player] && (mode == "multiple" || mode == "single" && depth == 1)
        return :invalid if depth > state[:discard].length
        depth.times { state[:hands][player] << state[:discard].pop }
        state[:drawn] = true
        state[:blocked_turns] = 0
        text = n_("%{player} takes %{count} discard.", "%{player} takes %{count} discards.", depth) % { player: participant_name(player), count: depth }
      end
      add_history(history, id, player, :draw, text)
      :ok
    end

    def apply_meld(state, data, player, id, history)
      return :invalid unless ready?(state)
      preview = meld_preview(data["groups"], state)
      return :invalid unless preview
      if !state[:first_meld][player] && preview[:points] < state[:options]["first_meld"]
        return :first_meld_too_small
      end
      unless state[:first_meld][player]
        state[:first_meld][player] = true
        state[:meld_turn][player] = state[:turn]
      end
      preview[:melds].each do |meld|
        meld[:id] = state[:next_meld_id]
        state[:next_meld_id] += 1
        state[:melds] << meld
        meld[:cards].each { |card| state[:hands][player].delete(card); repay(state, card) }
        score(state, player, Rules.points(meld, rounded: state[:options]["rounded"]))
        add_history(history, id, player, :play, _("%{player} creates meld %{number}: %{cards}.") % { player: participant_name(player), number: meld[:id], cards: meld[:cards].map { |c| playing_card_label(c) }.join(", ") })
      end
      state[:acted] = true
      :ok
    end

    def apply_add(state, data, player, id, history)
      card = data["card"]
      return :invalid unless state[:hands][player].include?(card)
      item = additions_for(state, card).find { |i| i[:target] == data["target"] && i[:mode].to_s == data["mode"].to_s }
      return :invalid unless item
      index = state[:melds].index { |m| m[:id] == item[:target] }
      old = state[:melds][index]
      replacement = item[:meld].merge(id: old[:id])
      state[:melds][index] = replacement
      state[:hands][player].delete(card)
      repay(state, card)
      delta = Rules.points(replacement, rounded: state[:options]["rounded"]) - Rules.points(old, rounded: state[:options]["rounded"])
      score(state, player, delta)
      if item[:mode] == :recover
        state[:hands][player] << item[:joker]
        state[:debts] << Rules.face(item[:joker])
        state[:borrowed_this_turn] = true
        text = _("%{player} exchanges %{card} for the joker in meld %{number}.") % { player: participant_name(player), card: playing_card_label(card), number: old[:id] }
      else
        text = _("%{player} lays off %{card} on meld %{number}.") % { player: participant_name(player), card: playing_card_label(card), number: old[:id] }
      end
      state[:acted] = state[:used_other_meld] = true
      add_history(history, id, player, :play, text)
      :ok
    end

    def manipulation_allowed?(state)
      ready?(state) && state[:options]["manipulation"] && state[:first_meld][state[:current_player]]
    end

    def apply_take(state, data, player, id, history)
      return :invalid unless manipulation_allowed?(state)
      meld = state[:melds].find { |m| m[:id] == data["target"] }
      return :invalid unless meld
      card = data["card"]
      if card
        item = Rules.removable(meld, identities: state[:options]["identities"]).find { |i| i[:card] == card }
        return :invalid unless item
        borrowed = [card]
        cost = Rules.values(meld, rounded: state[:options]["rounded"])[item[:index]]
        state[:melds][state[:melds].index(meld)] = item[:meld].merge(id: meld[:id])
      else
        return :invalid if meld[:cards].any? { |c| Rules.joker?(c) }
        borrowed = meld[:cards].dup
        cost = Rules.points(meld, rounded: state[:options]["rounded"])
        state[:melds].delete(meld)
      end
      state[:hands][player].concat(borrowed)
      state[:debts].concat(borrowed.map { |c| Rules.face(c) })
      state[:acted] = state[:borrowed_this_turn] = true
      score(state, player, -cost)
      add_history(history, id, player, :game, _("%{player} takes %{cards} from meld %{number}.") % { player: participant_name(player), number: meld[:id], cards: borrowed.map { |c| playing_card_label(c) }.join(", ") })
      :ok
    end

    def apply_merge(state, data, player, id, history)
      return :invalid unless manipulation_allowed?(state) && data["target"] != data["second"]
      first = state[:melds].find { |m| m[:id] == data["target"] }
      second = state[:melds].find { |m| m[:id] == data["second"] }
      return :invalid unless first && second
      replacement = Rules.validate(first[:cards] + second[:cards], identities: state[:options]["identities"])
      return :invalid unless replacement && Rules.preserves_joker?(first, replacement) && Rules.preserves_joker?(second, replacement)
      state[:melds][state[:melds].index(first)] = replacement.merge(id: first[:id])
      state[:melds].delete(second)
      state[:acted] = true
      add_history(history, id, player, :game, _("%{player} merges melds %{first} and %{second}.") % { player: participant_name(player), first: first[:id], second: second[:id] })
      :ok
    end

    def score(state, player, points)
      state[:scores][player] += points unless state[:options]["elimination"]
    end

    def penalty(state, player, points)
      state[:scores][player] += state[:options]["elimination"] ? points : -points
    end

    def repay(state, card)
      index = state[:debts].index(Rules.face(card))
      state[:debts].delete_at(index) if index
    end

    def settle_debts(state, player, id, history)
      points = state[:debts].length * 300
      return if points == 0
      penalty(state, player, points)
      state[:debts] = []
      add_history(history, id, player, :score, _("%{player}: %{points} penalty points for cards not returned to the table.") % { player: participant_name(player), points: points })
    end

    def end_turn(state, data, id, history)
      player = state[:current_player]
      settle_debts(state, player, id, history)
      if state[:hands][player].empty?
        finish_round(state, player, id, history)
        return
      end
      on_table = state[:melds].flat_map { |m| m[:cards] }
      progress = state[:drawn] || !(state[:turn_initial_hand] & on_table).empty?
      state[:blocked_turns] = progress ? 0 : state[:blocked_turns] + 1
      players = active_players(state)
      if !draw_possible?(state) && state[:blocked_turns] >= 2 * players.length
        finish_round(state, nil, id, history)
        return
      end
      state[:current_player] = players[(players.index(player) + 1) % players.length]
      begin_turn(state, data["time"])
    end

    def finish_round(state, winner, id, history)
      players = active_players(state)
      elimination = state[:options]["elimination"]
      rummy = winner && state[:meld_turn][winner] == state[:turn]
      pure = rummy && !state[:borrowed_this_turn] && !state[:used_other_meld]
      alone = winner && (state[:first_meld].keys - [winner]).empty?
      multiplier = pure ? (alone ? 4 : 3) : rummy ? 2 : 1
      add_history(history, id, winner.to_s, :round_result, winner ? _("%{player} won the round.") % { player: participant_name(winner) } : _("The round is blocked."))
      if elimination
        add_history(history, id, winner, :game, _("Rummy multiplier: %{factor}.") % { factor: multiplier }) if winner && multiplier > 1
        players.each do |player|
          points = player == winner ? 0 : state[:hands][player].sum { |c| Rules.hand_value(c, rounded: state[:options]["rounded"]) } * multiplier
          state[:scores][player] += points
          add_history(history, id, player, :score, _("%{player} receives %{points} points.") % { player: participant_name(player), points: points }, points)
        end
      elsif winner
        cards = (players - [winner]).sum { |p| state[:hands][p].sum { |c| Rules.hand_value(c, rounded: state[:options]["rounded"]) } }
        bonus = (alone ? 100 : 0) + (pure ? 300 : rummy ? 200 : 0)
        state[:scores][winner] += cards + bonus
        add_history(history, id, winner, :score, _("%{player}: %{cards} points for opponents' cards and %{bonus} bonus points.") % { player: participant_name(winner), cards: cards, bonus: bonus })
      end
      unless elimination
        players.each do |player|
          add_history(history, id, player, :score, _("%{player}: %{points} points in total.") % { player: participant_name(player), points: state[:scores][player] })
        end
      end
      winners = []
      limit = state[:options]["score_limit"]
      if elimination
        players.each do |player|
          next if state[:scores][player] < limit
          state[:eliminated][player] = true
          add_history(history, id, player, :game, _("%{player} is eliminated.") % { player: participant_name(player) })
        end
        remaining = active_players(state)
        winners = remaining if remaining.one?
        winners = players.select { |p| state[:scores][p] == players.map { |a| state[:scores][a] }.min } if remaining.empty?
      elsif state[:scores].values.max >= limit
        leaders = players.select { |p| state[:scores][p] == state[:scores].values.max }
        winners = leaders if leaders.one?
      end
      state[:winners] = winners
      state[:winner] = winners.one? ? winners.first : nil
      state[:draw] = winners.length > 1
      state[:phase] = winners.empty? ? :round_complete : :finished
      state[:current_player] = nil
      state[:drawn] = state[:acted] = false
      state[:turn_deadline] = 0
      unless winners.empty?
        text = winners.one? ? _("%{player} won the game.") % { player: participant_name(winners.first) } : _("Shared victory: %{players}.") % { players: winners.map { |p| participant_name(p) }.join(", ") }
        add_history(history, id, winners.first, :result, text)
      end
    end
  end
end

require_relative "rummy_bot"
require_relative "rummy_ui"
