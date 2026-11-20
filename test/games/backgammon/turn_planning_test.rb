require_relative '../../../games/backgammon'
require_relative '../../support/assertions'
include GameRoomTest::Assertions
rules, bot = GameRoomGames::BackgammonRules, GameRoomGames::BackgammonBot

# Independent exhaustive legal-turn traversal with the production move rules.
best = lambda do |board, side, dice, limit|
  moves = rules.legal(board, side, dice, point_limit: limit)
  next bot.value(board, side) if moves.empty?
  moves.map do |move|
    rest = dice.dup
    rest.delete_at(rest.index(move.last))
    best.call(rules.apply(board, side, move), side, rest, limit)
  end.max
end
%w[classic hyper egyptian].each do |variant|
  board = rules.initial(variant)
  [0, 1].each do |side|
    [[1, 6], [3, 4], [2, 2, 2, 2]].each do |dice|
      before = Marshal.dump(board)
      limit = variant == 'egyptian' ? 5 : nil
      plan = bot::TurnPlan.new(board, side, dice, point_limit: limit)
      rules.legal(board, side, dice, point_limit: limit).each do |move|
        rest = dice.dup
        rest.delete_at(rest.index(move.last))
        assert_equal(best.call(rules.apply(board, side, move), side, rest, limit), plan.score(move))
      end
      assert_equal(before, Marshal.dump(board))
      assert(plan.budget.nodes <= plan.budget.limit)
    end
  end
end
puts 'PASS whole legal Backgammon turns, doubles, both seats, Egyptian limits and bounded work'
