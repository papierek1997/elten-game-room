require_relative '../../lib/game_room_localization'
require_relative '../../lib/game_snapshot'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Spades
    module BidEvaluation
      private

      # Hypothetical hands change thousands of times; their public team
      # assignment does not. Own one value-keyed snapshot, never a caller's
      # mutable options or a global assignment used by the UI.
      def bot_team_assignment(state)
        key = [state[:players], state[:options]]
        cache = @bot_team_assignment_cache
        return cache.last if cache && cache.first == key

        assignment = team_assignment(state[:options], players: state[:players])
        @bot_team_assignment_cache = [GameRoomSnapshot.copy(key), assignment]
        assignment
      end

      def bidding_bot_features(state, actor, action)
        bid = selection_value(action, "bid")
        maximum = cards_per_player(state[:players].length)
        estimate = estimated_bot_bid(state, actor)
        # The mean hand estimate is useful during play, but a contract should
        # also survive an opponent deliberately attacking it. In a three-player
        # game, two or fewer spades and several long side suits make clustered
        # K/Q/J honors especially fragile: an opponent can become void and ruff
        # them. Keep the calibrated mean intact and apply only a small bidding
        # reserve for that specific shape.
        bid_target = estimate - estimated_contract_safety_reserve(state, actor)
        difference = (bid - bid_target) / [maximum, 1].max.to_f
        hand = hand_for(state, actor).to_a
        suit_lengths = SUITS.each_with_object({}) do |suit, result|
          result[suit] = hand.count { |card| card_suit(card) == suit }
        end
        certain = estimated_certain_tricks(state, actor)
        certain_difference = (bid - certain) / [maximum, 1].max.to_f
        bid_ratio = bid.to_f / [maximum, 1].max
        table_projection = bot_table_bid_projection(state, actor, bid)
        remaining_bidders = table_projection[:remaining_bidders]
        table_target = table_projection[:target]
        projected_table_bid = table_projection[:projected]
        table_difference = (projected_table_bid - table_target) / [maximum, 1].max.to_f
        assignment = bot_team_assignment(state)
        known_team_bids = if assignment == nil
          0
        else
          assignment.teammates_for(actor).reject { |player| same_user?(player, actor) }.sum do |player|
            state[:bids].fetch(player, 0).to_i
          end
        end
        score = bot_score_context(state, actor)
        nil_risk = estimated_nil_risk(state, actor)
        {
          "distance" => -difference.abs,
          "overbid" => -[difference, 0.0].max,
          "underbid" => -[-difference, 0.0].max,
          "nil_safety" => bid == 0 ? [[(2.0 - estimate) / 2.0, -1.0].max, 1.0].min : 0.0,
          "contract_size" => bid_ratio,
          "certain_tricks" => -certain_difference.abs,
          "nil_risk" => bid == 0 ? nil_risk : 0.0,
          "void_value" => suit_lengths.count { |_suit, length| length == 0 }.to_f / 3.0 * bid_ratio,
          "trump_length" => suit_lengths["S"].to_f / [maximum, 1].max * bid_ratio,
          "team_bid_balance" => assignment == nil ? 0.0 : -[known_team_bids + bid - maximum, 0].max.to_f / [maximum, 1].max,
          "table_bid_balance" => -table_difference.abs,
          "table_underbid_pressure" => -[-table_difference, 0.0].max,
          "table_overbid_pressure" => -[table_difference, 0.0].max,
          "last_bid_table_balance" => remaining_bidders == 0 ? -table_difference.abs : 0.0,
          "trailing_aggression" => [score[:deficit], 0.0].max * bid_ratio,
          "leading_caution" => [-score[:deficit], 0.0].max * bid_ratio,
          "bag_pressure_bid" => state[:options]["quicksand"] == true ? 0.0 : score[:bags].to_f / 9.0 * bid_ratio,
          "quicksand_precision" => state[:options]["quicksand"] == true ? -difference.abs : 0.0
        }
      end

      # Policy profiles may retain different learned weights, but deliberately
      # overloading the table is a rule-level tactical risk shared by every
      # Spades variant. Keep this small fixed adjustment outside those weights so
      # the same obvious correction is not trained independently for every
      # player count, partnership layout and scoring style.
      def bot_policy_score_adjustment(state, actor, action, context = nil)
        if state[:phase] == :playing
          return bot_nil_safety_score_adjustment(state, actor, action, context) +
            bot_opponent_bag_pressure_score_adjustment(state, actor, action) +
            bot_last_seat_winner_conservation_score_adjustment(state, actor, action) +
            bot_future_control_conservation_score_adjustment(state, actor, action, context) +
            bot_expiring_control_score_adjustment(state, actor, action, context) +
            bot_match_defense_score_adjustment(state, actor, action, context) +
            bot_partner_nil_risk_adjustment(action, context)
        end
        return 0.0 if state[:phase] != :bidding

        bid = selection_value(action, "bid")
        projection = bot_table_bid_projection(state, actor, bid)
        overflow = [projection[:projected] - projection[:target], 0.0].max
        -overflow * 0.85 + bot_nil_bid_context_score_adjustment(state, actor, bid) +
          bot_certain_trick_nil_score_adjustment(state, actor, bid) +
          bot_bid_threat_score_adjustment(bid, context) +
          bot_match_closing_bid_score_adjustment(state, actor, bid, context)
      end

      def bot_partner_nil_risk_adjustment(action, context)
        plan = context.is_a?(Hash) ? context[:round_plan] : nil
        risks = plan.is_a?(Hash) ? plan.fetch(:partner_nil_risks, {}) : {}
        return 0.0 unless risks.length > 1
        extra = risks.fetch(action["card"].to_s, 0.0) - risks.values.min
        # Preserve control when the difference is tiny/uncertain. A concrete
        # avoidable danger to nil weighs more than a generic saved-honour bonus.
        extra >= 0.25 ? -60.0 * extra : 0.0
      end

      # A complete-round rollout is still heuristic while most cards remain in
      # hand. In particular it can count the same fragile side-suit expectation
      # as though every opponent would cooperate with the contract. This compact
      # audit starts at the rollout's preferred bid and asks whether each of its
      # last tricks depends on an exposed honor or unsupported weak trump. When
      # two independent hazards overlap, the fallback bid is audited as well;
      # this prevents rejecting six only to accept an equally fragile five. The
      # calibrated mean hand estimate remains unchanged.
      def bot_bid_threat_context(state, actor, round_plan)
        raw_scores = round_plan.is_a?(Hash) ? round_plan.fetch(:raw_scores, {}) : {}
        planned_entry = raw_scores.max_by { |bid, score| [score.to_f, -bid.to_i] }
        planned_bid = planned_entry == nil ? 0 : planned_entry.first.to_i
        return empty_bid_threat_context if planned_bid < 2

        hand = hand_for(state, actor).to_a
        estimate = estimated_bot_bid(state, actor)
        certain = estimated_certain_tricks(state, actor).to_f
        reliance = [estimate - certain, 0.0].max
        spades = hand.count { |card| card_suit(card) == "S" }
        long_side_suits = SUITS.reject { |suit| suit == "S" }.count do |suit|
          hand.count { |card| card_suit(card) == suit } >= 5
        end

        ruff_exposure = exact_bid_ruff_exposure(state, actor)
        weak_trump = bid_weak_trump_pressure(state, actor, spades, reliance)
        correlated_shape = reliance >= 1.5 && long_side_suits > 0 ? 0.15 : 0.0
        shape_pressure = ruff_exposure + weak_trump + correlated_shape
        # Each distinct exact hazard can invalidate one marginal trick. Recheck
        # that many consecutive declarations instead of attaching the entire
        # correction only to the rollout winner. Correlated shape and table load
        # amplify a hazard but do not manufacture extra rejected tricks.
        risk_depth = [
          ruff_exposure > 0.0,
          weak_trump > 0.0
        ].count(true)
        risk_depth = 1 if shape_pressure >= 0.4 && risk_depth == 0
        lowest_risky_bid = [planned_bid - risk_depth + 1, 2].max
        highest_bid = raw_scores.keys.map(&:to_i).max.to_i
        bid_pressures = {}
        if shape_pressure >= 0.4
          (lowest_risky_bid..highest_bid).each do |candidate_bid|
            table = bid_table_load_pressure(state, actor, candidate_bid)
            bid_pressures[candidate_bid] = [shape_pressure + table[:pressure], 1.0].min
          end
        end
        # Table loading is an amplifier, not an independent reason to underbid.
        # A robust hand may safely allocate the final trick. A fragile marginal
        # trick becomes more dangerous when the known bids, or a plausible pending
        # bid, leave no spare trick with which to absorb a forecasting error.
        table = bid_table_load_pressure(state, actor, planned_bid)
        {
          planned_bid: planned_bid,
          pressure: bid_pressures.fetch(planned_bid, 0.0),
          bid_pressures: bid_pressures,
          risk_depth: risk_depth,
          lowest_risky_bid: bid_pressures.empty? ? 0 : lowest_risky_bid,
          ruff_exposure: ruff_exposure,
          weak_trump: weak_trump,
          correlated_shape: correlated_shape,
          projected_bid_low: table[:low],
          projected_bid_high: table[:high],
          table_pressure: table[:pressure]
        }
      end

      def empty_bid_threat_context
        {
          planned_bid: 0,
          pressure: 0.0,
          bid_pressures: {},
          risk_depth: 0,
          lowest_risky_bid: 0,
          ruff_exposure: 0.0,
          weak_trump: 0.0,
          correlated_shape: 0.0,
          projected_bid_low: 0.0,
          projected_bid_high: 0.0,
          table_pressure: 0.0
        }
      end

      def bot_bid_threat_score_adjustment(bid, context)
        threat = context.is_a?(Hash) ? context[:bid_threat] : nil
        return 0.0 if !threat.is_a?(Hash)

        pressures = threat[:bid_pressures]
        if pressures.is_a?(Hash)
          pressure = pressures.fetch(bid.to_i, 0.0).to_f
          return -BID_THREAT_MAX_PENALTY * pressure
        end
        return 0.0 if bid.to_i < threat[:planned_bid].to_i

        -BID_THREAT_MAX_PENALTY * threat[:pressure].to_f
      end

      # If the complete-round planner projects both its preferred declaration
      # and the declaration immediately below it as match wins, keep the safer
      # contract. The bot only needs its own score and the planner's match-win
      # projection; later opponents do not have to declare first. Repeat the
      # scoring check with the extra trick expected by the original declaration,
      # preserving the higher bid whenever lowering it would create bags whose
      # penalty removes the win.
      def bot_match_closing_bid_score_adjustment(state, actor, bid, context)
        plan = context.is_a?(Hash) ? context[:round_plan] : nil
        return 0.0 if !plan.is_a?(Hash)

        raw_scores = plan.fetch(:raw_scores, {})
        planned_entry = raw_scores.max_by { |candidate, score| [score.to_f, -candidate.to_i] }
        return 0.0 if planned_entry == nil

        planned_bid = planned_entry.first.to_i
        candidate_bid = bid.to_i
        return 0.0 if candidate_bid != planned_bid || candidate_bid < 2

        lower_bid = candidate_bid - 1
        planned_score = raw_scores.fetch(candidate_bid) { raw_scores[candidate_bid.to_s] }
        lower_score = raw_scores.fetch(lower_bid) { raw_scores[lower_bid.to_s] }
        return 0.0 if planned_score == nil || lower_score == nil
        return 0.0 if planned_score.to_f < PLANNING_MATCH_LOSS_RAW_THRESHOLD ||
          lower_score.to_f < PLANNING_MATCH_LOSS_RAW_THRESHOLD
        return 0.0 if !bot_lower_bid_safely_closes_match?(
          state, actor, lower_bid, candidate_bid
        )

        -MATCH_CLOSING_BID_PENALTY
      end

      def bot_lower_bid_safely_closes_match?(state, actor, lower_bid, original_bid)
        actor_key = player_key(state, actor)
        return false if actor_key == nil

        assignment = bot_team_assignment(state)
        members = assignment == nil ? [actor_key] : assignment.teammates_for(actor_key)
        return false if members.any? do |member|
          !same_user?(member, actor_key) && state[:bids].fetch(member, -1).to_i == 0
        end

        projected_tricks = [
          original_bid.to_i,
          estimated_bot_bid(state, actor_key).ceil
        ].max
        maximum = cards_per_player(state[:players].length)
        projected_tricks = [projected_tricks, maximum].min
        unit = bot_score_context(state, actor_key)[:unit].to_s
        limit = [state[:options]["score_limit"].to_i, 1].max
        strongest_opponent = state[:scores].reject do |candidate, _score|
          candidate.to_s == unit
        end.values.map(&:to_i).max || 0
        [lower_bid.to_i, projected_tricks].uniq.all? do |won|
          projected_score = bot_projected_unit_score(
            state, actor_key, lower_bid, won, unit
          )
          projected_score >= limit && projected_score > strongest_opponent
        end
      end

      def bot_projected_unit_score(state, actor, bid, won, unit)
        bids = state[:bids].dup
        bids[player_key(state, actor)] = bid.to_i
        tricks = state[:players].each_with_object({}) do |player, result|
          player_bid = bids.fetch(player_key(state, player), 0).to_i
          result[player_key(state, player)] = player_bid == 0 ? 0 : player_bid
        end
        tricks[player_key(state, actor)] = won.to_i
        result = Scoring.new(state[:players], state[:options]).apply(
          bids: bids,
          tricks: tricks,
          scores: state[:scores]
        )
        result.scores.fetch(unit, state[:scores].fetch(unit, 0)).to_i
      end

      def exact_bid_ruff_exposure(state, actor)
        return 0.0 if !omniscient_bots?(state)

        exposure = exact_side_suit_control_profile(state, actor).values.sum do |profile|
          factor = case profile[:shortest_trump_opponent].to_i
          when 0 then 0.70
          when 1 then 0.28
          when 2 then 0.20
          else 0.10
          end
          profile[:threatened_controls].to_i * factor
        end
        [exposure, 0.85].min
      end

      def bid_weak_trump_pressure(state, actor, spades, reliance)
        return 0.0 if reliance < 1.25

        if omniscient_bots?(state)
          actor_key = player_key(state, actor)
          strongest_opponent = state[:players].reject do |player|
            same_user?(player, actor_key) || bot_state_allied?(state, actor_key, player)
          end.map do |player|
            hand_for(state, player).to_a.count { |card| card_suit(card) == "S" }
          end.max.to_i
          return 0.0 if strongest_opponent < spades + 2

          # Three or four low spades are not independent winners when a hostile
          # hand owns a substantially longer trump suit and this hand has no
          # short side suit in which to spend them. Preserve the historical rule
          # for genuinely short trump holdings, but also detect this exact
          # dominated shape without penalizing a long, top-controlled trump run.
          if spades > 2
            return 0.0 if reliance < 2.5

            top_controls = exact_top_control_cards(state, actor, "S").length
            side_lengths = SUITS.reject { |suit| suit == "S" }.map do |suit|
              hand_for(state, actor).to_a.count { |card| card_suit(card) == suit }
            end
            short_side_suits = side_lengths.count { |length| length <= 2 }
            return 0.0 if strongest_opponent < spades + 4 ||
              short_side_suits > 0 || side_lengths.max.to_i < 6

            unsupported = [spades - top_controls - short_side_suits, 0].max
            return 0.0 if unsupported < 2
          end

          spades > 2 ? 0.45 : 0.55
        else
          return 0.0 if spades > 2

          # Without private cards this remains deliberately weaker and requires
          # another signal (long-suit correlation or a loaded table) before the
          # combined threshold can affect a declaration.
          0.30
        end
      end

      def bid_table_load_pressure(state, actor, planned_bid)
        maximum = cards_per_player(state[:players].length).to_f
        target = bot_table_bid_target(state, actor)
        actor_key = player_key(state, actor)
        pending = state[:players].reject do |player|
          same_user?(player, actor_key) ||
            state[:bids].keys.any? { |bidder| same_user?(bidder, player) }
        end
        known = state[:bids].values.sum(&:to_i) + planned_bid.to_i
        ranges = pending.map do |player|
          estimate = if omniscient_bots?(state)
            estimated_bot_bid(state, player)
          else
            target / [state[:players].length, 1].max
          end
          [[estimate.floor - 1, 0].max, [estimate.ceil + 1, maximum.to_i].min]
        end
        low = known + ranges.sum { |range| range[0] }
        high = known + ranges.sum { |range| range[1] }
        pressure = if low >= maximum
          0.30
        elsif high >= maximum
          0.25
        elsif high >= target
          0.15
        else
          0.0
        end
        { low: low.to_f, high: high.to_f, pressure: pressure }
      end

      # Bidding first makes a nil intrinsically less certain because neither the
      # partner's ability to cover nor the opponents' need to take tricks is
      # known yet. Already announced bids provide modest evidence in the other
      # direction. Keep this adjustment deliberately small: hand shape and the
      # complete-round planner remain the primary nil decision makers.
      def bot_nil_bid_context_score_adjustment(state, actor, bid)
        return 0.0 if bid.to_i != 0

        players = state[:players].to_a
        actor_key = player_key(state, actor)
        return 0.0 if actor_key == nil || players.length <= 1

        announced = state[:bids].to_h.reject { |player, _value| same_user?(player, actor_key) }
        remaining = [players.length - announced.length - 1, 0].max
        adjustment = -0.6 * remaining.to_f / (players.length - 1)
        maximum = [cards_per_player(players.length), 1].max.to_f
        expected = maximum / players.length
        assignment = bot_team_assignment(state)
        teammates = if assignment == nil
          []
        else
          assignment.teammates_for(actor_key).reject { |player| same_user?(player, actor_key) }
        end
        opponents = players.reject do |player|
          same_user?(player, actor_key) || teammates.any? { |teammate| same_user?(teammate, player) }
        end

        known_teammates = teammates.select { |player| announced.key?(player) }
        known_opponents = opponents.select { |player| announced.key?(player) }
        partner_evidence = known_teammates.sum do |player|
          announced.fetch(player, 0).to_f - expected
        end
        opponent_evidence = known_opponents.sum do |player|
          announced.fetch(player, 0).to_f - expected
        end
        adjustment += partner_evidence / maximum * 1.5
        # High opposing bids mean those players hold more likely winners and are
        # less free to duck every trick solely to attack nil. This is weaker
        # evidence than a partner's cover bid because opponents remain hostile.
        adjustment += opponent_evidence / maximum * 0.6
        [[adjustment, -1.5].max, 1.0].min
      end

      # With exact hands, a cashable top control is a proof that nil cannot
      # succeed against best defence. A sampled round rollout may still prefer
      # nil because of one cooperative line, so keep this rule outside the
      # learned profiles and make the impossible declaration uncompetitive.
      # The public estimator is intentionally not used as a veto: its historical
      # "certain" feature contains nominal honours that may still be discarded or
      # ruffed when the other hands are unknown.
      def bot_certain_trick_nil_score_adjustment(state, actor, bid)
        return 0.0 if bid.to_i != 0 || !omniscient_bots?(state)
        return 0.0 if estimated_certain_tricks(state, actor).to_i <= 0

        -CERTAIN_TRICK_NIL_PENALTY
      end

      # Top consecutive trumps are guaranteed independently of unknown hands.
      # Prune only strict score dominance, not merely bids below an average.
      def undominated_bot_bids(state, actor, bids)
        return bids unless state[:options]["team_size"].to_i == 0 && !state[:options]["no_hell"]
        hand = hand_for(state, actor).to_a
        guaranteed = RANKS.reverse.take_while { |rank| hand.include?("#{rank}S") }.length
        return bids if guaranteed.zero? || bids.length <= 1
        scoring = Scoring.new(state[:players], state[:options])
        values = bids.to_h do |bid|
          outcomes = (guaranteed..cards_per_player(state[:players].length)).map do |won|
            scoring.apply(bids: state[:bids].merge(actor => bid), tricks: { actor => won }, scores: state[:scores]).scores[actor]
          end
          [bid, outcomes]
        end
        bids.reject do |bid|
          bids.any? do |other|
            next false if other == bid
            pairs = values[bid].zip(values[other])
            pairs.all? { |old, replacement| replacement >= old } && pairs.any? { |old, replacement| replacement > old }
          end
        end
      end

      def estimated_bot_bid(state, actor)
        hand = hand_for(state, actor).to_a
        suit_lengths = SUITS.each_with_object({}) do |suit, result|
          result[suit] = hand.count { |card| card_suit(card) == suit }
        end
        estimate = hand.sum do |card|
          length = suit_lengths[card_suit(card)]
          case card_rank(card)
          when "A" then 0.95
          when "K" then length <= 5 ? 0.65 : 0.35
          when "Q" then length <= 4 ? 0.35 : 0.12
          when "J" then length <= 3 ? 0.18 : 0.05
          else 0.0
          end
        end
        spades = suit_lengths["S"].to_i
        estimate += [spades - 3, 0].max * 0.35
        suit_totals = DECK_SUIT_COUNTS.fetch(state[:players].length)
        short_suit_opportunities = SUITS.reject { |suit| suit == "S" }.sum do |suit|
          shortage = case suit_lengths[suit]
          when 0 then 1.0
          when 1 then 0.65
          when 2 then 0.30
          else 0.0
          end
          shortage * (13.0 / [suit_totals[suit], 1].max)
        end
        ruff_capacity = [spades - 2, 0].max
        estimate += [short_suit_opportunities, ruff_capacity].min * 0.45
        estimate += SUITS.reject { |suit| suit == "S" }.count { |suit| suit_lengths[suit] == 0 } * 0.10
        estimate *= BID_STRENGTH_SCALE.fetch(state[:players].length)
        estimate = estimated_omniscient_bid(state, actor, estimate) if omniscient_bots?(state)
        [[estimate, 0.0].max, cards_per_player(state[:players].length).to_f].min
      end

      # Perfect information is most useful in bidding when a nominal top-card
      # sequence can already be seen to survive, or to be vulnerable to a ruff.
      # Keep the calibrated public estimate as the baseline and adjust only the
      # part that the exact distribution can prove or disprove.
      def estimated_omniscient_bid(state, actor, public_estimate)
        side_profiles = exact_side_suit_control_profile(state, actor)
        side_controls = side_profiles.values.sum do |profile|
          profile[:safe_controls].to_f + profile[:threatened_controls].to_f * 0.35
        end
        spade_controls = exact_top_control_cards(state, actor, "S").length.to_f
        exact_controls = side_controls + spade_controls
        public_controls = estimated_public_certain_tricks(state, actor).to_f
        public_estimate + (exact_controls - public_controls) * 0.75
      end

      def omniscient_bots?(state)
        options = state[:options]
        options.is_a?(Hash) && options["omniscient_bots"] == true
      end

      def estimated_contract_safety_reserve(state, actor)
        return 0.0 if state[:players].length != 3
        return 0.0 if state[:options]["quicksand"] == true

        hand = hand_for(state, actor).to_a
        spades = hand.count { |card| card_suit(card) == "S" }
        return 0.0 if spades >= 3

        vulnerable_suits = SUITS.reject { |suit| suit == "S" }.count do |suit|
          cards = hand.select { |card| card_suit(card) == suit }
          next false if cards.length < 5

          cards.count { |card| %w[K Q J].include?(card_rank(card)) } >= 2
        end
        [vulnerable_suits * 0.5, 1.0].min
      end

      def bot_table_bid_target(state, actor)
        maximum = cards_per_player(state[:players].length).to_f
        score = bot_score_context(state, actor)
        # Allocating every trick creates a knife-edge table:
        # one contested overtrick automatically breaks another contract. This is
        # true for every player count and for both individual and team contracts,
        # and it also remains true in Quicksand: paying ten points for an extra
        # trick can be profitable when it breaks an opponent's contract. Keep the
        # reasoning in the shared model rather than tuning every policy profile.
        # In standard Spades a player or team close to the ten-bag penalty may
        # accept that risk. Match-position aggression remains a separate learned
        # feature and must not silently erase the shared safety margin.
        bag_relief = if state[:options]["quicksand"] == true
          0.0
        else
          [[(score[:bags] - 6).to_f / 3.0, 0.0].max, 1.0].min
        end
        buffer = 1.0 - bag_relief
        maximum - buffer
      end

      def bot_table_bid_projection(state, actor, bid)
        target = bot_table_bid_target(state, actor)
        remaining = [state[:players].length - state[:bids].length - 1, 0].max
        average = target / [state[:players].length, 1].max
        {
          target: target,
          remaining_bidders: remaining,
          projected: state[:bids].values.sum(&:to_i) + bid.to_i + remaining * average
        }
      end

      def estimated_certain_tricks(state, actor)
        if omniscient_bots?(state)
          side_controls = exact_side_suit_control_profile(state, actor).values.sum do |profile|
            profile[:safe_controls].to_i
          end
          spade_controls = exact_top_control_cards(state, actor, "S").length
          return [side_controls + spade_controls, cards_per_player(state[:players].length)].min
        end

        estimated_public_certain_tricks(state, actor)
      end

      # This is the historical public-hand feature used by the trained bidding
      # profiles. It describes nominal top-card strength, not a mathematical
      # guarantee. Perfect-information bots compare it with the actually cashable
      # controls instead of assuming every A-K-Q-J run survives intact.
      def estimated_public_certain_tricks(state, actor)
        hand = hand_for(state, actor).to_a
        certain = SUITS.sum do |suit|
          ranks = hand.select { |card| card_suit(card) == suit }.map { |card| card_rank(card) }
          %w[A K Q J].take_while { |rank| ranks.include?(rank) }.length
        end
        spades = hand.count { |card| card_suit(card) == "S" }
        voids = SUITS.reject { |suit| suit == "S" }.count do |suit|
          hand.none? { |card| card_suit(card) == suit }
        end
        certain += [[spades - 4, 0].max, voids].min
        [certain, cards_per_player(state[:players].length)].min
      end

      def exact_top_control_cards(state, actor, suit)
        actor_key = player_key(state, actor)
        return [] if actor_key == nil

        state[:players].flat_map do |player|
          key = player_key(state, player)
          hand_for(state, key).to_a.select { |card| card_suit(card) == suit }.map do |card|
            [key, card]
          end
        end.sort_by { |_player, card| -RANKS.index(card_rank(card)).to_i }
          .take_while { |player, _card| same_user?(player, actor_key) }
          .map(&:last)
      end

      # A side-suit control is safely cashable only while every hostile player
      # who still owns trump can follow suit. The remaining cards in the top run
      # are correlated: once the shortest opponent becomes void, all of them are
      # exposed together rather than remaining independent "certain" tricks.
      def exact_side_suit_control_profile(state, actor)
        actor_key = player_key(state, actor)
        return {} if actor_key == nil

        opponents = state[:players].reject do |player|
          same_user?(player, actor_key) || bot_state_allied?(state, actor_key, player)
        end
        trump_opponents = opponents.select do |player|
          hand_for(state, player).to_a.any? { |card| card_suit(card) == "S" }
        end
        SUITS.reject { |suit| suit == "S" }.each_with_object({}) do |suit, result|
          controls = exact_top_control_cards(state, actor_key, suit)
          shortest = if trump_opponents.empty?
            controls.length
          else
            trump_opponents.map do |player|
              hand_for(state, player).to_a.count { |card| card_suit(card) == suit }
            end.min.to_i
          end
          safe = [controls.length, shortest].min
          result[suit] = {
            suit: suit,
            control_cards: controls,
            safe_controls: safe,
            threatened_controls: [controls.length - safe, 0].max,
            shortest_trump_opponent: shortest
          }
        end
      end

      def estimated_nil_risk(state, actor)
        hand = hand_for(state, actor).to_a
        maximum = cards_per_player(state[:players].length)
        risk = hand.sum do |card|
          rank = RANKS.index(card_rank(card)).to_i
          suit_length = hand.count { |candidate| card_suit(candidate) == card_suit(card) }
          high = [rank - 8, 0].max / 4.0
          card_suit(card) == "S" ? high * 1.4 : high / [suit_length, 1].max
        end
        [risk / [maximum, 1].max, 1.5].min
      end

      def bot_score_context(state, actor)
        assignment = bot_team_assignment(state)
        unit = if assignment == nil
          player_key(state, actor)
        else
          "team:#{assignment.team_index_for(actor)}"
        end
        own_score = state[:scores].fetch(unit, 0).to_i
        opponent_scores = state[:scores].reject { |candidate, _score| candidate.to_s == unit.to_s }.values.map(&:to_i)
        opponent_score = opponent_scores.max || 0
        limit = [state[:options]["score_limit"].to_i, 1].max
        deficit = [[(opponent_score - own_score).to_f / limit, -2.0].max, 2.0].min
        {
          unit: unit,
          own_score: own_score,
          opponent_score: opponent_score,
          deficit: deficit,
          bags: state[:options]["quicksand"] == true ? 0 : own_score % 10
        }
      end

      def bot_state_allied?(state, first, second)
        assignment = bot_team_assignment(state)
        return same_user?(first, second) if assignment == nil

        assignment.team_index_for(first) == assignment.team_index_for(second)
      end

      def bot_contract_remaining(state, actor)
        assignment = bot_team_assignment(state)
        members = assignment == nil ? [player_key(state, actor)] : assignment.teammates_for(actor)
        regular = members.reject { |player| state[:bids].fetch(player, -1).to_i == 0 }
        required = regular.sum { |player| state[:bids].fetch(player, 0).to_i }
        won = regular.sum { |player| state[:tricks].fetch(player, 0).to_i }
        required - won
      end

      def bot_bag_risk?(state, actor)
        return false if state[:options]["quicksand"] == true

        assignment = bot_team_assignment(state)
        unit = if assignment == nil
          player_key(state, actor)
        else
          "team:#{assignment.team_index_for(actor)}"
        end
        state[:scores].fetch(unit, 0).to_i % 10 >= 7 && bot_contract_remaining(state, actor) <= 0
      end
    end

    include BidEvaluation
    public :bot_policy_score_adjustment
  end
end
