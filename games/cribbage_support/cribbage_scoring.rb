module GameRoomGames
  module CribbageScoring
    module_function

    # Cards are [rank 1..13, suit]; the starter is separate.
    def hand(cards, starter, crib: false)
      all = cards + [starter]
      fifteens = (2..all.size).sum do |size|
        all.combination(size).count { |set| set.sum { |rank, _| [rank, 10].min } == 15 }
      end * 2
      pairs = all.combination(2).count { |a, b| a.first == b.first } * 2
      runs = 0
      all.size.downto(3) do |size|
        runs = size * all.combination(size).count { |set| run?(set.map(&:first)) }
        break if runs.positive?
      end
      flush = if cards.map(&:last).uniq.one?
        cards.first.last == starter.last ? all.size : crib ? 0 : cards.size
      else
        0
      end
      nobs = cards.any? { |rank, suit| rank == 11 && suit == starter.last } ? 1 : 0
      fifteens + pairs + runs + flush + nobs
    end

    def pegging(ranks)
      total = ranks.sum { |rank| [rank, 10].min }
      return nil if total > 31
      same = ranks.reverse.take_while { |rank| rank == ranks.last }.length
      longest = ranks.size.downto(3).find { |size| run?(ranks.last(size)) }
      (total == 15 || total == 31 ? 2 : 0) + same * (same - 1) + (longest || 0)
    end

    def run?(ranks)
      ranks.sort.each_cons(2).all? { |a, b| b == a + 1 }
    end
  end
end
