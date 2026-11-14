module GameRoomGames
  class JassRound
    SUITS = %i[clubs diamonds hearts spades].freeze
    DECK = SUITS.product((6..14).to_a).map(&:freeze).freeze
    TRUMP_ORDER = [6, 7, 8, 10, 12, 13, 14, 9, 11].freeze
    VALUES = {10 => 10, 11 => 2, 12 => 3, 13 => 4, 14 => 11}.freeze

    attr_reader :turn, :trump

    def initialize(deck, dealer:)
      raise ArgumentError unless deck.size == 36 && deck.uniq.size == 36 && (deck - DECK).empty?
      raise ArgumentError unless [0, 1, 2, 3].include?(dealer)
      @leader = @turn = (dealer + 1) % 4
      @hands = deck.map { |card| card.dup.freeze }.each_slice(9).to_a
      @trick, @scores = [], [0, 0]
      @played = 0
    end

    def hand(seat); @hands.fetch(seat).dup; end
    def scores; @scores.dup; end

    # Build a seat-specific view; nil is the spectator perspective.
    def observation(seat)
      raise ArgumentError unless seat.nil? || [0, 1, 2, 3].include?(seat)
      {
        turn: @turn, trump: @trump, leader: @leader, scores: scores,
        trick: @trick.dup, counts: @hands.map(&:size),
        hand: seat.nil? ? [] : hand(seat),
        bids: seat.nil? ? [] : bids(seat),
        legal_cards: seat.nil? ? [] : legal_cards(seat)
      }
    end

    def bids(seat)
      return [] if @trump || seat != @turn
      seat == @leader ? SUITS + [:pass] : SUITS.dup
    end

    def bid(seat, choice)
      return false unless bids(seat).include?(choice)
      if choice == :pass
        @turn = (seat + 2) % 4
      else
        @trump = choice
        @turn = @leader
      end
      true
    end

    def legal_cards(seat)
      return [] unless @trump && @turn && seat == @turn
      cards = @hands[seat]
      self.class.legal(cards, @trick, @trump)
    end

    def self.legal(cards, trick, trump)
      return cards.dup if trick.empty?
      lead = trick.first.first
      follow = cards.select { |suit, _| suit == lead }
      return follow.empty? ? cards.dup : follow if lead == trump
      candidates = follow.empty? ? cards : cards.select { |suit, _| suit == lead || suit == trump }
      highest = trick.filter_map { |suit, rank| TRUMP_ORDER.index(rank) if suit == trump }.max
      return candidates.dup unless highest
      allowed = candidates.reject { |suit, rank| suit == trump && TRUMP_ORDER.index(rank) < highest }
      allowed.empty? ? candidates.dup : allowed
    end

    def self.settle_trick(trick, trump, last: false)
      lead = trick.first.first
      winner = trick.each_index.max_by do |index|
        suit, rank = trick.fetch(index)
        suit == trump ? [2, TRUMP_ORDER.index(rank)] : [suit == lead ? 1 : 0, trump == :low ? -rank : rank]
      end
      points = trick.sum do |suit, rank|
        if suit == trump && rank == 11
          20
        elsif suit == trump && rank == 9
          14
        else
          if trump == :low && rank == 6
            11
          elsif trump == :low && rank == 14
            0
          elsif %i[high low].include?(trump) && rank == 8
            8
          else
            VALUES.fetch(rank, 0)
          end
        end
      end
      [winner, points + (last ? 5 : 0)]
    end

    def play(seat, card)
      return false unless legal_cards(seat).include?(card)
      @trick << @hands[seat].delete(card)
      @played += 1
      if @trick.size == 4
        index, points = self.class.settle_trick(@trick, @trump, last: @played == 36)
        @leader = (@leader + index) % 4
        @scores[@leader % 2] += points
        @trick.clear
        @turn = @played == 36 ? nil : @leader
      else
        @turn = (seat + 1) % 4
      end
      true
    end
  end
end
