require_relative 'elten_array_shuffle'
require_relative 'assertions'
require_relative '../../games/catalog'
require_relative '../../lib/game_random'

module GameRoomTest
  class DealtCardTable
    Repository = Struct.new(:players) do
      def players_for(_session); players; end
      def actor_of(event, _session = nil); event.fetch('actor'); end
      def event_id(event); event.fetch('id'); end
    end
    attr_reader :game, :session, :events, :repository, :replay
    def initialize(id, count: 2, options: {}, seed: 1)
      @game = GameRoomGames::CATALOG.build(id)
      players = %w[Alice Bob Carol Dave Eve Frank Grace Heidi].first(count)
      options = @game.normalize_options(options)
      if (assignment = @game.team_assignment(options, players: players))
        options = @game.with_team_assignment(options, players: players, seats: assignment.seats)
      end
      @session = {'game' => id, 'options' => JSON.generate(options)}
      @repository, @events = Repository.new(players), []
      @random = GameRoomRandom::SeededSource.new(seed)
      refresh
      deal
    end
    def state; replay.state; end
    def refresh; @replay = game.replay(session, events, repository); end
    def act(actor, selection)
      status, plan = game.action_for(selection, replay, actor,
        context: GameRoomGames::ActionContext.new(random_source: @random))
      return status unless status == :ok
      plan.events.each do |command|
        events << {'id' => events.size + 1, 'actor' => actor, 'action' => command.action, 'value' => command.value}
      end
      refresh
      :ok
    end
    def deal; act(replay.players.first, {'kind' => 'command', 'action' => 'deal'}); end
    def play
      actor = replay.current_player
      actions = game.legal_actions(replay, actor)
      selection = game.bot_strategy.choose(actions: actions, observation: game.bot_observation(replay, actor),
        actor: actor, random_source: @random)
      raise "No legal action: #{state[:phase]}" unless selection
      raise 'Legal card rejected' unless act(actor, selection) == :ok
    end
    def finish_round
      play while state[:phase] == :playing
    end

    # New round/bot regressions drive the registered production table, including
    # bidding, exchanges and counting, rather than a second Match model.
    def play_strategy
      actor = replay.current_player
      actions = game.legal_actions(replay, actor)
      selection = GameRoomBots.choose(game.bot_strategy, {
        actions: actions, actor: actor, random_source: @random,
        game: game, replay: replay,
        context: GameRoomGames::ActionContext.new(random_source: @random)
      }) { game.bot_observation(replay, actor) }
      raise "No production action in #{state[:phase]}" unless selection
      raise 'Production action was rejected' unless act(actor, selection) == :ok
    end

    def finish_production_round(limit: 300)
      limit.times do
        return if replay.finished? || state[:phase] == :round_complete
        play_strategy
      end
      raise "Unfinished production round: #{state[:phase]}"
    end

    def finish_production_match(limit: 4_000)
      limit.times do
        return if replay.finished?
        state[:phase] == :round_complete ? deal : play_strategy
      end
      raise "Unfinished production match: #{state[:phase]}"
    end
  end
end
