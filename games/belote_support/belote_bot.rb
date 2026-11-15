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

    def play(legal, trump)
      legal.min_by { |suit, rank| [suit == trump ? 1 : 0, (suit == trump ? BeloteTrick::TRUMP : BeloteTrick::NORMAL).index(rank)] }
    end
  end
end
