require_relative "belote_round"

module GameRoomGames
  class BeloteDeal
    attr_reader :turn, :phase, :trump, :taker, :upcard

    def initialize(deck, dealer:)
      raise ArgumentError unless deck.size == 32 && deck.uniq.size == 32 && (deck - BeloteRound::DECK).empty?
      raise ArgumentError unless [0, 1, 2, 3].include?(dealer)
      @deck = deck.map { |card| card.dup.freeze }
      @leader = @turn = (dealer + 1) % 4
      @hands = Array.new(4) { [] }
      [3, 2].each do |count|
        4.times { |i| @hands[(@leader + i) % 4].concat(@deck.shift(count)) }
      end
      @upcard = @deck.shift
      @phase = :bidding
      @passes = 0
      @announced = {}
    end

    def bids(seat)
      return [] unless @phase == :bidding && seat == @turn
      self.class.bid_choices(@upcard.first, @passes)
    end

    def self.bid_choices(offered, passes)
      [:pass] + (passes < 4 ? [offered] : BeloteRound::SUITS - [offered])
    end

    def hand(seat)
      @phase == :play ? @round.hand(seat) : @hands.fetch(seat).dup
    end

    def bid(seat, choice)
      return false unless bids(seat).include?(choice)
      if choice == :pass
        @passes += 1
        if @passes == 8
          @phase = :redeal
          @turn = nil
        else
          @turn = (@turn + 1) % 4
        end
      else
        @taker, @trump = seat, choice
        @hands[seat] << @upcard
        4.times do |i|
          receiver = (seat + i) % 4
          @hands[receiver].concat(@deck.shift(i.zero? ? 2 : 3))
        end
        @round = BeloteRound.new(@hands.flatten(1), trump: @trump, leader: @leader)
        @turn = @round.turn
        @phase = :play
      end
      true
    end

    def legal_cards(seat)
      @phase == :play ? @round.legal_cards(seat) : []
    end

    def play(seat, card, announce: false)
      return false unless legal_cards(seat).include?(card)
      if announce
        return false unless card.first == @trump
        valid = case card.last
        when 13 then @round.hand(seat).include?([@trump, 12])
        when 12 then @announced[seat] == :belote
        else false
        end
        return false unless valid
        @announced[seat] = card.last == 13 ? :belote : :rebelote
      end
      @round.play(seat, card)
      @turn = @round.turn
      @phase = :finished unless @turn
      true
    end

    def settlement(carry: 0)
      return unless @phase == :finished
      bonuses = [0, 0]
      @announced.each { |seat, status| bonuses[seat % 2] += 20 if status == :rebelote }
      self.class.settle(@round.scores, taker: @taker % 2, bonuses: bonuses, carry: carry)
    end

    def self.settle(tricks, taker:, bonuses: [0, 0], carry: 0)
      defender = 1 - taker
      compared = tricks.zip(bonuses).map(&:sum)
      winner = nil
      if compared[taker] == compared[defender]
        paid = tricks.dup
        carry += paid[taker]
        paid[taker] = 0
      elsif compared[taker] >= 82 && compared[taker] > compared[defender]
        winner = taker
        paid = tricks.dup
      else
        winner = defender
        paid = [0, 0]
        paid[defender] = 162
      end
      if winner
        paid[winner] += carry + (tricks[winner] == 162 ? 90 : 0)
        carry = 0
      end
      {scores: paid.zip(bonuses).map(&:sum), carry: carry, winner: winner}
    end
  end
end
