module GameRoomGames
  module FrenchTarotTrick
    module_function

    def legal(hand, trick)
      lead = trick.find { |suit, _| suit != :excuse }&.first
      return hand.dup unless lead
      excuse = hand.select { |suit, _| suit == :excuse }
      following = hand.select { |suit, _| suit == lead }
      return following + excuse if lead != :trump && !following.empty?

      trumps = hand.select { |suit, _| suit == :trump }
      return hand.dup if trumps.empty?
      highest = trick.filter_map { |suit, rank| rank if suit == :trump }.max
      higher = highest ? trumps.select { |_, rank| rank > highest } : trumps
      (higher.empty? ? trumps : higher) + excuse
    end

    def winner(trick)
      lead = trick.find { |suit, _| suit != :excuse }&.first
      return unless lead
      trick.each_index.reject { |i| trick[i].first == :excuse }.max_by do |i|
        suit, rank = trick[i]
        [suit == :trump ? 2 : suit == lead ? 1 : 0, rank]
      end
    end

    def distribute(trick, units:, winner:, last:)
      piles, debt = [[], []], [0, 0]
      taking = units.fetch(winner)
      trick.each do |owner, card|
        side = units.fetch(owner)
        if card.first == :excuse && !last && side != taking
          piles[side] << card
          debt[side] += 1
        else
          piles[taking] << card
        end
      end
      [piles, debt]
    end
  end
end
