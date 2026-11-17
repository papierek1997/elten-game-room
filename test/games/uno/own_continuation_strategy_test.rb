require_relative '../../support/binary_rule_dictionary'

def replay_of(state)
  GameRoomGames::Replay.new(players:state[:players], current_player:state[:current_player], state:state,
    history:[],accepted_events:[],winner:state[:winner],draw:false)
end

game = GameRoomGames::Uno.new
env = GameRoomSimulation::Environment.new_game(game:game,players:%w[Alice Bob],seed:31)
state = GameRoomSnapshot.copy(env.replay.state)
hand, top = %w[B9a BSb RVb RSa], 'R1a'
deck = game.send(:uno_deck,state[:options]) - hand - [top]
state.merge!(hands:{'Alice'=>hand,'Bob'=>deck.shift(7)},draw_pile:deck,discard:[top],colour:'R',
  current_player:'Alice',direction:1,phase: :playing)
before = Marshal.dump(state)
replay = replay_of(state)
20.times do |seed|
  choice = game.bot_strategy.choose(actions:game.legal_actions(replay,'Alice'), actor:'Alice',game:game,replay:replay,
    random_source:GameRoomRandom::SeededSource.new(seed))
  raise 'Missed complete owned reverse/skip/skip/9 sequence' unless choice['card']=='RVb'
  raise 'Finisher work is unbounded' unless game.bot_strategy.last_stats[:nodes]<=256
  raise 'Normal executor refuses chosen card' unless game.action_for(choice,replay,'Alice',context:env.context).first==:ok
end
raise 'Analysis changed real position' unless before==Marshal.dump(state)

altered = GameRoomSnapshot.copy(state)
altered[:hands]['Bob'].reverse!
altered[:draw_pile].reverse!
altered[:seed] = 'f'*32
altered[:private_cards],altered[:private_viewer] = true,'Alice'
choice = game.bot_strategy.choose(actions:game.legal_actions(replay_of(altered),'Alice'),actor:'Alice',game:game,replay:replay_of(altered),
  random_source:GameRoomRandom::SeededSource.new(17))
raise 'Owned continuation leaked foreign cards, future deck or private-mode proof' unless choice['card']=='RVb'

[false,true].each do |super_interceptions|
  state[:options].merge!('interceptions'=>true,'super_interceptions'=>super_interceptions)
  state[:current_player], state[:discard], state[:colour] = 'Bob',['R9b'],'R'
  state[:hands]['Alice'] = %w[R9a B9a NW0]
  replay = replay_of(state)
  game.define_singleton_method(:bot_finishing_continuations) { |*_args| raise 'Reaction invoked slow planner' }
  choice = game.bot_strategy.choose(actions:game.legal_actions(replay,'Alice'),actor:'Alice',game:game,replay:replay,
    random_source:GameRoomRandom::SeededSource.new(17))
  raise 'Interception must use existing immediate heuristic' unless choice['interception'] && game.bot_strategy.last_stats[:fast_reaction]
  raise 'Interception model refuses chosen reaction' unless game.action_for(choice,replay,'Alice',context:env.context).first==:ok
end
puts 'PASS UNO: exact own finish, bounded work, legal executor, interception and super-interception never invoke planner'
