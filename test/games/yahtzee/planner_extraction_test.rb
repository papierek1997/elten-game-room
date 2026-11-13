require_relative '../../support/new_games_fixture'

# An independent copy of the former recurrence is deliberately kept in the
# test only: extraction must preserve every legal-action score and RNG state.
class PreviousYahtzeePlanner
  def initialize(game, state, actor)
    @game, @state, @actor = game, state, actor
    @roll, @best = {}, {}
  end
  def roll(kept, rolls)
    key = [rolls, kept]
    return @roll[key] if @roll.key?(key)
    @roll[key] = if kept.size == 5
      best(kept, rolls - 1)
    else
      (1..6).sum { |value| roll((kept + [value]).sort, rolls) } / 6.0
    end
  end
  def best(dice, rolls)
    key = [rolls, dice]
    return @best[key] if @best.key?(key)
    simulated = @state.merge(dice:dice)
    score = @game.send(:available_scoring_categories, simulated, @actor).map do |category|
      @game.send(:bot_category_value, category, dice, simulated, @actor)
    end.max
    if rolls > 0
      subsets = [[]]
      dice.tally.each do |face, count|
        subsets = subsets.flat_map { |subset| (0..count).map { |number| subset + [face] * number } }
      end
      subsets.reject { |kept| kept.size == 5 }.each { |kept| score = [score, roll(kept, rolls)].max }
    end
    @best[key] = score
  end
end

repo = NewGames116Repository.new(%w[Alice Bob])
[[1,1,2,4,6], [2,2,2,3,3], [6,6,6,6,6]].each do |dice|
  [1,2].each do |rolls|
    game = GameRoomGames::Yahtzee.new
    session = {'options'=>JSON.generate(game.default_options)}
    replay = game.replay(session, [], repo)
    state = replay.state
    state[:dice], state[:turn_rolls] = dice, rolls
    state[:sheets]['Alice']['ones'] = 3
    before = Marshal.dump(state)
    previous = PreviousYahtzeePlanner.new(game,state,'Alice')
    game.legal_actions(replay,'Alice').select { |action| action['action']=='roll' }.each do |action|
      selected = action['die_ids'].split(',').map { |id| id.delete_prefix('d').to_i }
      kept = dice.each_with_index.filter_map { |value,index| value unless selected.include?(index) }.sort
      expected = previous.roll(kept,3-rolls)-0.0001
      actual = game.bot_action_score(replay,'Alice',action)
      assert((actual-expected).abs < 1e-10, "Extracted Yahtzee planner differs: #{dice}/#{rolls}/#{selected}")
    end
    assert(Marshal.dump(state)==before,'Planner mutated the actual position')
  end
end
puts 'PASS Yahtzee planner extraction: identical exhaustive values on six positions and no mutation'
