# frozen_string_literal: true
require_relative 'bot'
require_relative 'claim_offers'
require_relative 'hong_kong_scoring'
require_relative 'mcr_scoring'
require_relative 'riichi_deal'
require_relative 'riichi_scoring'

module GameRoomMahjong
  module Bot
    # Takes only TileFlow's player observation plus public round metadata.
    # Legal actions and actual settlement still belong to TableRound.
    class Policy
      def initialize(observation, seat:, dealer:, variant:, round_wind:, riichi_levels:)
        @view, @seat, @variant, @round_wind = observation, seat, variant, round_wind
        @seats = observation.fetch(:hand_counts).size
        @seat_wind = 27 + (seat - dealer) % @seats
        @hand = kinds(observation.fetch(:concealed))
        @melds = observation.fetch(:melds).fetch(seat).map do |meld|
          [meld.fetch(:type), meld.fetch(:first_kind), !meld[:from].nil?]
        end
        @rivers = Array.new(@seats) { [] }
        observation.fetch(:discard_history).each { |owner, tile| @rivers[owner] << Tiles.kind(tile) }
        @levels = riichi_levels || Array.new(@seats, 0)
        @threats = @levels.each_index.select { |other| other != seat && @levels[other].positive? }
        indicators = observation.fetch(:dora_indicators)
        @dora = indicators.map { |tile| RiichiDeal.dora_kind(tile, sanma: @seats == 3) }
        @flowers = kinds(observation.fetch(:flowers).fetch(seat))
        public_tiles = observation.fetch(:discard_history).map(&:last) +
          observation.fetch(:melds).flatten(1).flat_map { |meld| meld.fetch(:tiles) } + indicators
        @visible = kinds(public_tiles.uniq).tally
        owned = @hand.tally
        @available = Array.new(34) do |kind|
          @variant == 'riichi' && @seats == 3 && kind.between?(1, 7) ? 0 :
            4 - @visible.fetch(kind, 0) - owned.fetch(kind, 0)
        end
        @analysis = Efficiency.new(variant: @variant, available: @available, discards: @rivers[seat],
          completion: method(:scoring_wait), dora: @dora,
          route: @variant == 'hong_kong' ? method(:hong_kong_route) : nil)
      end

      def choose(actions)
        pass = actions.find { |action| action[:choice] == [:pass] }
        return claim(actions, pass) if pass

        discards = actions.select { |action| action[:type] == :discard }
        return actions.first if discards.empty?

        choice = @analysis.discard(@hand, @melds, kinds(discards.map { |action| action[:tile] }),
          risk: @threats.empty? ? nil : method(:danger))
        discard = discards.find { |action| Tiles.kind(action[:tile]) == choice.kind }
        kong = useful_kong(actions, choice)
        return kong if kong

        declaration = actions.find { |action| action[:type] == :riichi && action[:tile] == discard[:tile] }
        declaration && declare?(choice) ? declaration : discard
      end

      private

      def kinds(tiles); tiles.map { |tile| Tiles.kind(tile) }; end

      def claim(actions, pass)
        return pass unless @threats.empty?
        discarded = Tiles.kind(@view.fetch(:discards).last.last)
        before = @analysis.rest(@hand, @melds)
        best = actions.filter_map do |action|
          type, first = action.fetch(:choice)
          next unless %i[chow pung kong].include?(type)

          needed = Hand.tiles_for([type, first])
          needed.delete_at(needed.index(discarded))
          concealed = remove(@hand, needed)
          melds = @melds + [[type, first, true]]
          if type == :kong
            after = @analysis.rest(concealed, melds)
          else
            choices = concealed.uniq - ClaimOffers.discard_restrictions(@variant, discarded, type, first)
            next if choices.empty?

            after = @analysis.discard(concealed, melds, choices)
          end
          next unless after.acceptance.positive?
          # A plausible structural hand isn't enough: don't lock an open
          # hand out of the scoring minimum. A public value-honor set is a
          # reliable path in Riichi; otherwise require actual scoring waits.
          ready = after.distance.zero?
          value_honor = @variant == 'riichi' && melds.any? do |meld_type, kind, _|
            meld_type != :chow && (kind >= 31 || [@seat_wind, @round_wind].include?(kind))
          end
          next unless ready || value_honor && after.distance == 1 && after.acceptance >= 4
          next unless after.distance < before.distance ||
            before.distance.zero? && before.acceptance.zero? && ready

          [action, -after.distance, after.acceptance + after.ron, after.links]
        end.max_by { |entry| entry.drop(1) }
        best ? best.first : pass
      end

      def useful_kong(actions, discard)
        return nil unless @threats.empty?

        actions.find do |action|
          next false unless action[:type] == :concealed_kong

          kind = action.fetch(:tile)
          concealed = remove(@hand, [kind] * 4)
          after = @analysis.rest(concealed, @melds + [[:kong, kind, false]])
          after.acceptance.positive? && (after.distance < discard.distance ||
            after.distance == discard.distance && after.acceptance >= discard.acceptance && after.ron >= discard.ron)
        end
      end

      def declare?(choice)
        return false unless choice.distance.zero? && choice.acceptance.positive? && !choice.furiten
        return false if !@threats.empty? && (!danger(choice.kind).zero? || choice.acceptance < 3)

        @view.fetch(:wall_count) >= @seats * 2 || choice.ron.zero? && choice.acceptance >= 2
      end

      def danger(kind)
        @threats.sum do |other|
          # Furiten makes this tile safe against this specific opponent.
          next 0.0 if @rivers[other].include?(kind)

          # These are softer estimates, never a claim of safety.
          remaining = @available[kind]
          base = kind >= 27 ? 0.8 + remaining * 0.35 :
            1.6 + [kind % 9, 8 - kind % 9].min * 0.23 + remaining * 0.12
          base + @dora.count(kind) * 0.45
        end
      end

      def scoring_wait(tiles, winning, melds)
        dora = (tiles + melds.flat_map { |meld| Hand.tiles_for(meld.first(2)) }).sum { |kind| @dora.count(kind) }
        [true, false].map do |self_draw|
          common = {concealed: tiles, winning_tile: winning, melds: melds, self_draw: self_draw,
            seat_wind: @seat_wind, round_wind: @round_wind}
          result = case @variant
          when 'riichi'
            RiichiScoring.score(**common, riichi: @levels[@seat], dora: dora)
          when 'hong_kong'
            HongKongScoring.score(**common, flowers: @flowers)
          when 'mcr'
            MCRScoring.score(**common, flowers: @flowers.size, flags: {last_kind: @visible.fetch(winning, 0) == 3})
          end
          !result.nil?
        end
      end

      # A near half-flush or a live value-honor set is a route to the
      # three-fan minimum. Use this only as a modest earlier preference;
      # ready hands are ranked by actual qualifying completions.
      def hong_kong_route(tiles, melds)
        open_tiles = melds.flat_map { |meld| Hand.tiles_for(meld) }
        suits = [0, 0, 0]
        (tiles + open_tiles).each { |kind| suits[kind / 9] += 1 if kind < 27 }
        main = suits.each_index.max_by { |suit| suits[suit] }
        outside = suits.sum - suits[main]
        value = if suits[main] >= 6 && outside <= 3 && open_tiles.none? { |kind| kind < 27 && kind / 9 != main }
          (4 - outside) * 1.25
        else
          0.0
        end
        hand = tiles.tally
        ([@seat_wind, @round_wind] + [31, 32, 33]).each do |kind|
          count = hand.fetch(kind, 0)
          value += 1.5 if count >= 3 || count == 2 && @available[kind].positive?
        end
        value
      end

      def remove(hand, tiles)
        result = hand.dup
        tiles.each { |kind| result.delete_at(result.index(kind)) }
        result
      end
    end
  end
end
