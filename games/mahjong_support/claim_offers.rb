# frozen_string_literal: true
require_relative 'tile_flow'

module GameRoomMahjong
  module ClaimOffers
    module_function

    def discard_restrictions(variant, discarded, type, first)
      return [] unless variant == 'riichi' && %i[chow pung].include?(type)

      blocked = [discarded]
      if type == :chow
        opposite = discarded == first ? first + 3 : discarded == first + 2 ? first - 1 : nil
        blocked << opposite if opposite && opposite.between?(0, 26) && opposite / 9 == first / 9
      end
      blocked
    end

    # Only the rules/scoring adapter may certify a win. Shape alone is not
    # enough for a yaku/minimum-fan rule. A kong also needs an available legal
    # replacement draw, which is decided by the variant's wall adapter.
    def for_discard(flow, replacement_available: false, win_checker: nil, sets_allowed: true)
      raise ArgumentError, 'No pending mahjong discard' unless flow.is_a?(TileFlow) && flow.phase == :reactions
      unless [true, false].include?(replacement_available) && [true, false].include?(sets_allowed) && (win_checker.nil? || win_checker.respond_to?(:call))
        raise ArgumentError, 'Invalid mahjong claim policy'
      end
      kind = Tiles.kind(flow.discards.last.last)
      seats = flow.hands.length
      offers = ((0...seats).to_a - [flow.seat]).to_h do |seat|
        concealed = flow.concealed_tiles(seat).map { |tile| Tiles.kind(tile) }.freeze
        counts = concealed.tally
        choices = [[:pass]]
        choices << [:pung, kind] if sets_allowed && counts.fetch(kind, 0) >= 2
        choices << [:kong, kind] if sets_allowed && replacement_available && counts.fetch(kind, 0) >= 3
        if sets_allowed && seats == 4 && seat == (flow.seat + 1) % seats && kind < 27
          first = (kind / 9) * 9
          (first..first + 6).each do |start|
            next unless (start..start + 2).cover?(kind)
            needed = [start, start + 1, start + 2]
            needed.delete_at(needed.index(kind))
            choices << [:chow, start] if needed.all? { |tile_kind| counts.fetch(tile_kind, 0).positive? }
          end
        end
        if win_checker && win_checker.call(seat, concealed, kind) == true
          choices << [:win]
        end
        [seat, choices]
      end
      ClaimWindow.new(seats: seats, discarder: flow.seat, tile_kind: kind,
        generation: flow.generation, offers: offers)
    end
  end
end
