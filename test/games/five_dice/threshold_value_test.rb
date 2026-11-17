require_relative '../../support/cat_head_tail'
require_relative '../../../games/balut'

game = GameRoomGames::Balut.new
sheet = GameRoomGames::BalutScoring::CATEGORIES.to_h { |category|[category,[]] }
sheet[:fours] = [4,8,12]
before = Marshal.dump(sheet)
points = game.send(:bot_progress,sheet)
filled = sheet.merge(fours:[4,8,12,16])
assert(game.send(:bot_progress,filled)==points,
  'Filling an unreachable numeric threshold manufactures category progress')
assert(game.send(:bot_category_value,sheet,:fours,[4,4,4,4,5])==3,
  'Unreachable bonus progress is awarded, or future raw-score opportunity cost was removed')
assert(Marshal.dump(sheet)==before,'Threshold valuation mutates the actual score sheet')

sheet[:straight] = [0]
assert(game.send(:bot_progress,sheet)==game.send(:bot_progress,sheet.merge(straight:[0,15])),
  'A broken straight bonus retains fictitious progress')
sheet[:full_house] = [0]
assert(game.send(:bot_progress,sheet)==game.send(:bot_progress,sheet.merge(full_house:[0,18])),
  'A broken full-house bonus retains fictitious progress')

sheet[:fours] = [16,16,0]
assert(GameRoomGames::BalutScoring.row_points_possible?(:fours,sheet[:fours]),
  'Reachable threshold fixture was damaged')
assert(game.send(:bot_progress,sheet.merge(fours:[16,16,0,20]))>
  game.send(:bot_progress,sheet), 'A reachable exact threshold loses its real bonus')
sheet[:fours] = [16,16,20]
assert(game.send(:bot_progress,sheet.merge(fours:[16,16,20,0]))==game.send(:bot_progress,sheet),
  'A secured numeric bonus disappears when its last result is zero')

yahtzee = GameRoomGames::Yahtzee.new
assert(yahtzee.send(:bot_upper_bonus_probability,[0,1],16).zero?,
  'Impossible upper bonus is valued above its physical maximum')
assert(yahtzee.send(:bot_upper_bonus_probability,[0,1],0)==1,
  'An already secured upper bonus is not recognized')
64.times do |mask|
  faces = 6.times.select { |i|(mask & (1<<i)).positive? }
  maximum = faces.sum { |i|(i+1)*5 }
  assert(yahtzee.send(:bot_upper_bonus_probability,faces,maximum+1).zero?,
    'A future upper box can contribute beyond five matching dice')
end
puts 'PASS Balut impossible/secured/exact thresholds, retained raw-score opportunity, and Yahtzee upper bounds'
