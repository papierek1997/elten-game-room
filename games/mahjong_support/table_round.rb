# frozen_string_literal: true
require_relative 'claim_offers'
require_relative 'round_settlement'
require_relative 'bot_policy'
require_relative 'riichi_state'

module GameRoomMahjong
  # Internal round coordinator, not yet a registered session game. Context is
  # supplied by accepted history, never by client scoring claims. This joins
  # physical actions, declaration barriers and the per-hand deposit ledger;
  # whole-match/dealer progression remains the session adapter's next stage.
  class TableRound
    attr_reader :flow, :variant, :dealer, :round_wind, :window, :result, :furiten, :blocked_discards, :added_kong_kind,
      :riichi_state, :pending_riichi, :riichi_outcome, :honba

    def initialize(flow:, variant:, dealer:, round_wind: 27, window: nil, result: nil, furiten: nil, blocked_discards: [], added_kong_kind: nil,
        riichi_state: nil, pending_riichi: nil, riichi_outcome: nil, honba: 0)
      unless flow.is_a?(TileFlow) && %w[riichi hong_kong mcr].include?(variant) && dealer.is_a?(Integer) && dealer.between?(0, flow.hands.length - 1) &&
          round_wind.is_a?(Integer) && round_wind.between?(27, 30) && (variant == 'riichi' || flow.hands.length == 4)
        raise ArgumentError, 'Invalid mahjong round'
      end
      if variant == 'riichi'
        physical = flow.visible_tiles
        if !flow.flowers.flatten.empty? || physical.any? { |tile| Tiles.bonus?(tile) || flow.hands.length == 3 && Tiles.kind(tile).between?(1, 7) }
          raise ArgumentError, 'Tiles outside the selected Riichi seat profile'
        end
      end
      furiten ||= Array.new(flow.hands.length, false)
      unless furiten.is_a?(Array) && furiten.length == flow.hands.length && furiten.all? { |value| [true, false].include?(value) }
        raise ArgumentError, 'Invalid temporary furiten'
      end
      @flow, @variant, @dealer, @round_wind = flow, variant, dealer, round_wind
      unless honba.is_a?(Integer) && honba.between?(0, 1000) && (variant == 'riichi' || honba.zero?)
        raise ArgumentError, 'Invalid mahjong continuance counter'
      end
      @honba = honba
      unless added_kong_kind.nil? || added_kong_kind.is_a?(Integer) && added_kong_kind.between?(0, 33)
        raise ArgumentError, 'Invalid pending kong kind'
      end
      if flow.phase == :kong_reactions && added_kong_kind.nil?
        raise ArgumentError, 'Missing pending kong kind'
      end
      @added_kong_kind = added_kong_kind
      riichi_state ||= RiichiState.new(points: Array.new(flow.hands.length, 30000)) if variant == 'riichi'
      unless variant == 'riichi' ? riichi_state.is_a?(RiichiState) && riichi_state.points.length == flow.hands.length : riichi_state.nil?
        raise ArgumentError, 'Invalid riichi round ledger'
      end
      @riichi_state, @pending_riichi, @riichi_outcome = riichi_state, pending_riichi, riichi_outcome
      @window, @result, @furiten = window, result, furiten.dup.freeze
      unless blocked_discards.is_a?(Array) && blocked_discards.all? { |kind| kind.is_a?(Integer) && kind.between?(0, 33) }
        raise ArgumentError, 'Invalid immediate discard restriction'
      end
      @blocked_discards = blocked_discards.dup.freeze
      freeze
    end

    def finished?
      !result.nil? || flow.phase == :exhausted
    end

    def winning_result(seat, include_ura: true)
      robbed = flow.phase == :kong_reactions
      return nil if robbed && seat == flow.seat
      settlement_flow = robbed ? flow.robbed_added_kong(kind: added_kong_kind) : flow
      RoundSettlement.win(flow: settlement_flow, variant: variant, winner: seat, dealer: dealer,
        round_wind: round_wind, temporary_furiten: variant == 'riichi' && (furiten.fetch(seat) || riichi_state.furiten.fetch(seat)),
        riichi: riichi_state ? riichi_state.levels.fetch(seat) : 0,
        flags: riichi_state ? {ippatsu: riichi_state.ippatsu.fetch(seat)} : {}, robbing_kong: robbed, honba: honba, include_ura: include_ura)
    end

    def legal_discards
      return [] if finished? || flow.phase != :discard
      return [flow.last_draw].compact if riichi_state && riichi_state.levels[flow.seat].positive?
      flow.hands[flow.seat].reject { |tile| blocked_discards.include?(Tiles.kind(tile)) }
    end

    def concealed_kongs
      return [] if finished? || flow.phase != :discard || !flow.last_draw || !flow.replacement_available?
      kinds = flow.hands[flow.seat].map { |tile| Tiles.kind(tile) }.tally.select { |_, count| count == 4 }.keys
      return kinds unless riichi_state && riichi_state.levels[flow.seat].positive?
      kinds.select { |kind| riichi_state.concealed_kong_allowed?(flow: flow, seat: flow.seat, kind: kind) }
    end

    def added_kongs
      return [] if finished? || flow.phase != :discard || !flow.last_draw || !flow.replacement_available?
      flow.melds[flow.seat].select { |meld| meld[:type] == :pung }.map { |meld| meld[:first_kind] } &
        flow.hands[flow.seat].map { |tile| Tiles.kind(tile) }
    end

    def riichi_discards
      return [] unless riichi_state && !finished? && flow.phase == :discard
      legal_discards.select { |tile| riichi_state.declaration(flow: flow, seat: flow.seat, tile: tile) }
    end

    # Plans only. The session adapter must revalidate the selected action and
    # send it through the ordinary action_for / shared executor write boundary.
    def legal_actions(seat:)
      raise ArgumentError, 'Invalid mahjong seat' unless seat.is_a?(Integer) && seat.between?(0, flow.hands.length - 1)
      return [].freeze if finished?
      base = {seat: seat, generation: flow.generation}
      actions = if %i[reactions kong_reactions].include?(flow.phase)
        window&.pending&.include?(seat) ? window.offers.fetch(seat).map { |choice| base.merge(type: :claim, choice: choice) } : []
      elsif flow.seat != seat
        []
      elsif %i[draw replacement].include?(flow.phase)
        [base.merge(type: flow.phase)]
      elsif flow.phase == :discard
        choices = legal_discards.map { |tile| base.merge(type: :discard, tile: tile) }
        choices << base.merge(type: :win) if flow.last_draw && winning_result(seat)
        choices.concat(concealed_kongs.map { |kind| base.merge(type: :concealed_kong, tile: kind) })
        choices.concat(added_kongs.map { |kind| base.merge(type: :added_kong, tile: kind) })
        choices.concat(riichi_discards.map { |tile| base.merge(type: :riichi, tile: tile) })
      else
        []
      end
      actions.map(&:freeze).freeze
    end

    # Validate the selected action without enumerating every possible Riichi
    # declaration, kong and winning preview for an unrelated discard or Pass.
    def legal_action?(action)
      return false unless action.is_a?(Hash) && !finished? && action[:generation].is_a?(Integer) && action[:generation] == flow.generation &&
        action[:seat].is_a?(Integer) && action[:seat].between?(0, flow.hands.length - 1)
      seat, type = action.values_at(:seat, :type)
      extra = type == :claim ? [:choice] : %i[discard concealed_kong added_kong riichi].include?(type) ? [:tile] : []
      return false unless action.keys.sort == (%i[seat generation type] + extra).sort
      if type == :claim
        return false unless window
        return %i[reactions kong_reactions].include?(flow.phase) && window.pending.include?(seat) &&
          window.offers.fetch(seat).include?(action[:choice])
      end
      return false unless flow.seat == seat
      return flow.phase == type if %i[draw replacement].include?(type)
      return false unless flow.phase == :discard
      case type
      when :discard then legal_discards.include?(action[:tile])
      when :win then !flow.last_draw.nil? && !winning_result(seat).nil?
      when :concealed_kong then concealed_kongs.include?(action[:tile])
      when :added_kong then added_kongs.include?(action[:tile])
      when :riichi then !riichi_state.nil? && legal_discards.include?(action[:tile]) &&
        !riichi_state.declaration(flow: flow, seat: seat, tile: action[:tile]).nil?
      else false
      end
    end

    def bot_action(seat:)
      actions = legal_actions(seat: seat)
      return actions.first if actions.size <= 1
      win = actions.find { |candidate| candidate[:type] == :win || candidate[:choice] == [:win] }
      return win if win

      Bot::Policy.new(flow.observation(viewer: seat), seat: seat, dealer: dealer,
        variant: variant, round_wind: round_wind, riichi_levels: riichi_state&.levels).choose(actions)
    end

    def action(seat:, type:, generation:, tile: nil, choice: nil)
      raise ArgumentError, 'Finished or stale mahjong round' if finished? || !generation.is_a?(Integer) || generation != flow.generation
      raise ArgumentError, 'Invalid mahjong seat' unless seat.is_a?(Integer) && seat.between?(0, flow.hands.length - 1)
      case type
      when :riichi
        declaration = riichi_state&.declaration(flow: flow, seat: seat, tile: tile)
        raise ArgumentError, 'Riichi requires a closed ready discard' unless declaration
        action(seat: seat, type: :discard, tile: tile, generation: generation).with(pending_riichi: declaration)
      when :added_kong
        next_flow = flow.begin_added_kong(seat: seat, kind: tile, generation: generation)
        pending = with(flow: next_flow, added_kong_kind: tile, blocked_discards: [], riichi_state: riichi_state&.interrupt)
        offers = ((0...flow.hands.length).to_a - [seat]).to_h do |peer|
          [peer, pending.winning_result(peer) ? [[:pass], [:win]] : [[:pass]]]
        end
        pending.with(window: ClaimWindow.new(seats: flow.hands.length, discarder: seat,
          tile_kind: tile, generation: next_flow.generation, offers: offers))
      when :concealed_kong
        raise ArgumentError, 'No legal concealed kong' unless seat == flow.seat && concealed_kongs.include?(tile)
        with(flow: flow.concealed_kong(seat: seat, kind: tile, generation: generation), blocked_discards: [], riichi_state: riichi_state&.interrupt)
      when :draw, :replacement
        next_flow = type == :draw ? flow.draw(seat: seat, generation: generation) : flow.draw_replacement(seat: seat, generation: generation)
        next_furiten = furiten.dup
        next_furiten[seat] = false
        settlement = next_flow.phase == :exhausted ? RoundSettlement.draw(flow: next_flow, variant: variant) : nil
        next_round = with(flow: next_flow, furiten: next_furiten, blocked_discards: [])
        settlement ? next_round.finish_with(settlement) : next_round
      when :discard
        raise ArgumentError, 'Riichi locks the concealed hand' unless seat == flow.seat && legal_discards.include?(tile)
        raise ArgumentError, 'Swap-calling discard is forbidden' if blocked_discards.include?(Tiles.kind(tile))
        next_flow = flow.discard(seat: seat, tile: tile, generation: generation)
        next_round = with(flow: next_flow, blocked_discards: [], riichi_state: riichi_state&.after_discard(seat: seat))
        offers = ClaimOffers.for_discard(next_flow, replacement_available: next_flow.replacement_available?,
          sets_allowed: variant != 'riichi' || !next_flow.wall.empty?,
          win_checker: ->(player, _hand, _tile) { !next_round.winning_result(player).nil? })
        if riichi_state
          restricted = offers.offers.to_h do |peer, choices|
            [peer, riichi_state.levels[peer].positive? ? choices.select { |choice| %i[pass win].include?(choice.first) } : choices]
          end
          offers = ClaimWindow.new(seats: offers.seats, discarder: offers.discarder, tile_kind: offers.tile_kind,
            generation: offers.generation, offers: restricted)
        end
        next_round.with(window: offers)
      when :claim
        respond_to_claim(seat: seat, choice: choice, generation: generation)
      when :win
        raise ArgumentError, 'Discard wins must use the claim window' unless flow.phase == :discard && seat == flow.seat
        settlement = winning_result(seat)
        raise ArgumentError, 'The concealed hand cannot win' unless settlement
        finish_with(settlement)
      else
        raise ArgumentError, 'Unknown mahjong round action'
      end
    end

    private def respond_to_claim(seat:, choice:, generation:)
      raise ArgumentError, 'No current claim window' unless window && %i[reactions kong_reactions].include?(flow.phase)
      updated = window.respond(seat: seat, choice: choice, generation: generation)
      next_furiten = furiten.dup
      next_riichi = riichi_state
      next_riichi = next_riichi.pass_ron(seat: seat) if next_riichi && choice != [:win] && window.offers.fetch(seat).include?([:win])
      next_furiten[seat] = true if variant == 'riichi' && choice != [:win] && window.offers.fetch(seat).include?([:win])
      resolution = updated.resolution
      return with(window: updated, furiten: next_furiten, riichi_state: next_riichi) unless resolution
      if resolution.type == :win
        settlement = winning_result(resolution.seat)
        raise ArgumentError, 'The winning claim is no longer valid' unless settlement
        final_flow = flow.phase == :kong_reactions ? flow.robbed_added_kong(kind: added_kong_kind) : flow
        with(flow: final_flow, window: updated, furiten: next_furiten, riichi_state: next_riichi,
          pending_riichi: nil).finish_with(settlement)
      else
        next_riichi = next_riichi.accept(pending_riichi) if next_riichi && pending_riichi
        next_riichi = next_riichi.interrupt if next_riichi && resolution.type != :passed
        if flow.phase == :kong_reactions
          return with(flow: flow.complete_added_kong(kind: added_kong_kind, generation: generation),
            window: nil, added_kong_kind: nil, furiten: next_furiten, blocked_discards: [], riichi_state: next_riichi)
        end
        blocked = ClaimOffers.discard_restrictions(variant, Tiles.kind(flow.discards.last.last), resolution.type, resolution.first_kind)
        next_furiten[resolution.seat] = false if variant == 'riichi' && %i[chow pung kong].include?(resolution.type)
        with(flow: flow.apply_claim(updated), window: nil, furiten: next_furiten, blocked_discards: blocked,
          riichi_state: next_riichi, pending_riichi: nil)
      end
    end

    def finish_with(settlement)
      return with(result: settlement) unless riichi_state
      outcome = riichi_state.settle(payments: settlement.payments, winner: settlement.winner)
      adjusted = RoundSettlement::Result.new(**settlement.to_h.merge(payments: outcome.delta)).freeze
      with(result: adjusted, riichi_outcome: outcome, pending_riichi: nil)
    end

    # Public to allow an accepted event reducer to attach a reconstructed
    # claim window without mutating earlier replay snapshots.
    def with(**changes)
      self.class.new(**{flow: flow, variant: variant, dealer: dealer, round_wind: round_wind,
        window: window, result: result, furiten: furiten, blocked_discards: blocked_discards,
        added_kong_kind: added_kong_kind, riichi_state: riichi_state, pending_riichi: pending_riichi,
        riichi_outcome: riichi_outcome, honba: honba}.merge(changes))
    end
  end
end
