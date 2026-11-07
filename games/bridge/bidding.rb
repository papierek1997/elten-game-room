require_relative 'rules'

module GameRoomGames
  # Compact natural bidding, using only our cards and the public auction.
  # A higher opposing bid changes the available contracts, not the meaning
  # of partner's first natural opening.
  class BridgeBidding
    R = BridgeRules
    MAJORS = %w[S H].freeze
    SUITS = %w[S H D C].freeze
    BALANCED = [[2, 3, 3, 5], [2, 3, 4, 4], [3, 3, 3, 4]].freeze
    Bid = Struct.new(:seat, :strain, :level, :role, :support, :contested, :jump, keyword_init: true)

    def initialize(observation)
      @seat = observation.fetch('seat')
      @partner = R.partner_of(@seat)
      @side = R.side_of(@seat)
      @vulnerable = R.vulnerable?(observation.fetch('vulnerability', 'none'), @side)
      hand = observation.fetch('hand')
      @points = R.high_card_points(hand)
      @cards = hand.group_by { |card| R.card_suit(card) }
      @lengths = SUITS.to_h { |suit| [suit, @cards.fetch(suit, []).length] }
      @balanced = BALANCED.include?(@lengths.values.sort)
      calls = observation.fetch('calls')
      @legal = R.legal_calls(calls, @seat)
      @shown_lengths = Array.new(R::SEATS) { Hash.new(0) }
      bids = read_auction(calls)
      @own, @partners = bids.select { |bid| R.side_of(bid.seat) == @side }.partition { |bid| bid.seat == @seat }
      @opponents = bids.reject { |bid| R.side_of(bid.seat) == @side }
      @last = bids.last
      @contested = @last && R.side_of(@last.seat) != @side
      @minimum, @estimate = partner_strength
    end

    def call
      (if @own.empty? && @partners.empty?
        @contested ? overcall : opening
      elsif @own.empty?
        response
      else
        rebid
      end) || R::PASS
    end

    private

    def read_auction(calls)
      bids, seen = [], Array.new(R::SEATS) { [] }
      calls.each do |seat, value|
        next unless R.bid?(value)

        partner = R.partner_of(seat)
        strain, level = R.bid_strain(value), R.bid_level(value)
        role = if !seen[seat].empty? then :rebid
        elsif !seen[partner].empty? then :response
        elsif bids.empty? then :opening
        else :overcall
        end
        previous = bids.last
        contested = previous && R.side_of(previous.seat) != R.side_of(seat)
        cheapest = previous && (R::STRAINS.index(strain) <= R::STRAINS.index(previous.strain) ? previous.level + 1 : previous.level)
        support = strain != 'N' && @shown_lengths[partner][strain].positive?
        bid = Bid.new(seat: seat, strain: strain, level: level, role: role, support: support,
          contested: contested, jump: cheapest && level > cheapest)
        if strain != 'N'
          length = if support
            [3, 8 - @shown_lengths[partner][strain]].max
          elsif seen[seat].any? { |earlier| earlier.strain == strain }
            6
          elsif role == :opening
            level > 1 ? 6 : (MAJORS.include?(strain) ? 5 : (strain == 'D' ? 4 : 3))
          elsif role == :overcall || (role == :response && level > 1)
            5
          else
            4
          end
          @shown_lengths[seat][strain] = [@shown_lengths[seat][strain], length].max
        end
        bids << bid
        seen[seat] << bid
      end
      bids
    end

    # For invitations and game tries, distinguish a minimum from a typical
    # holding. A forced raise at the three level is not an invitation.
    def partner_strength
      first = @partners.first
      return [0, 0] unless first

      last = @partners.last
      if last.support && last.role != :opening
        return [13, 14] if last.level >= game_level(last.strain)
        if last.role == :rebid && first.role == :opening
          return last.jump && !last.contested ? [16, 17] : [12, 13]
        end
        return [10, 11] if !last.contested && last.level >= 3
        return [6, 8] if last.level <= 3
      end
      if first.strain == 'N'
        if first.role == :response
          return [8, 9] if first.level == 2 && @own.first&.strain == 'N' && @own.first.level == 1
          return [5, 7] if first.level == 3 && @own.first&.strain == 'N' && @own.first.level == 2
          return [[6, 8], [11, 12], [13, 14]].fetch([first.level, 3].min - 1)
        end
        return [15, 16] if first.level == 1
        return [20, 20] if first.level == 2 && first.role == :opening
      elsif first.role == :opening
        return [6, 8] if first.level > 1
        if last.strain == 'N' && last.role == :rebid
          return [12, 13] if last.level == 1
          return [18, 19] if last.level == 2 && last.jump && !last.contested
        end
        if last.role == :rebid && !last.contested && last.level == 2 && last.strain != 'N' &&
            R::SUITS.index(last.strain) > R::SUITS.index(first.strain)
          return [17, 18]
        end
        return [12, 14]
      end
      return [9, first.level == 1 ? 11 : 13] if first.role == :overcall
      return [8, 9] if @own.first&.strain == 'N' && first.level >= 3
      return [10, 12] if first.level > 1 && first.role == :response

      [6, 8]
    end

    def exact(level, strain)
      call = "#{level}#{strain}"
      call if @legal.include?(call)
    end

    def cheapest(strain, limit, from: 1)
      (from..limit).each do |level|
        candidate = exact(level, strain)
        return candidate if candidate
      end
      nil
    end

    def ordered_suits(suits = SUITS)
      suits.sort_by { |suit| [-@lengths.fetch(suit), SUITS.index(suit)] }
    end

    def sound?(suit)
      cards = @cards.fetch(suit, [])
      ranks = cards.map { |card| R.card_rank(card) }
      (ranks & %w[A K Q J T]).length >= 2 && (ranks & %w[A K Q]).any?
    end

    def stopped?(suit)
      cards = @cards.fetch(suit, [])
      cards.include?("A#{suit}") || cards.include?("K#{suit}") && cards.length >= 2 ||
        cards.include?("Q#{suit}") && cards.length >= 3
    end

    def notrump_safe?
      @opponents.all? { |bid| bid.strain == 'N' || stopped?(bid.strain) }
    end

    def game_level(strain)
      return 3 if strain == 'N'
      MAJORS.include?(strain) ? 4 : 5
    end

    def fit?(suit)
      support = @lengths.fetch(suit)
      partner = @shown_lengths[@partner][suit]
      support >= 2 && partner.positive? && support + partner >= 8
    end

    def fit_points(suit)
      shortness = @lengths.reject { |name, _length| name == suit }.values.sum { |length| [2 - length, 0].max }
      extra_trump = @lengths[suit] >= 4 && @lengths[suit] + @shown_lengths[@partner][suit] >= 9
      @points + shortness + (extra_trump ? 1 : 0)
    end

    def opening
      return exact(1, 'N') if @balanced && @points.between?(15, 17)
      return exact(2, 'N') if @balanced && @points.between?(20, 21)
      if @points >= 12 || (@points == 11 && SUITS.any? { |suit| @lengths[suit] >= 6 && sound?(suit) })
        major = ordered_suits(MAJORS).find { |suit| @lengths[suit] >= 5 }
        minor = @lengths['D'] >= 4 && @lengths['D'] >= @lengths['C'] ? 'D' : 'C'
        return exact(1, major || minor)
      end
      if @points.between?(6, 10)
        weak = ordered_suits(%w[S H D]).find { |suit| @lengths[suit] >= 6 && sound?(suit) }
        return exact(2, weak) if weak
      end
      nil
    end

    def overcall
      if @balanced && @points.between?(15, 18) && notrump_safe?
        candidate = exact(1, 'N')
        return candidate if candidate
      end
      return nil if @points < 9

      # Another suit at a safe level is preferable to passing only because
      # the longest one would need a bid above that level.
      limit = @points >= (@vulnerable ? 12 : 10) ? 2 : 1
      ordered_suits.each do |suit|
        next if @lengths[suit] < 5 || !sound?(suit) || @opponents.any? { |bid| bid.strain == suit }

        candidate = cheapest(suit, limit)
        return candidate if candidate
      end
      nil
    end

    def response
      first = @partners.first
      return notrump_response(first) if first.strain == 'N'
      return preempt_response(first) if first.role == :opening && first.level > 1
      return nil if @points < 6

      strain = first.strain
      fit = fit?(strain)
      if fit && MAJORS.include?(strain)
        points = fit_points(strain) - (first.role == :overcall ? 2 : 0)
        target = points >= 13 ? 4 : (points >= 10 ? 3 : 2)
        candidate = exact(target, strain)
        return candidate if candidate
      end

      new_suits = ordered_suits.reject { |suit| suit == strain || @opponents.any? { |bid| bid.strain == suit } }
      # Name a four-card major before settling in a minor or in notrump.
      new_suits.sort_by! { |suit| [MAJORS.include?(suit) ? 0 : 1, -@lengths[suit], SUITS.index(suit)] }
      new_suits.each do |suit|
        candidate = exact(1, suit) if @lengths[suit] >= 4
        return candidate if candidate
      end
      new_suits.each do |suit|
        candidate = exact(2, suit) if @points >= (first.role == :overcall ? 11 : 10) && @lengths[suit] >= 5
        return candidate if candidate
      end
      if @balanced && notrump_safe?
        target = @points + @estimate >= 25 && @points >= 13 ? 3 : (@points >= 11 ? 2 : 1)
        candidate = exact(target, 'N')
        return candidate if candidate
      end
      if fit && !MAJORS.include?(strain)
        candidate = exact(3, strain) if @points >= 11 && !@contested
        return candidate || cheapest(strain, 2)
      end

      exact(1, 'N') if notrump_safe? && @lengths.values.min.positive?
    end

    def notrump_response(first)
      return nil if first.level > 2 || !notrump_safe? && !MAJORS.any? { |suit| @lengths[suit] >= 6 }

      long = ordered_suits(MAJORS).find { |suit| @lengths[suit] >= 6 && sound?(suit) }
      if long
        total = @points + @estimate
        level = if total >= 25 then 4
        elsif first.level == 1 && @points >= 8 then 3
        elsif first.level == 1 then 2
        end
        candidate = exact(level, long) if level
        return candidate if candidate
      end
      return nil unless notrump_safe?
      return exact(6, 'N') if @balanced && @points + @minimum >= 33
      return exact(3, 'N') if @points + @minimum >= 25

      exact(2, 'N') if first.level == 1 && @points.between?(8, 9)
    end

    def preempt_response(first)
      strain = first.strain
      return nil if @lengths.fetch(strain) < 3

      return exact(game_level(strain), strain) if fit_points(strain) + @estimate >= (MAJORS.include?(strain) ? 25 : 28)

      exact(3, strain) if first.level == 2 && !@vulnerable
    end

    def rebid
      return nil if @partners.empty?

      major = ordered_suits(MAJORS).find { |suit| fit?(suit) }
      agreed = major && (@own + @partners).any? { |bid| bid.strain == major && bid.support }
      total = (major ? fit_points(major) : @points) + @estimate
      safe_nt = @balanced && notrump_safe?
      if @points + @minimum >= 33 && (!@contested || @points >= 18)
        slam = exact(6, major) if agreed
        slam ||= exact(6, 'N') if safe_nt && !major
        return slam if slam
      end
      return nil if !@contested && @last.level >= game_level(@last.strain)

      first = @own.first
      if first.strain == 'N' && @partners.last.strain == 'N'
        # Over our 1NT, 2NT is an invitation (8–9), not a new opening.
        return exact(3, 'N') if first.level == 1 && @partners.last.level == 2 && @points + @estimate >= 25
        return nil
      end
      if major
        candidate = exact(4, major) if total >= 25
        return candidate if candidate
        return nil if agreed && !@contested
        # Raise to three on a clear invitation, not because two was taken.
        invite = !@contested && first.role == :opening && @points >= 16 && total >= 23
        return exact(3, major) if invite
        return cheapest(major, 2)
      end
      candidate = new_suit_rebid(first, 1)
      return candidate if candidate
      if safe_nt
        candidate = exact(3, 'N') if total >= 26 || (@partners.last.strain == 'N' && total >= 25)
        return candidate if candidate
        if first.role == :opening && first.strain != 'N' && @own.size == 1
          candidate = exact(@points >= 18 ? 2 : 1, 'N')
          return candidate if candidate
        end
      end
      return nil if @own.size > 1

      # A natural repeat shows a six-card suit. Never push a minimum above
      # the two level to find a second call.
      if first.strain != 'N' && @lengths[first.strain] >= 6
        candidate = cheapest(first.strain, 2)
        return candidate if candidate
      end
      candidate = new_suit_rebid(first, 2)
      return candidate if candidate
      suit = ordered_suits.find { |name| fit?(name) && name != first.strain }
      cheapest(suit, 2) if suit
    end

    def new_suit_rebid(first, level)
      return nil unless first.role == :opening && first.strain != 'N' && @own.size == 1 && !@contested
      return nil if level == 2 && @lengths[first.strain] < 5

      ordered_suits.each do |suit|
        next if suit == first.strain || @lengths[suit] < 4 || @opponents.any? { |bid| bid.strain == suit }
        # Moving up to a higher-ranking second suit can force partner to
        # return to our first suit at the three level. Show extras first.
        next if level == 2 && R::SUITS.index(suit) > R::SUITS.index(first.strain) && @points < 17

        candidate = exact(level, suit)
        return candidate if candidate
      end
      nil
    end
  end
end
