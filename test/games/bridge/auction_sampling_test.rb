require_relative '../../support/bridge'
include GameRoomTest::Assertions
rules = GameRoomGames::BridgeRules
strong = %w[AS KH QD JC 9S 8S 7H 6H 5D 4D 3C 2C TC]
weak = %w[2S 3S 4S 2H 3H 4H 2D 3D 6D 4C 5C 6C 7C]
rest = rules::DECK - strong - weak
hands = [rest.first(13), strong, rest.last(13), weak]
view = {'seat' => 2, 'seat_to_play' => 2, 'hand' => hands[2], 'dummy' => nil, 'played' => [],
  'trick' => [], 'tricks_won' => [0, 0], 'phase' => 'playing',
  'calls' => [[1, '1N'], [2, 'P'], [3, 'P'], [0, 'P']], 'vulnerability' => 'none',
  'contract' => {'level' => 1, 'strain' => 'N', 'doubled' => 0, 'declarer' => 1}}
planner = GameRoomGames::BridgePlayPlanner.new(view)
encoded = hands.map { |hand| hand.map { |card| rules::DECK.index(card) } }
weight = planner.send(:auction_weight, encoded)
other = encoded.map(&:dup)
other[1], other[3] = other[3], other[1]
assert(weight > planner.send(:auction_weight, other), 'A 1NT opener was not more likely to hold a plausible hand')
assert(planner.send(:auction_weight, other).positive?, 'An unusual human opening became impossible')
worlds, exact = planner.send(:worlds_for)
assert(!exact && !worlds.empty? && worlds.size <= 5)
worlds.each do |world|
  assert_equal((0...52).to_a, world.hands.flatten.sort)
  assert_equal(encoded[2].sort, world.hands[2])
end
puts 'PASS soft auction ranges, plausible NT weighting, bounded common samples and preserved visible hand'
