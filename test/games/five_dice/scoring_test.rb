require_relative "../../../games/kosciane_support/five_dice_scoring"
rules = GameRoomGames::FiveDiceScoring
def check(expected, actual)
  raise "Expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end
hand = [5, 2, 5, 2, 5]
check [19, 0], rules.score(:full_house, hand)
check [14, 0], rules.score(:two_pairs, hand)
check [70, 0], rules.score(:full_house, hand, fixed: true, double_first: true)
check [35, 0], rules.score(:full_house, hand, fixed: true, double_first: true, rolls: 2)
check nil, rules.score(:full_house, [5] * 5)
check [18, 0], rules.score(:small_straight, [2, 3, 4, 5, 6])
check [20, 0], rules.score(:large_straight, [6, 4, 3, 5, 2])
check [24, 1], rules.score(6, [6, 6, 2, 6, 6], double_first: true)
check nil, rules.score(6, [6, 6, 1, 2, 3])
check [12, -1], rules.score(6, [6, 6, 1, 2, 3], reserve: 1)
check false, rules.categories.include?(:even)
check true, rules.categories(parity: true).include?(:even)
check [false, false, true], [1, 2, 3].map { |n| rules.bonuses_enabled?(n) }
puts "PASS Five Dice scoring"

