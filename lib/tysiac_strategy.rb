require_relative "game_bots"
require_relative "game_random"
require_relative "participant_decision_events"

# Information-set planning for two- and three-player Tysiac. The planner never
# reads the identities of cards in an opponent's real hand. Instead it samples
# complete deals consistent with the bot's own hand, public plays, auction
# information and suits in which a player has publicly shown a void.
module TysiacPlanning
  # Private-card writes may combine the contract and opening play into one
  # accepted event. Both histories expose the same public card and mode; keep
  # the immutable records intact and normalize only this decision view.
  def self.public_play(event)
    value = event['value'].to_s
    case event['action'].to_s
    when 'play'
      # Ordinary play is already mode|card.
    when 'contract_play'
      _contract, value = value.split('|', 2)
    else
      return nil
    end
    mode, card = value.to_s.split('|', 2)
    return nil unless card && /\A[9JQKTA][CDHS]\z/.match?(card)

    { player: event['actor'], mode: mode, card: card }
  end

  class Strategy
    include GameRoomBots::ReplayOnlyStrategy

    BIDDING_SAMPLES = 64
    PLAY_SAMPLES = 48
    CONTRACT_SAMPLES = 64
    PASSING_SAMPLES = 40

    def initialize(fallback: GameRoomBots::HeuristicStrategy.new)
      @fallback = fallback
    end

    def choose(actions:, actor:, random_source:, game:, replay:, context: nil, **_extra)
      choices = actions.to_a
      return nil if choices.empty?
      return choices.first if choices.length == 1
      redeal = choices.find { |action| action["action"] == "redeal" }
      return redeal if redeal

      planner = Planner.new(game, replay, actor, random_source)
      selected = case replay.state[:phase]
      when :bidding
        planner.choose_bid(choices, samples: BIDDING_SAMPLES)
      when :playing
        planner.choose_play(choices, samples: PLAY_SAMPLES)
      when :passing
        planner.choose_passing(choices, samples: PASSING_SAMPLES)
      when :choosing_talon
        planner.choose_talon(choices)
      when :discarding
        planner.choose_discarding(choices, samples: PASSING_SAMPLES)
      when :contract
        planner.choose_contract(choices, samples: CONTRACT_SAMPLES)
      end
      return selected if selected != nil

      GameRoomBots.choose(@fallback, {
        actions: choices,
        observation: game.bot_observation(replay, actor),
        actor: actor,
        random_source: random_source,
        game: game,
        replay: replay,
        context: context
      })
    end
  end

  class Planner
    PASS_MARRIAGE_RISK_WEIGHT = 12.0
    BREAK_MARRIAGE_RISK_WEIGHT = 60.0

    def initialize(game, replay, actor, random_source)
      @game = game
      @replay = replay
      @state = replay.state
      @players = game.send(:round_players, @state).to_a
      @teams = @state.fetch(:teams, {})
      # The planner's per-seat view refers to a shared account for partners.
      # Production scoring still writes each team exactly once.
      unless @teams.empty?
        @state = @state.merge(%i[scores barrels zero_rounds surrender_uses].to_h do |field|
          [field, @players.to_h { |player| [player, @state[field].fetch(@teams.fetch(player))] }]
        end)
      end
      @actor = player_key(actor)
      @random = Random.new(random_seed(random_source))
      @ranks = game.class::RANKS
      @suits = game.class::SUITS
      @card_points = game.class::CARD_POINTS
      @marriage_points = game.class::MARRIAGE_POINTS
      @events_after_last_deal = events_after_last_deal
      @public_played_cards = public_played_cards
      @known_passed_cards = known_passed_cards
      @inferred_void_suits = inferred_void_suits
      @deck = deck
      @talon_limits = public_talon_limits
    end

    def choose_bid(actions, samples:)
      pass = actions.find { |action| action["bid"].to_s == "pass" }
      bids = actions.filter_map do |action|
        next if action["action"].to_s != "bid" || action["bid"].to_s == "pass"

        [action, Integer(action["bid"].to_s, 10)]
      rescue ArgumentError
        nil
      end
      return pass if bids.empty? && pass != nil
      return nil if bids.empty?

      worlds = sampled_bidding_worlds(samples)
      return nil if worlds.empty?

      # The winning bidder will know the talon before passing cards. Each
      # sampled future therefore adds its talon, chooses a discard pair using
      # only that ten-card hand, and then plays the deal to completion.
      simulation_contract = bids.map(&:last).max
      outcomes = worlds.filter_map do |world|
        simulated = prepare_bidding_world(world, simulation_contract)
        next if simulated == nil

        finish_round(simulated)
        collected_points(simulated, @actor)
      end
      return nil if outcomes.empty?

      statistics = bids.map do |action, bid|
        made = outcomes.count { |points| points >= bid }
        probability = made.to_f / outcomes.length
        mean_margin = outcomes.sum { |points| points - bid } / outcomes.length.to_f
        [action, bid, probability, mean_margin]
      end
      threshold = bidding_safety_threshold
      safe = statistics.select { |_action, _bid, probability, _margin| probability >= threshold }
      if !safe.empty?
        winning = safe.select { |_action, bid, _probability, _margin| projected_win?(@actor, bid) }
        return winning.min_by { |_action, bid, _probability, _margin| bid }.first if !winning.empty?

        return safe.max_by { |_action, bid, probability, margin| [bid, probability, margin] }.first
      end

      denial = barrel_denial_bid(statistics, worlds)
      return denial if denial != nil

      # Passing is preferable to a declaration which failed in too many
      # plausible talons. The compulsory opener still says the lowest legal
      # value when passing is unavailable.
      pass || statistics.min_by { |_action, bid, _probability, _margin| bid }.first
    end

    def choose_play(actions, samples:)
      # On the first trick a marriage cannot be announced.  If the taker has
      # one and also holds an ace, keep control with an unbeatable lead so the
      # marriage can be declared on the next trick.  Pure determinized
      # rollouts used to prefer a vulnerable ten in this position because
      # their model of the defenders was too cooperative.
      actions = marriage_control_opening_actions(actions)
      actions = late_contract_control_actions(actions)
      worlds = sampled_worlds(samples)
      return nil if worlds.empty?

      scored = actions.map do |action|
        utilities = worlds.filter_map do |world|
          simulated = clone_world(world)
          mode, card = parse_action_card(action)
          next if !play_card(simulated, @actor, mode, card)

          finish_round(simulated)
          evaluate(simulated, @actor)
        end
        next [action, -Float::INFINITY] if utilities.empty?

        ordered = utilities.sort
        mean = utilities.sum / utilities.length.to_f
        lower_quartile = ordered[((ordered.length - 1) * 0.25).floor]
        heuristic = @game.bot_action_score(@replay, @actor, action).to_f
        # Averaging across worlds chooses robust actions. A small lower-tail
        # term rejects spectacular moves which fail in too many plausible
        # deals; the ordinary heuristic remains a deterministic tie-breaker.
        [action, mean + lower_quartile * 0.18 + heuristic * 0.03]
      end
      best(scored)
    end

    def choose_contract(actions, samples:)
      worlds = sampled_worlds(samples)
      return nil if worlds.empty?

      bids = actions.filter_map do |action|
        next if action["action"].to_s != "contract"

        [action, Integer(action["bid"].to_s, 10)]
      rescue ArgumentError
        nil
      end
      return nil if bids.empty?

      # The contract changes the score threshold, not the cards which can be
      # won. Play every sampled deal once with the highest legal target so the
      # taker keeps maximizing points, then evaluate all possible declarations
      # against the same outcomes. This removes up to 61 identical full-round
      # simulations without lowering the number of sampled hidden deals.
      simulation_contract = bids.map { |_action, bid| bid }.max
      outcomes = worlds.map do |world|
        simulated = clone_world(world)
        simulated[:contract] = simulation_contract
        finish_round(simulated)
        collected_points(simulated, @actor)
      end
      statistics = bids.map do |action, bid|
        made = outcomes.count { |points| points >= bid }
        utilities = outcomes.map { |points| contract_utility(@actor, bid, points) }
        probability = made.to_f / outcomes.length
        mean = utilities.sum / outcomes.length.to_f
        [action, bid, probability, mean]
      end

      # Determinized play is slightly optimistic because every sampled world
      # is played as if its exact layout were known. Require a substantial
      # safety margin before voluntarily raising the post-talon contract.
      threshold = barrel_active?(@actor) ? 0.86 : 0.82
      safe = statistics.select { |_action, _bid, probability, _mean| probability >= threshold }
      if !safe.empty?
        winning = safe.select { |_action, bid, _probability, _mean| projected_win?(@actor, bid) }
        # When several declarations win the whole match, take the smallest
        # reliable one. Extra risk earns nothing once the target is reached.
        return winning.min_by { |_action, bid, _probability, _mean| bid }.first if !winning.empty?

        return safe.max_by do |_action, bid, probability, mean|
          [bid * (probability * 2.0 - 1.0), mean, bid]
        end.first
      end

      if barrel_active?(@actor)
        barrel_try = statistics.select { |_action, bid, _probability, _mean| bid >= 120 }
        return barrel_try.max_by { |_action, _bid, probability, mean| [probability, mean] }.first if !barrel_try.empty?
      end

      # The auction contract cannot be lowered. If no declaration is reliably
      # safe, retain the smallest legal loss rather than increasing exposure.
      statistics.min_by { |_action, bid, _probability, _mean| bid }.first
    end

    def choose_passing(actions, samples:)
      card_actions = actions.select { |action| action["action"].to_s == "select" }
      surrender = actions.find { |action| action["action"].to_s == "surrender" }
      return surrender if card_actions.empty? && surrender != nil
      return nil if card_actions.empty?

      worlds = sampled_worlds(samples)
      return nil if worlds.empty?
      recipients = @game.send(:pass_recipients, @state)
      pass_index = @state[:pass_index].to_i
      current = recipients[pass_index]
      following = recipients[pass_index + 1]
      current_recipient = current == nil ? nil : player_key(current)
      next_recipient = following == nil ? nil : player_key(following)
      candidates = if !@teams.empty?
        remaining = recipients.drop(pass_index)
        card_actions.flat_map do |action|
          first = action["card"].to_s
          team_pass_sequences(@state[:hands].fetch(@actor) - [first], remaining.drop(1)).map do |rest|
            [action, [[current_recipient, first]] + rest]
          end
        end
      elsif next_recipient == nil
        card_actions.map { |action| [action, [[current_recipient, action["card"].to_s]]] }
      else
        card_actions.flat_map do |first_action|
          card_actions.filter_map do |second_action|
            next if first_action["card"].to_s == second_action["card"].to_s

            [first_action, [
              [current_recipient, first_action["card"].to_s],
              [next_recipient, second_action["card"].to_s]
            ]]
          end
        end
      end

      scored = candidates.map do |action, passes|
        outcomes = worlds.filter_map do |world|
          simulated = clone_world(world)
          valid = passes.all? { |recipient, card| pass_card(simulated, recipient, card) }
          next if !valid

          simulated[:current_player] = @actor
          simulated[:taker] = @actor
          simulated[:contract] = @state[:contract].to_i
          finish_round(simulated)
          collected_points(simulated, @actor)
        end
        next [action, -Float::INFINITY, 0.0] if outcomes.empty?

        contract = @state[:contract].to_i
        probability = outcomes.count { |points| points >= contract }.to_f / outcomes.length
        ordered = outcomes.sort
        lower_quartile = ordered[((ordered.length - 1) * 0.25).floor]
        mean = outcomes.sum / outcomes.length.to_f
        heuristic = @game.bot_action_score(@replay, @actor, action).to_f
        pass_risk = passes.sum do |recipient, card|
          allied?(recipient, @actor) ? 0 : pass_marriage_risk_penalty(card, hand: @state[:hands].fetch(@actor, []))
        end
        [
          action,
          probability * 20_000.0 + mean * 25.0 + lower_quartile * 12.0 +
            heuristic * 0.02 - pass_risk,
          probability
        ]
      end
      chosen = scored.max_by { |_action, score, _probability| score }
      return nil if chosen == nil

      if surrender != nil && surrender_better_than_playing?(chosen[2], @state[:contract].to_i)
        return surrender
      end
      chosen[0]
    end

    # Both talons are face down. Their indices carry no information about
    # their cards, even though the deterministic replay contains those cards.
    def choose_talon(actions)
      actions[@random.rand(actions.length)]
    end

    def choose_discarding(actions, samples:)
      card_actions = actions.select { |action| action["kind"] == "card" }
      return nil if card_actions.empty?
      hand = @state[:hands].fetch(@actor)
      remaining = @game.send(:talon_size, @state) - @state[:pass_index].to_i
      # Shortlist full discard sets, not greedy single-card choices. Keep a
      # candidate for every selectable card without increasing the old
      # passing planner's simulation budget (up to 90 pairs x 40 worlds).
      ranked = ranked_discards(hand, remaining, actor: @actor)
      candidates = ranked.first(12)
      card_actions.each do |action|
        candidate = ranked.find { |cards| cards.include?(action["card"]) }
        candidates << candidate if candidate && !candidates.include?(candidate)
      end
      worlds = sampled_worlds(samples)
      return nil if worlds.empty?
      scored = candidates.map do |cards|
        outcomes = worlds.map do |world|
          simulated = clone_world(world)
          cards.each do |card|
            simulated[:hands][@actor].delete(card)
            simulated[:set_aside] << card
          end
          simulated[:current_player] = @actor
          finish_round(simulated)
          simulated[:round_points].fetch(@actor, 0)
        end
        probability = outcomes.count { |points| points >= @state[:contract].to_i }.to_f / outcomes.length
        ordered = outcomes.sort
        score = probability * 20_000 + outcomes.sum.to_f / outcomes.length * 25 + ordered[((ordered.length - 1) * 0.25).floor] * 12
        [cards, score, probability]
      end
      chosen = scored.max_by { |_cards, score, _probability| score }
      return nil unless chosen
      surrender = actions.find { |action| action["action"] == "surrender" }
      if surrender && surrender_better_than_playing?(chosen[2], @state[:contract].to_i)
        return surrender
      end
      card_actions.find { |action| chosen[0].include?(action["card"]) }
    end

    private

    def marriage_control_opening_actions(actions)
      choices = actions.to_a
      return choices if !same_player?(@state[:taker], @actor)
      return choices if @state[:trick_number].to_i != 0 || !@state[:current_trick].to_a.empty?

      hand = @state[:hands].fetch(@actor, []).to_a
      marriage = @suits.any? do |suit|
        hand.include?("K#{suit}") && hand.include?("Q#{suit}")
      end
      return choices if !marriage

      aces = choices.select do |action|
        mode, card = parse_action_card(action)
        mode == "normal" && card_rank(card) == "A"
      end
      aces.empty? ? choices : aces
    end

    def late_contract_control_actions(actions)
      choices = actions.to_a
      # Cashing an ace now can give away the set-aside cards on the last
      # trick. In this variant evaluate every legal continuation instead.
      return choices if two_players? && @state[:options]["last_trick_talon"]
      return choices if !same_player?(@state[:taker], @actor)
      return choices if !@state[:current_trick].to_a.empty?

      hand = @state[:hands].fetch(@actor, []).to_a
      return choices if hand.length > 2
      return choices if @state[:round_points].fetch(@actor, 0).to_i >= @state[:contract].to_i
      # A side-suit ace can be ruffed. Do not discard every alternative before
      # the planner has even evaluated it; only a trump ace (or no trumps)
      # provides the unconditional control this shortcut assumes.
      trump = @state[:trump]

      aces = choices.select do |action|
        mode, card = parse_action_card(action)
        mode == "normal" && card_rank(card) == "A" && (trump == nil || card_suit(card) == trump)
      end
      aces.empty? ? choices : aces
    end

    def pass_marriage_risk_penalty(card, hand:)
      rank = card_rank(card)
      return 0.0 if !["K", "Q"].include?(rank)

      suit = card_suit(card)
      partner = "#{rank == 'K' ? 'Q' : 'K'}#{suit}"
      weight = hand.to_a.include?(partner) ? BREAK_MARRIAGE_RISK_WEIGHT : PASS_MARRIAGE_RISK_WEIGHT
      @marriage_points.fetch(suit).to_f * weight
    end

    def sampled_bidding_worlds(count)
      result = []
      attempts = 0
      maximum_attempts = [count.to_i * 80, 80].max
      while result.length < count.to_i && attempts < maximum_attempts
        attempts += 1
        world = sample_bidding_world
        result << world if world != nil
      end
      result
    end

    def sample_bidding_world
      own_hand = @state[:hands].fetch(@actor, []).to_a.dup
      unknown = deck - own_hand
      opponents = @players.reject { |player| same_player?(player, @actor) }
      sizes = opponents.to_h { |player| [player, @state[:hands].fetch(player, []).length] }
      talon_size = unknown.length - sizes.values.sum
      expected = @game.send(:talon_size, @state) * (two_players? ? 2 : 1)
      return nil if talon_size != expected

      shuffled = deterministic_shuffle(unknown, @random)
      hands = { @actor => own_hand }
      offset = 0
      opponents.each do |player|
        hands[player] = shuffled.slice(offset, sizes.fetch(player)).to_a
        offset += sizes.fetch(player)
      end
      talon = shuffled.slice(offset, talon_size).to_a
      return nil if publicly_promised_marriage_missing?(hands)

      if two_players?
        size = @game.send(:talon_size, @state)
        world_from_state(hands: hands).merge(talon: talon.first(size), set_aside: talon.last(size))
      else
        world_from_state(hands: hands).merge(talon: talon)
      end
    end

    def prepare_bidding_world(world, contract, taker: @actor)
      simulated = clone_world(world)
      ten_cards = simulated[:hands].fetch(taker, []).to_a + world.fetch(:talon, []).to_a
      pair = if two_players?
        ranked_discards(ten_cards, @game.send(:talon_size, @state), actor: taker).first
      elsif !@teams.empty?
        recipients = @players.reject { |player| same_player?(player, taker) }
        team_pass_sequences(ten_cards, recipients, actor: taker, width: 1).first&.map(&:last)
      else
        recommended_pass_pair(ten_cards, actor: taker)
      end
      return nil if pair == nil

      retained = ten_cards.dup
      pair.each { |card| retained.delete_at(retained.index(card)) }
      if two_players?
        simulated[:set_aside].concat(pair)
      else
        recipients = @players.reject { |player| same_player?(player, taker) }
        recipients.each_with_index { |recipient, index| simulated[:hands].fetch(recipient) << pair[index] }
      end
      simulated[:hands][taker] = retained
      simulated[:current_player] = taker
      simulated[:taker] = taker
      simulated[:contract] = contract.to_i
      simulated[:trump] = nil
      simulated[:current_trick] = []
      simulated[:trick_number] = 0
      simulated[:round_points] = @players.to_h { |player| [player, 0] }
      simulated
    end

    def two_players?
      @game.send(:two_players?, @state)
    end

    # Keep every first-card candidate, but bound the continuation beam. Only
    # the bidder's own hand is used here, never a real partner's hidden hand.
    def team_pass_sequences(hand, recipients, actor: @actor, width: 3)
      return [[]] if recipients.empty?
      recipient = recipients.first
      candidates = hand.sort_by do |card|
        marriage = breaks_marriage?(hand, card) ? 2_000 : 0
        value = @card_points.fetch(card_rank(card)) * 18 + card_strength(card) * 12
        [marriage + (allied?(recipient, actor) ? -value : value), card]
      end.first(width)
      candidates.flat_map do |card|
        team_pass_sequences(hand - [card], recipients.drop(1), actor: actor, width: width).map do |rest|
          [[recipient, card]] + rest
        end
      end
    end

    def ranked_discards(hand, count, actor:)
      public_hands = @players.to_h { |player| [player, []] }
      public_hands[actor] = hand
      public_state = @state.merge(phase: :discarding, hands: public_hands, taker: actor)
      hand.combination(count).sort_by do |cards|
        retained_state = public_state.merge(hands: public_hands.merge(actor => hand - cards))
        estimate = @game.send(:bot_contract_estimate, retained_state, actor)
        disposal = cards.sum { |card| @game.send(:bot_pass_card_score, public_state, actor, card) }
        # No passed-marriage penalty: these cards cannot form a marriage in
        # the opponent's hand. The retained-hand estimate values our pairs.
        [-(estimate * 100 + disposal), cards.join]
      end
    end

    def recommended_pass_pair(hand, actor: @actor)
      public_hands = @players.to_h { |player| [player, []] }
      public_hands[actor] = hand.to_a
      state_with_talon = @state.merge(
        phase: :passing,
        current_player: actor,
        taker: actor,
        hands: public_hands
      )
      hand.to_a.combination(2).max_by do |pair|
        retained = hand.to_a.dup
        pair.each { |card| retained.delete_at(retained.index(card)) }
        retained_state = state_with_talon.merge(
          hands: state_with_talon[:hands].merge(actor => retained)
        )
        estimate = @game.send(:bot_contract_estimate, retained_state, actor).to_f
        disposal = pair.sum do |card|
          @game.send(:bot_pass_card_score, state_with_talon, actor, card).to_f
        end
        marriage_risk = pair.sum { |card| pass_marriage_risk_penalty(card, hand: hand) }
        [estimate * 100.0 + disposal - marriage_risk, pair.sort.join]
      end
    end

    def barrel_denial_bid(statistics, worlds)
      return nil if barrel_active?(@actor)

      threatened = player_key(@state[:current_bidder])
      return nil if threatened == nil || allied?(threatened, @actor)
      threatened_barrel = @state[:barrels].fetch(threatened, { active: false })
      return nil if threatened_barrel[:active] != true

      threat_probability = barrel_bidder_success_probability(worlds, threatened)
      blocker = next_available_blocker(threatened)
      blocker_capacity = blocker == nil ? 0.0 : blocker_bid_capacity(worlds, blocker)
      select_barrel_denial(
        statistics,
        threatened: threatened,
        threat_probability: threat_probability,
        blocker: blocker,
        blocker_capacity: blocker_capacity
      )
    end

    def select_barrel_denial(statistics, threatened:, threat_probability:, blocker:, blocker_capacity:)
      return nil if barrel_active?(@actor)

      barrel = @state[:barrels].fetch(threatened, { active: false, deals_left: 0 })
      return nil if barrel[:active] != true

      minimum_threat = barrel[:deals_left].to_i <= 1 ? 0.34 : 0.48
      return nil if threat_probability.to_f < minimum_threat

      # A still-active next player with a credible hand is allowed to carry
      # the defensive auction. Passing here is deliberate burden sharing, not
      # an assumption that the current bot can return after passing.
      delegation_level = barrel_active?(blocker) ? 0.55 : 0.70
      return nil if blocker != nil && blocker_capacity.to_f >= delegation_level

      threshold = barrel_denial_threshold(
        deals_left: barrel[:deals_left].to_i,
        blocker_capacity: blocker_capacity,
        blocker_present: blocker != nil
      )
      normal_threshold = bidding_safety_threshold
      candidates = statistics.select do |_action, bid, probability, _margin|
        required = surrender_could_award_match?(bid) ? normal_threshold : threshold
        probability >= required
      end
      return nil if candidates.empty?

      # Denial is not an invitation to inflate the eventual loss. Raise by the
      # minimum supported amount and let the next auction turn reassess any
      # counterbid from the barrel player.
      candidates.min_by { |_action, bid, probability, margin| [bid, -probability, -margin] }.first
    end

    def barrel_bidder_success_probability(worlds, bidder)
      contract = [@state[:current_bid].to_i, 120].max
      outcomes = worlds.filter_map do |world|
        simulated = prepare_bidding_world(world, contract, taker: bidder)
        next if simulated == nil

        finish_round(simulated)
        collected_points(simulated, bidder)
      end
      return 0.0 if outcomes.empty?

      outcomes.count { |points| points >= contract }.to_f / outcomes.length
    end

    def next_available_blocker(threatened)
      @players.find do |player|
        !same_player?(player, @actor) && !same_player?(player, threatened) &&
          @state[:passed].fetch(player, false) != true
      end
    end

    def blocker_bid_capacity(worlds, blocker)
      next_bid = @state[:current_bid].to_i + 5
      capable = worlds.count do |world|
        hand = world[:hands].fetch(blocker, [])
        public_hands = @players.to_h { |player| [player, []] }
        public_hands[blocker] = hand
        sampled_state = @state.merge(phase: :bidding, hands: public_hands)
        @game.send(:bot_contract_estimate, sampled_state, blocker).to_f >= next_bid
      end
      worlds.empty? ? 0.0 : capable.to_f / worlds.length
    end

    def barrel_denial_threshold(deals_left:, blocker_capacity:, blocker_present:)
      threshold = if deals_left.to_i <= 1
        0.34
      elsif deals_left.to_i == 2
        0.42
      else
        0.50
      end
      if blocker_present
        # The more often the next active player appears capable of raising,
        # the less risk this bot should accept on that player's behalf.
        threshold += 0.08 + blocker_capacity.to_f * 0.12
      end
      threshold += 0.16 if @state[:surrender_uses].fetch(@actor, 0).to_i >= 2
      [threshold, 0.70].min
    end

    def surrender_could_award_match?(contract)
      raw_award = [60.0, contract.to_f / 2.0].max
      award = (raw_award / 5.0).ceil * 5
      target = @state[:options]["score_limit"].to_i
      @players.any? do |player|
        next false if allied?(player, @actor) || barrel_active?(player)

        @state[:scores].fetch(player, 0).to_i + award >= target
      end
    end

    def bidding_safety_threshold
      return 0.70 if !barrel_active?(@actor)

      deals_left = @state[:barrels].fetch(@actor, { deals_left: 3 })[:deals_left].to_i
      [0.70 - (3 - deals_left) * 0.06, 0.56].max
    end

    def sampled_worlds(count)
      result = []
      attempts = 0
      maximum_attempts = [count.to_i * 80, 80].max
      while result.length < count.to_i && attempts < maximum_attempts
        attempts += 1
        world = sample_world
        result << world if world != nil
      end
      result
    end

    def sample_world
      return sample_two_player_world if two_players?
      own_hand = @state[:hands].fetch(@actor, []).to_a.dup
      played = @public_played_cards
      fixed = @known_passed_cards.transform_values do |cards|
        cards.reject { |card| played.include?(card) }
      end
      unknown = deck - own_hand - played - fixed.values.flatten
      opponents = @players.reject { |player| same_player?(player, @actor) }
      sizes = opponents.to_h do |player|
        [player, @state[:hands].fetch(player, []).length - fixed.fetch(player, []).length]
      end
      return nil if sizes.values.sum != unknown.length

      voids = @inferred_void_suits
      shuffled = deterministic_shuffle(unknown, @random)
      hands = { @actor => own_hand }
      offset = 0
      opponents.each do |player|
        hands[player] = fixed.fetch(player, []).dup + shuffled.slice(offset, sizes.fetch(player)).to_a
        offset += sizes.fetch(player)
      end
      return nil if opponents.any? do |player|
        hands.fetch(player).any? { |card| voids.fetch(player, []).include?(card_suit(card)) }
      end
      return nil if publicly_promised_marriage_missing?(hands)
      return nil if public_talon_assignment_impossible?(hands)

      world_from_state(hands: hands)
    end

    def sample_two_player_world
      own_hand = @state[:hands].fetch(@actor, []).dup
      taker = player_key(@state[:taker])
      opponent = @players.find { |player| player != @actor }
      # Only the bidder knows which cards they discarded. Never derive this
      # from somebody else's discard events or from the actual reserve.
      known_discards = @actor == taker ? @state[:discarded_cards].to_a.dup : []
      unknown = deck - own_hand - @public_played_cards - known_discards
      size = @game.send(:talon_size, @state)
      hidden_discards = @actor == taker ? 0 : @state[:pass_index].to_i
      opponent_size = @state[:hands].fetch(opponent).length
      return nil unless unknown.length == opponent_size + size + hidden_discards
      shuffled = deterministic_shuffle(unknown, @random)
      allowed = shuffled.reject { |card| @inferred_void_suits.fetch(opponent).include?(card_suit(card)) }
      return nil if allowed.length < opponent_size
      public_talon = @state[:talon].to_a - @public_played_cards
      mandatory = if opponent == taker
        count = [public_talon.length - hidden_discards, 0].max
        (allowed & public_talon).first(count)
      else
        []
      end
      opponent_hand = mandatory + (allowed - mandatory).first(opponent_size - mandatory.length)
      remaining = shuffled - opponent_hand
      public_discards = opponent == taker ? remaining & public_talon : []
      return nil if public_discards.length > hidden_discards
      discards = public_discards + (remaining - public_discards).first(hidden_discards - public_discards.length)
      unused = remaining - discards
      discards += known_discards
      hands = { @actor => own_hand, opponent => opponent_hand }
      # Publicly revealed talon cards can be held, played or discarded by
      # the taker, but cannot secretly belong to the unused talon/defender.
      return nil unless (public_talon - hands.fetch(taker) - discards).empty?
      return nil if publicly_promised_marriage_missing?(hands)
      world_from_state(hands: hands).merge(set_aside: unused + discards)
    end

    def public_talon_assignment_impossible?(hands)
      @talon_limits.any? do |player, (talon, maximum)|
        (hands.fetch(player, []) & talon).length > maximum
      end
    end

    def public_talon_limits
      # The UI hides the talon after the contract; its earlier disclosure is
      # still public knowledge. Never apply this before the auction finishes.
      return {} unless @state[:taker] && [:passing, :contract, :playing, :round_complete].include?(@state[:phase])
      talon = @state[:talon].to_a
      @players.reject { |player| same_player?(player, @state[:taker]) }.to_h do |player|
        received = @events_after_last_deal.count do |event|
          event["action"] == "pass_card" && same_player?(event["value"].to_s.split("|", 2).first, player)
        end
        played = @events_after_last_deal.filter_map do |event|
          event["value"].to_s.split("|", 2)[1] if event["action"] == "play" && same_player?(event["actor"], player)
        end
        [player, [talon - played, received - (played & talon).length]]
      end
    end

    def world_from_state(hands:)
      {
        players: @players.dup,
        hands: hands,
        current_player: player_key(@state[:current_player]),
        taker: @state[:taker] == nil ? nil : player_key(@state[:taker]),
        contract: @state[:contract].to_i,
        trump: @state[:trump],
        current_trick: @state[:current_trick].to_a.map(&:dup),
        trick_number: @state[:trick_number].to_i,
        round_points: @players.to_h { |player| [player, @state[:round_points].fetch(player, 0).to_i] },
        scores: @state[:scores].each_with_object({}) do |(player, points), result_hash|
          result_hash[player_key(player)] = points.to_i
        end,
        barrels: @state[:barrels].each_with_object({}) do |(player, barrel), result_hash|
          result_hash[player_key(player)] = barrel.dup
        end,
        zero_rounds: @state[:zero_rounds].each_with_object({}) do |(player, count), result_hash|
          result_hash[player_key(player)] = count.to_i
        end,
        surrender_uses: @state[:surrender_uses].each_with_object({}) do |(player, count), result_hash|
          result_hash[player_key(player)] = count.to_i
        end,
        last_trick_talon: two_players? && @state[:options]["last_trick_talon"] == true,
        set_aside: [],
        score_limit: @state[:options]["score_limit"].to_i
      }
    end

    # Keep this planner entry point and its caller-owned RNG stable.
    def deterministic_shuffle(values, random)
      GameRoomRandom.shuffle(values, random: random)
    end

    def finish_round(world)
      32.times do
        break if world[:hands].values.all?(&:empty?)
        actor = world[:current_player]
        break if actor == nil

        mode, card = rollout_choice(world, actor)
        break if card == nil || !play_card(world, actor, mode, card)
      end
      world
    end

    def rollout_choice(world, actor)
      hand = world[:hands].fetch(actor, [])
      return [nil, nil] if hand.empty?

      if world[:current_trick].empty? && world[:trick_number] > 0
        marriages = @suits.select do |suit|
          hand.include?("K#{suit}") && hand.include?("Q#{suit}")
        end
        if !marriages.empty?
          suit = marriages.max_by { |candidate| @marriage_points.fetch(candidate) }
          # Use the cheaper half when both declare the same marriage; retain
          # the king for a later trick whenever possible.
          return ["marriage", "Q#{suit}"]
        end
      end

      legal = legal_cards(world, actor)
      return ["normal", legal.first] if legal.length <= 1
      preserving = legal.reject { |card| breaks_marriage?(hand, card) }
      legal = preserving if !preserving.empty?
      taker = world[:taker]
      need = [world[:contract] - collected_points(world, taker), 0].max

      if world[:current_trick].empty?
        certain = legal.select { |card| guaranteed_lead_winner?(world, actor, card) }
        if !certain.empty?
          return ["normal", certain.max_by { |card| [@card_points.fetch(card_rank(card)), card_strength(card)] }]
        end
        return ["normal", legal.min_by { |card| rollout_card_cost(card) }]
      end

      current_winner = trick_winner(world[:current_trick], world[:trump])
      if !@teams.empty? && allied?(current_winner, actor)
        donated = legal.select do |card|
          allied?(trick_winner(world[:current_trick] + [{player: actor, card: card}], world[:trump]), actor)
        end
        if world[:current_trick].length == @players.length - 1 && !donated.empty?
          return ["normal", donated.max_by { |card| @card_points.fetch(card_rank(card)) }]
        end
      end
      trick_points = world[:current_trick].sum { |play| @card_points.fetch(card_rank(play[:card])) }
      avoids_third_zero = collected_points(world, actor) == 0 &&
        world[:zero_rounds].fetch(actor, 0).to_i >= 2
      wants_trick = if allied?(actor, taker)
        need > 0 || trick_points >= 10 || opponent_close_to_winning?(world, actor)
      else
        allied?(current_winner, taker) || trick_points >= 10 || avoids_third_zero
      end
      return ["normal", legal.min_by { |card| rollout_card_cost(card) }] if !wants_trick

      winners = legal.select do |card|
        candidate = world[:current_trick] + [{ player: actor, card: card }]
        same_player?(trick_winner(candidate, world[:trump]), actor)
      end
      if winners.empty?
        return ["normal", legal.min_by { |card| rollout_card_cost(card) }]
      end

      guaranteed = winners.select { |card| guaranteed_current_trick_winner?(world, actor, card) }
      chosen = (guaranteed.empty? ? winners : guaranteed).min_by { |card| rollout_card_cost(card) }
      ["normal", chosen]
    end

    def play_card(world, actor, mode, card)
      hand = world[:hands].fetch(actor, [])
      return false if !hand.include?(card) || !legal_cards(world, actor).include?(card)

      if mode == "marriage"
        suit = card_suit(card)
        return false if !world[:current_trick].empty? || world[:trick_number] == 0
        return false if !["K", "Q"].include?(card_rank(card))
        return false if !hand.include?("K#{suit}") || !hand.include?("Q#{suit}")

        world[:round_points][actor] += @marriage_points.fetch(suit)
        world[:trump] = suit
      end
      hand.delete_at(hand.index(card))
      world[:current_trick] << { player: actor, card: card }
      if world[:current_trick].length < world[:players].length
        world[:current_player] = next_player(actor)
        return true
      end

      winner = trick_winner(world[:current_trick], world[:trump])
      points = world[:current_trick].sum { |play| @card_points.fetch(card_rank(play[:card])) }
      world[:round_points][winner] += points
      world[:current_trick] = []
      world[:trick_number] += 1
      world[:current_player] = world[:hands].values.all?(&:empty?) ? nil : winner
      if world[:current_player] == nil && world[:last_trick_talon]
        world[:round_points][winner] += world[:set_aside].sum { |item| @card_points.fetch(card_rank(item)) }
      end
      true
    end

    def pass_card(world, recipient, card)
      hand = world[:hands].fetch(@actor, [])
      index = hand.index(card)
      return false if index == nil || recipient == nil

      hand.delete_at(index)
      world[:hands].fetch(recipient) << card
      true
    end

    def legal_cards(world, actor)
      hand = world[:hands].fetch(actor, [])
      return hand.dup if world[:current_trick].empty?

      led = card_suit(world[:current_trick].first[:card])
      following = hand.select { |card| card_suit(card) == led }
      return following if !following.empty?

      if world[:trump] != nil
        trumps = hand.select { |card| card_suit(card) == world[:trump] }
        return trumps if !trumps.empty?
      end
      hand.dup
    end

    def guaranteed_lead_winner?(world, actor, card)
      opponents = world[:players].reject { |player| same_player?(player, actor) }
      suit = card_suit(card)
      higher = opponents.any? do |player|
        world[:hands].fetch(player).any? do |candidate|
          card_suit(candidate) == suit && card_strength(candidate) > card_strength(card)
        end
      end
      return false if higher

      trump = world[:trump]
      return true if trump == nil || suit == trump

      !opponents.any? do |player|
        hand = world[:hands].fetch(player)
        hand.none? { |candidate| card_suit(candidate) == suit } &&
          hand.any? { |candidate| card_suit(candidate) == trump }
      end
    end

    def guaranteed_current_trick_winner?(world, actor, card)
      actor_index = world[:players].index(actor)
      remaining = world[:players].length - world[:current_trick].length - 1
      future = []
      current = actor_index
      remaining.times do
        current = (current + 1) % world[:players].length
        future << world[:players][current]
      end
      trick = world[:current_trick] + [{ player: actor, card: card }]
      return false if !same_player?(trick_winner(trick, world[:trump]), actor)

      future.all? do |player|
        legal_cards_for_trick(world, player, trick).all? do |reply|
          same_player?(trick_winner(trick + [{ player: player, card: reply }], world[:trump]), actor)
        end
      end
    end

    def legal_cards_for_trick(world, actor, trick)
      hand = world[:hands].fetch(actor, [])
      led = card_suit(trick.first[:card])
      following = hand.select { |card| card_suit(card) == led }
      return following if !following.empty?
      if world[:trump] != nil
        trumps = hand.select { |card| card_suit(card) == world[:trump] }
        return trumps if !trumps.empty?
      end
      hand.dup
    end

    def evaluate(world, actor)
      taker = world[:taker]
      taker_points = collected_points(world, taker)
      made = taker_points >= world[:contract]
      actor_points = collected_points(world, actor)
      if allied?(actor, taker)
        value = made ? 12_000.0 : -14_000.0
        value += (taker_points - world[:contract]) * (made ? 8.0 : 35.0)
        return value + match_context_utility(world, actor, made)
      end

      value = made ? -10_000.0 : 13_000.0
      value += actor_points * (barrel_active?(actor) ? 1.0 : 18.0)
      value -= taker_points * 3.0
      value + match_context_utility(world, actor, made)
    end

    def match_context_utility(world, actor, taker_made)
      deltas = world[:players].to_h do |player|
        [player, projected_round_delta(world, player, taker_made)]
      end
      projected = world[:players].to_h do |player|
        [player, world[:scores].fetch(player, 0).to_i + deltas.fetch(player, 0).to_i]
      end
      value = deltas.fetch(actor, 0).to_f * 20.0
      value += 50_000.0 if projected.fetch(actor, 0) >= world[:score_limit].to_i
      value -= 50_000.0 if world[:players].any? do |player|
        !allied?(player, actor) && projected.fetch(player, 0) >= world[:score_limit].to_i
      end
      opponent_gain = world[:players].reject { |player| allied?(player, actor) }
        .map { |player| deltas.fetch(player, 0) }.max.to_i
      value - [opponent_gain, 0].max * 4.0
    end

    def projected_round_delta(world, player, taker_made)
      barrel = world[:barrels].fetch(player, { active: false, deals_left: 0 })
      active_barrel = barrel[:active] == true
      points = collected_points(world, player)
      delta = if allied?(player, world[:taker])
        if active_barrel
          if taker_made && world[:contract].to_i >= 120
            world[:contract].to_i
          elsif !taker_made
            -world[:contract].to_i
          else
            0
          end
        else
          taker_made ? world[:contract].to_i : -world[:contract].to_i
        end
      elsif active_barrel
        0
      else
        (points.to_f / 5.0).round * 5
      end

      if active_barrel && !(!taker_made && allied?(player, world[:taker])) &&
          !(taker_made && allied?(player, world[:taker]) && world[:contract].to_i >= 120) &&
          barrel[:deals_left].to_i <= 1
        delta -= 120
      elsif !active_barrel && points == 0 && world[:zero_rounds].fetch(player, 0).to_i >= 2
        delta -= 120
      end
      delta
    end

    def opponent_close_to_winning?(world, actor)
      world[:players].any? do |player|
        !allied?(player, actor) &&
          world[:scores].fetch(player, 0).to_i >= world[:score_limit].to_i - 120
      end
    end

    def publicly_promised_marriage_missing?(hands)
      # The auction promise is useful while sampling the first position. Once
      # cards have been played it can become false naturally (and the taker may
      # already have passed half of the marriage to a defender).
      return false if !public_played_cards.empty?

      @state[:bids].any? do |player, bid|
        next false if bid.to_s == "pass" || bid.to_i <= 120
        next false if same_player?(player, @state[:taker])

        sampled = hands.fetch(player_key(player), [])
        !@suits.any? { |suit| sampled.include?("K#{suit}") && sampled.include?("Q#{suit}") }
      end
    end

    def inferred_void_suits
      return @inferred_void_suits if defined?(@inferred_void_suits) && @inferred_void_suits != nil

      voids = @players.to_h { |player| [player, []] }
      trick = []
      trump = nil
      public_plays.each do |play|
        mode, card = play.values_at(:mode, :card)
        trump = card_suit(card) if trick.empty? && mode == "marriage"
        if !trick.empty?
          led = card_suit(trick.first[:card])
          player = player_key(play[:player])
          if card_suit(card) != led
            voids[player] << led
            voids[player] << trump if trump != nil && card_suit(card) != trump
          end
        end
        trick << { player: player_key(play[:player]), card: card }
        trick = [] if trick.length == @players.length
      end
      voids.transform_values(&:uniq)
    end

    def events_after_last_deal
      return @events_after_last_deal if defined?(@events_after_last_deal) && @events_after_last_deal != nil

      events = GameRoomParticipantDecisionEvents.for(@replay).to_a
      index = events.rindex { |event| event["action"].to_s == "deal" }
      index == nil ? events : events[(index + 1)..]
    end

    def public_played_cards
      return @public_played_cards if defined?(@public_played_cards) && @public_played_cards != nil

      public_plays.map { |play| play[:card] }
    end

    def public_plays
      @public_plays ||= events_after_last_deal.filter_map { |event| TysiacPlanning.public_play(event) }
    end

    def known_passed_cards
      known = @players.to_h { |player| [player, []] }
      events_after_last_deal.each do |event|
        next if event["action"].to_s != "pass_card" || !same_player?(event["actor"], @actor)

        recipient, card = event["value"].to_s.split("|", 2)
        key = player_key(recipient)
        known[key] << card if key != nil && card != nil
      end
      known
    end

    def parse_action_card(action)
      action["card"].to_s.split("|", 2)
    end

    def trick_winner(trick, trump)
      led = card_suit(trick.first[:card])
      trick.max_by do |play|
        suit = card_suit(play[:card])
        suit_value = if trump != nil && suit == trump
          2
        elsif suit == led
          1
        else
          0
        end
        [suit_value, card_strength(play[:card])]
      end[:player]
    end

    def rollout_card_cost(card)
      @card_points.fetch(card_rank(card)) * 20 + card_strength(card) * 8
    end

    def breaks_marriage?(hand, card)
      rank = card_rank(card)
      return false if !["K", "Q"].include?(rank)

      suit = card_suit(card)
      hand.include?("K#{suit}") && hand.include?("Q#{suit}")
    end

    def card_rank(card)
      card.to_s[0]
    end

    def card_suit(card)
      card.to_s[1]
    end

    def card_strength(card)
      @ranks.index(card_rank(card)).to_i
    end

    def deck
      return @deck if defined?(@deck) && @deck != nil

      @suits.product(@ranks).map { |suit, rank| "#{rank}#{suit}" }
    end

    def next_player(actor)
      index = @players.index { |player| same_player?(player, actor) }
      raise KeyError, "unknown simulated player #{actor.inspect}; players=#{@players.inspect}" if index == nil
      @players[(index + 1) % @players.length]
    end

    def player_key(actor)
      return nil if actor == nil || actor.to_s.empty?

      @players.find { |player| same_player?(player, actor) } || actor.to_s
    end

    def same_player?(first, second)
      first.to_s.casecmp?(second.to_s)
    end

    def allied?(first, second)
      return true if same_player?(first, second)
      team = @teams[player_key(first)]
      team && team == @teams[player_key(second)]
    end

    def collected_points(world, actor)
      world[:players].sum { |player| allied?(player, actor) ? world[:round_points].fetch(player, 0).to_i : 0 }
    end

    def barrel_active?(actor)
      key = player_key(actor)
      barrel = @state[:barrels].fetch(key, { active: false })
      barrel[:active] == true
    end

    def projected_win?(actor, contract)
      key = player_key(actor)
      return false if barrel_active?(key) && contract.to_i < 120

      @state[:scores].fetch(key, 0).to_i + contract.to_i >= @state[:options]["score_limit"].to_i
    end

    def contract_utility(actor, contract, points)
      made = points.to_i >= contract.to_i
      value = made ? 12_000.0 : -14_000.0
      value += (points.to_i - contract.to_i) * (made ? 8.0 : 35.0)
      value += 50_000.0 if made && projected_win?(actor, contract)
      value
    end

    def surrender_better_than_playing?(sample_probability, contract)
      # Determinization lets each rollout adapt to a sampled hidden layout, so
      # its raw success rate is optimistic. Reserving twelve percentage points
      # prevents the compulsory opening bid of 100 from becoming an automatic
      # large loss after an unhelpful talon.
      adjusted = [[sample_probability.to_f - 0.12, 0.0].max, 1.0].min
      playing_value = contract.to_f * (adjusted * 2.0 - 1.0)
      uses = @state[:surrender_uses].fetch(@actor, 0).to_i
      surrender_value = uses >= 2 ? -120.0 : 0.0
      playing_value < surrender_value
    end

    def best(scored)
      maximum = scored.map(&:last).max
      candidates = scored.select { |_action, score| score == maximum }.map(&:first)
      candidates[@random.rand(candidates.length)]
    end

    def random_seed(random_source)
      values = random_source.roll(count: 7, sides: 1_000).values
      values.reduce(0) { |seed, value| ((seed * 1_001) ^ value.to_i) & 0x7fff_ffff_ffff_ffff }
    end

    def clone_world(world)
      {
        players: world[:players].dup,
        hands: world[:hands].transform_values(&:dup),
        current_player: world[:current_player],
        taker: world[:taker],
        contract: world[:contract],
        trump: world[:trump],
        current_trick: world[:current_trick].map(&:dup),
        trick_number: world[:trick_number],
        round_points: world[:round_points].dup,
        scores: world[:scores].dup,
        barrels: world[:barrels].transform_values(&:dup),
        zero_rounds: world[:zero_rounds].dup,
        surrender_uses: world[:surrender_uses].dup,
        last_trick_talon: world[:last_trick_talon],
        set_aside: world.fetch(:set_aside, []).dup,
        score_limit: world[:score_limit]
      }
    end
  end
end
