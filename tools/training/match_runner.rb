require_relative '../../lib/game_simulation'

module GameRoomSimulation
  class MatchRunner
    def initialize(game:, players: nil, options: nil, strategies: {}, default_strategy: nil, max_actions: 10_000)
      @game = game
      @players = players || GameRoomParticipants.bots_for(1, game.minimum_players)
      @options = options
      @strategies = strategies
      @default_strategy = default_strategy || game.bot_strategy || GameRoomBots::RandomStrategy.new
      @max_actions = [max_actions.to_i, 1].max
    end

    def run(seed: 1)
      environment = Environment.new_game(
        game: @game,
        players: @players,
        options: @options,
        seed: seed
      )
      action_count = 0
      reason = :finished
      while !environment.finished?
        if action_count >= @max_actions
          reason = :action_limit
          break
        end

        actor = environment.active_actor
        actions = environment.legal_actions(actor)
        if actor == nil || actions.empty?
          reason = :no_legal_action
          break
        end

        strategy = strategy_for(actor)
        action = GameRoomBots.choose(strategy, {
          actions: actions,
          observation: environment.observation(actor),
          actor: actor,
          random_source: environment.random_source,
          game: @game,
          replay: environment.replay,
          context: environment.context,
          simulation: environment
        })
        if action == nil || environment.step(action, actor: actor) != :ok
          reason = :invalid_strategy_action
          break
        end
        action_count += 1
      end

      rewards = @players.each_with_object({}) do |actor, result|
        result[actor.to_s] = environment.reward(actor)
      end
      finish_strategies(rewards, finished: reason == :finished)
      MatchResult.new(
        game_id: @game.id,
        players: @players.dup,
        winner: environment.replay.winner,
        draw: environment.replay.draw == true,
        rewards: rewards,
        events: Environment.deep_copy(environment.events),
        actions: action_count,
        seed: seed.to_i,
        reason: reason,
        final_state: Environment.deep_copy(environment.replay.state)
      )
    end

    private

    def strategy_for(actor)
      @strategies[actor] || @strategies[actor.to_s] || @strategies[:default] || @default_strategy
    end

    def finish_strategies(rewards, finished:)
      @players.each do |actor|
        strategy = strategy_for(actor)
        if finished
          strategy.finish_episode(actor, rewards[actor.to_s]) if strategy.respond_to?(:finish_episode)
        elsif strategy.respond_to?(:reset_episode)
          strategy.reset_episode(actor)
        end
      end
    end
  end
end
