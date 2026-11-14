module GameRoomGames
  module HeartsRules
    module_function

    def exchange(hands, passes, offset)
      hands.each_index.map do |seat|
        retained = hands.fetch(seat) - passes.fetch(seat)
        retained + passes.fetch((seat - offset) % hands.size)
      end
    end

    def penalty(card)
      suit, rank = card
      return 1 if suit == :hearts
      suit == :spades && rank == 12 ? 13 : 0
    end

    def legal(hand, trick, first_trick:, hearts_broken:)
      if trick.empty?
        return hand.select { |card| card == [:clubs, 2] } if first_trick
        non_hearts = hand.reject { |suit, _| suit == :hearts }
        return !hearts_broken && !non_hearts.empty? ? non_hearts : hand.dup
      end
      follow = hand.select { |suit, _| suit == trick.first.first }
      return follow unless follow.empty?
      safe = hand.reject { |card| penalty(card).positive? }
      first_trick && !safe.empty? ? safe : hand.dup
    end

    def trick_winner(trick)
      trick.each_index.select { |i| trick[i].first == trick.first.first }.max_by { |i| trick[i].last }
    end

    def settle(captured)
      scores = captured.map { |cards| cards.sum { |card| penalty(card) } }
      shooter = scores.index(26)
      shooter ? scores.each_index.map { |i| i == shooter ? 0 : 26 } : scores
    end
  end
end
