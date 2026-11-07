require_relative 'play_planner'

module GameRoomGames
  # Natural bidding and a play planner using the same information as a
  # player: own hand, dummy after the lead, auction and public tricks.
  class BridgeStrategy
    include GameRoomBots::ReplayOnlyStrategy
    R = BridgeRules

    def choose(actions:, observation:, actor:, random_source:, **_extra)
      values = actions.to_a
      return values.first if values.size <= 1

      choice = if observation["phase"] == "bidding"
        call = Bidding.new(observation).call
        values.find { |action| action["call"] == call }
      else
        legal = values.map { |action| action["card"] }
        fallback = Play.new(observation).card(legal)
        card = BridgePlayPlanner.new(observation).choose(legal, fallback)
        values.find { |action| action["card"] == card }
      end
      choice || values.find { |action| action["call"] == R::PASS } || values.first
    end

    module HandShape
      def lengths(cards)
        R::SUITS.to_h { |suit| [suit, cards.count { |card| R.card_suit(card) == suit }] }
      end

      def balanced?(cards)
        shape = lengths(cards).values.sort
        [[3, 3, 3, 4], [2, 3, 4, 4], [2, 3, 3, 5]].include?(shape)
      end
    end

    class Bidding
      include HandShape

      def initialize(observation)
        @seat = observation["seat"].to_i
        @hand = observation["hand"].to_a
        @calls = observation["calls"].to_a
        @points = R.high_card_points(@hand)
        @lengths = lengths(@hand)
        @vulnerable = R.vulnerable?(observation.fetch("vulnerability", "none"), R.side_of(@seat))
      end

      def call
        choice = proposed_call
        legal = R.legal_calls(@calls, @seat)
        legal.include?(choice) ? choice : R::PASS
      end

      private

      def partner
        R.partner_of(@seat)
      end

      def bids_by(seat)
        @calls.select { |caller, call| caller == seat && R.bid?(call) }.map(&:last)
      end

      def opponents_bid?
        @calls.any? { |caller, call| R.side_of(caller) != R.side_of(@seat) && R.bid?(call) }
      end

      def proposed_call
        mine = bids_by(@seat)
        partners = bids_by(partner)
        return opening_or_overcall if mine.empty? && partners.empty?
        return response(partners.first) if mine.empty?

        rebid(mine, partners)
      end

      def longest_suit(minimum: 0)
        suit = R::SUITS.reverse.max_by { |name| [@lengths[name], %w[S H].include?(name) ? 1 : 0] }
        @lengths[suit] >= minimum ? suit : nil
      end

      def cheapest_bid(strain)
        highest = R.last_bid(@calls)
        level = 1
        level += 1 while highest != nil && R.bid_index("#{level}#{strain}") <= R.bid_index(highest[1]) && level < 7
        "#{level}#{strain}"
      end

      def opening_or_overcall
        return overcall if opponents_bid?
        return "1N" if balanced?(@hand) && @points.between?(15, 17)
        return "2N" if balanced?(@hand) && @points.between?(20, 21)
        if @points >= 12 || (@points >= 11 && @lengths.values.max >= 6)
          major = %w[S H].max_by { |suit| @lengths[suit] }
          major = nil if @lengths[major] < 5
          return "1#{major}" if major
          return "1D" if @lengths["D"] >= 4 && @lengths["D"] >= @lengths["C"]

          return "1C"
        end
        weak = %w[S H D].select { |suit| @lengths[suit] >= 6 && sound_suit?(suit) }
          .max_by { |suit| @lengths[suit] }
        return "2#{weak}" if weak && @points.between?(6, 10)

        R::PASS
      end

      def overcall
        suit = %w[S H D C].select { |name| @lengths[name] >= 5 && sound_suit?(name) }
          .max_by { |name| @lengths[name] }
        if suit && @points.between?(9, 16)
          bid = cheapest_bid(suit)
          return bid if R.bid_level(bid) == 1 || R.bid_level(bid) == 2 && @points >= (@vulnerable ? 12 : 10)
        end
        bid = cheapest_bid("N")
        return bid if balanced?(@hand) && @points.between?(15, 18) && R.bid_level(bid) == 1 && stopped_opponents?

        R::PASS
      end

      def response(opening)
        strain = R.bid_strain(opening)
        level = R.bid_level(opening)
        return notrump_response(level) if strain == "N"
        return weak_two_response(strain) if weak_two_opening?(partner, opening)
        return R::PASS if @points < 6

        support = @lengths[strain] >= (%w[S H].include?(strain) ? 3 : 4)
        if support
          points = @points + fit_shortness(strain)
          target = if points >= 13 && %w[S H].include?(strain) then "4#{strain}"
          elsif @points >= 13 && stopped_opponents? then "3N"
          elsif points >= 10 then "3#{strain}"
          else "2#{strain}"
          end
          return target
        end
        new_suit = %w[S H D C].find { |suit| @lengths[suit] >= 4 && R.bid_index("1#{suit}") > R.bid_index(opening) }
        return "1#{new_suit}" if new_suit && level == 1
        return "3N" if @points >= 13 && stopped_opponents?
        return "2N" if @points >= 11 && stopped_opponents?

        cheapest_bid("N").start_with?("1") ? "1N" : R::PASS
      end

      def weak_two_opening?(seat, call)
        @calls.find { |_, bid| R.bid?(bid) } == [seat, call] && call.match?(/\A2[DSH]\z/)
      end

      def weak_two_response(strain)
        support = @lengths.fetch(strain)
        return R::PASS if support < 3

        total = @points + 8 + fit_shortness(strain)
        return "4#{strain}" if %w[S H].include?(strain) && total >= 25
        return "5D" if strain == "D" && total >= 28
        return "3#{strain}" if total >= 20 || !@vulnerable

        R::PASS
      end

      def fit_shortness(trump)
        @lengths.reject { |suit, _| suit == trump }.values.sum { |length| [2 - length, 0].max }
      end

      def sound_suit?(suit)
        cards = @hand.select { |card| R.card_suit(card) == suit }
        cards.count { |card| R.rank_index(card) >= R.rank_index('TS') } >= 2
      end

      def stopped_opponents?
        suits = @calls.filter_map do |seat, bid|
          strain = R.bid_strain(bid) if R.bid?(bid)
          strain if R.side_of(seat) != R.side_of(@seat) && R::SUITS.include?(strain)
        end.uniq
        suits.all? do |suit|
          @hand.include?("A#{suit}") || @hand.include?("K#{suit}") && @lengths[suit] >= 2 ||
            @hand.include?("Q#{suit}") && @lengths[suit] >= 3
        end
      end

      def notrump_response(level)
        partner_points = level == 1 ? 16 : 20
        total = @points + partner_points
        major = %w[S H].find { |suit| @lengths[suit] >= 6 }
        return R::PASS if total < 23
        return "#{level + 1}N" if total < 25 && level == 1
        return "6N" if total >= 33
        return "4#{major}" if major

        "3N"
      end

      # Opening bids promise about 13 points, a response about 8.
      def partner_estimate(partners)
        first = partners.first
        return 0 if first == nil
        return 16 if first == "1N"
        return 20 if first == "2N"
        return 8 if weak_two_opening?(partner, first)

        first_index = ->(seat) { @calls.index { |caller, call| caller == seat && R.bid?(call) } }
        mine = first_index.call(@seat)
        mine == nil || first_index.call(partner) < mine ? 13 : 8
      end

      def rebid(mine, partners)
        total = @points + partner_estimate(partners)
        fit = (mine + partners).map { |bid| R.bid_strain(bid) }.tally.find { |strain, count| count >= 2 && strain != "N" }&.first
        fit ||= partners.map { |bid| R.bid_strain(bid) }.find { |strain| strain != "N" && @lengths[strain] >= 3 }
        total += fit_shortness(fit) if fit && %w[S H].include?(fit)
        current = R.last_bid(@calls)
        ours = current != nil && R.side_of(current[0]) == R.side_of(@seat)
        target = if total >= 33
          fit ? "6#{fit}" : "6N"
        elsif total >= 25
          fit && %w[S H].include?(fit) ? "4#{fit}" : (stopped_opponents? ? "3N" : nil)
        elsif fit
          "2#{fit}"
        end
        return R::PASS if target == nil
        return R::PASS if ours && R.bid_index(current[1]) >= R.bid_index(target)
        return R::PASS if !ours && current != nil && R.bid_level(current[1]) >= 3 && total < 25

        target
      end
    end

    class Play
      def initialize(observation)
        @seat = observation["seat"].to_i
        @to_play = observation["seat_to_play"].to_i
        @hand = observation["hand"].to_a
        @dummy = observation["dummy"].to_a
        @trick = observation["trick"].to_a
        @played = observation["played"].to_a.map(&:last)
        contract = observation["contract"] || {}
        @strain = contract["strain"].to_s
        @declarer = contract["declarer"].to_i
        @calls = observation["calls"].to_a
      end

      def card(legal)
        return legal.first if legal.length == 1
        return lead(legal) if @trick.empty?

        follow(legal)
      end

      private

      def trump?(card)
        @strain != "N" && R.card_suit(card) == @strain
      end

      def lowest(cards)
        cards.min_by { |card| [trump?(card) ? 1 : 0, R.rank_index(card)] }
      end

      def highest(cards)
        cards.max_by { |card| R.rank_index(card) }
      end

      def known_cards
        @played + @hand + @dummy + @trick.map(&:last)
      end

      # A card is a sure winner when every higher card of its suit is gone or
      # sits in a hand this player can see on its own side.
      def boss?(card)
        suit = R.card_suit(card)
        higher = R::RANKS.drop(R.rank_index(card) + 1).map { |rank| "#{rank}#{suit}" }
        own = declaring_side? ? @hand + @dummy : @hand
        higher.all? { |other| @played.include?(other) || own.include?(other) || @trick.any? { |_s, c| c == other } }
      end

      def declaring_side?
        R.side_of(@seat) == R.side_of(@declarer)
      end

      def winning_play(trick)
        winner = R.trick_winner(trick, @strain.empty? ? "N" : @strain)
        trick.find { |seat, _card| seat == winner }
      end

      def beats?(card, current)
        led = R.card_suit(@trick.first[1])
        return trump?(card) && (!trump?(current) || R.rank_index(card) > R.rank_index(current)) if R.card_suit(card) != R.card_suit(current)

        R.card_suit(card) == led || trump?(card) ? R.rank_index(card) > R.rank_index(current) : false
      end

      def follow(legal)
        winner_seat, winner_card = winning_play(@trick)
        partner_winning = R.side_of(winner_seat) == R.side_of(@to_play)
        winners = legal.select { |card| beats?(card, winner_card) }
        last_to_play = @trick.length == 3
        if partner_winning && (last_to_play || boss?(winner_card) || R.rank_index(winner_card) >= R.rank_index("QS"))
          return lowest(legal)
        end
        return lowest(legal) if winners.empty?
        return winners.min_by { |card| [trump?(card) ? 1 : 0, R.rank_index(card)] } if last_to_play || @trick.length == 2
        # Second hand plays low unless it can win with a certain winner.
        sure = winners.select { |card| boss?(card) && !trump?(card) }
        sure.empty? ? lowest(legal) : sure.min_by { |card| R.rank_index(card) }
      end

      def lead(legal)
        if @played.empty? && !declaring_side?
          return opening_lead(legal)
        end
        if declaring_side? && @strain != "N"
          trumps = legal.select { |card| trump?(card) }
          outstanding = R::RANKS.map { |rank| "#{rank}#{@strain}" } - known_cards
          return (trumps.find { |card| boss?(card) } || lowest(trumps)) if trumps.any? && outstanding.any?
        end
        sure = legal.select { |card| boss?(card) && !trump?(card) }
        return highest(sure) if sure.any?

        partner_suit = partner_bid_suit
        partner_cards = legal.select { |card| R.card_suit(card) == partner_suit }
        return lowest(partner_cards) if partner_cards.any? && !declaring_side?

        longest = legal.reject { |card| trump?(card) }.group_by { |card| R.card_suit(card) }.max_by { |_suit, cards| cards.length }
        longest == nil ? lowest(legal) : lowest(longest[1])
      end

      def partner_bid_suit
        partner = R.partner_of(@to_play)
        bid = @calls.reverse.find { |seat, call| seat == partner && R.bid?(call) && R.bid_strain(call) != "N" }
        bid == nil ? nil : R.bid_strain(bid[1])
      end

      def opening_lead(legal)
        suit = partner_bid_suit
        candidates = legal.select { |card| R.card_suit(card) == suit }
        if candidates.empty?
          groups = legal.reject { |card| trump?(card) }.group_by { |card| R.card_suit(card) }
          groups = legal.group_by { |card| R.card_suit(card) } if groups.empty?
          candidates = groups.max_by { |_suit, cards| [cards.length, cards.sum { |card| R.rank_index(card) }] }[1]
        end
        sorted = candidates.sort_by { |card| -R.rank_index(card) }
        touching = sorted.length >= 2 && R.rank_index(sorted[0]) == R.rank_index(sorted[1]) + 1 && R.rank_index(sorted[0]) >= R.rank_index("QS")
        return sorted.first if touching || sorted.length <= 2
        return sorted[3] if sorted.length >= 4

        sorted.last
      end
    end
  end
end
