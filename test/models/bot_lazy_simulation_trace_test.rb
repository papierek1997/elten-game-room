require_relative "../support/elten_array_shuffle"
require_relative "../support/new_games_fixture"
require_relative "../support/contract_values"
require_relative "../../lib/game_execution_policy"

def trace_environment(type, seed)
  environment = GameRoomSimulation::Environment.new_game(game: type.new,
    players: GameRoomParticipants.bots_for(71, 2), seed: seed)
  repository = environment.repository
  def repository.session_id(session); session["__id"]; end
  environment
end

comparisons = 0
[GameRoomGames::Uno, GameRoomGames::Makao, GameRoomGames::Monopoly].each do |type|
  game_decisions = 0
  [31, 5, 17].each do |seed|
    eager, lazy = 2.times.map { trace_environment(type, seed) }
    coordinator = GameRoomBots::Coordinator.new
    completed = 0
    40.times do
      # Marshal records shared-object identity too; a copied cache checkpoint
      # may use different aliases while retaining every state/history value.
      assert(GameRoomTest::ContractValues.canonical(eager.replay) == GameRoomTest::ContractValues.canonical(lazy.replay), "#{type}: replay diverged before planning")
      break if eager.finished?

      simulation = GameRoomSimulation::Environment.from_snapshot(game: eager.game,
        session: eager.session, events: eager.replay.accepted_events, players: eager.players,
        seed: GameRoomExecutionPolicy.bot_seed(eager.repository, eager.session, eager.replay))
      before = coordinator.decide_next(game: eager.game, replay: eager.replay,
        context: eager.context, simulation: simulation)
      after = GameRoomExecutionPolicy.bot_decision(game: lazy.game, session: lazy.session,
        replay: lazy.replay, repository: lazy.repository, coordinator: coordinator,
        context: lazy.context, players: lazy.players)
      assert(before == after && before, "#{type}: action/actor/legal list diverged or stopped")
      assert(eager.random_source.dup.roll(count: 4, sides: 1000).values ==
        lazy.random_source.dup.roll(count: 4, sides: 1000).values, "#{type}: decision RNG diverged")
      statuses = [[eager, before], [lazy, after]].map { |env, decision| env.step(decision.action, actor: decision.actor) }
      assert(statuses == [:ok, :ok], "#{type}: comparison action was rejected")
      assert(eager.events == lazy.events, "#{type}: canonical move or automatic events diverged")
      completed += 1
    end
    assert(completed > 0 && (completed == 40 || eager.finished?), "#{type}: trace stopped without a final game result")
    assert(GameRoomTest::ContractValues.canonical(eager.replay) == GameRoomTest::ContractValues.canonical(lazy.replay), "#{type}: final state/history diverged")
    puts "#{type}/#{seed}: #{completed} consecutive decisions, #{eager.events.length} accepted events identical, finished=#{eager.finished?}"
    comparisons += completed
    game_decisions += completed
  end
  assert(game_decisions >= 20, "#{type}: traces did not exercise sufficient decisions")
end

puts "PASS #{comparisons} bounded eager/lazy decisions with history, automatic actions, exact canonical events and next RNG; not full-match coverage"
