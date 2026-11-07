module BouillabaissePlanning
  # Both root ordering and simulated players use the same fair information:
  # an own hand, counts, public cards and proven voids. A hypothetical hand
  # of another player is never passed into this evaluation.
  class Policy
    def initialize(round, state, style: 0)
      @round, @state, @style = round, state, style
      @actor = state.turn
      @hand = state.hands[@actor]
      @unseen = state.unplayed - @hand
      @suits = Array.new(4) { [] }
      @unseen.each { |card| @suits[card % 4] << card }
      @behind = (1...(round.size - state.trick.size)).map { |offset| (@actor + offset) % round.size }
      lead = state.trick.first
      @led = lead && lead.last % 4
      @winner, @winning_card = round.winning_play(state.trick) unless @led.nil?
      @cost = round.trick_points + state.trick.sum { |_, card| round.points[card] }
      @pressure = {}
      @win = {}
      @sweep = sweep_holder
      @collect = round.number == 6 || pursue_sweep?
    end

    def choose(cards)
      cards.max_by { |card| [score(card), -card] }
    end

    def score(card)
      win = win_chance(card)
      value = @round.points[card]
      cost = @cost + value
      danger = win.zero? ? 0 : discard_pressure(@led || card % 4)
      rank = card / 4
      if @collect
        score = win * (cost + danger + 0.8) - (1 - win) * (value * 0.6 + rank * 0.12)
        score -= win * rank * 0.05
      else
        shed = value * 0.85 + rank * (@style.zero? ? 0.16 : 0.23)
        shed += 0.35 if @hand.count { |other| other % 4 == card % 4 } == 1
        score = (1 - win) * shed - win * (cost + danger)
        # A clean trick can be the safest chance to get rid of a high card.
        score += win * rank * 0.20 if cost.zero? && danger.zero?
      end
      score + sweep_adjustment(win, cost)
    end

    def candidates(cards)
      return cards if @collect

      # With the same suit, immediate points and guaranteed trick outcome,
      # keep the lower card for later instead of needlessly playing it now.
      equivalent = {}
      groups = cards.to_h do |card|
        outcome = already_loses?(card) ? :loses : (:wins if win_chance(card) == 1.0)
        points = @round.points[card]
        # Keep a possible future stopper if the opponent can still sweep.
        # A guaranteed scoring win already stops that sweep in this trick.
        if @sweep && @sweep != @actor && !(outcome == :wins && (@cost + points).positive?)
          outcome = nil
        end
        key = outcome && [card % 4, points, outcome]
        equivalent[key] = [card, equivalent[key] || card].max if key
        [card, key]
      end
      cards.select { |card| groups[card].nil? || equivalent.fetch(groups[card]) == card }
    end

    def win_chance(card)
      @win[card] ||= begin
        suit = @led || card % 4
        if already_loses?(card)
          0.0
        else
          higher = @suits[suit].count { |other| other > card }
          lower = @suits[suit].size - higher
          @behind.reduce(1.0) do |chance, player|
            next chance if higher.zero? || @round.void?(@state, player, suit)

            chance * (1 - overtake_chance(player, higher, lower))
          end
        end
      end
    end

    private

    def already_loses?(card)
      @led && (card % 4 != @led || card < @winning_card)
    end

    def overtake_chance(player, higher, lower)
      count = @state.counts[player]
      can_overtake = 1 - @round.absence(@unseen.size, higher, count)
      forced = @round.absence(@unseen.size, lower, count) - @round.absence(@unseen.size, higher + lower, count)
      wants_trick = @round.number == 6 || @sweep == player && @state.raw[player] * 2 >= @round.total
      willingness = wants_trick ? 0.9 : (@cost.zero? ? 0.2 : 0.1)
      forced + (can_overtake - forced) * willingness
    end

    def sweep_holder
      return nil unless @round.all_or_nothing

      holders = @state.raw.each_index.select { |player| @state.raw[player].positive? }
      holders.size == 1 ? holders.first : nil
    end

    def pursue_sweep?
      return false unless @round.all_or_nothing && @sweep == @actor && @state.raw[@actor] * 2 >= @round.total

      controls = @hand.count { |card| @suits[card % 4].none? { |other| other > card } }
      controls * 3 >= @hand.size * 2
    end

    def sweep_adjustment(win, cost)
      return 0.0 unless @sweep && cost.positive?

      held = @state.raw[@sweep]
      if @round.number == 6
        # In the final round, completing one's own sweep turns a reward into
        # a penalty. A rival's sweep is desirable for the opposite reason.
        return -win * @round.total * 2 if @sweep == @actor && held + cost == @round.total
        return 0.0
      end
      return 0.0 if @sweep == @actor || held * 2 < @round.total

      bonus = win * @round.total * 0.18
      bonus -= (1 - win) * @round.total * 2 if @winner == @sweep && held + cost == @round.total
      bonus
    end

    def discard_pressure(suit)
      @pressure[suit] ||= begin
        cards = @unseen - @suits[suit]
        prizes = cards.filter_map { |card| @round.points[card] if @round.points[card].positive? }
        return @pressure[suit] = 0.0 if prizes.empty?

        levels = prizes.uniq.sort
        thresholds = levels.each_with_index.map do |points, index|
          [points - (index.zero? ? 0 : levels[index - 1]), prizes.count { |value| value >= points }]
        end
        @behind.sum do |player|
          count = @state.counts[player]
          void_chance = @round.void?(@state, player, suit) ? 1.0 : @round.absence(@unseen.size, @suits[suit].size, count)
          next 0.0 if void_chance.zero?

          void_chance * thresholds.sum do |points, targets|
            # A player trying to take points normally keeps their expensive
            # cards, instead of handing over the highest one for free.
            probability = if @round.number == 6
              @round.absence(cards.size, cards.size - targets, count)
            else
              1 - @round.absence(cards.size, targets, count)
            end
            points * probability
          end
        end
      end
    end
  end
end
