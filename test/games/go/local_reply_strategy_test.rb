require_relative '../../../games/go'
game = GameRoomGames::Go.new
state = {players:%w[Alice Bob],current_player:'Alice',options:game.normalize_options('size'=>'9'),
  stones:Array.new(81),seen:{},captures:[0,0],passes:0,moves:12,phase: :playing,dead:[],neutral:[]}
state[:stones][10] = 0
[1,9,2,12,20].each { |p|state[:stones][p]=1 }
# Placing at 11 joins a two-stone group with one liberty at 19. White's
# legal immediate reply captures both; the old flat atari cost was only 20.
action = {'kind'=>'grid','action'=>'place','x'=>2,'y'=>1}
state[:seen][GameRoomGoPosition.key(state[:stones])] = true
replay = GameRoomGames::Replay.new(players:state[:players],current_player:'Alice',state:state,history:[],accepted_events:[])
before = Marshal.dump(state)
value = game.bot_action_score(replay,'Alice',action)
raise 'New connected group capture is still priced as one stone' unless value < -200
raise 'Reply check mutated the board or superko history' unless Marshal.dump(state)==before
puts 'PASS Go legal immediate group reply, multi-stone risk and immutable superko history'
