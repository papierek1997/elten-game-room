require_relative '../../support/binary_rule_dictionary'

def choose(game,state)
  replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state,history:[],accepted_events:[])
  before = Marshal.dump(state)
  action = game.bot_strategy.choose(actions:game.legal_actions(replay,'Alice'),actor:'Alice',game:game,replay:replay,
    random_source:GameRoomRandom::SeededSource.new(17))
  raise 'Planning mutates live sheet/model' unless Marshal.dump(state)==before
  raise 'Chosen score bypasses normal validation' unless game.action_for(action,replay,'Alice').first==:ok
  action
end

v = GameRoomBots::ExpectedValue
raise 'Zero-outcome chance branch lost points' unless (v.new(0,4)+v.new(0,6)).points==10
raise 'Expected outcome is not primary' unless v.new(0.01,0)>v.new(0,100000)
raise 'Expected points do not break an outcome tie' unless v.new(-1,20)>v.new(-1,6)
raise 'Chance averaging lost the tie breaker' unless [v.new(0,4),v.new(0,6)].sum/2==v.new(0,5)

y = GameRoomGames::Yahtzee.new
state = y.send(:initial_state,%w[Alice Bob],y.normalize_options('upper_bonus'=>false))
state[:sheets]['Alice'] = (y.send(:categories,state)-%w[large_straight chance]).to_h { |c|[c,0] }
state[:dice],state[:turn_rolls] = [4,4,4,4,4],3
raise 'Yahtzee still consumes Chance instead of forty-point straight' unless choose(y,state)['category']=='large_straight'

b = GameRoomGames::Balut.new
sheet = {fours:[4,8,12,16],fives:[5,10,15,20],sixes:[6,12,18,24],straight:[15,15,20,20],
  full_house:[18,21,24,27],balut:[0,50,0],choice:[20,22,24]}
opponent = sheet.merge(balut:[50,0,0,0],choice:[15,18,21,24])
state = {players:%w[Alice Bob],current_player:'Alice',turn_rolls:3,dice:[1,1,1,1,2],sheets:{'Alice'=>sheet,'Bob'=>opponent}}
raise 'Balut still consumes easy Chance instead of zeroing rare Balut' unless choose(b,state)['category']=='balut'
tail = b.instance_variable_get(:@bot_tail)
evaluations = tail.future_evaluations
choose(b,state)
raise 'Unchanged sheet recomputes future rolls' unless tail.equal?(b.instance_variable_get(:@bot_tail)) && tail.future_evaluations==evaluations

g = GameRoomGames::Kosciane.new
model = GameRoomGames::FiveDiceMatch.new(%w[Alice Bob],columns:1)
sheets = model.instance_variable_get(:@sheets)
sheets.each { |p,rows|rows.each_key { |c|rows[c]=p=='Alice' && %i[poker chance].include?(c) ? [] : [:cross] } }
sheets['Bob'][:chance] = [20]
3.times { raise 'Legal dice prefix failed' unless model.roll('Alice',(0...5).to_a,[1,1,1,1,2]) }
state = {players:%w[Alice Bob],current_player:'Alice',match_model:model,dice:model.dice,turn_rolls:3,options:g.normalize_options('columns'=>1)}
raise 'General still spends Chance on six instead of preserving it' unless choose(g,state)['category']=='cross:poker'
puts 'PASS shared score tails: exact next turn, real three score models, match-first/points-second, no mutation and cache reuse'
