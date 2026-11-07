require 'digest'
require_relative 'game_bots'
require_relative 'game_random'

module GameRoomGames
  class ScopaStrategy
    include GameRoomBots::ReplayOnlyStrategy

    def choose(actions:, observation:, **_extra)
      return actions.first if actions.size <= 1

      position = Position.new(observation)
      by_card = actions.to_h { |action| [action.fetch('card'), action] }
      by_card.fetch(position.choose(by_card.keys))
    end

    class Position
      State = Struct.new(:table, :hands, :taken, :scopas, :last, :turn)
      WORLD_LIMIT = 6
      SHORT_HAND_WORLDS = 10
      ROOT_LIMIT = 7
      ENDGAME_CARDS = 8
      MAJORITIES = [[40, ->(cards) { cards.size }],
        [10, ->(cards) { cards.count { |card| card[1] == 'D' } }],
        [4, ->(cards) { cards.count { |card| card[0] == '7' } }]].freeze

      def initialize(view)
        @seat, @units, @counts = view.values_at('seat', 'units', 'counts')
        @hand = view.fetch('hand')
        @escoba, @muerto = view.values_at('escoba', 'muerto')
        @stock, @discarded = view.values_at('stock_count', 'discard_count')
        @scores = view.fetch('scores')
        @limit, @lead = view.values_at('score_limit', 'two_point_lead')
        @side = @units.fetch(@seat)
        hands = @counts.map { |count| Array.new(count) }
        hands[@seat] = @hand
        @root = State.new(view.fetch('table'), hands, view.fetch('taken'), view.fetch('scopas'),
          view['last_capturer'], @seat)
        @captures = {}
        @deck = Scopa::DECK
      end

      def choose(cards)
        priors = cards.to_h { |card| [card, tactical(@root, card)] }
        order = cards.sort_by { |card| [-priors.fetch(card), card] }
        worlds = worlds_for(@root)
        return order.first if worlds.empty?

        if exact_endgame?
          return cards.max_by do |card|
            [solve(play(worlds.first, card), -Float::INFINITY, Float::INFINITY), priors.fetch(card)]
          end
        end

        # The same possible deals are used for each candidate. A short
        # continuation accounts for the whole table order, including partners.
        horizon = short_hands? ? @counts.sum : [2 * @units.size, 8].min
        prior_weight = short_hands? ? 0.85 : 0.55
        baseline = order.first
        reference = forecast(worlds, baseline, horizon)
        order.first(ROOT_LIMIT).max_by do |card|
          outcomes = card == baseline ? reference : forecast(worlds, card, horizon)
          gains = outcomes.zip(reference).map { |value, old| value - old }
          mean = gains.sum.fdiv(gains.size)
          error = gains.size == 1 ? 0.0 :
            Math.sqrt(gains.sum { |gain| (gain - mean)**2 }.fdiv(gains.size * (gains.size - 1)))
          [mean - 0.45 * error + (priors.fetch(card) - priors.fetch(baseline)) * prior_weight, priors.fetch(card)]
        end
      end

      private

      def unseen(state, seat)
        @deck - (state.hands[seat] + state.table + state.taken.values.flatten(1))
      end

      def worlds_for(state)
        unknown = unseen(state, @seat)
        return [] unless unknown.size == @counts.sum - @hand.size + @stock + @discarded

        # No deal seed, foreign card values or actual stock order enter here.
        seed = Digest::SHA256.hexdigest(Marshal.dump([state.table, state.taken, @hand.sort, @counts, @seat])).to_i(16)
        rng = Random.new(seed)
        count = if @units.size == 2 && @stock.zero? && @discarded.zero?
          1
        else
          short_hands? ? SHORT_HAND_WORLDS : WORLD_LIMIT
        end
        Array.new(count) do
          pool = count == 1 ? unknown.dup : GameRoomRandom.shuffle(unknown, random: rng)
          hands = @counts.each_with_index.map { |size, seat| seat == @seat ? @hand : pool.shift(size) }
          State.new(state.table, hands, state.taken, state.scopas, state.last, state.turn)
        end.uniq { |world| world.hands.map(&:sort) }
      end

      def exact_endgame?
        @units.size == 2 && @stock.zero? && @discarded.zero? && @counts.sum <= ENDGAME_CARDS
      end

      def short_hands?; @counts.max <= 4; end

      def capture(table, card)
        @captures[[table, card[0]]] ||= Scopa.capture(table, card, escoba: @escoba)
      end

      def play(state, card)
        side = @units.fetch(state.turn)
        hands = state.hands.dup
        hands[state.turn] = hands[state.turn] - [card]
        captured = capture(state.table, card)
        table = captured.empty? ? state.table + [card] : state.table - captured
        taken = captured.empty? ? state.taken : state.taken.merge(side => state.taken.fetch(side) + captured + [card])
        scopas = !captured.empty? && table.empty? ?
          state.scopas.merge(side => state.scopas.fetch(side) + 1) : state.scopas
        offset = (1..hands.size).find { |step| !hands[(state.turn + step) % hands.size].empty? }
        turn = (state.turn + offset) % hands.size if offset
        State.new(table, hands, taken, scopas, captured.empty? ? state.last : side, turn)
      end

      def final?(state); state.turn.nil? && @stock.zero?; end

      def forecast(worlds, card, horizon)
        worlds.map do |world|
          state = play(world, card)
          (horizon - 1).times do
            break unless state.turn

            legal = state.hands.fetch(state.turn)
            reply = legal.size == 1 ? legal.first : legal.max_by { |move| rollout_score(state, move) }
            state = play(state, reply)
          end
          utility(state, @side)
        end
      end

      def solve(state, low, high)
        return utility(state, @side) unless state.turn

        maximizing = @units.fetch(state.turn) == @side
        state.hands.fetch(state.turn).each do |card|
          value = solve(play(state, card), low, high)
          maximizing ? low = [low, value].max : high = [high, value].min
          break if low >= high
        end
        maximizing ? low : high
      end

      def tactical(state, card)
        side = @units.fetch(state.turn)
        after = play(state, card)
        value = utility(after, side)
        return value if final?(after)

        # A sweep requires one specific rank. Count remaining copies, not
        # just the sum on the table. The next hand is unknown even in rollouts.
        value += exposure(after, state.turn, side)
        value + disposal(state, after, card)
      end

      def rollout_score(state, card)
        side = @units.fetch(state.turn)
        after = play(state, card)
        return utility(after, side) if final?(after)

        captured = capture(state.table, card)
        material = if captured.empty?
          0.0
        else
          packet = captured + [card]
          packet.size * 0.07 + packet.count { |item| item[1] == 'D' } * 0.13 +
            packet.count { |item| item[0] == '7' } * 0.16 + (packet.include?('7D') ? 1.0 : 0.0) +
            (after.table.empty? ? 1.0 : 0.0)
        end
        (@muerto ? -material : material) + exposure(after, state.turn, side, sweep_only: true) + disposal(state, after, card)
      end

      def exposure(state, from, side, sweep_only: false)
        return 0.0 if state.table.empty? || !state.turn || state.turn == from

        sum = state.table.sum { |card| Scopa.card_value(card) }
        sweep = @escoba ? 15 - sum : sum
        seven = !sweep_only && state.table.include?('7D')
        return 0.0 unless sweep.between?(1, 10) || seven

        pool = unseen(state, from)
        count = state.hands.fetch(state.turn).size
        value = chance(pool, count) { |card| Scopa.card_value(card) == sweep } * 0.9
        if seven
          value += chance(pool, count) { |card| capture(state.table, card).include?('7D') } * 0.75
        end
        aligned = @units.fetch(state.turn) == side
        aligned == @muerto ? -value : value
      end

      def chance(pool, count)
        hits = pool.count { |card| yield(card) }
        return 0.0 if hits.zero? || count.zero?
        return 1.0 if pool.size - hits < count

        1 - (0...count).reduce(1.0) { |miss, i| miss * (pool.size - hits - i).fdiv(pool.size - i) }
      end

      def disposal(before, after, card)
        return 0.0 unless after.table.size > before.table.size

        # Don't expose the seven of diamonds when a less important drop is
        # equivalent. Muerto reverses the incentive, not the capture rules.
        value = card == '7D' ? -0.08 : 0.0
        # In classic capture a second card of the same rank can recover
        # this drop later. Prefer that opportunity over an equal loose drop.
        if !@escoba && !@muerto && after.hands[before.turn].any? { |other| other[0] == card[0] }
          value += 0.07
        end
        (@muerto ? -value : value) - Scopa.card_value(card) * 0.001
      end

      def utility(state, side)
        if final?(state)
          taken = state.last ? state.taken.merge(state.last => state.taken.fetch(state.last) + state.table) : state.taken
          points = Scopa.round_points(taken, state.scopas, muerto: @muerto)
          total = @scores.to_h { |unit, score| [unit, score + points.fetch(unit)] }
          ordered = total.sort_by { |_, score| -score }
          gap = ordered[0].last - ordered[1].last
          finished = ordered[0].last >= @limit && gap >= (@lead ? 2 : 1)
          return margin(points, side) + (finished ? (ordered[0].first == side ? 4.0 : -4.0) : 0.0)
        end

        raw = state.scopas.transform_values(&:to_f)
        state.taken.each { |unit, cards| raw[unit] += 1 if cards.include?('7D') }
        MAJORITIES.each do |supply, measure|
          counts = state.taken.transform_values(&measure)
          remaining = supply - counts.values.sum
          largest = counts.values.max
          possible = counts.reject { |_, value| value + remaining < largest }
          if remaining.zero?
            leaders = counts.keys.select { |unit| counts[unit] == largest }
            raw[leaders.first] += 1 if leaders.one?
          else
            spread = 0.65 + Math.sqrt(remaining.fdiv(counts.size)) * 0.7
            weights = possible.transform_values { |value| Math.exp((value - largest) / spread) }
            total = weights.values.sum
            weights.each { |unit, weight| raw[unit] += weight / total }
          end
        end
        # All other sides get the raw point in Muerto. Their common sum
        # cancels in a score difference, so subtract each side's own points.
        margin(@muerto ? raw.transform_values { |value| -value } : raw, side)
      end

      def margin(points, side)
        rivals = points.reject { |unit, _| unit == side }
        strongest = rivals.max_by { |unit, value| value + @scores.fetch(unit) * 0.45 }.last
        points.fetch(side) - strongest * 0.75 - rivals.values.sum.fdiv(rivals.size) * 0.25
      end
    end
    private_constant :Position
  end
end
