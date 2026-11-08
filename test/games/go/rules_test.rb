require_relative '../../../games/go'
require_relative '../../support/dice_games'
require_relative '../../../lib/game_simulation'
include DiceGamesSupport

engine = GameRoomGoPosition
board = [nil, 1, nil, 1, nil, 1, nil, 1, nil]
check(engine.place(board, 4, 0, 3, {}).nil?, 'Suicide accepted')
capture = [nil, 0, nil, 0, 1, 0, nil, nil, nil]
placed = engine.place(capture, 7, 0, 3, {})
check(placed.last == [4] && placed.first[4].nil?, 'Capture not removed before suicide check')
board = Array.new(25)
[[1,2],[2,1],[3,2]].each { |x,y| board[y*5+x]=0 }
[[2,2],[1,3],[3,3],[2,4]].each { |x,y| board[y*5+x]=1 }
after, removed = engine.place(board, 17, 0, 5, {engine.key(board)=>true})
check(removed == [12], 'Ko capture failed')
check(engine.place(after,12,1,5,{engine.key(board)=>true,engine.key(after)=>true}).nil?, 'Ko recapture accepted')
check(board[12] == 1 && board[17].nil?, 'Placement mutated parent')

state = {options:{'size'=>'3','variant'=>'territory','komi'=>'0'},stones:[0,0,0,0,nil,0,0,0,0],dead:[],neutral:[],captures:[2,1]}
check(engine.score(state)==[6,2], 'Territory/prisoners score')
state[:neutral]=[4]
check(engine.score(state)==[4,2], 'Seki counted as territory')
state[:options]['variant']='area'
check(engine.score(state)==[16,0], 'Area counted prisoners or neutral region')

game, repo = GameRoomGames::Go.new, DiceGamesSupport::Repository.new(%w[Alice Bob])
session = dice_session(game, komi:'0')
events = [dice_event(1,'Alice','place','0'),dice_event(2,'Bob','place','80'),dice_event(3,'Alice','pass',''),dice_event(4,'Bob','pass','')]
replay = game.replay(session,events,repo)
check(replay.state[:phase]==:scoring && replay.current_player=='Alice','Two passes did not enter scoring')
events << dice_event(5,'Alice','accept','') << dice_event(6,'Bob','mark','0')
replay = game.replay(session,events,repo)
check(replay.state[:approved].empty? && replay.state[:dead]==[0], 'Mark did not reset approvals')
events << dice_event(7,'Alice','resume','')
replay = game.replay(session,events,repo)
check(replay.state[:phase]==:playing && replay.state[:stones][0]==0 && replay.state[:dead].empty?, 'Resume removed live stones')
events << dice_event(8,'Bob','pass','') << dice_event(9,'Alice','pass','') << dice_event(10,'Bob','accept','') << dice_event(11,'Alice','accept','')
replay = game.replay(session,events,repo)
check(replay.finished? && replay.draw && replay.state[:scores]==[2,2], 'Mutual score agreement failed')
check(replay.history.any? { |entry| entry.kind==:score && entry.text.include?('Black 1.0; White 1.0') },'Agreed score not announced in history')
check(game.replay(session,events+[events.last],repo)==replay,'Duplicate changed Go result')
check(game.action_for({'kind'=>'grid','action'=>'select','x'=>-1,'y'=>0},game.replay(session,[],repo),'Alice').first==:invalid,'Bad grid coordinate accepted')
check(game.replay(session,[dice_event(1,'Bob','place','0')],repo).accepted_events.empty?,'Wrong actor accepted')

atari = dice_session(game,variant:'atari')
events = [[0,0],[1,0],[1,1],[8,8],[2,0]].each_with_index.map { |(x,y),i| dice_event(i+1,repo.players[i%2],'place',(y*9+x).to_s) }
result = game.replay(atari,events,repo)
check(result.winner=='Alice' && result.state[:captures][0]==1,'First capture did not win Atari Go')
check(result.history.any? { |entry| entry.kind==:capture && entry.text.include?('1 stones') },'Capture count not announced')

env = GameRoomSimulation::Environment.new_game(game:game,players:%w[bot:1:1:pl01 bot:1:2:pl02],options:{'size'=>'9','komi'=>'7.5','bot_delay'=>0},seed:11)
coordinator = GameRoomBots::Coordinator.new
350.times do
  break if env.finished?
  decision = coordinator.decide_next(game:game,replay:env.replay,context:env.context,strategy:game.bot_strategy)
  check(decision && env.step(decision.action,actor:decision.actor)==:ok,'Go bot failed')
end
check(env.finished? && env.replay==game.replay(env.session,env.events,env.repository),'Go bot match/replay diverged')
puts 'Go: capture, suicide, ko, territory/area/seki, agreement, resume, Atari and complete bot match passed.'
