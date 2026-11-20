require_relative "../../../games/kosciane_support/five_dice_match"

def check(condition)
  raise "Unexpected match state" unless condition
end

def play(match, category, faces = [6] * 5)
  player = match.current_player
  check(match.roll(player, (0..4).to_a, faces))
  check(match.record(player, category))
end

match = GameRoomGames::FiveDiceMatch.new(%w[A B])
check(!match.roll("B", (0..4).to_a, [6] * 5))
check(!match.roll("A", [0], [6]))
3.times do
  play(match, 6)
  play(match, 6)
end
check(match.bonuses("A") == {[:row, 6] => 30})
check(match.bonuses("B").empty?)
check(match.reserve("A", 6) == 6)
check(match.roll("A", (0..4).to_a, [1, 1, 1, 1, 6]))
check(!match.record("A", 2, cross: true))
check(match.roll("A", [4], [2]))
check(match.roll("A", [4], [3]))
check(match.dice == [1, 1, 1, 1, 3])
check(!match.roll("A", [4], [4]))
check(match.record("A", 2, cross: true))
check(match.bonuses("A").empty?)

[1, 2, 3].each do |columns|
  game = GameRoomGames::FiveDiceMatch.new(%w[A B], columns: columns)
  straights = %i[small_straight large_straight]
  columns.times do
    game.categories.each do |category|
      faces = if straights.include?(category)
        [2, 3, 4, 5, 6]
      elsif %i[two_pairs full_house].include?(category)
        [6, 6, 6, 5, 5]
      else
        [category.is_a?(Integer) ? category : 6] * 5
      end
      2.times { play(game, category, faces) }
    end
  end
  check(game.current_player.nil?)
  check(game.bonuses("B").empty?)
  if columns == 3
    check(game.bonuses("A")[[:column, 0]] == 60)
    check(game.winners == ["A"])
  else
    check(game.bonuses("A").empty?)
    check(game.winners == %w[A B])
  end
end
puts "PASS Five Dice match"

