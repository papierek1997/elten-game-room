require_relative "hearts_rules"
require 'digest'
require_relative '../../lib/game_random'
require_relative '../../lib/hidden_card_deals'
require_relative '../../lib/game_tree_search'

module GameRoomGames
  module HeartsBot
    module_function

    def pass(hand)
      hand.combination(3).min_by do |cards|
        kept = hand - cards
        groups = kept.group_by(&:first)
        danger = kept.sum { |suit, rank| rank + (suit == :spades && rank >= 12 ? 20 : 0) }
        # Passing three related cards can create a useful void; simply
        # discarding the three largest ranks misses that joint decision.
        danger - (4 - groups.size) * 3
      end
    end

    def play(legal, trick, hand: legal, captured: nil, seat: nil, owners: nil)
      points = captured&.map { |cards| cards.sum { |card| HeartsRules.penalty(card) } }
      shooter = points&.each_index&.find { |index| points[index] >= 13 && points.each_with_index.all? { |value, other| other == index || value.zero? } }
      # The queen alone is not a moon attempt: chasing the remaining hearts
      # with an ordinary losing hand turns 13 penalties into 20 or more.
      moon = seat && shooter == seat && points[seat] >= 23
      if trick.empty?
        return legal.max_by(&:last) if moon
        return legal.min_by { |suit, rank| [rank, hand.count { |card| card.first == suit }] }
      end

      lead = trick.first.first
      return legal.max_by { |card| [HeartsRules.penalty(card), card.last] } if legal.none? { |card| card.first == lead }

      high = trick.select { |card| card.first == lead }.map(&:last).max
      winning = legal.select { |suit, rank| suit == lead && rank > high }
      if !winning.empty? && (moon || shooter && shooter != seat && owners &&
          owners[HeartsRules.trick_winner(trick)] == shooter && trick.any? { |card| HeartsRules.penalty(card).positive? })
        return winning.min_by(&:last)
      end
      below = legal.select { |card| card.last < high }
      return below.max_by(&:last) unless below.empty?
      return legal.max_by(&:last) if trick.size == 3 && trick.none? { |card| HeartsRules.penalty(card).positive? }

      legal.min_by(&:last)
    end

    class Position
      WORLD_LIMIT = 16
      ROOT_LIMIT = 7
      attr_reader :stats

      def initialize(view)
        @view, @seat = view, view.fetch(:seat)
        @played, @hand = view.values_at(:played, :hand)
        @budget = GameRoomBots::SearchBudget.new(limit: 8_000)
        @forecasts = {}
      end

      def choose(legal)
        fallback = HeartsBot.play(legal, @view[:trick].map(&:last), hand: @hand,
          captured: @view[:captured], seat: @seat, owners: @view[:trick].map(&:first))
        return fallback if legal.size <= 1
        worlds = possible_hands
        return fallback if worlds.empty?
        # Compare all distinct ranks in short hands. In long hands retain a
        # representative low/high of each suit plus the tactical fallback.
        candidates = if legal.size <= ROOT_LIMIT
          legal
        else
          ([fallback] + legal.group_by(&:first).values.flat_map { |cards| [cards.min_by(&:last), cards.max_by(&:last)] }).uniq.first(ROOT_LIMIT)
        end
        reference = worlds.map { |hands| forecast(hands, fallback) }
        selected = candidates.max_by do |card|
          outcomes = card == fallback ? reference : worlds.map { |hands| forecast(hands, card) }
          gains = outcomes.zip(reference).map { |value, base| value - base }
          mean = gains.sum.fdiv(gains.size)
          error = Math.sqrt(gains.sum { |gain| (gain - mean)**2 }.fdiv([gains.size * (gains.size - 1), 1].max))
          [mean - 1.5 * error, card == fallback ? 1 : 0]
        end
        @stats = {worlds: worlds.size, candidates: candidates.size, nodes: @budget.nodes}
        selected
      end

      private

      def possible_hands
        counts = Array.new(4, 13)
        voids = Array.new(4) { [] }
        @played.each_slice(4) do |trick|
          trick.each do |seat, card|
            counts[seat] -= 1
            voids[seat] |= [trick.first.last.first] unless card.first == trick.first.last.first
          end
        end
        known = @view[:passed].transform_values { |cards| cards - @played.map(&:last) }
        known[@seat] = @hand
        pool = HeartsRules::DECK - (@played.map(&:last) + known.values.flatten(1))
        hidden = (0...4).to_a - [@seat]
        sizes = hidden.to_h { |seat| [seat, counts[seat] - known.fetch(seat, []).size] }
        return [] unless sizes.values.all? { |size| size >= 0 } && sizes.values.sum == pool.size
        random = Random.new(Digest::SHA256.hexdigest(Marshal.dump([@hand.sort, @played, known])).to_i(16))
        worlds = []
        64.times do
          deal = GameRoomHiddenCardDeals.assign(pool, hidden, sizes, random) { |seat, card| !voids[seat].include?(card.first) }
          next unless deal
          worlds << Array.new(4) { |seat| seat == @seat ? @hand.dup : known.fetch(seat, []) + deal.fetch(seat) }
          break if worlds.size == WORLD_LIMIT
        end
        worlds
      end

      def forecast(source, card)
        key = [source, card]
        return @forecasts[key] if @forecasts.key?(key)
        hands, captured = source.map(&:dup), @view[:captured].map(&:dup)
        trick = @view[:trick].map(&:dup)
        turn, count, broken = @seat, @played.size, @view[:broken]
        choice = card
        until hands.all?(&:empty?)
          @budget.visit!
          legal = HeartsRules.legal(hands[turn], trick.map(&:last), first_trick: count < 4, hearts_broken: broken)
          choice ||= HeartsBot.play(legal, trick.map(&:last), hand: hands[turn], captured: captured, seat: turn, owners: trick.map(&:first))
          hands[turn].delete(choice)
          trick << [turn, choice]
          count += 1
          broken ||= choice.first == :hearts
          choice = nil
          if trick.size == 4
            turn = trick[HeartsRules.trick_winner(trick.map(&:last))].first
            captured[turn].concat(trick.map(&:last))
            trick.clear
          else
            turn = (turn + 1) % 4
          end
        end
        penalties = HeartsRules.settle(captured)
        totals = @view[:scores].zip(penalties).map(&:sum)
        value = -penalties[@seat] - 0.15 * (totals[@seat] - (totals.each_with_index.reject { |_, seat| seat == @seat }.map(&:first).min))
        @forecasts[key] = value
      end
    end
  end
end
