module GameRoomGames
  module BackgammonRules
    module_function

    START = {24 => 2, 13 => 5, 8 => 3, 6 => 5}.freeze
    NACK = {24 => 2, 23 => 2, 13 => 4, 8 => 3, 6 => 4}.freeze
    HYPER = {24 => 1, 23 => 1, 22 => 1}.freeze
    def initial(variant = "classic")
      Array.new(2) { {"nack" => NACK, "hyper" => HYPER, "long" => {24 => 15}}.fetch(variant, START).dup }
    end

    # Each player's points are numbered in their own direction, from 24 to 1.
    # Point 25 is the bar and point 0 holds checkers already borne off.
    def moves(board, player, die, point_limit: nil)
      own, other = board.values_at(player, 1 - player)
      origins = own.fetch(25, 0).positive? ? [25] : own.keys.select { |point| point > 0 && own[point] > 0 }
      home = origins.all? { |point| point <= 6 }
      origins.filter_map do |from|
        to = from - die
        if to <= 0
          next unless home && (to.zero? || from == origins.max)
          to = 0
        else
          next if point_limit && own.fetch(to, 0) >= point_limit
          next if other.fetch(25 - to, 0) >= 2
        end
        [from, to, die]
      end
    end

    def apply(board, player, move)
      from, to, = move
      result = board.map(&:dup)
      own, other = result.values_at(player, 1 - player)
      own[from] -= 1
      own.delete(from) if own[from].zero?
      own[to] = own.fetch(to, 0) + 1
      if to.positive? && other.fetch(25 - to, 0) == 1
        other.delete(25 - to)
        other[25] = other.fetch(25, 0) + 1
      end
      result
    end

    def continuation(board, player, dice, cache, point_limit)
      return 0 if dice.empty?
      key = [board, dice]
      return cache[key] if cache.key?(key)
      best = 0
      dice.uniq.each do |die|
        remaining = dice.dup
        remaining.delete_at(remaining.index(die))
        moves(board, player, die, point_limit: point_limit).each do |move|
          best = [best, 1 + continuation(apply(board, player, move), player, remaining, cache, point_limit)].max
          return cache[key] = best if best == dice.size
        end
      end
      cache[key] = best
    end

    def legal(board, player, dice, point_limit: nil)
      cache = {}
      ranked = dice.uniq.flat_map do |die|
        remaining = dice.dup
        remaining.delete_at(remaining.index(die))
        moves(board, player, die, point_limit: point_limit).map do |move|
          [move, 1 + continuation(apply(board, player, move), player, remaining, cache, point_limit)]
        end
      end
      maximum = ranked.map(&:last).max
      choices = ranked.select { |_, length| length == maximum }.map(&:first)
      return choices unless maximum == 1 && dice.length == 2
      highest = choices.map(&:last).max
      choices.select { |move| move.last == highest }
    end

    def stake(board, winner)
      loser = board.fetch(1 - winner)
      return 1 if loser.fetch(0, 0).positive?
      loser.keys.any? { |point| point >= 19 && loser[point].positive? } ? 3 : 2
    end
  end
end
