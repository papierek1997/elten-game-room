require_relative '../../support/cat_head_tail'
require_relative '../../../games/balut'
require_relative '../../../games/kosciane'

planner = GameRoomFiveDicePlanner.new { |dice, _rolls| dice.count(4).to_f }
kept = [4, 4, 4, 4]
assert((planner.roll_value(kept, 1) - (4 + 1.0 / 6)).abs < 1e-10, 'One-roll expectation differs from independent probability')
assert((planner.roll_value(kept, 2) - (4 + 1 - (5.0 / 6)**2)).abs < 1e-10, 'Remaining-roll look-ahead is incorrect')
assert(kept == [4, 4, 4, 4], 'Planner mutated the kept dice')

players = %w[Alice Bob]
sheet = GameRoomGames::BalutScoring::CATEGORIES.to_h { |category| [category, [0, 0, 0, 0]] }
sheet[:fours] = [16, 16, 16]
state = {players: players, current_player: 'Alice', turn_rolls: 2, dice: [1, 1, 1, 1, 1],
  sheets: {'Alice' => sheet, 'Bob' => sheet.transform_values { [0, 0, 0, 0] }}}
balut = GameRoomGames::Balut.new
replay = GameRoomGames::Replay.new(players: players, current_player: 'Alice', state: state)
random = GameRoomRandom::LocalSecureSource.new
choose = lambda do |game, position|
  game.bot_strategy.choose(actions: game.legal_actions(position, 'Alice'), actor: 'Alice',
    game: game, replay: position, random_source: random)
end
choice = choose.call(balut, replay)
assert(choice['action'] == 'roll' && choice['die_ids'].split(',').size == 5,
  'Balut kept useless ones when the final open category requires a four')
state[:dice] = [4, 4, 4, 4, 4]
choice = choose.call(balut, replay)
assert(choice['action'] == 'score' && choice['category'] == 'fours', 'Balut rerolled an already secured final bonus')
state[:dice] = [1, 1, 1, 1, 1]
state[:sheets]['Bob'][:balut] = [50, 50, 50, 50]
assert(choose.call(balut, replay)['die_ids'].split(',').size == 5, 'Unrelated opponent dice changed the own-sheet tactic')

game = GameRoomGames::Kosciane.new
match = GameRoomGames::FiveDiceMatch.new(players, columns: 1)
sheet = match.instance_variable_get(:@sheets).fetch('Alice')
sheet.each_key { |category| sheet[category] = category == :full_house ? [] : [:cross] }
2.times { assert(match.roll('Alice', (0...5).to_a, [2, 2, 2, 3, 4]), 'Tactical roll setup failed') }
state = {players: players, current_player: 'Alice', match_model: match, turn_rolls: 2,
  dice: match.dice, options: game.default_options.merge('columns' => 1)}
replay = GameRoomGames::Replay.new(players: players, current_player: 'Alice', state: state)
choice = choose.call(game, replay)
assert(choice['action'] == 'roll' && choice['die_ids'] == 'd3',
  'Dice General did not keep the triple and higher pair candidate for its sole open full house')
assert(game.action_for(choice, replay, 'Alice', context: Struct.new(:random_source, :server_random).new(random, false)).first == :ok,
  'Planned tactic bypasses the ordinary legal action path')
puts 'PASS exact dice probabilities, remaining rolls, slot-aware tactics, secure scoring and public-information decisions'
