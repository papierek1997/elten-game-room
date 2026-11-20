require_relative '../../support/new_games_fixture'
game = GameRoomGames::Poker.new
random = Random.new(20261118)
examples = [%w[AC AD AH KC KD KH 2C], %w[AC AD AH AS KC KD KH],
  %w[AC 2C 3C 4C 5C 6C 9H], %w[AC 2D 3H 4C 5S 6C 9H], %w[AC AD KC KD QC QD 2C]]
%w[full nine].each do |deck|
  cards = game.send(:poker_deck, game.normalize_options('deck'=>deck))
  [5,6,7].each do |size|
    1200.times { examples << GameRoomRandom.shuffle(cards, random:random).first(size) }
  end
end
examples.each do |cards|
  # The unchanged five-card evaluator is an independent exhaustive oracle.
  expected = cards.combination(5).map { |five| game.send(:five_card_rank, five) }.max
  actual = game.send(:hand_rank, cards)
  assert(actual == expected, "Fast rank changed #{cards}: #{actual} != #{expected}")
end
assert(game.send(:hand_rank, %w[AC KD]) == [0], 'Incomplete ranks changed')
puts "PASS #{examples.length} full/short-deck ranks against all five-card subsets, wheels, two trips and three pairs"
