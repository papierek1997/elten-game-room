require "digest"
require_relative "game_bots"
require_relative "game_random"

module NinetyNinePlanning
  # Sampled worlds own an immutable value graph. Search branches copy only
  # the collections this reducer changes; all shared leaves stay frozen.
  # This contract is local to the planner, never a general snapshot policy.
  class State < Hash
    def self.from(source)
      owned = Marshal.load(Marshal.dump(source))
      freeze_tree(owned, {})
      new.replace(owned)
    end

    def self.freeze_tree(value, seen)
      return value if value.frozen? || seen[value.object_id]
      seen[value.object_id] = true
      case value
      when Hash then value.each { |key, item| freeze_tree(key, seen); freeze_tree(item, seen) }
      when Array then value.each { |item| freeze_tree(item, seen) }
      end
      value.freeze
    end
    private_class_method :freeze_tree

    def fork
      dup.tap do |copy|
        copy[:tokens] = self[:tokens].dup
        copy[:eliminated] = self[:eliminated].dup
        copy[:hands] = self[:hands].transform_values(&:dup)
        copy[:draw_pile] = self[:draw_pile].dup
        copy[:discard] = self[:discard].dup
      end
    end
  end

  module Transition
    module_function

    # Apply a play to an isolated planning state and perform the replacement
    # draw immediately.  The live game still uses its normal play/draw events;
    # this is only a pure preview for the bot's search tree.
    def play(game, source, actor, action)
      state = (source.is_a?(State) ? source : State.from(source)).fork
      card, mode = action["card"].to_s.split("|", 2)
      player = state[:players].find { |candidate| game.send(:same_user?, candidate, actor) }
      return nil if player == nil || !state[:hands].fetch(player, []).include?(card)

      old_total = state[:total].to_i
      new_total = game.send(:total_after_card, old_total, card, mode)
      state[:hands][player].delete_at(state[:hands][player].index(card))
      state[:discard] << card.freeze
      state[:total] = new_total
      rank = card.to_s[1]
      state[:direction] *= -1 if rank == "4" && active_players(state).length > 2

      [33, 66].each do |limit|
        charge(state, player, 1) if old_total < limit && new_total > limit
      end
      if game.send(:exact_danger_reached?, old_total, new_total, card)
        active_players(state).each do |other|
          charge(state, other, 1) if other != player
        end
      end

      if new_total == 99
        active_players(state).each do |other|
          charge(state, other, 2) if other != player
        end
        finish_round(state)
        return state
      elsif new_total > 99
        charge(state, player, 2)
        finish_round(state)
        return state
      elsif active_players(state).length <= 1
        state[:winner] = active_players(state).first
        state[:phase] = :finished
        state[:current_player] = nil
        state[:pending_player] = nil
        return state
      end

      next_player = next_active_player(state, player, rank == "J" ? 2 : 1)
      if state[:eliminated][player]
        state[:phase] = :playing
        state[:current_player] = next_active_player(state, player, 1)
        state[:pending_player] = nil
        return state
      end

      refill_draw_pile(state)
      state[:hands][player] << state[:draw_pile].shift if !state[:draw_pile].empty?
      state[:phase] = :playing
      state[:current_player] = next_player
      state[:pending_player] = nil
      state
    end

    def active_players(state)
      state[:players].reject { |player| state[:eliminated][player] }
    end

    def next_active_player(state, actor, steps)
      index = state[:players].index(actor)
      return nil if index == nil

      steps.to_i.times do
        state[:players].length.times do
          index = (index + state[:direction].to_i) % state[:players].length
          break if !state[:eliminated][state[:players][index]]
        end
      end
      state[:players][index]
    end

    def charge(state, player, amount)
      return if player == nil || state[:eliminated][player]

      available = state[:tokens][player].to_i
      if available >= amount.to_i
        state[:tokens][player] = available - amount.to_i
      else
        state[:tokens][player] = 0
        state[:eliminated][player] = true
      end
    end

    def finish_round(state)
      if active_players(state).length <= 1
        state[:winner] = active_players(state).first
        state[:phase] = :finished
      else
        state[:phase] = :round_complete
      end
      state[:current_player] = nil
      state[:pending_player] = nil
    end

    def refill_draw_pile(state)
      return if !state[:draw_pile].empty? || state[:discard].length <= 1

      top = state[:discard].pop
      cards = state[:discard].dup
      # The seed belongs to the sampled world, never the real game's deck.
      serial = state.fetch(:planning_recycles, 0)
      random = Random.new(Digest::SHA256.hexdigest([state.fetch(:planning_seed, 0), serial, cards].inspect)[0, 16].to_i(16))
      state[:draw_pile] = GameRoomRandom.shuffle(cards, random: random)
      state[:planning_recycles] = serial + 1
      state[:discard] = [top]
    end
  end

  class WorldSampler
    def initialize(game, state, actor, omniscient: false)
      @game = game
      @state = state
      @actor = actor
      @omniscient = omniscient
    end

    def sample(index)
      state = Marshal.load(Marshal.dump(@state))
      visible_player = state[:players].find { |player| @game.send(:same_user?, player, @actor) }
      deck = @game.send(:deck_for, state[:players].length).dup
      known = state[:discard].dup
      known.concat(state[:hands].fetch(visible_player, [])) if !@omniscient
      known.concat(state[:hands].values.flatten) if @omniscient
      known.each do |card|
        position = deck.index(card)
        deck.delete_at(position) if position != nil
      end

      random = Random.new(seed_for(index))
      unseen = deterministic_shuffle(deck, random)
      if @omniscient
        state[:hands] = state[:hands].transform_values(&:dup)
      else
        state[:players].each do |player|
          next if player == visible_player

          count = state[:hands].fetch(player, []).length
          state[:hands][player] = unseen.shift(count)
        end
      end
      state[:draw_pile] = unseen
      state[:planning_seed] = seed_for(index)
      state[:planning_recycles] = 0
      State.from(state)
    end

    private

    # Keep this planner entry point and its caller-owned RNG stable.
    def deterministic_shuffle(values, random)
      GameRoomRandom.shuffle(values, random: random)
    end

    def seed_for(index)
      own = @state[:players].find { |player| @game.send(:same_user?, player, @actor) }
      public_value = [
        @actor.to_s.downcase,
        @state[:round],
        @state[:total],
        @state[:direction],
        @state[:tokens].sort_by { |player, _value| player.to_s.downcase },
        @state[:eliminated].sort_by { |player, _value| player.to_s.downcase },
        @state[:discard],
        @state[:hands].fetch(own, []).sort,
        index
      ].inspect
      Digest::SHA256.hexdigest(public_value)[0, 16].to_i(16)
    end
  end

  # Information-set Max-N search.  Fair bots average decisions over hidden-card
  # worlds consistent with public play; challenge bots use the exact hands but
  # still do not peek at the future draw order.
  class Strategy
    include GameRoomBots::ReplayOnlyStrategy

    attr_reader :last_stats

    def initialize(depth: 4, fair_worlds: 20, omniscient_worlds: 10, node_limit: 45_000)
      @depth = [depth.to_i, 1].max
      @fair_worlds = [fair_worlds.to_i, 1].max
      @omniscient_worlds = [omniscient_worlds.to_i, 1].max
      @node_limit = [node_limit.to_i, 1].max
      @last_stats = {}
    end

    def choose(actions:, actor:, random_source:, game: nil, replay: nil, **_extra)
      choices = actions.to_a
      return nil if choices.empty?
      draw = choices.find { |action| action["action"].to_s == "draw" }
      return draw if draw != nil
      return choices.first if choices.length == 1
      return GameRoomBots.random_choice(choices, random_source) if game == nil || replay == nil

      state = replay.state
      omniscient = state[:options].is_a?(Hash) && state[:options]["omniscient_bots"] == true
      world_count = omniscient ? @omniscient_worlds : @fair_worlds
      sampler = WorldSampler.new(game, state, actor, omniscient: omniscient)
      worlds = world_count.times.map { |index| sampler.sample(index) }
      @budget = GameRoomBots::SearchBudget.new(limit: @node_limit)
      @cache = {}

      scored, completed_depth = nil, 0
      1.upto(@depth) do |depth|
        begin
          iteration = choices.map do |action|
            values = worlds.map do |world|
              next_state = Transition.play(game, world, actor, action)
              next -Float::INFINITY if next_state == nil
              search(game, next_state, depth - 1).fetch(actor.to_s, -Float::INFINITY)
            end
            average = values.sum.fdiv([values.length, 1].max)
            [action, average, game.bot_action_score(replay, actor, action).to_f]
          end
          scored, completed_depth = iteration, depth
        rescue GameRoomBots::SearchBudget::Exhausted
          break
        end
      end
      selected = scored.max_by { |action, value, tactical| [value, tactical, game.bot_action_key(action)] }.first
      @last_stats = {
        worlds: world_count,
        nodes: @budget.nodes,
        cooperative_yields: @budget.yields,
        omniscient: omniscient,
        depth: @depth, completed_depth: completed_depth
      }
      selected
    ensure
      @budget = nil
      @cache = nil
    end

    private

    def search(game, state, depth)
      return utilities(game, state) if depth <= 0 || state[:current_player] == nil || state[:winner] != nil

      @budget.visit!

      key = state_key(state, depth)
      cached = @cache[key]
      return cached if cached != nil

      actor = state[:current_player]
      hand = state[:hands].fetch(actor, [])
      return utilities(game, state) if hand.empty?

      actions = hand.flat_map { |card| game.send(:card_play_actions, card, state[:total]) }
      best = nil
      actions.each do |action|
        next_state = Transition.play(game, state, actor, action)
        next if next_state == nil

        candidate = search(game, next_state, depth - 1)
        if best == nil || candidate.fetch(actor.to_s, -Float::INFINITY) > best.fetch(actor.to_s, -Float::INFINITY)
          best = candidate
        end
      end
      @cache[key] = best || utilities(game, state)
    end

    def utilities(game, state)
      active = Transition.active_players(state)
      state[:players].each_with_object({}) do |player, result|
        value = state[:tokens][player].to_i * 200.0
        value += state[:eliminated][player] ? -2_000.0 : 1_000.0
        value += 8_000.0 if state[:winner] == player
        value -= 8_000.0 if state[:winner] != nil && state[:winner] != player
        rivals = state[:players] - [player]
        # Damage matters, but never as much as sacrificing our own survival.
        value -= rivals.sum { |other| state[:tokens][other].to_i * 40.0 + (state[:eliminated][other] ? 0 : 100.0) } / [rivals.length, 1].max
        value += hand_value(game, state, player) if active.include?(player) && state[:phase] == :playing
        result[player.to_s] = value
      end
    end

    def hand_value(game, state, player)
      total = state[:total].to_i
      state[:hands].fetch(player, []).sum do |card|
        rank = card.to_s[1]
        flexible = case rank
        when "9" then 38.0
        when "T" then 36.0
        when "2" then 32.0
        when "J" then 25.0
        when "4" then 20.0
        when "A" then 18.0
        else 5.0
        end
        safe = game.send(:modes_for, card, total).any? do |mode|
          game.send(:total_after_card, total, card, mode) <= 99
        end
        flexible + (safe ? 12.0 : -35.0)
      end
    end

    def state_key(state, depth)
      [
        depth,
        state[:total],
        state[:direction],
        state[:phase],
        state[:current_player],
        state[:tokens].sort_by { |player, _value| player.to_s },
        state[:eliminated].sort_by { |player, _value| player.to_s },
        state[:hands].sort_by { |player, _value| player.to_s }.map { |player, cards| [player, cards.sort] },
        state[:draw_pile],
        state[:discard],
        state[:planning_seed], state[:planning_recycles]
      ]
    end
  end
end
