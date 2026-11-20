require_relative "../lib/rummy_planner"

module GameRoomGames
  class Rummy
    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def bot_observation(replay, actor)
      state = replay.state
      { "hand" => hand(state, actor).dup, "melds" => copy_state(state[:melds]),
        "discard" => state[:discard].dup, "stock_count" => state[:stock].length,
        "hand_counts" => state[:hands].transform_values(&:length),
        "scores" => state[:scores].dup, "options" => state[:options].dup,
        "current_player" => state[:current_player], "debts" => state[:debts].dup }
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if replay.finished? || state[:phase] != :playing || !same_user?(state[:current_player], actor)
      return [] if deadline_reached?(state, context&.now)
      player = state[:current_player]
      cards = hand(state, player)
      actions = []
      unless state[:drawn] || state[:acted]
        actions << command("draw", depth: 0) if !state[:stock].empty? || state[:discard].length > 1
        if state[:first_meld][player] && %w[single multiple].include?(state[:options]["discard_mode"])
          count = state[:options]["discard_mode"] == "single" ? [state[:discard].length, 1].min : state[:discard].length
          1.upto(count) { |depth| actions << command("draw", depth: depth) }
        end
      end
      return actions unless ready?(state)
      plans = hand_plans(state, cards)
      plans.each { |plan| actions << command("meld", groups: plan[:groups]) }
      cards.each do |card|
        additions_for(state, card).each do |item|
          actions << command("add", card: card, target: item[:target], mode: item[:mode].to_s)
        end
      end
      if manipulation_allowed?(state)
        state[:melds].each do |meld|
          actions << command("take", target: meld[:id]) unless meld[:cards].any? { |c| Rules.joker?(c) }
          Rules.removable(meld, identities: state[:options]["identities"]).each { |i| actions << command("take", target: meld[:id], card: i[:card]) }
          state[:melds].each do |other|
            next if other[:id] == meld[:id]
            merged = Rules.validate(meld[:cards] + other[:cards], identities: state[:options]["identities"])
            next unless merged && Rules.preserves_joker?(meld, merged) && Rules.preserves_joker?(other, merged)
            actions << command("merge", target: meld[:id], second: other[:id])
          end
        end
      end
      if state[:options]["discard_mode"] == "none"
        actions << command("end")
      else
        cards.each { |card| actions << command("discard", card: card) }
      end
      actions
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      cards = hand(state, actor)
      rounded = state[:options]["rounded"]
      case action["action"]
      when "meld"
        preview = meld_preview(action["groups"], state)
        return -100_000 unless preview
        used = action["groups"].flatten
        debt_gain = GameRoomRummyPlanner.repaid(used, state[:debts]) * 2000
        finish = used.length == cards.length ? 50_000 : 0
        return finish + debt_gain + used.length * 100 + preview[:points] unless await_rummy?(state, actor, cards)
        -100 # A bounded strategic hold, never used near an opponent's finish.
      when "add"
        item = additions_for(state, action["card"]).find { |i| i[:target] == action["target"] && i[:mode].to_s == action["mode"] }
        return -100_000 unless item
        if item[:mode] == :recover
          projected = cards.reject { |c| c == action["card"] } + [item[:joker]]
          plan = hand_plans(state, projected, debts: state[:debts] + ["X"]).first
          return -100_000 unless plan && plan[:cards].include?(item[:joker])
          return 150 + plan[:cards].length * 70
        end
        return 50_000 if cards.one?
        debt_gain = state[:debts].include?(Rules.face(action["card"])) ? 2000 : 0
        # Prefer a multi-card meld over breaking it to lay off a single card.
        return 110 + debt_gain + Rules.hand_value(action["card"], rounded: rounded)
      when "take"
        # A borrowed group must improve the original hand and pay every debt.
        # Limit expensive projections to a few promising physical candidates.
        return -100_000 if state[:borrowed_this_turn] || !state[:debts].empty?
        meld = state[:melds].find { |m| m[:id] == action["target"] }
        return -100_000 unless meld
        borrowed = action["card"] ? [action["card"]] : meld[:cards]
        return -100_000 if borrowed.none? { |c| GameRoomRummyPlanner.card_usefulness(c, cards + [c]) >= 6 }
        @take_probes ||= {}
        cache_key = [state[:round], state[:turn], cards, state[:melds]]
        if @take_probe_key != cache_key
          @take_probe_key = copy_state(cache_key)
          @take_probes = {}
        end
        key = [action["target"], action["card"]]
        return @take_probes[key] if @take_probes.key?(key)
        return -100_000 if @take_probes.length >= 8
        debts = borrowed.map { |c| Rules.face(c) }
        plan = hand_plans(state, cards + borrowed, debts: debts).find do |p|
          GameRoomRummyPlanner.repaid(p[:cards], debts) == debts.length && !(p[:cards] & cards).empty?
        end
        direct = cards.select { |card| additions_for(state, card).any? { |item| item[:mode] == :extend } }
        already_playable = ((hand_plans(state, cards).first&.fetch(:cards, []) || []) + direct).uniq.length
        gained = plan ? (plan[:cards] & cards).length : 0
        # Restoring the same borrowed meld next to an unrelated own meld is
        # not an improvement. Borrow only when it unlocks extra cards.
        @take_probes[key] = gained > already_playable ? 90 + gained * 80 : -100_000
      when "merge"
        -100_000 # Rearranging alone sheds no card; don't make pointless loops.
      when "draw"
        depth = action["depth"].to_i
        return 1 if depth == 0
        # Inspect only public discards, never the hidden draw pile.
        packet = state[:discard].last(depth).reverse
        return -20_000 if depth > 12
        before = hand_plans(state, cards).first
        after = hand_plans(state, cards + packet).first
        new_used = (after && after[:cards].length || 0) - (before && before[:cards].length || 0)
        valuable = packet.sum { |c| GameRoomRummyPlanner.card_usefulness(c, cards + packet) }
        new_used * 30 + valuable - depth * 45
      when "discard"
        card = action["card"]
        return 50_000 if cards.one? && state[:debts].empty?
        utility = GameRoomRummyPlanner.card_usefulness(card, cards)
        # Public meld ends reveal immediate opportunities for an opponent.
        danger = state[:melds].count { |m| !Rules.additions(m, card, identities: state[:options]["identities"]).empty? } * 5
        if await_rummy?(state, actor, cards)
          utility += 100 if hand_plans(state, cards).first[:cards].include?(card)
        end
        danger *= 3 if active_players(state).any? { |p| !same_user?(p, actor) && hand(state, p).length <= 2 }
        weight = state[:options]["elimination"] ? 2 : 1
        Rules.hand_value(card, rounded: rounded) * weight - utility - danger - 50
      when "end" then -100
      else -100_000
      end
    end

    protected

    def await_rummy?(state, actor, cards)
      return false if state[:options]["elimination"] || state[:first_meld][actor] || cards.length < 6
      return false if state[:scores][actor] >= state[:options]["score_limit"] - 200
      return false if active_players(state).any? { |p| !same_user?(p, actor) && hand(state, p).length < 6 }
      plan = hand_plans(state, cards).first
      # At most one draw away from an all-at-once finish; with one leftover
      # and a discard mode there is already a certain finish, so never wait.
      leftover = plan ? cards.length - plan[:cards].length : cards.length
      leftover == 2 && state[:options]["discard_mode"] != "none"
    end

    def hand_plans(state, cards, debts: state[:debts])
      minimum = state[:first_meld][state[:current_player]] ? 0 : state[:options]["first_meld"]
      key = Marshal.dump([cards, state[:options]["identities"], state[:options]["rounded"], minimum, debts])
      @rummy_plans ||= {}
      @rummy_plans.clear if @rummy_plans.length >= 32
      @rummy_plans[key] ||= GameRoomRummyPlanner.plans(cards,
        identities: state[:options]["identities"], rounded: state[:options]["rounded"], minimum: minimum, debts: debts)
    end
  end
end
