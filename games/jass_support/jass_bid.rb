module GameRoomGames
  module JassBid
    module_function

    def actions(round, seat)
      round.bids(seat).map do |choice|
        {"kind" => "command", "action" => "choose_trump", "choice" => choice.to_s}
      end
    end

    def apply(match, seat, value)
      round = match.round
      choice = round&.bids(seat)&.find { |candidate| candidate.to_s == value }
      !!(choice && match.bid(seat, choice))
    end
  end
end
