require_relative '../support/assertions'
require_relative '../../games/tic_tac_toe'
require_relative '../../lib/local_game_presentation'
include GameRoomTest::Assertions

renderer = GameRoomLocalGamePresentation.new(GameRoomGames::TicTacToe.new, nil)
node = Data.define(:items)
left = node.new(items: {cards: %w[AC 2D], limits: Hash.new(0)})
right = node.new(items: {limits: Hash.new(0), cards: %w[AC 2D]})
assert(renderer.send(:same_value?, left, right), 'Value copies and hash insertion order changed a Data model')
assert(!renderer.send(:same_value?, left, node.new(items: {cards: %w[2D AC], limits: Hash.new(0)})), 'Array order was ignored')
assert(!renderer.send(:same_value?, left, node.new(items: {cards: %w[AC 2D], limits: {}})), 'Hash default behavior was ignored')
cycle_a, cycle_b = [], []
cycle_a << cycle_a
cycle_b << cycle_b
assert(renderer.send(:same_value?, cycle_a, cycle_b), 'Copied cycles caused unbounded recursion')
cycle_b << 1
assert(!renderer.send(:same_value?, cycle_a, cycle_b), 'A changed cyclic model was accepted')
puts 'PASS local model value comparison: Data fields, ordered cards, unordered hash insertion, default values and bounded cyclic comparison'
