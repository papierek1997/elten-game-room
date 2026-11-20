require_relative 'backgammon_rules'
require_relative '../../lib/game_tree_search'

module GameRoomGames
  module BackgammonBot
    module_function

    def value(board, side)
      own, other = board.values_at(side, 1 - side)
      pips = ->(pieces) { pieces.sum { |point, count| point * count } }
      contact = own.keys.max.to_i + other.keys.max.to_i > 25
      result = (pips.call(other) - pips.call(own)) * 0.3
      result += 35 * (own.fetch(0, 0) - other.fetch(0, 0))
      return result unless contact

      [own, other].each_with_index do |pieces, index|
        made = (1..24).select { |point| pieces.fetch(point, 0) >= 2 }
        home = made.count { |point| point <= 6 }
        prime = (1..24).map { |point| (point..24).take_while { |next_point| made.include?(next_point) }.size }.max
        shape = home * 4 + prime**2 * 1.5 - pieces.fetch(25, 0) * 15
        shape -= 22 * blot_risk(board, index == 0 ? side : 1 - side)
        result += (index == 0 ? 1 : -1) * shape
      end
      result
    end

    def blot_risk(board, side)
      own, other = board.values_at(side, 1 - side)
      if [own,other].sum { |pieces|pieces.sum { |point,count|point.positive? ? count : 0 } } <= 4
        exact = reply_exposure(board,side)
        return exact unless exact.nil?
      end
      own.sum do |point, count|
        next 0.0 unless point.between?(1, 24) && count == 1
        origins = other.fetch(25, 0).positive? ? [25] : other.keys.select(&:positive?)
        faces = origins.map { |origin| origin + point - 25 }.select { |distance| distance.between?(1, 6) }.uniq.size
        1.0 - ((6 - faces) / 6.0)**2
      end
    end

    # Sparse contact tails can afford every real two-dice reply, including
    # composed hits and doubles. Large positions retain the cheap evaluator;
    # do not multiply this tree by every leaf of the 6,000-node own-turn plan.
    def reply_exposure(board, side)
      base = board[side].fetch(25,0)
      budget = GameRoomBots::SearchBudget.new(limit:2_000)
      memo = {}
      hits = lambda do |position,dice|
        key = [position,dice]
        return memo[key] if memo.key?(key)
        budget.visit!
        moves = BackgammonRules.legal(position,1-side,dice)
        return position[side].fetch(25,0)-base if moves.empty?
        memo[key] = moves.map do |move|
          rest = dice.dup
          rest.delete_at(rest.index(move.last))
          hits.call(BackgammonRules.apply(position,1-side,move),rest)
        end.max
      end
      (1..6).sum do |first|
        (1..6).sum { |second|hits.call(board,first==second ? [first]*4 : [first,second]) }
      end / 36.0
    rescue GameRoomBots::SearchBudget::Exhausted
      nil
    end

    class TurnPlan
      attr_reader :budget

      def initialize(board, side, dice, point_limit: nil)
        @side, @point_limit = side, point_limit
        @budget = GameRoomBots::SearchBudget.new(limit: 6_000)
        @memo = {}
        @scores = BackgammonRules.legal(board, side, dice, point_limit: point_limit).to_h do |move|
          [move, continuation(BackgammonRules.apply(board, side, move), remaining(dice, move.last))]
        end
      end

      def score(move)
        @scores.fetch(move)
      end

      private

      def remaining(dice, die)
        result = dice.dup
        result.delete_at(result.index(die))
        result
      end

      def continuation(board, dice)
        key = [board, dice]
        return @memo[key] if @memo.key?(key)
        moves = BackgammonRules.legal(board, @side, dice, point_limit: @point_limit)
        return @memo[key] = BackgammonBot.value(board, @side) if moves.empty?
        begin
          @budget.visit!
        rescue GameRoomBots::SearchBudget::Exhausted
          # Even the bounded fallback uses every legal remaining die. Never
          # compare an unfinished half-turn with another candidate's full turn.
          until moves.empty?
            move = moves.max_by { |candidate| BackgammonBot.value(BackgammonRules.apply(board, @side, candidate), @side) }
            board = BackgammonRules.apply(board, @side, move)
            dice = remaining(dice, move.last)
            moves = BackgammonRules.legal(board, @side, dice, point_limit: @point_limit)
          end
          return BackgammonBot.value(board, @side)
        end
        @memo[key] = moves.map do |move|
          continuation(BackgammonRules.apply(board, @side, move), remaining(dice, move.last))
        end.max
      end
    end
  end
end
