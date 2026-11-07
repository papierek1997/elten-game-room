# frozen_string_literal: true
require_relative 'hand'
require_relative 'mcr_shapes'

module GameRoomMahjong
  module Bot
    module_function

    VARIANTS = %w[riichi hong_kong mcr].freeze

    # The strategy receives only its own hand and public visible tile counts.
    # There is deliberately no opponent-hand or future-wall parameter.
    def discard_kind(concealed:, melds: [], public_counts: {}, choices: nil, variant: 'riichi')
      Hand.counts_for(concealed, melds)
      unless VARIANTS.include?(variant) && concealed.length == 14 - 3 * melds.length && public_counts.is_a?(Hash)
        raise ArgumentError, 'Invalid mahjong bot observation'
      end
      own = concealed.tally
      public_counts.each do |kind, count|
        Tiles.validate_kind(kind, bonuses: false)
        raise ArgumentError, 'Invalid public mahjong count' unless count.is_a?(Integer) && count.between?(0, 4)
      end
      known_public = public_counts.dup
      melds.flat_map { |group| Hand.tiles_for(group) }.tally.each do |kind, count|
        known_public[kind] = [known_public.fetch(kind, 0), count].max
      end
      known_public.each do |kind, count|
        Tiles.validate_kind(kind, bonuses: false)
        unless count.is_a?(Integer) && count.between?(0, 4) && count + own.fetch(kind, 0) <= 4
          raise ArgumentError, 'Visible mahjong counts exceed the tile inventory'
        end
      end
      choices ||= concealed.uniq
      unless choices.is_a?(Array) && !choices.empty? && choices.all? { |kind| kind.is_a?(Integer) && concealed.include?(kind) }
        raise ArgumentError, 'Bot discard choices must be legal owned tiles'
      end
      available = Array.new(34) { |kind| 4 - known_public.fetch(kind, 0) - own.fetch(kind, 0) }
      Efficiency.new(variant: variant, available: available).discard(concealed, melds.map { |meld| [*meld, true] }, choices).kind
    end

    def shanten(concealed, melds: [], variant: 'riichi', memo: {})
      counts = Hand.counts_for(concealed, melds)
      raise ArgumentError, 'Unknown mahjong bot variant' unless VARIANTS.include?(variant)
      if concealed.length == 14 - 3 * melds.length && !win_forms(concealed, melds, variant).empty?
        return -1
      end

      [shape_distance(counts, melds.length, variant, memo), 0].max
    end

    def win_forms(concealed, melds, variant)
      variant == 'mcr' ? MCRShapes.forms(concealed, melds: melds) :
        Hand.forms(concealed, melds: melds, split_quads: variant == 'hong_kong')
    end

    def shape_distance(counts, meld_count, variant, memo)
      result = standard_distance(counts, meld_count, memo)
      if meld_count.zero?
        pairs = counts.count { |count| count >= 2 }
        pairs = counts.sum { |count| count / 2 } unless variant == 'riichi'
        pair_distance = 6 - pairs + (variant == 'riichi' ? [0, 7 - counts.count(&:positive?)].max : 0)
        result = [result, pair_distance].min
        orphan_unique = Tiles::ORPHANS.count { |kind| counts[kind].positive? }
        orphan_pair = Tiles::ORPHANS.any? { |kind| counts[kind] >= 2 } ? 1 : 0
        result = [result, 13 - orphan_unique - orphan_pair].min
      end
      if variant == 'mcr' && meld_count <= 1
        honors = counts[27..33].count(&:positive?)
        MCRShapes::KNITTED.each do |knitted|
          missing = knitted.count { |kind| counts[kind].zero? }
          result = [result, 13 - [9 - missing + honors, 14].min].min if meld_count.zero?
          next if missing > 1

          # A knitted straight is nine tiles plus a set and a pair. Unlike
          # the disconnected honor forms, it can use one exposed set.
          other = counts.dup
          knitted.each { |kind| other[kind] -= 1 if other[kind].positive? }
          result = [result, missing + standard_distance(other, meld_count + 3, memo)].min
        end
      end
      result
    end

    # Suits cannot share sets. Cache each group's decompositions separately
    # so trying a draw in one suit reuses the other three groups' work.
    # A profile index encodes (completed melds * 2 + has_pair); for each
    # index only the largest number of partial sets can improve distance.
    def standard_distance(counts, meld_count, memo)
      key = counts.pack('C*') << meld_count
      return memo[key] if memo.key?(key)

      combined = {meld_count * 2 => 0}
      [0, 9, 18, 27].each do |start|
        group = group_profiles(counts[start, start == 27 ? 7 : 9], memo)
        next_combined = {}
        combined.each do |profile, partial|
          group.each do |addition, links|
            next if (profile & addition & 1) != 0 || profile / 2 + addition / 2 > 4

            index = profile + addition
            total = partial + links
            next_combined[index] = total if total > next_combined.fetch(index, -1)
          end
        end
        combined = next_combined
      end
      memo[key] = combined.map { |profile, partial| 8 - profile - [partial, 4 - profile / 2].min }.min
    end

    def group_profiles(counts, memo)
      key = counts.pack('C*')
      return memo[key] if memo.key?(key)

      first = counts.index(&:positive?)
      return memo[key] = {0=>0} unless first

      # Skipping a tile as well as using it avoids greedily fixing one
      # interpretation of an overlapping run, pung or pair.
      counts[first] -= 1
      profiles = group_profiles(counts, memo).dup
      counts[first] += 1
      groups = []
      groups << [[first] * 3, 2, 0] if counts[first] >= 3
      if counts[first] >= 2
        groups << [[first, first], 1, 0]
        groups << [[first, first], 0, 1]
      end
      if counts.size == 9
        if first <= 6 && counts[first + 1].positive? && counts[first + 2].positive?
          groups << [[first, first + 1, first + 2], 2, 0]
        end
        [1, 2].each do |gap|
          groups << [[first, first + gap], 0, 1] if counts.fetch(first + gap, 0).positive?
        end
      end
      groups.each do |used, offset, links|
        used.each { |kind| counts[kind] -= 1 }
        group_profiles(counts, memo).each do |profile, partial|
          next if (profile & offset & 1) != 0 || profile / 2 + offset / 2 > 4

          index = profile + offset
          total = partial + links
          profiles[index] = total if total > profiles.fetch(index, -1)
        end
        used.each { |kind| counts[kind] += 1 }
      end
      memo[key] = profiles
    end
    private_class_method :standard_distance, :group_profiles

    # One decision owns its memo and tile inventory. The latter is computed
    # before discarding/calling: a tile leaving our hand is still visible.
    class Efficiency
      Evaluation = Struct.new(:kind, :distance, :acceptance, :ron, :furiten, :links, :route)

      def initialize(variant:, available:, discards: [], completion: nil, dora: [], route: nil)
        @variant, @available, @discards, @completion, @dora = variant, available, discards, completion, dora
        @route = route
        @memo = {}
      end

      def discard(concealed, melds, choices, risk: nil)
        raw = melds.map { |meld| meld.first(2) }
        candidates = choices.uniq.to_h do |kind|
          tiles = concealed.dup
          tiles.delete_at(tiles.index(kind))
          [kind, [tiles, Bot.shanten(tiles, melds: raw, variant: @variant, memo: @memo)]]
        end
        evaluated = {}
        closest = candidates.values.map(&:last).min
        evaluate = ->(kind) do
          evaluated[kind] ||= rest(candidates.fetch(kind).first, melds, kind: kind, distance: candidates.fetch(kind).last)
        end
        pool = candidates.keys.select { |kind| candidates.fetch(kind).last == closest }
        best = pool.map(&evaluate).max_by { |item| rank(item, risk) }

        if best.acceptance.zero?
          next_group = candidates.keys.select { |kind| candidates.fetch(kind).last == closest + 1 }
          alternative = next_group.map(&evaluate).select { |item| item.acceptance.positive? }.max_by { |item| rank(item, risk) }
          best = alternative if alternative
        end
        if risk && !(best.distance.zero? && (best.acceptance >= 2 || risk.call(best.kind).zero?))
          safest = candidates.keys.map(&risk).min
          return candidates.keys.select { |kind| risk.call(kind) == safest }.map(&evaluate)
            .max_by { |item| [-item.distance, *rank(item, nil)] }
        end
        best
      end

      def rest(concealed, melds, kind: nil, distance: nil)
        raw = melds.map { |meld| meld.first(2) }
        counts = Hand.counts_for(concealed, raw)
        distance ||= Bot.shanten(concealed, melds: raw, variant: @variant, memo: @memo)
        remaining, ron, furiten = if distance.zero?
          ready(concealed, raw, melds, kind)
        else
          [advances(counts, raw.length, distance), 0, false]
        end
        links = counts.each_index.sum do |tile|
          next 0.0 if counts[tile].zero?

          value = @available[tile] * (counts[tile] >= 2 ? 2 : 1) + @dora.count(tile) * counts[tile] * 2
          if @variant != 'riichi' && tile < 27 && distance > 1
            [-2, -1, 1, 2].each do |gap|
              neighbor = tile + gap
              value += @available[neighbor] if neighbor.between?(0, 26) && neighbor / 9 == tile / 9 && counts[neighbor].positive?
            end
          end
          value
        end
        route = @route && distance.positive? ? @route.call(concealed, raw) : 0.0
        Evaluation.new(kind, distance, remaining, ron, furiten, links, route)
      end

      private

      def rank(item, risk)
        cost = risk ? risk.call(item.kind) : 0.0
        if @variant != 'riichi' && item.distance > 1
          # Far from a scoring hand, raw acceptance is a weaker signal
          # than flexible shapes and a route to the fan minimum.
          return [item.acceptance.positive? ? 1 : 0, item.links + item.route + item.acceptance * 0.2, -item.kind]
        end
        [item.acceptance * 2 + item.ron + item.route - cost * 3, item.links, -item.kind]
      end

      def advances(counts, meld_count, distance)
        counts.each_index.sum do |tile|
          next 0 unless @available[tile].positive?

          counts[tile] += 1
          better = Bot.shape_distance(counts, meld_count, @variant, @memo) < distance
          counts[tile] -= 1
          better ? @available[tile] : 0
        end
      end

      def ready(concealed, raw, melds, discard)
        own = (concealed + raw.flat_map { |meld| Hand.tiles_for(meld) }).tally
        own_discards = @variant == 'riichi' ? @discards + [discard] : []
        wait_tiles = (0...34).select do |tile|
          own.fetch(tile, 0) < 4 && (@available[tile].positive? || own_discards.include?(tile)) &&
            !Bot.win_forms(concealed + [tile], raw, @variant).empty?
        end
        furiten = !(own_discards & wait_tiles).empty?
        live = ron = 0
        wait_tiles.each do |tile|
          next unless @available[tile].positive?

          tsumo, by_discard = @completion ? @completion.call(concealed + [tile], tile, melds) : [true, true]
          live += @available[tile] if tsumo || (by_discard && !furiten)
          ron += @available[tile] if by_discard && !furiten
        end
        [live, ron, furiten]
      end
    end
  end
end
