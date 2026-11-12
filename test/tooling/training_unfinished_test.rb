require_relative '../../lib/game_bots'

def _(text)
  text
end

require_relative '../../tools/training/game_training'
require_relative '../../games/tic_tac_toe'

game = GameRoomGames::TicTacToe.new
competitors = {
  'first' => GameRoomBots::HeuristicStrategy.new,
  'second' => GameRoomBots::HeuristicStrategy.new
}
unfinished = GameRoomTraining::Tournament.new(
  game: game, competitors: competitors, max_actions: 1
).run(seeds: [1, 2])

raise 'fixture did not reach the real action limit' unless unfinished.results.all? do |entry|
  result = entry.fetch(:result)
  !result.finished? && !result.draw && result.reason == :action_limit && result.actions == 1
end
raise 'unfinished attempts counted as draws' unless unfinished.draws.zero?
raise 'unfinished attempts were not reported separately' unless unfinished.unfinished == 4
raise 'attempted matches disappeared' unless unfinished.matches == 4 && unfinished.results.size == 4
raise 'unfinished attempts awarded a win or changed Elo' unless unfinished.wins.empty? && unfinished.ratings.empty?

completed = GameRoomTraining::Tournament.new(
  game: game, competitors: competitors
).run(seeds: [1, 2])
raise 'complete-match fixture did not finish' unless completed.results.all? { |entry| entry.fetch(:result).finished? }
raise 'complete attempts marked unfinished' unless completed.unfinished.zero?
raise 'complete outcomes lost' unless completed.draws + completed.wins.values.sum == completed.matches
raise 'complete games stopped updating Elo' unless completed.ratings.keys.sort == competitors.keys.sort

policy = GameRoomTraining::PolicyTable.new
players = GameRoomParticipants.bots_for(1, game.minimum_players)
environment = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 918)
actor = environment.active_actor
state_key = game.bot_state_key(environment.replay, actor)
action_key = game.bot_action_key(environment.legal_actions(actor).first)
policy.update(state_key, action_key, 1.0)
before = Marshal.dump(policy.to_h)
report = GameRoomTraining::SelfPlayTrainer.new(game: game, players: players, policy: policy,
  epsilon: 0, max_actions: 1).train(episodes: 1, seed: 918)
raise 'self-play fixture did not hit its action limit' unless report.unfinished == 1
raise 'unfinished self-play changed learned values or visits' unless Marshal.dump(policy.to_h) == before

class EpisodeTrackingStrategy < GameRoomBots::LearnedStrategy
  attr_reader :finished_actors, :reset_actors
  def initialize(**options)
    super
    @finished_actors, @reset_actors = [], []
  end
  def finish_episode(actor, reward)
    @finished_actors << actor
    super
  end
  def reset_episode(actor = nil)
    @reset_actors << actor
    super
  end
end

# Reuse the same real learner across interrupted and completed matches. Only
# actual completed trajectories may update its policy; no previous choices leak.
learner = EpisodeTrackingStrategy.new(policy: policy, epsilon: 0)
limited = GameRoomSimulation::MatchRunner.new(game: game, players: players,
  default_strategy: learner, max_actions: 1).run(seed: 918)
raise 'action-limited learner was not reset' unless limited.reason == :action_limit &&
  learner.finished_actors.empty? && learner.reset_actors == players &&
  learner.instance_variable_get(:@trajectories).empty? && Marshal.dump(policy.to_h) == before
visits_before = policy.to_h.values.sum { |actions| actions.values.sum { |entry| entry.fetch('visits') } }
finished = GameRoomSimulation::MatchRunner.new(game: game, players: players,
  default_strategy: learner).run(seed: 918)
visits_after = policy.to_h.values.sum { |actions| actions.values.sum { |entry| entry.fetch('visits') } }
raise 'completed episode did not learn exactly its own accepted choices' unless finished.finished? &&
  learner.finished_actors == players && visits_after - visits_before == finished.actions &&
  learner.instance_variable_get(:@trajectories).empty?

class NoContinuationTrainingGame < GameRoomGames::TicTacToe
  def legal_actions(replay, actor, context: nil)
    replay.board.flatten.compact.empty? ? super : []
  end
end
class InvalidTrainingStrategy < EpisodeTrackingStrategy
  def choose(**arguments)
    super
    nil
  end
end
[[NoContinuationTrainingGame.new, EpisodeTrackingStrategy, :no_legal_action],
 [game, InvalidTrainingStrategy, :invalid_strategy_action]].each do |attempt_game, strategy_class, reason|
  attempt_policy = GameRoomTraining::PolicyTable.new
  strategy = strategy_class.new(policy: attempt_policy, epsilon: 0)
  attempt = GameRoomSimulation::MatchRunner.new(game: attempt_game, players: players,
    default_strategy: strategy).run(seed: 918)
  raise "#{reason} was treated as a completed learning episode" unless attempt.reason == reason &&
    strategy.finished_actors.empty? && strategy.reset_actors == players &&
    strategy.instance_variable_get(:@trajectories).empty? && attempt_policy.to_h.empty?
end

puts 'PASS offline training separates action-limit attempts from completed draws and Elo results'
