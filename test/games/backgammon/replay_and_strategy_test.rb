require_relative '../../support/private_simulation'
require_relative '../../support/model_contract'
require_relative '../../../games/backgammon'
include GameRoomTest::Assertions
game = GameRoomGames::Backgammon.new
env = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[Alice Bob],
  options: {'variant' => 'hyper', 'score_limit' => 3}, seed: 137)
400.times do
  warm = env.replay
  cold = GameRoomGames::Backgammon.new.replay(env.session, env.events, env.repository)
  assert_equal(GameRoomTest::ContractValues.canonical(cold), GameRoomTest::ContractValues.canonical(warm), 'Append cache changed a real match')
  assert_equal(env.events, warm.accepted_events)
  break if env.finished?
  actions = env.legal_actions
  chosen = actions.max_by { |action| game.bot_action_score(warm, env.active_actor, action) }
  assert_equal(:ok, env.step(chosen))
end
assert(env.finished?, 'Hypergammon match did not finish')
events = Marshal.load(Marshal.dump(env.events))
events.first['value'] = events.first['value'] == '1,2' ? '2,1' : '1,2'
warm = game.replay(env.session, events, env.repository)
cold = GameRoomGames::Backgammon.new.replay(env.session, events, env.repository)
assert_equal(GameRoomTest::ContractValues.canonical(cold), GameRoomTest::ContractValues.canonical(warm), 'Changed earlier roll reused a cached future')
assert_equal(1, GameRoomGames::BackgammonRules.stake([{0=>15}, {0=>1, 6=>14}], 0))
assert_equal(2, GameRoomGames::BackgammonRules.stake([{0=>15}, {6=>15}], 0))
assert_equal(3, GameRoomGames::BackgammonRules.stake([{0=>15}, {25=>1, 6=>14}], 0))
position = env.replay.dup
position.state = position.state.merge(turn: 0)
position.board = [{0=>14, 1=>1}, {24=>15}]
take = game.bot_action_score(position, 'Alice', {'action'=>'take'})
drop = game.bot_action_score(position, 'Alice', {'action'=>'drop'})
assert(take > drop, 'A nearly won race was conceded')
position.board = position.board.reverse
assert(game.bot_action_score(position, 'Alice', {'action'=>'drop'}) > game.bot_action_score(position, 'Alice', {'action'=>'take'}), 'A hopeless race was always accepted')
puts 'PASS complete match, cold/append/changed-prefix replay, stakes and public-board cube decisions'
