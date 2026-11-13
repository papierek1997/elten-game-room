require_relative "french_tarot_trick"
require_relative "french_tarot_scoring"

module GameRoomGames
  class FrenchTarotRound
    DECK = (%i[clubs diamonds hearts spades].product((1..14).to_a) +
      [:trump].product((1..21).to_a) + [[:excuse, 0]]).map(&:freeze).freeze

    attr_reader :turn, :phase, :contract, :taker

    def initialize(deck, dealer:)
      raise ArgumentError unless deck.size == 78 && deck.uniq.size == 78 && (deck - DECK).empty?
      raise ArgumentError unless (0..3).include?(dealer)
      cards = deck.map { |card| card.dup.freeze }
      @hands = cards.first(72).each_slice(18).to_a
      @kitty = cards.last(6)
      @first = @turn = (dealer + 1) % 4
      @phase = :bid
      @bids = @played = 0
      @trick = []
      @piles = [[], []]
      @excuse_debt = [0, 0]
    end

    def bids(seat)
      return [] unless @phase == :bid && seat == @turn
      contracts = FrenchTarotScoring::CONTRACTS
      [:pass] + contracts.keys.select { |choice| !@contract || contracts[choice] > contracts[@contract] }
    end

    def bid(seat, choice)
      return false unless bids(seat).include?(choice)
      @taker, @contract = seat, choice unless choice == :pass
      @bids += 1
      @turn = (@turn + 1) % 4
      return true if @bids < 4
      if !@taker
        @phase = :redeal
        @turn = nil
      elsif %i[petite garde].include?(@contract)
        @hands[@taker].concat(@kitty)
        @phase = :discard
        @turn = @taker
      else
        begin_play
      end
      true
    end

    def hand(seat)
      @hands.fetch(seat).dup
    end

    def discard(seat, cards)
      return false unless @phase == :discard && seat == @taker
      return false unless cards.size == 6 && cards.uniq.size == 6 && (cards - @hands[seat]).empty?
      ordinary = @hands[seat].reject { |suit, rank| %i[trump excuse].include?(suit) || rank == 14 }
      return false unless (cards & ordinary).size == [6, ordinary.size].min
      return false unless (cards - ordinary).all? { |card| card.first == :trump && !FrenchTarotScoring.oudler?(card) }
      @kitty = @hands[seat].select { |card| cards.include?(card) }
      @hands[seat] -= cards
      begin_play
      true
    end

    def trick
      @trick.map(&:last)
    end

    def lead_seat
      @trick.first&.first || @turn
    end

    def legal_cards(seat)
      return [] unless @phase == :play && seat == @turn
      FrenchTarotTrick.legal(@hands[seat], @trick.map(&:last))
    end

    def play(seat, card)
      return false unless legal_cards(seat).include?(card)
      @trick << [seat, @hands[seat].delete(card)]
      @played += 1
      @turn = (seat + 1) % 4
      return true unless @trick.size == 4
      winner = @trick.fetch(FrenchTarotTrick.winner(@trick.map(&:last))).first
      taking = side(winner)
      @trick.each do |owner, played|
        if played.first == :excuse && @played < 72 && side(owner) != taking
          @piles[side(owner)] << played
          @excuse_debt[side(owner)] += 1
        else
          @piles[taking] << played
        end
      end
      @trick.clear
      @turn = winner
      if @played == 72
        @piles[@contract == :garde_contre ? 1 : 0].concat(@kitty)
        @phase = :finished
        @turn = nil
      end
      true
    end

    def result
      return unless @phase == :finished
      totals = @piles.map { |cards| cards.sum { |card| FrenchTarotScoring.half_points(card) } }
      correction = @excuse_debt[0] - @excuse_debt[1]
      totals[0] -= correction
      totals[1] += correction
      {half_points: totals, oudlers: @piles[0].count { |card| FrenchTarotScoring.oudler?(card) }}
    end

    # Base contract settlement, in half-points. Special bonuses are separate.
    def contract_scores
      summary = result
      return unless summary
      margin = summary[:half_points].first - FrenchTarotScoring::TARGET.fetch(summary[:oudlers])
      value = (50 + margin.abs) * FrenchTarotScoring::CONTRACTS.fetch(@contract)
      value = -value if margin.negative?
      4.times.map { |seat| seat == @taker ? 3 * value : -value }
    end

    private

    def side(seat)
      seat == @taker ? 0 : 1
    end

    def begin_play
      @turn = @first
      @phase = :play
    end
  end
end
