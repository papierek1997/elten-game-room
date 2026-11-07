require "digest"
require_relative "hidden_card_deals"

# Shared, information-aware round planning for Spades bots.
#
# The planner always plays complete hypothetical rounds. A fair bot receives
# several possible deals consistent with its hand and the public play log. An
# omniscient bot receives the one real deal. Both modes then use the same move
# model and terminal scoring, so improvements to contract play, nil protection
# and bag handling do not have to be implemented twice.
module SpadesPlanning
  class RoundPlanner
    attr_reader :last_failure
    PlanningWorld = Struct.new(:state, :weight, keyword_init: true)

    # These budgets keep one UI decision comfortably below a perceptible
    # pause. Fair play spends its budget on different possible deals; perfect
    # information spends it on different adversarial rollout styles.
    FAIR_WORLD_COUNT = 3
    FAIR_REFINEMENT_WORLD_COUNT = 3
    OMNISCIENT_ROLLOUTS = 2
    OMNISCIENT_REFINEMENT_ROLLOUTS = 3
    EXACT_ENDGAME_CARDS = 12
    MAX_PLAYS = 64
    NIL_SET_PRIORITY = 180.0
    CRITICAL_LOOKAHEAD_CANDIDATES = 4
    # The root planner already evaluates two different hostile styles. One
    # complete continuation per shortlisted future move keeps that branching
    # useful without multiplying the same work again inside each style.
    CRITICAL_CONTINUATION_VARIANTS = 1
    ROLLOUT_CACHE_LIMIT = 12_000
    EXACT_CACHE_LIMIT = 60_000
    COOPERATIVE_YIELD_INTERVAL = 0.005
    REFINEMENT_ABSOLUTE_MARGIN = 8.0
    REFINEMENT_RELATIVE_MARGIN = 0.15
    REFINEMENT_SWITCH_MARGIN = 5.0
    MATCH_WIN_UTILITY = 1_000.0
    MATCH_POSITION_WEIGHT = 45.0
    BAG_LIABILITY_WEIGHT = 0.35

    def initialize(game)
      @game = game
      # These caches live as long as the game object. An actual next move is a
      # child of states considered during the previous decision, so keeping
      # solved continuations avoids rebuilding the same tree on every turn.
      @rollout_cache = {}
      @exact_cache = {}
    end

    def plan(state:, actor:, information:)
      @last_failure = nil
      @next_cooperative_yield_at = monotonic_time + COOPERATIVE_YIELD_INTERVAL
      phase = state[:phase]
      choices = case phase
      when :bidding
        @game.send(:undominated_bot_bids, state, actor, @game.send(:legal_bid_values, state, actor))
      when :playing
        @game.send(:legal_cards, state, actor)
      else
        []
      end
      return empty_plan(phase) if choices.length <= 1

      worlds = planning_worlds(
        state,
        actor,
        information,
        count: omniscient?(state) ? 1 : FAIR_WORLD_COUNT
      )
      return empty_plan(phase) if worlds.empty?

      exact_limit = planning_exact_limit(state)
      samples = choices.each_with_object({}) do |choice, result|
        cooperative_checkpoint
        result[choice] = evaluate_choice(
          state,
          actor,
          phase,
          choice,
          worlds,
          exact_limit: exact_limit,
          variants: omniscient?(state) ? (0...OMNISCIENT_ROLLOUTS) : [0]
        )
      end
      initial_raw_scores = aggregate_samples(samples, omniscient?(state))
      raw_scores = initial_raw_scores.dup
      refinement_attempted = false
      refinement_accepted = false
      evaluated_world_count = worlds.length
      risk_worlds = worlds

      if refinement_needed?(state, actor, phase, initial_raw_scores)
        refinement_attempted = true
        candidates = best_choices(initial_raw_scores, 2)
        refinement_worlds, variants = refinement_budget(state, actor, information, worlds)
        risk_worlds = worlds + refinement_worlds unless omniscient?(state)
        evaluated_world_count += refinement_worlds.length if !omniscient?(state)
        candidates.each do |choice|
          samples[choice].concat(
            evaluate_choice(
              state,
              actor,
              phase,
              choice,
              refinement_worlds,
              exact_limit: exact_limit,
              variants: variants
            )
          )
        end
        proposed_scores = aggregate_samples(samples, omniscient?(state))
        refinement_accepted = refinement_acceptable?(initial_raw_scores, proposed_scores)
        raw_scores = proposed_scores if refinement_accepted
      end

      exact_decision = phase == :playing && omniscient?(state) && remaining_card_count(state) - 1 <= exact_limit
      # Reuse the already solved tails to certify short, low-branching endings.
      # A failed bounded attempt is NOT advertised as an exact result.
      if !exact_decision && phase == :playing && omniscient?(state) && remaining_card_count(state) <= 18
        certified = certify_choices(state, actor, choices)
        if certified
          raw_scores = certified
          exact_decision = true
        end
      end

      {
        phase: phase,
        scores: normalize(raw_scores),
        raw_scores: raw_scores,
        initial_scores: normalize(initial_raw_scores),
        initial_raw_scores: initial_raw_scores,
        worlds: evaluated_world_count,
        exact_information: omniscient?(state),
        exact_decision: exact_decision,
        partner_nil_risks: phase == :playing ? immediate_partner_nil_risks(state, actor, choices, risk_worlds) : {},
        refinement_attempted: refinement_attempted,
        refinement_accepted: refinement_accepted,
        confidence: score_margin(raw_scores),
        exact_limit: exact_limit
      }
    rescue StandardError => error
      # Planning is deliberately advisory. A malformed historical state must
      # not prevent the existing trained policy from making a legal move.
      @last_failure = { type: error.class.name, message: error.message }
      failure_key = [error.class.name, Array(error.backtrace).first]
      if @logged_failure != failure_key
        @logged_failure = failure_key
        Log.warning("ELTEN Game Room Spades planner fallback: #{error.class}: #{error.message}; #{failure_key.last}") if defined?(Log)
      end
      empty_plan(phase)
    end

    private

    def immediate_partner_nil_risks(state, actor, choices, worlds)
      actor = player_key(state, actor)
      return {} unless actor
      partner = active_partner_nil(state, actor)
      trick = state[:current_trick]
      return {} unless partner && !trick.empty? && choices.length > 1
      return {} if trick.any? { |play| same_player?(play[:player], partner) }
      # A small exact tail, using the SAME public-information worlds as the
      # round plan. Do not turn this into another complete-round search.
      return {} if state[:players].length - trick.length - 1 > 2
      budget = [1_500]
      result = catch(:nil_risk_budget) do
        choices.to_h do |card|
          total = worlds.sum(&:weight)
          risk = worlds.sum do |world|
            child = copy_state(world.state)
            child[:hands][actor].delete(card)
            child[:current_trick] << { player: actor, card: card }
            index = child[:players].index(actor)
            child[:current_player] = child[:players][(index + 1) % child[:players].length]
            partner_nil_trick_risk(child, actor, partner, budget) * world.weight
          end
          [card, risk / total]
        end
      end
      result.is_a?(Hash) ? result : {}
    end

    def partner_nil_trick_risk(state, root, partner, budget)
      throw :nil_risk_budget if budget[0] <= 0
      budget[0] -= 1
      if state[:current_trick].length == state[:players].length
        return same_player?(@game.send(:trick_winner, state[:current_trick]), partner) ? 1.0 : 0.0
      end
      actor = state[:current_player]
      allied = score_unit(state, actor) == score_unit(state, root)
      value = allied ? 1.0 : 0.0
      @game.send(:legal_cards, state, actor).each do |card|
        child = copy_state(state)
        child[:hands][actor].delete(card)
        child[:current_trick] << { player: actor, card: card }
        index = child[:players].index(actor)
        child[:current_player] = child[:players][(index + 1) % child[:players].length]
        next_value = partner_nil_trick_risk(child, root, partner, budget)
        value = allied ? [value, next_value].min : [value, next_value].max
        break if value == (allied ? 0.0 : 1.0)
      end
      value
    end

    def certify_choices(state, actor, choices)
      @certification_budget = 4_000
      catch(:certification_exhausted) do
        return choices.to_h do |card|
          child = copy_state(state)
          apply_card(child, actor, card)
          [card, exact_utilities(child, @exact_cache).fetch(player_key(state, actor))]
        end
      end
      nil
    ensure
      @certification_budget = nil
    end

    def empty_plan(phase)
      {
        phase: phase,
        scores: {},
        raw_scores: {},
        initial_scores: {},
        initial_raw_scores: {},
        worlds: 0,
        exact_information: false,
        refinement_attempted: false,
        refinement_accepted: false,
        confidence: 0.0,
        exact_limit: 0
      }
    end

    def planning_worlds(state, actor, information, count:, offset: 0)
      if omniscient?(state)
        return [PlanningWorld.new(state: copy_state(state), weight: 1.0)]
      end

      fair_worlds(state, actor, information, count: count, offset: offset)
    end

    def fair_worlds(state, actor, information, count:, offset: 0)
      actor_key = player_key(state, actor)
      return [] if actor_key == nil

      opponents = state[:players].reject { |player| same_player?(player, actor_key) }
      counts = opponents.each_with_object({}) do |player, result|
        result[player] = state[:hands].fetch(player, []).length
      end
      unseen = information.fetch(:unseen_cards, []).to_a
      void_suits = information.fetch(:void_suits, {})
      base_seed = public_seed(state, actor_key)
      worlds = []
      attempts = 0
      while worlds.length < count && attempts < count * 12
        cooperative_checkpoint
        attempt_index = offset * 97 + attempts
        random = Random.new((base_seed + attempt_index * 1_000_003) & 0x7fffffff)
        assignment = assign_hidden_cards(unseen, opponents, counts, void_suits, random)
        if assignment != nil
          world = copy_state(state)
          opponents.each { |player| world[:hands][player] = assignment.fetch(player) }
          worlds << PlanningWorld.new(
            state: world,
            weight: world_likelihood(world, actor_key, information)
          )
        end
        attempts += 1
      end
      worlds
    end

    def evaluate_choice(
      state,
      actor,
      phase,
      choice,
      worlds,
      exact_limit:,
      variants:
    )
      worlds.flat_map do |planning_world|
        variants.map do |variant|
          cooperative_checkpoint
          simulated = copy_state(planning_world.state)
          if phase == :bidding
            prepare_bids(simulated, actor, choice)
          else
            apply_card(simulated, actor, choice)
          end
          value = play_round(
            simulated,
            actor,
            variant,
            # A fair bot already branches over possible deals. The additional
            # hostile continuation beam remains exclusive to exact information.
            allow_lookahead: phase == :playing && omniscient?(state),
            exact_limit: exact_limit
          )
          [value, planning_world.weight]
        end
      end
    end

    def aggregate_samples(samples, exact_information)
      samples.transform_values { |values| aggregate(values, exact_information) }
    end

    def refinement_budget(state, actor, information, initial_worlds)
      if omniscient?(state)
        variants = OMNISCIENT_ROLLOUTS...(
          OMNISCIENT_ROLLOUTS + OMNISCIENT_REFINEMENT_ROLLOUTS
        )
        return [initial_worlds, variants]
      end

      worlds = planning_worlds(
        state,
        actor,
        information,
        count: FAIR_REFINEMENT_WORLD_COUNT,
        offset: FAIR_WORLD_COUNT
      )
      [worlds, [0]]
    end

    def refinement_needed?(state, actor, phase, raw_scores)
      return false if raw_scores.length < 2

      margin = score_margin(raw_scores)
      spread = raw_scores.values.max.to_f - raw_scores.values.min.to_f
      uncertain = margin <= REFINEMENT_ABSOLUTE_MARGIN ||
        margin <= spread.abs * REFINEMENT_RELATIVE_MARGIN
      uncertain || critical_root_decision?(state, actor, phase)
    end

    def critical_root_decision?(state, actor, phase)
      limit = [state[:options].fetch("score_limit", 300).to_i, 1].max
      match_close = state[:scores].values.any? { |score| score.to_i >= limit * 0.8 }
      return match_close if phase != :playing

      actor_key = player_key(state, actor)
      live_nil = state[:players].any? do |player|
        state[:bids].fetch(player, -1).to_i == 0 &&
          state[:tricks].fetch(player, 0).to_i == 0
      end
      bags_critical = state[:options]["quicksand"] != true &&
        state[:scores].values.any? { |score| score.to_i % 10 >= 8 }
      contract = actor_key == nil ? { need: 0 } : @game.send(:bot_regular_contract, state, actor_key)
      tight_contract = contract[:need].to_i.between?(1, 2)
      short_endgame = remaining_card_count(state) <= state[:players].length * 5
      match_close || live_nil || bags_critical || tight_contract || short_endgame
    end

    def refinement_acceptable?(initial_scores, proposed_scores)
      candidates = best_choices(initial_scores, 2)
      initial_best = best_choices(initial_scores, 1).first
      proposed_best = best_choices(proposed_scores, 1).first
      return false if !candidates.include?(proposed_best)
      return true if initial_best == proposed_best

      score_margin(proposed_scores) >= REFINEMENT_SWITCH_MARGIN
    end

    def best_choices(scores, count)
      scores.sort_by { |choice, score| [-score.to_f, choice.to_s] }.first(count).map(&:first)
    end

    def score_margin(scores)
      ordered = scores.values.map(&:to_f).sort.reverse
      return 0.0 if ordered.length < 2

      ordered[0] - ordered[1]
    end

    def hidden_card_allowed?(void_suits, player, card)
      voids = void_suits.fetch(player.to_s, [])
      !voids.include?(card_suit(card)) &&
        !(card_suit(card) == "S" && card != "AS" && voids.include?("S_except_ace"))
    end

    def assign_hidden_cards(cards, players, counts, void_suits, random)
      GameRoomHiddenCardDeals.assign(cards, players, counts, random) do |player, card|
        hidden_card_allowed?(void_suits, player, card)
      end
    end

    # A fair bot never reads the real hidden hands. It does, however, prefer
    # sampled deals which better explain public bids and public card choices.
    # The evidence is intentionally soft: an unusual human move lowers a
    # world's weight but never removes that world from consideration.
    def world_likelihood(world, actor, information)
      plays = information.fetch(:public_plays, []).to_a
      initial_hands = reconstructed_hands(world, plays)
      bid_weight = world_bid_likelihood(world, actor, initial_hands)
      play_weight = world_play_likelihood(world, initial_hands, plays)
      [[bid_weight * play_weight, 0.15].max, 1.0].min
    end

    def reconstructed_hands(world, plays)
      hands = world[:players].each_with_object({}) do |player, result|
        key = player_key(world, player)
        result[key] = world[:hands].fetch(key, []).dup
      end
      plays.each do |play|
        key = player_key(world, play[:player] || play["player"])
        card = (play[:card] || play["card"]).to_s
        hands[key] << card if key != nil && card != ""
      end
      hands
    end

    def world_bid_likelihood(world, actor, initial_hands)
      components = world[:bids].filter_map do |player, observed_bid|
        key = player_key(world, player)
        next if key == nil || same_player?(key, actor)

        estimate_state = world.dup
        estimate_state[:hands] = initial_hands
        estimate = @game.send(:estimated_bot_bid, estimate_state, key)
        error = observed_bid.to_f - estimate.to_f
        1.0 / (1.0 + error * error * 0.22)
      end
      geometric_mean(components)
    end

    def world_play_likelihood(world, initial_hands, plays)
      return 1.0 if plays.empty?

      hands = initial_hands.transform_values(&:dup)
      trick = []
      tricks = world[:players].each_with_object({}) do |player, result|
        result[player_key(world, player)] = 0
      end
      spades_broken = false
      components = []
      plays.each do |play|
        cooperative_checkpoint
        actor = player_key(world, play[:player] || play["player"])
        card = (play[:card] || play["card"]).to_s
        hand = actor == nil ? [] : hands.fetch(actor, [])
        legal = observed_legal_cards(hand, trick, spades_broken)
        return 0.15 if actor == nil || !legal.include?(card)

        scored = legal.map do |candidate|
          [candidate, observed_play_score(world, actor, candidate, trick, tricks)]
        end
        best = scored.map(&:last).max.to_f
        chosen = scored.find { |candidate, _score| candidate == card }[1].to_f
        relative = Math.exp([[chosen - best, -8.0].max, 0.0].min / 3.0)
        components << 0.85 + relative * 0.15

        hand.delete_at(hand.index(card))
        spades_broken = true if card_suit(card) == "S"
        trick << { player: actor, card: card }
        if trick.length == world[:players].length
          winner = @game.send(:trick_winner, trick)
          tricks[winner] = tricks.fetch(winner, 0).to_i + 1
          trick = []
        end
      end
      geometric_mean(components)
    end

    def observed_legal_cards(hand, trick, spades_broken)
      if !trick.empty?
        led_suit = card_suit(trick.first[:card])
        return @game.send(:legal_cards_for_led_suit, hand, led_suit)
      elsif !spades_broken
        non_spades = hand.reject { |card| card_suit(card) == "S" }
        return non_spades if !non_spades.empty?
      end
      hand
    end

    def observed_play_score(world, actor, card, trick, tricks)
      candidate_trick = trick + [{ player: actor, card: card }]
      wins = same_player?(@game.send(:trick_winner, candidate_trick), actor)
      bid = world[:bids].fetch(actor, -1).to_i
      won = tricks.fetch(actor, 0).to_i
      rank = @game.class::RANKS.index(card.to_s[0]).to_i
      cost = rank + (card_suit(card) == "S" ? 4 : 0)

      if bid == 0 && won == 0
        (wins ? -8.0 : 2.0) + cost * (wins ? -0.1 : 0.08)
      elsif bid - won > 0
        (wins ? 4.0 : -1.0) - cost * (wins ? 0.05 : 0.0)
      else
        (wins ? -3.0 : 1.0) + cost * (wins ? -0.05 : 0.08)
      end
    end

    def geometric_mean(values)
      samples = values.to_a.select { |value| value.to_f > 0.0 }
      return 1.0 if samples.empty?

      Math.exp(samples.sum { |value| Math.log(value.to_f) } / samples.length)
    end

    def prepare_bids(state, actor, bid)
      actor_key = player_key(state, actor)
      state[:bids][actor_key] = bid.to_i
      if state[:bids].length == state[:players].length
        begin_play(state)
        return
      end

      state[:current_player] = next_player(state, actor_key)
      while state[:bids].length < state[:players].length
        cooperative_checkpoint
        bidder = state[:current_player]
        legal = @game.send(:legal_bid_values, state, bidder)
        estimate = @game.send(:estimated_bot_bid, state, bidder)
        chosen = legal.min_by { |candidate| [(candidate.to_f - estimate).abs, candidate] }
        state[:bids][player_key(state, bidder)] = chosen.to_i
        if state[:bids].length == state[:players].length
          begin_play(state)
        else
          state[:current_player] = next_player(state, bidder)
        end
      end
    end

    def begin_play(state)
      state[:phase] = :playing
      dealer = state[:dealer_index].to_i
      state[:current_player] = state[:players][(dealer + 1) % state[:players].length]
    end

    def play_round(
      state,
      root_actor,
      variant,
      allow_lookahead: true,
      exact_limit: EXACT_ENDGAME_CARDS
    )
      plays = 0
      visited_cache_keys = []
      loop do
        cooperative_checkpoint
        cache_key = rollout_cache_key(
          state,
          root_actor,
          variant,
          allow_lookahead,
          exact_limit
        )
        cached = @rollout_cache[cache_key]
        return cache_rollout_result(visited_cache_keys, cached) if cached != nil
        visited_cache_keys << cache_key

        remaining = remaining_card_count(state)
        if remaining <= 0
          return cache_rollout_result(visited_cache_keys, terminal_utility(state, root_actor))
        end
        if remaining <= exact_limit
          utilities = exact_utilities(state, @exact_cache)
          value = utilities.fetch(player_key(state, root_actor)) { terminal_utility(state, root_actor) }
          return cache_rollout_result(visited_cache_keys, value)
        end
        if plays >= MAX_PLAYS
          return cache_rollout_result(visited_cache_keys, terminal_utility(state, root_actor))
        end

        actor = state[:current_player]
        legal = @game.send(:legal_cards, state, actor)
        if legal.empty?
          return cache_rollout_result(visited_cache_keys, terminal_utility(state, root_actor))
        end

        card = rollout_card(
          state,
          actor,
          legal,
          variant,
          allow_lookahead: allow_lookahead,
          exact_limit: exact_limit
        )
        apply_card(state, actor, card)
        plays += 1
      end
    end

    # Once the deal is small enough, solve it to the end with Max-N. Every
    # player maximizes their own (or their team's) actual round score. This is
    # exact for the remaining cards and also works for individual games, where
    # treating all opponents as one coalition would produce artificial play.
    def exact_utilities(state, memo)
      cooperative_checkpoint
      return terminal_utilities(state) if remaining_card_count(state) <= 0

      key = exact_state_key(state)
      cached = memo[key]
      return cached if cached != nil

      if @certification_budget
        throw :certification_exhausted if @certification_budget <= 0
        @certification_budget -= 1
      end

      actor = state[:current_player]
      legal = @game.send(:legal_cards, state, actor)
      return terminal_utilities(state) if legal.empty?

      actor_key = player_key(state, actor)
      candidates = legal.map do |card|
        child = copy_state(state)
        apply_card(child, actor, card)
        [card, exact_utilities(child, memo)]
      end
      chosen = candidates.max_by do |card, utilities|
        [utilities.fetch(actor_key, -Float::INFINITY), -card_cost(card)]
      end
      cache_write(memo, key, chosen[1], EXACT_CACHE_LIMIT)
      chosen[1]
    end

    def rollout_card(
      state,
      actor,
      legal,
      variant,
      allow_lookahead: true,
      exact_limit: EXACT_ENDGAME_CARDS
    )
      context = exact_trick_context(state)
      need = @game.send(:bot_contract_remaining, state, actor)
      own_key = player_key(state, actor)
      own_bid = state[:bids].fetch(own_key, -1).to_i
      own_tricks = state[:tricks].fetch(own_key, 0).to_i
      nil_active = own_bid == 0 && own_tricks == 0
      partner_nil = active_partner_nil(state, actor)
      opponent_nil = active_opponent_nil(state, actor)
      quicksand = state[:options]["quicksand"] == true
      trick = state[:current_trick]
      leader = trick.empty? ? nil : @game.send(:trick_winner, trick)
      decision_public_seed = public_seed(state, player_key(state, actor))
      exact_control_context = { omniscient: true, known_hands: state[:hands] }
      expiring_control = if need > 0
        @game.send(:bot_expiring_contract_control, state, actor, exact_control_context)
      end

      style = variant.to_i % 4
      scored = legal.map do |card|
        cooperative_checkpoint
        win_probability = @game.send(
          :bot_exact_trick_win_probability, state, actor, card, context
        )
        cost = card_cost(card)
        score = 0.0
        if nil_active
          # A later player who can beat this card is not obliged to do so.
          # Opponents deliberately duck to set nil; partners cover it where
          # possible. Use that hostile continuation instead of treating every
          # available higher card as automatic protection.
          retention_risk = @game.send(
            :bot_nil_retention_risk,
            state,
            actor,
            card,
            { known_hands: state[:hands] }
          )
          score -= 120.0 * retention_risk
          score += cost * (1.0 - retention_risk) * 0.8
        elsif partner_nil != nil
          partner_winning = leader != nil && same_player?(leader, partner_nil)
          score += 70.0 * win_probability if partner_winning
          score += 35.0 * win_probability if trick.empty?
          score -= cost * 0.2
        elsif need > 0
          urgency = [need.to_f / [state[:hands].fetch(own_key, []).length, 1].max, 1.0].min
          contract_weight = [1.0, 0.92, 1.12, 1.04][style]
          control_cost = [0.35, 0.25, 0.5, 0.4][style]
          score += (28.0 + urgency * 24.0) * contract_weight * win_probability
          score -= cost * control_cost
          if @game.send(:bot_future_control_discard?, state, actor, card, exact_control_context)
            score -= @game.class::FUTURE_CONTROL_DISCARD_PENALTY
          end
          if expiring_control != nil
            if expiring_control[:control_cards].include?(card)
              score += @game.class::EXPIRING_CONTROL_PRIORITY
            elsif card_suit(card) == expiring_control[:suit]
              score -= @game.class::EXPIRING_CONTROL_PRIORITY
            end
          end
        else
          avoidance_style = [1.0, 1.2, 0.82, 1.35][style]
          avoidance = (quicksand ? 35.0 : 10.0 + current_bags(state, actor) * 1.8) * avoidance_style
          score -= avoidance * win_probability
          score += cost * (1.0 - win_probability) * 0.65
        end
        if opponent_nil != nil && leader != nil && same_player?(leader, opponent_nil)
          winner_after = @game.send(
            :trick_winner,
            trick + [{ player: player_key(state, actor), card: card }]
          )
          # Setting an opposing nil normally swings one hundred points, so a
          # legal duck must dominate ordinary contract-card preferences.
          score += NIL_SET_PRIORITY if same_player?(winner_after, opponent_nil)
        end
        if opponent_nil != nil && trick.empty?
          # A nil may also be set before it has played into the current trick.
          # When it acts immediately after this lead, test every legal reply
          # with the same hostile continuation used by the live nil safety
          # model. If even the safest reply can be ducked under, the lead is a
          # forced nil attack and must dominate ordinary contract technique.
          score += NIL_SET_PRIORITY * opponent_nil_forced_lead_risk(
            state, actor, card, opponent_nil
          )
        end
        denial_style = [1.0, 1.35, 0.8, 1.6][style]
        score += opponent_denial_value(state, actor, win_probability) * denial_style
        score += deterministic_tie_break(
          state,
          actor,
          card,
          variant,
          base_seed: decision_public_seed
        )
        [card, score]
      end

      if allow_lookahead && critical_lookahead?(state, actor, legal, need, exact_limit)
        candidates = critical_candidates(state, scored)
        evaluated = candidates.map do |card, immediate_score|
          cooperative_checkpoint
          values = CRITICAL_CONTINUATION_VARIANTS.times.map do |offset|
            child = copy_state(state)
            apply_card(child, actor, card)
            continuation_variant = (style + offset) % 4
            play_round(
              child,
              actor,
              continuation_variant,
              allow_lookahead: false,
              exact_limit: exact_limit
            )
          end
          [card, aggregate(values, true), immediate_score]
        end
        return evaluated.max_by do |_card, continuation, immediate_score|
          [continuation, immediate_score]
        end.first
      end

      scored.max_by { |_card, score| score }.first
    end

    def opponent_nil_forced_lead_risk(state, actor, card, nil_player)
      return 0.0 if !state[:current_trick].empty?

      after_lead = copy_state(state)
      return 0.0 if !apply_card(after_lead, actor, card)
      return 0.0 if !same_player?(after_lead[:current_player], nil_player)

      legal = @game.send(:legal_cards, after_lead, nil_player)
      return 0.0 if legal.empty?

      exact_context = { known_hands: after_lead[:hands] }
      # The nil bidder chooses its safest response. The lead is forced only to
      # the degree that even this best response remains vulnerable.
      legal.map do |reply|
        @game.send(
          :bot_nil_retention_risk,
          after_lead,
          nil_player,
          reply,
          exact_context
        ).to_f
      end.min
    end

    def critical_lookahead?(state, actor, legal, need, exact_limit)
      return false if legal.length <= 1

      remaining_cards = remaining_card_count(state)
      return false if remaining_cards <= exact_limit
      # Root actions are already enumerated by plan. Extra branching is most
      # valuable once contracts become tight or trump/non-trump preservation
      # starts deciding the endgame; doing it on every early discard would
      # multiply work without adding useful information.
      hand_size = state[:hands].fetch(player_key(state, actor), []).length
      second_half = remaining_cards <= 18
      tight_contract = second_half && need > 0 && hand_size - need <= 4
      live_nil = state[:players].any? do |player|
        state[:bids].fetch(player, -1).to_i == 0 &&
          state[:tricks].fetch(player, 0).to_i == 0
      end
      mixed_control = state[:current_trick].empty? && hand_size <= 10 &&
        legal.any? { |card| card_suit(card) == "S" } &&
        legal.any? { |card| card_suit(card) != "S" }
      tight_contract || (second_half && live_nil) || mixed_control
    end

    def critical_candidates(state, scored)
      ordered = scored.sort_by { |_card, score| -score }
      cards = ordered.first(3).dup
      cards << scored.min_by { |card, _score| card_cost(card) }
      cards << scored.max_by { |card, _score| card_cost(card) }
      if state[:current_trick].empty?
        scored.group_by { |card, _score| card_suit(card) }.each_value do |entries|
          cards << entries.min_by { |card, _score| card_cost(card) }
        end
      end
      cards.compact.uniq { |card, _score| card }.first(CRITICAL_LOOKAHEAD_CANDIDATES)
    end

    def exact_trick_context(state)
      known_hands = state[:players].each_with_object({}) do |player, result|
        result[player_key(state, player)] = state[:hands].fetch(player, []).dup
      end
      {
        omniscient: true,
        known_hands: known_hands,
        unseen_cards: known_hands.values.flatten,
        void_suits: known_hands.transform_values do |cards|
          @game.class::SUITS.select { |suit| cards.none? { |card| card_suit(card) == suit } }
        end
      }
    end

    def opponent_denial_value(state, actor, win_probability)
      return 0.0 if win_probability <= 0.0

      opponents = state[:players].reject do |player|
        same_player?(player, actor) || @game.send(:bot_state_allied?, state, actor, player)
      end
      threatened = opponents.count do |player|
        contract = @game.send(:bot_regular_contract, state, player)
        contract[:need] > 0 && contract[:need] >= state[:hands].fetch(player, []).length - 1
      end
      threatened * 8.0 * win_probability
    end

    def active_partner_nil(state, actor)
      state[:players].find do |player|
        !same_player?(player, actor) &&
          @game.send(:bot_state_allied?, state, actor, player) &&
          state[:bids].fetch(player, -1).to_i == 0 &&
          state[:tricks].fetch(player, 0).to_i == 0
      end
    end

    def active_opponent_nil(state, actor)
      state[:players].find do |player|
        !same_player?(player, actor) &&
          !@game.send(:bot_state_allied?, state, actor, player) &&
          state[:bids].fetch(player, -1).to_i == 0 &&
          state[:tricks].fetch(player, 0).to_i == 0
      end
    end

    def apply_card(state, actor, card)
      key = player_key(state, actor)
      hand = state[:hands].fetch(key)
      index = hand.index(card)
      return false if index == nil

      hand.delete_at(index)
      state[:spades_broken] = true if card_suit(card) == "S"
      state[:current_trick] << { player: key, card: card }
      if state[:current_trick].length == state[:players].length
        winner = @game.send(:trick_winner, state[:current_trick])
        state[:tricks][winner] = state[:tricks].fetch(winner, 0).to_i + 1
        state[:current_trick] = []
        state[:current_player] = winner
      else
        state[:current_player] = next_player(state, actor)
      end
      true
    end

    def terminal_utilities(state)
      scored = terminal_score(state)
      state[:players].each_with_object({}) do |player, result|
        result[player_key(state, player)] = terminal_utility(state, player, scored)
      end
    end

    def terminal_score(state)
      scoring = @game.class::Scoring.new(state[:players], state[:options])
      scoring.apply(bids: state[:bids], tricks: state[:tricks], scores: state[:scores])
    end

    def terminal_utility(state, actor, result = terminal_score(state))
      unit = score_unit(state, actor)
      own_before = state[:scores].fetch(unit, 0).to_i
      own_delta = result.scores.fetch(unit, own_before).to_i - own_before
      opponents = result.scores.keys.reject { |candidate| candidate.to_s == unit.to_s }
      opponent_deltas = opponents.map do |candidate|
        result.scores.fetch(candidate, 0).to_i - state[:scores].fetch(candidate, 0).to_i
      end
      opposition = opponent_deltas.max || 0
      round_value = team_game?(state) ? own_delta - opposition : own_delta - opposition * 0.35
      limit = [state[:options].fetch("score_limit", 300).to_i, 1].max
      winner = match_winner(result.scores, limit)
      if winner != nil
        outcome = winner.to_s == unit.to_s ? MATCH_WIN_UTILITY : -MATCH_WIN_UTILITY
        return outcome + round_value
      end

      position_before = match_position(state[:scores], unit, limit)
      position_after = match_position(result.scores, unit, limit)
      relevance = match_position_relevance(state[:scores], result.scores, limit)
      position_swing = (position_after - position_before) * MATCH_POSITION_WEIGHT * relevance
      bag_cost = bag_liability_change(state, result.scores, unit)
      round_value + position_swing - bag_cost
    end

    def match_winner(scores, limit)
      leaders = scores.group_by { |_unit, score| score.to_i }.max_by { |score, _items| score }
      return nil if leaders == nil || leaders[0] < limit.to_i || leaders[1].length != 1

      leaders[1].first[0]
    end

    def match_position(scores, unit, limit)
      own = score_progress(scores.fetch(unit, 0), limit)
      opponents = scores.reject { |candidate, _score| candidate.to_s == unit.to_s }
      strongest = opponents.values.map { |score| score_progress(score, limit) }.max || 0.0
      own - strongest
    end

    def score_progress(score, limit)
      ratio = score.to_f / limit.to_f
      ratio >= 0.0 ? ratio * ratio : -((-ratio) ** 1.5)
    end

    def match_position_relevance(before_scores, after_scores, limit)
      leading_score = (before_scores.values + after_scores.values).map(&:to_i).max || 0
      [[(leading_score.to_f / limit - 0.5) * 2.0, 0.0].max, 1.0].min
    end

    def bag_liability_change(state, resulting_scores, unit)
      return 0.0 if state[:options]["quicksand"] == true

      before = state[:scores].fetch(unit, 0).to_i % 10
      after = resulting_scores.fetch(unit, 0).to_i % 10
      return 0.0 if [before, after].max < 7

      (after * after - before * before) * BAG_LIABILITY_WEIGHT
    end

    def score_unit(state, actor)
      assignment = @game.team_assignment(state[:options], players: state[:players])
      return player_key(state, actor) if assignment == nil

      "team:#{assignment.team_index_for(actor)}"
    end

    def team_game?(state)
      @game.team_assignment(state[:options], players: state[:players]) != nil
    end

    def current_bags(state, actor)
      return 0 if state[:options]["quicksand"] == true

      state[:scores].fetch(score_unit(state, actor), 0).to_i % 10
    end

    def aggregate(values, exact_information)
      return 0.0 if values.empty?

      samples = values.map do |entry|
        entry.is_a?(Array) ? [entry[0].to_f, entry[1].to_f] : [entry.to_f, 1.0]
      end
      total_weight = samples.sum { |_value, weight| [weight, 0.0].max }
      mean = if total_weight <= 0.0
        samples.sum { |value, _weight| value } / samples.length
      else
        samples.sum { |value, weight| value * [weight, 0.0].max } / total_weight
      end
      return mean if !exact_information

      # Exact information should also survive a hostile plausible continuation,
      # not merely achieve a high average against one rollout personality.
      mean * 0.75 + samples.map(&:first).min.to_f * 0.25
    end

    def normalize(values)
      return {} if values.empty?

      minimum, maximum = values.values.minmax
      span = maximum.to_f - minimum.to_f
      return values.transform_values { 0.0 } if span.abs < 0.000001

      values.transform_values { |value| ((value.to_f - minimum) / span) * 2.0 - 1.0 }
    end

    def planning_exact_limit(state)
      remaining = remaining_card_count(state)
      return EXACT_ENDGAME_CARDS if state[:phase] == :playing && remaining <= 18

      # Solving twelve cards at the end of every candidate bid would repeat a
      # large exact tree dozens of times before the first card is played.
      # Early full-round branches therefore hand off at nine known cards (or
      # eight inside sampled fair worlds), while an actual approaching
      # endgame switches to the full twelve-card solver.
      omniscient?(state) ? 9 : 8
    end

    def rollout_cache_key(
      state,
      root_actor,
      variant,
      allow_lookahead,
      exact_limit
    )
      [
        player_key(state, root_actor).to_s,
        variant.to_i % 4,
        allow_lookahead == true ? 1 : 0,
        exact_limit.to_i,
        exact_state_key(state)
      ].join("|")
    end

    def cache_rollout_result(keys, value)
      keys.each { |key| cache_write(@rollout_cache, key, value.to_f, ROLLOUT_CACHE_LIMIT) }
      value
    end

    def cache_write(cache, key, value, limit)
      cache.shift if cache.length >= limit && !cache.key?(key)
      cache[key] = value
    end

    def deterministic_tie_break(state, actor, card, variant, base_seed: nil)
      seed = decision_seed(state, actor, card, 313, variant, base_seed: base_seed)
      (seed % 1_000_000).to_f / 10_000_000_000.0
    end

    def omniscient?(state)
      state[:options].is_a?(Hash) && state[:options]["omniscient_bots"] == true
    end

    def remaining_card_count(state)
      state[:hands].values.sum(&:length)
    end

    def exact_state_key(state)
      payload = [
        state[:phase].to_s,
        state[:round].to_i,
        state[:dealer_index].to_i,
        state[:current_player].to_s,
        state[:spades_broken] == true,
        state[:players].map(&:to_s),
        state[:players].map { |player| state[:hands].fetch(player, []).sort },
        state[:current_trick].map { |play| [play[:player].to_s, play[:card].to_s] },
        state[:players].map { |player| [player.to_s, state[:bids].fetch(player, -1).to_i] },
        state[:players].map { |player| [player.to_s, state[:tricks].fetch(player, 0).to_i] },
        state[:scores].to_a.sort_by { |unit, _score| unit.to_s },
        state[:options].to_a.sort_by { |name, _value| name.to_s }
      ]
      # The binary digest is the same collision-resistant cache identity as
      # its hexadecimal representation, but occupies half as much memory and
      # avoids formatting more than three hundred thousand keys per round.
      Digest::SHA256.digest(Marshal.dump(payload))
    end

    def public_seed(state, actor)
      players = state[:players]
      actor_key = player_key(state, actor)
      actor_index = players.index { |player| same_player?(player, actor_key) }
      player_entries = lambda do |values|
        players.each_with_index.filter_map do |player, index|
          next if !values.key?(player)

          [index, values.fetch(player)]
        end
      end
      public = [
        state[:phase].to_s,
        actor_index,
        state[:round].to_i,
        players.each_index.to_a,
        state[:hands].fetch(actor_key, []).sort,
        player_entries.call(state[:bids]),
        player_entries.call(state[:tricks]),
        state[:current_trick].map do |play|
          [players.index { |player| same_player?(player, play[:player]) }, play[:card].to_s]
        end,
        state[:spades_broken] == true
      ]
      Digest::SHA256.hexdigest(Marshal.dump(public))[0, 15].to_i(16)
    end

    def decision_seed(state, actor, choice, world_index, variant, base_seed: nil)
      seed = base_seed || public_seed(state, player_key(state, actor))
      value = [seed, choice.to_s, world_index, variant]
      Digest::SHA256.hexdigest(Marshal.dump(value))[0, 15].to_i(16)
    end

    def card_cost(card)
      rank = @game.class::RANKS.index(card.to_s[0]).to_i
      rank + (card_suit(card) == "S" ? 4 : 0)
    end

    def card_suit(card)
      card.to_s[1]
    end

    def next_player(state, actor)
      players = state[:players]
      index = players.index { |player| same_player?(player, actor) }
      index == nil ? nil : players[(index + 1) % players.length]
    end

    def player_key(state, actor)
      state[:players].find { |player| same_player?(player, actor) }
    end

    def same_player?(first, second)
      GameRoomParticipants.same?(first, second)
    end

    # Planner states contain only scalar values plus these known collections.
    # Copying them explicitly preserves branch isolation without serializing
    # the complete state hundreds of thousands of times during one round.
    def copy_state(state)
      copy = state.dup
      copy[:players] = state[:players].dup
      copy[:options] = state[:options].dup
      copy[:units] = state[:units].dup if state[:units].is_a?(Array)
      copy[:scores] = state[:scores].dup
      copy[:hands] = state[:hands].transform_values(&:dup)
      copy[:bids] = state[:bids].dup
      copy[:tricks] = state[:tricks].dup
      copy[:current_trick] = state[:current_trick].map(&:dup)
      copy
    end

    # The planner shares ELTEN's Ruby runtime with conference audio, speech and
    # the user interface. A short, time-gated scheduler hand-off keeps those
    # services responsive without changing search depth, branch order, random
    # seeds or any other part of the bot's decision.
    def cooperative_checkpoint
      now = monotonic_time
      return if @next_cooperative_yield_at != nil && now < @next_cooperative_yield_at

      Thread.pass
      @next_cooperative_yield_at = monotonic_time + COOPERATIVE_YIELD_INTERVAL
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue Exception
      Time.now.to_f
    end
  end
end
