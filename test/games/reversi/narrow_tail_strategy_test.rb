require_relative '../../../games/reversi'
require_relative '../../../lib/game_simulation'
game = GameRoomGames::Reversi.new
cases = []
random = Random.new(1917)
200.times do
  env = GameRoomSimulation::Environment.new_game(game:game,players:%w[Alice Bob],options:{'allow_passing'=>false})
  until env.finished? || env.replay.board.flatten.count(nil)<=10
    actions = env.legal_actions
    env.step(actions[random.rand(actions.size)])
  end
  if !env.finished? && env.legal_actions.size.between?(2,3)
    cases << env
    break if cases.size==3
  end
end
raise 'No informative narrow ten-empty-square fixture' if cases.empty?
deeper = 0
cases.each do |env|
  actor = env.active_actor
  before = Marshal.dump(env.replay)
  choice = game.bot_strategy.choose(actions:env.legal_actions,actor:actor,
    random_source:GameRoomRandom::SeededSource.new(23),game:game,replay:env.replay,simulation:env)
  stats = game.bot_strategy.last_stats
  raise 'Adaptive tail changed the node ceiling' unless stats[:nodes]<=55_000
  deeper += 1 if stats[:completed_depth]>8
  raise 'Tail analysis mutated the actual board' unless Marshal.dump(env.replay)==before
  raise 'Chosen tail move was rejected' unless env.step(choice)==:ok
end
raise 'No narrow finite end completed beyond eight plies' if deeper.zero?
puts "PASS Reversi #{cases.size} narrow finite ten-square tails, #{deeper} completed deeper iterations, unchanged node ceiling and legal execution"
