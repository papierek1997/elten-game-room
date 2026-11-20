require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'

def school_model(category: 1, slots: 1, reserve: 0, flexible: 0, bonus: 100)
  model = GameRoomGames::FiveDiceMatch.new(%w[Alice Bob], columns: 3)
  sheet = model.instance_variable_get(:@sheets)['Alice']
  sheet.each_key { |key|sheet[key] = Array.new(3, key.is_a?(Integer) ? key * 3 : 20) }
  sheet[category] = Array.new(3 - slots, category * 3)
  sheet[:chance] = Array.new(3 - flexible, 20)
  model.instance_variable_get(:@reserves)['Alice'][category] = reserve
  model.instance_variable_get(:@bonuses)['Alice'][[:row, :pair]] = bonus
  model
end

weights = GameRoomFiveDicePlanner::TARGET_COUNTS
assert((weights.sum - 1).abs < 1e-12, 'Conditional dice distribution is not normalized')
probability = 1.0 - (5.0 / 6)**3
independent = (3..5).sum do |count|
  [1,5,10,10,5,1][count] * probability**count * (1-probability)**(5-count)
end
model = school_model
before = Marshal.dump(model)
estimate = GameRoomGames::GeneralSchoolStrategy.new(model, 'Alice')
assert((estimate.value(1,0,0) - 100 * (1-independent)).abs < 1e-10,
  'Securing the final school entry ignores the actual protected-bonus probability')
assert(estimate.value(1,2,0) == estimate.value(1,0,0), 'Terminal reserve is rewarded')
assert(Marshal.dump(model)==before, 'School estimate mutates the actual model')

model = school_model(flexible:1)
estimate = GameRoomGames::GeneralSchoolStrategy.new(model, 'Alice')
assert((estimate.value(:chance,0,0) + 100 * independent * (1-independent)).abs < 1e-10,
  'Consuming a flexible box does not price the lost school retry')

model = school_model(category:4,reserve:1,bonus:0)
estimate = GameRoomGames::GeneralSchoolStrategy.new(model, 'Alice')
assert(estimate.value(4,-1,0).zero?, 'Spending unusable terminal reserve is penalized')
model = school_model(category:4,slots:2,reserve:2,bonus:0)
estimate = GameRoomGames::GeneralSchoolStrategy.new(model, 'Alice')
assert(estimate.value(4,2,0).zero?, 'Reserve beyond the remaining usable capacity is rewarded')

game = GameRoomGames::Kosciane.new
model = school_model(category:4,bonus:0)
assert(model.roll('Alice',(0...5).to_a,[4,4,4,4,6]), 'Legal fixture roll failed')
assert(game.send(:category_value,model,4,model.dice,1)-model.preview_bonus(4,16)==4,
  'Production category valuation still gives points for terminal reserve')
assert(game.send(:category_value,model,4,model.dice,1)==
  GameRoomGames::Kosciane.new.send(:category_value,model,4,model.dice,1), 'Warm estimate differs from cold')

# Public prefix of the reviewed real game, with neutral account labels. Every
# final roll and score goes through the production model, including claims.
prefix = [
  [3,[2,3,3,5,5],:two_pairs],[1,[1,3,4,5,6],:small_straight],
  [1,[3,3,4,4,5],:two_pairs],[1,[1,3,5,6,6],:chance],
  [1,[2,3,4,5,5],:small_straight],[1,[1,2,4,5,6],:chance],
  [3,[1,3,4,4,4],4],[1,[2,3,3,4,6],:chance],
  [3,[3,3,4,4,6],:chance],[1,[1,1,2,4,4],:pair],
  [3,[4,5,6,6,6],6],[1,[1,3,4,4,5],:pair],
  [3,[1,3,5,5,5],5],[1,[1,1,2,3,4],:small_straight],
  [1,[2,3,4,5,6],:large_straight],[3,[3,3,4,5,6],:small_straight],
  [3,[1,3,3,5,6],:chance]
]
model = GameRoomGames::FiveDiceMatch.new(%w[Alice Bob],columns:3,double_first:true)
prefix.each do |rolls,dice,category|
  actor = model.current_player
  rolls.times { assert(model.roll(actor,(0...5).to_a,dice),'Recorded roll prefix refused') }
  assert(model.record(actor,category),'Recorded score prefix refused')
end
assert(model.bonuses('Bob').values.sum==54,'Recorded public bonus prefix differs')
assert(model.roll('Bob',(0...5).to_a,[1,1,1,3,5]),'Reviewed own dice refused')
state = {players:%w[Alice Bob],current_player:'Bob',match_model:model,dice:model.dice,turn_rolls:1,
  options:game.normalize_options('columns'=>3,'double_first'=>true)}
replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Bob',state:state)
choice = game.bot_strategy.choose(actions:game.legal_actions(replay,'Bob'),actor:'Bob',game:game,replay:replay,
  random_source:GameRoomRandom::SeededSource.new(17))
rerolled = choice.fetch('die_ids').split(',').map { |id|id.delete_prefix('d').to_i }
assert(choice['action']=='roll' && state[:dice].each_with_index.filter_map { |face,i|face unless rerolled.include?(i) }==[1,1,1],
  'The reviewed early triple is still discarded for one high die')
puts 'PASS school survival, finite flexible retries, terminal/capped reserve, owned state and production valuation'
