require_relative '../../support/dealt_card_games'
include GameRoomTest::Assertions

table = GameRoomTest::DealtCardTable.new('scopa')
game = table.game
state = table.state
own = %w[AC 3C]
peer = %w[3D 9H]
remaining = GameRoomGames::Scopa::DECK - own - peer - ['2H']
state.update(hands: {'Alice' => own, 'Bob' => peer}, table: ['2H'], stock: [], discarded: [],
  current_player: 'Alice', last_capturer: 'Bob',
  taken: {'Alice' => remaining.take(17), 'Bob' => remaining.drop(17)}, scopas: {'Alice' => 0, 'Bob' => 0})
table.replay.current_player = 'Alice'

actions = game.legal_actions(table.replay, 'Alice')
observation = game.bot_observation(table.replay, 'Alice')
before = Marshal.dump(observation)
chosen = game.bot_strategy.choose(actions: actions, observation: observation)
assert_equal('3C', chosen.fetch('card'), 'Do not drop the ace and hand the opponent a sweep')
assert_equal(before, Marshal.dump(observation), 'Search must not alter the position')

# Only the public count can be read. Opponent cards and hidden stock values
# aren't needed to find the safer play, even when the endgame is deducible.
state[:hands]['Bob'] = Struct.new(:size).new(2)
masked = game.bot_observation(table.replay, 'Alice')
assert_equal(observation, masked)
assert_equal(chosen, game.bot_strategy.choose(actions: actions, observation: masked))

# The same public board and stock size must yield identical decisions even
# when the remaining deal and the opponent's cards differ.
table = GameRoomTest::DealtCardTable.new('scopa', count: 4, options: {'team_size' => 2, 'escoba' => true, 'muerto' => true})
game, state, actor = table.game, table.state, table.state[:current_player]
options = game.legal_actions(table.replay, actor)
view = game.bot_observation(table.replay, actor)
choice = game.bot_strategy.choose(actions: options, observation: view)
other = (state[:players] - [actor]).first
state[:hands][other][0], state[:stock][0] = state[:stock][0], state[:hands][other][0]
masked = game.bot_observation(table.replay, actor)
assert_equal(view, masked)
assert_equal(choice, game.bot_strategy.choose(actions: options, observation: masked))
assert(options.include?(choice), 'Planner must return a legal card')
puts 'PASS Scopa: avoid a deducible sweep and plan Escoba/Muerto with public information only'
