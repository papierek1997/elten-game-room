require 'digest'
require_relative 'rules'
require_relative '../../lib/game_random'
require_relative '../../lib/hidden_card_deals'

module GameRoomGames
  class BridgePlayPlanner
    R = BridgeRules
    CARD_IDS = R::DECK.each_with_index.to_h.freeze
    DECK = (0...52).to_a.freeze
    SEATS = (0...4).to_a.freeze
    WORLD_LIMIT = 5
    ROOT_LIMIT = 7

    State = Struct.new(:hands, :remaining, :voids, :trick, :tricks, :turn, :dummy_visible) do
      def branch
        State.new(hands.map(&:dup), remaining, voids.dup, trick.dup, tricks.dup, turn, dummy_visible)
      end
    end

    def initialize(view)
      @view = view
      @seat, @turn = view.values_at('seat', 'seat_to_play')
      @contract = R::Contract.new(**view.fetch('contract').transform_keys(&:to_sym))
      @dummy = R.partner_of(@contract.declarer)
      @trump = R::SUITS.index(@contract.strain)
      @side = R.side_of(@seat)
      @trick = encode(view.fetch('trick'))
      plays = encode(view.fetch('played'))
      @counts = Array.new(4, 13)
      @voids = Array.new(4, 0)
      (plays.each_slice(4).to_a + [@trick]).each do |trick|
        trick.each do |seat, card|
          @counts[seat] -= 1
          @voids[seat] |= 1 << suit(trick.first.last) unless suit(card) == suit(trick.first.last)
        end
      end
      @remaining = DECK - (plays + @trick).map(&:last)
      @visible = {@seat => view.fetch('hand').map { |card| CARD_IDS.fetch(card) }}
      @visible[@dummy] = view['dummy'].map { |card| CARD_IDS.fetch(card) } if view['dummy']
      @hidden = SEATS - @visible.keys
      @tricks = view.fetch('tricks_won')
      @partner_suits = SEATS.map do |seat|
        call = view.fetch('calls').reverse.find do |owner, bid|
          owner == R.partner_of(seat) && R.bid?(bid) && R::SUITS.include?(R.bid_strain(bid))
        end
        R::SUITS.index(R.bid_strain(call.last)) if call
      end
      vulnerable = R.vulnerable?(view.fetch('vulnerability'), @contract.side)
      @values = (0..13).map do |tricks|
        points = R.duplicate_score(@contract, tricks, vulnerable: vulnerable)
        value = R.imps(points) * 0.4 + tricks * 0.23
        @contract.side == @side ? value : -value
      end
    end

    def choose(legal, fallback)
      worlds, exact = worlds_for
      return fallback if worlds.empty?

      cards = legal.map { |card| CARD_IDS.fetch(card) }
      baseline = CARD_IDS.fetch(fallback)
      policy = Policy.new(self, worlds.first)
      priors = cards.to_h { |card| [card, policy.score(card)] }
      ordered = cards.sort_by { |card| [-priors.fetch(card), card] }
      if exact && @remaining.size <= 12
        best = cards.max_by do |card|
          state = worlds.first.branch
          play(state, card)
          [solve(state, -Float::INFINITY, Float::INFINITY), priors.fetch(card)]
        end
        return R::DECK.fetch(best)
      end

      # Retain the prior policy's choice and representative alternatives in
      # other suits. Compare each of them in the same possible deals.
      candidates = ([baseline] + ordered.first(2) + ordered.uniq { |card| suit(card) } + ordered).uniq.first(ROOT_LIMIT)
      reference = evaluate(worlds, baseline)
      best = candidates.max_by do |card|
        if card == baseline
          [0.0, priors.fetch(card)]
        else
          gains = evaluate(worlds, card).zip(reference).map { |new_value, old_value| new_value - old_value }
          mean = gains.sum.fdiv(gains.size)
          error = gains.size == 1 ? 0.0 :
            Math.sqrt(gains.sum { |gain| (gain - mean)**2 }.fdiv(gains.size * (gains.size - 1)))
          [mean - 0.4 * error + (priors.fetch(card) - priors.fetch(baseline)) * 0.06, priors.fetch(card)]
        end
      end
      R::DECK.fetch(best)
    end

    attr_reader :trump, :dummy, :partner_suits, :contract

    def suit(card); card / 13; end
    def rank(card); card % 13; end
    def trumps?(card); suit(card) == @trump; end

    def power(card, led)
      return 26 + rank(card) if trumps?(card)
      suit(card) == led ? 13 + rank(card) : 0
    end

    def follow(cards, led)
      matching = cards.select { |card| suit(card) == led }
      matching.empty? ? cards : matching
    end

    private

    def encode(trick)
      trick.map { |seat, card| [seat, CARD_IDS.fetch(card)] }
    end

    def worlds_for
      unseen = @remaining - @visible.values.flatten(1)
      counts = @hidden.to_h { |seat| [seat, @counts.fetch(seat)] }
      return [[], false] unless @visible.key?(@turn) && unseen.size == counts.values.sum &&
        @visible.all? { |seat, cards| cards.size == @counts[seat] && (cards - @remaining).empty? }

      allowed = ->(seat, card) { (@voids.fetch(seat) & (1 << suit(card))).zero? }
      hidden = @hidden.select { |seat| counts[seat].positive? }
      exact = unseen.all? { |card| hidden.count { |seat| allowed.call(seat, card) } == 1 }
      seed = Digest::SHA256.hexdigest(Marshal.dump([@remaining, @visible, @voids, @view['calls'], @turn])).to_i(16)
      random = Random.new(seed)
      worlds = []
      signatures = {}
      (exact ? 1 : WORLD_LIMIT * 3).times do
        found = GameRoomHiddenCardDeals.assign(unseen, @hidden, counts, random, &allowed)
        next unless found

        hands = SEATS.map { |seat| (@visible[seat] || found.fetch(seat)).sort }
        next if signatures[hands]

        signatures[hands] = true
        worlds << State.new(hands, @remaining, @voids, @trick, @tricks, @turn, !@view['dummy'].nil?).branch
        break if worlds.size >= WORLD_LIMIT
      end
      [worlds, exact]
    end

    def play(state, card)
      seat = state.turn
      led = state.trick.empty? ? suit(card) : suit(state.trick.first.last)
      state.voids[seat] |= 1 << led if suit(card) != led
      state.hands[seat].delete(card)
      state.remaining = state.remaining - [card]
      state.trick << [seat, card]
      state.dummy_visible = true
      if state.trick.size == 4
        winner = state.trick.max_by { |_, item| power(item, led) }.first
        state.tricks[winner % 2] += 1
        state.turn = winner
        state.trick.clear
      else
        state.turn = (seat + 1) % 4
      end
    end

    def legal(state)
      cards = state.hands.fetch(state.turn)
      state.trick.empty? ? cards : follow(cards, suit(state.trick.first.last))
    end

    def evaluate(worlds, card)
      worlds.map do |world|
        state = world.branch
        play(state, card)
        until state.remaining.empty?
          options = legal(state)
          choice = options.one? ? options.first : options.max_by(&Policy.new(self, state).method(:score))
          play(state, choice)
        end
        @values.fetch(state.tricks.fetch(@contract.side))
      end
    end

    def solve(state, low, high)
      return @values.fetch(state.tricks.fetch(@contract.side)) if state.remaining.empty?

      maximizing = state.turn % 2 == @side
      legal(state).each do |card|
        next_state = state.branch
        play(next_state, card)
        value = solve(next_state, low, high)
        maximizing ? low = [low, value].max : high = [high, value].min
        break if low >= high
      end
      maximizing ? low : high
    end

    # Each rollout player evaluates its own cards and visible dummy, not the
    # other hands of the hypothetical deal. The exact short search is used
    # only when public voids and counts determine all remaining hands.
    class Policy
      def initialize(planner, state)
        @p, @state = planner, state
        @turn = state.turn
        @side = @turn % 2
        @partner = R.partner_of(@turn)
        @declarer = planner.contract.declarer
        @hand = state.hands.fetch(@turn)
        @known = {@turn => @hand}
        @known[planner.dummy] = state.hands.fetch(planner.dummy) if state.dummy_visible
        @known[@declarer] = state.hands.fetch(@declarer) if @turn == planner.dummy
        @unknown = state.remaining - @known.values.flatten(1)
        @by_suit = @unknown.group_by { |card| @p.suit(card) }
        @later = (1..(3 - state.trick.size)).map { |step| (@turn + step) % 4 }
        @rivals = @later.reject { |seat| seat % 2 == @side }
        unless state.trick.empty?
          @led = @p.suit(state.trick.first.last)
          @winning = state.trick.max_by { |_, card| @p.power(card, @led) }
        end
      end

      def score(card)
        @led ? follow_score(card) : lead_score(card)
      end

      private

      def follow_score(card)
        overtakes = @p.power(card, @led) > @p.power(@winning.last, @led)
        owner, winner = overtakes ? [@turn, card] : @winning
        value = owner % 2 == @side ? 6.5 * survives(winner, @led) : 0.0
        value - keeping_cost(card)
      end

      def lead_score(card)
        suit = @p.suit(card)
        partner = @known[@partner]
        value = 4.5 * survives(card, suit)
        if partner
          continuation = @p.follow(partner, suit).max_by { |item| @p.power(item, suit) }
          if continuation && @p.power(continuation, suit) > @p.power(card, suit)
            # Entries put the lead in the other hand. With a shorter trump
            # hand, a ruff adds a trick instead of consuming a long-hand winner.
            control = survives(continuation, suit)
            value = [value, 4.1 * control].max
            value += 0.45 * control if entry_needed?(partner, suit)
            if @p.trumps?(continuation) && !@p.trumps?(card)
              short = partner.count { |item| @p.trumps?(item) } < @hand.count { |item| @p.trumps?(item) }
              value += (short ? 1.2 : 0.3) * control
            end
          end
          if @p.trumps?(card) && @by_suit.fetch(suit, []).any?
            value += 0.65
          elsif !@p.trumps?(card) && partner.any? { |item| @p.suit(item) == suit }
            value += 0.25
          end
        elsif @p.partner_suits[@turn] == suit
          value += 0.45
        end
        value + @hand.count { |item| @p.suit(item) == suit } * 0.16 - keeping_cost(card)
      end

      def entry_needed?(partner, led)
        partner.any? do |item|
          suit = @p.suit(item)
          suit != led && !@p.trumps?(item) && @hand.none? { |card| @p.suit(card) == suit } &&
            @by_suit.fetch(suit, []).none? { |other| other > item }
        end
      end

      def keeping_cost(card)
        @p.rank(card) * 0.038 + (@p.trumps?(card) ? 0.32 : 0.0)
      end

      def survives(card, led)
        @rivals.reduce(1.0) { |chance, rival| chance * (1.0 - overtaking_risk(rival, card, led)) }
      end

      def overtaking_risk(seat, card, led)
        power = @p.power(card, led)
        known = @known[seat]
        return @p.follow(known, led).any? { |other| @p.power(other, led) > power } ? 0.96 : 0.0 if known

        follow = @by_suit.fetch(led, [])
        count = @state.hands.fetch(seat).size
        share = count.fdiv([@unknown.size, 1].max)
        risk = if void?(seat, led)
          0.0
        else
          higher = follow.count { |item| @p.power(item, led) > power }
          1.0 - (1.0 - share)**higher
        end
        trump = @p.trump
        if trump && trump != led && !void?(seat, trump)
          trumps = @by_suit.fetch(trump, []).count { |item| @p.power(item, led) > power }
          may_ruff = void?(seat, led) ? 1.0 : (1.0 - share)**follow.size
          risk += (1.0 - risk) * may_ruff * (1.0 - (1.0 - share)**trumps)
        end
        risk
      end

      def void?(seat, suit); (@state.voids.fetch(seat) & (1 << suit)) != 0; end
    end
    private_constant :State, :Policy
  end
end
