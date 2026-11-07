require_relative 'play_planner'
require_relative 'bidding'

module GameRoomGames
  # Natural bidding and a play planner using the same information as a
  # player: own hand, dummy after the lead, auction and public tricks.
  class BridgeStrategy
    include GameRoomBots::ReplayOnlyStrategy
    R = BridgeRules
    Bidding = BridgeBidding

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
