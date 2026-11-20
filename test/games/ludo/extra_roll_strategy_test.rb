require_relative '../../support/new_board_games'
game = GameRoomGames::Ludo.new
state = game.send(:initial_state,%w[Alice Bob],game.default_options)
state.update(phase: :moving,roll:6,consecutive_sixes:1,pawns:[[0,51,-1,57],[4,18,35,57]])
replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state,history:[],accepted_events:[])
before = Marshal.dump(state)
actions = game.legal_actions(replay,'Alice')
actions.each do |action|
  pawn = action['pawn'].to_i
  base = game.send(:bot_pawn_score,state,0,pawn)
  value = game.bot_action_score(replay,'Alice',action)
  raise 'Guaranteed extra roll was not valued' unless value>base
end
state[:options]['extra_on_six']=false
actions.each do |action|
  raise 'Disabled extra roll was still simulated' unless game.bot_action_score(replay,'Alice',action)==game.send(:bot_pawn_score,state,0,action['pawn'].to_i)
end
state[:options]['extra_on_six']=true
raise 'Owned planning mutated pawns or public options' unless Marshal.dump(state)==before
puts 'PASS Ludo extra-six expectation from legal own continuations, variant gate and nonmutation'
