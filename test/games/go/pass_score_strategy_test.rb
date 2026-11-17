require_relative '../../support/binary_rule_dictionary'

game = GameRoomGames::Go.new
env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob],
  options: {'variant'=>'area', 'size'=>'9', 'komi'=>'7.5'})
holes = [[2,1],[6,1],[2,7],[6,7],[4,4],[4,3]]
black = (0..4).flat_map { |y| (0..8).map { |x| [x,y] } } - holes
white = (5..8).flat_map { |y| (0..8).map { |x| [x,y] } } - holes
until black.empty?
  x,y = black.shift
  raise 'Black prefix rejected' unless env.step({'kind'=>'grid','action'=>'select','x'=>x,'y'=>y}, actor:'Alice') == :ok
  action = if white.empty?
    {'kind'=>'command','action'=>'pass'}
  else
    x,y = white.shift
    {'kind'=>'grid','action'=>'select','x'=>x,'y'=>y}
  end
  raise 'White prefix rejected' unless env.step(action, actor:'Bob') == :ok
end
before = Marshal.dump(env.replay)
chosen = GameRoomBots.choose(game.bot_strategy, actions:env.legal_actions, actor:'Alice',
  random_source:GameRoomRandom::SeededSource.new(1), game:game, replay:env.replay, context:env.context)
raise 'Bot passes a lost score instead of claiming neutral area' unless chosen.values_at('x','y') == [4,4]
raise 'Scoring analysis mutates real replay' unless before == Marshal.dump(env.replay)
raise 'Chosen improvement rejected' unless env.step(chosen, actor:'Alice') == :ok
scores = GameRoomGoPosition.score(env.replay.state)
raise 'Claim did not turn score into a lead' unless scores[0] > scores[1]
puts 'PASS Go: legal losing-pass prefix, neutral-area improvement, nonmutation'
