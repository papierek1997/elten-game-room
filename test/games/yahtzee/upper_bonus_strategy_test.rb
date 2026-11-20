require_relative '../../support/cat_head_tail'
require_relative '../../../games/yahtzee'

def upper_choice(dice, upper_bonus: true)
  game = GameRoomGames::Yahtzee.new
  state = game.send(:initial_state,%w[Alice Bob],game.normalize_options('upper_bonus'=>upper_bonus))
  categories = game.send(:categories,state)
  state[:sheets]['Alice'] = (categories-%w[ones chance yahtzee]).to_h { |name|[name,0] }
  %w[twos threes fours fives sixes].each_with_index { |name,i|state[:sheets]['Alice'][name]=(i+2)*3 }
  state[:dice],state[:turn_rolls]=dice,1
  replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state)
  before = Marshal.dump(state)
  chosen = game.bot_strategy.choose(actions:game.legal_actions(replay,'Alice'),actor:'Alice',game:game,replay:replay,
    random_source:GameRoomRandom::SeededSource.new(19))
  raise 'Upper bonus planning mutates the actual score sheet' unless before==Marshal.dump(state)
  [chosen,dice]
end

choice,dice = upper_choice([1,1,1,5,6])
kept = if choice['action']=='roll'
  indices = choice.fetch('die_ids').split(',').map { |id|id.delete_prefix('d').to_i }
  dice.each_with_index.filter_map { |face,i|face unless indices.include?(i) }
end
assert(choice['category']=='ones' || kept==[1,1,1],
  'A currently secured 35-point bonus is thrown away for speculative lower-section points')

game = GameRoomGames::Yahtzee.new
state = game.send(:initial_state,%w[Alice Bob],game.normalize_options('upper_bonus'=>true))
state[:sheets]['Alice'] = %w[twos threes fours fives sixes].to_h { |name|[name,0] }
state[:sheets]['Alice']['sixes']=30
assert(game.send(:bot_upper_bonus_probability,[0],33).zero?, 'An unreachable school is treated as a recoverable bonus')

[["fours",[1,3,4,4,6]],["sixes",[1,3,4,6,6]]].each do |category,dice|
  game = GameRoomGames::Yahtzee.new
  state = game.send(:initial_state,%w[Alice Bob],game.normalize_options('upper_bonus'=>true))
  categories = game.send(:categories,state)
  state[:sheets]['Alice'] = (categories-[category,'yahtzee','full_house','large_straight']).to_h { |name|[name,0] }
  %w[twos threes fours fives sixes].each_with_index do |name,i|
    state[:sheets]['Alice'][name]=(i+2)*3 unless name==category
  end
  state[:dice],state[:turn_rolls]=dice,3
  replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state)
  before = Marshal.dump(state)
  choice = game.bot_strategy.choose(actions:game.legal_actions(replay,'Alice'),actor:'Alice',game:game,replay:replay,
    random_source:GameRoomRandom::SeededSource.new(19))
  assert(choice['category']!='fours' && choice['category']!='sixes',
    'A weak final upper result kills a reachable bonus instead of using a cheap retry box')
  assert(game.action_for(choice,replay,'Alice').first==:ok,'The preserving choice bypasses normal scoring validation')
  assert(before==Marshal.dump(state),'The preserving forecast changes the actual sheet')
end

model = GameRoomFiveDiceUpperBonus.new
success = GameRoomFiveDicePlanner::TARGET_COUNTS.drop(4).sum
assert((model.probability([3],15,0)-success).abs<1e-12,
  'The conditional last-box probability differs from independent dice counting')
assert((model.probability([3],15,1)-(1-(1-success)**2)).abs<1e-12,
  'One alternative box does not provide exactly one bounded retry')
assert(model.probability([3],21,10).zero?, 'Retries create points beyond the upper box maximum')
assert(model.probability([],0,10)==1 && model.probability([],1,10).zero?,
  'Finished upper-section boundaries are wrong')
assert(model.instance_variable_get(:@values).size==64*106*11,'Upper retry cache is not statically bounded')
owned = [3]
expected = model.probability(owned,15,2)
owned[0]=0
assert(model.probability([3],15,2)==expected,'Caller mutation changes an already computed upper probability')

game = GameRoomGames::Yahtzee.new
state = game.send(:initial_state,%w[Alice Bob],game.normalize_options('upper_bonus'=>false))
game.define_singleton_method(:bot_upper_bonus_delta) { |*|raise 'Disabled upper bonus still invokes its forecast' }
state[:dice],state[:turn_rolls]=[1,1,1,5,6],3
replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state)
game.legal_actions(replay,'Alice').each { |action|game.bot_action_score(replay,'Alice',action) }
puts 'PASS Yahtzee keeps the secured school triple and rejects a physically impossible upper bonus'
