require_relative "belote_trick"

module GameRoomGames
  module BeloteBot
    module_function

    def bid(choices, hand, upcard)
      suits = choices - [:pass]
      return :pass if suits.empty?
      strength = ->(suit) { BeloteTrick.points((hand + [upcard]).select { |card| card.first == suit }, suit) }
      best = suits.max_by(&strength)
      strength.call(best) >= 20 ? best : :pass
    end

    def play(legal, trump, trick: [], partner_winning: false)
      strength = ->(card) { suit, rank = card; [suit == trump ? 1 : 0, (suit == trump ? BeloteTrick::TRUMP : BeloteTrick::NORMAL).index(rank)] }
      return legal.min_by(&strength) if trick.empty?
      winning, losing = legal.partition { |card| BeloteTrick.winner(trick + [card], trump) == trick.size }
      # Feed points to a winning partner instead of overtaking them. If the
      # trick is inevitably ours, shed a high card; otherwise win cheaply.
      return losing.max_by { |card| [BeloteTrick.points([card], trump), strength.call(card)] } if partner_winning && !losing.empty?
      return legal.max_by(&strength) if winning.size == legal.size
      return winning.min_by(&strength) unless winning.empty?
      legal.min_by { |card| [BeloteTrick.points([card], trump), strength.call(card)] }
    end
  end
end
