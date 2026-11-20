require_relative '../../support/new_board_games'
game = GameRoomGames::Chess.new
env = GameRoomSimulation::Environment.new_game(game:game,players:%w[Alice Bob])
random,checks = Random.new(1729),0
36.times do
  break if env.finished?
  before = Marshal.dump(env.replay)
  env.legal_actions.each do |action|
    normal,fast = env.fork,env.fork_for_search
    assert(normal.step(action)==fast.step_for_search(action),'Chess fast status differs from ordinary play')
    assert(normal.replay.state==fast.replay.state,'Chess fast transition differs from production state')
    assert(game.bot_tactical_actions(normal.replay)==game.bot_tactical_actions(fast.replay),'Fast branch lost the last recapture target') unless fast.finished?
    checks += 1
  end
  assert(Marshal.dump(env.replay)==before,'Chess search mutated its parent')
  actions = env.legal_actions
  env.step(actions[random.rand(actions.size)])
end
repository,session = NewGamesRepository.new(%w[Alice Bob]),{'options'=>'{}'}
boards = []
castle = Array.new(8) { Array.new(8) }
castle[0][4],castle[0][0],castle[0][7],castle[7][4] = 'wK','wR','wR','bK'
boards << {board:castle,castling:'KQ',en_passant:nil}
ep = Array.new(8) { Array.new(8) }
ep[0][4],ep[7][4],ep[4][4],ep[4][3] = 'wK','bK','wP','bP'
boards << {board:ep,castling:'',en_passant:[3,5]}
promotion = Array.new(8) { Array.new(8) }
promotion[0][4],promotion[7][4],promotion[6][0] = 'wK','bK','wP'
boards << {board:promotion,castling:'',en_passant:nil}
boards.each do |fields|
  state = game.send(:initial_state,%w[Alice Bob]).merge(fields)
  queue = [GameRoomGames::Replay.new(board:state[:board],players:state[:players],current_player:'Alice',state:state,
    history:[],accepted_events:[],winner:nil,draw:false)]
  until queue.empty?
    replay = queue.shift
    game.legal_actions(replay,'Alice').each do |action|
      status,plan = game.action_for(action,replay,'Alice')
      command = plan.events.first
      event = {'id'=>checks+1,'actor'=>'Alice','action'=>command.action,'value'=>command.value}
      normal = game.incremental_replay(replay,session,[event],repository)
      fast_status,fast = game.bot_search_transition(replay,action,'Alice',event_id:checks+1)
      assert(status==fast_status && normal.state==fast.state,'Castling, en passant or promotion differs')
      queue << fast if fast.state[:pending_promotion]
      checks += 1
    end
  end
end
puts "PASS Chess #{checks} production/fast transitions, parent isolation, recaptures, castling, en passant and every promotion"
