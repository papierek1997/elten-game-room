module GameRoomGames
  module BeloteSettlement
    def self.settle(tricks, taker:, bonuses: [0, 0], carry: 0, sweep: nil)
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
        paid[winner] += carry + (sweep == winner ? 90 : 0)
        carry = 0
      end
      {scores: paid.zip(bonuses).map(&:sum), carry: carry, winner: winner}
    end
  end
end
