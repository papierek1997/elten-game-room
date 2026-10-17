require_relative "../../support/bridge"
require_relative "../../../lib/game_simulation"
include GameRoomTest::Assertions

game = GameRoomGames::CATALOG.build("bridge")
players = %w[Alice Bob Carol Dave]
variants = [{ "variant" => "rubber" }, { "variant" => "duplicate", "boards" => 4, "scoring" => "imp" },
  { "variant" => "duplicate", "boards" => 4, "scoring" => "mp" }]

variants.each do |options|
  [3, 11].each do |seed|
    env = GameRoomSimulation::Environment.new_game(game: game, players: players, options: game.normalize_options(options), seed: seed)
    steps = 0
    until env.finished?
      actor = env.active_actor
      assert(actor, "#{options}: no active player in #{env.replay.state[:phase]}")
      actions = env.legal_actions(actor)
      assert(!actions.empty?, "#{options}: no legal action")
      action = GameRoomBots.choose(game.bot_strategy, actions: actions, observation: env.observation(actor), actor: actor,
        random_source: env.random_source, game: game, replay: env.replay, context: env.context)
      assert(actions.include?(action), "the bot chose an illegal action")
      assert_equal(:ok, env.step(action, actor: actor), "the bot's action was rejected")
      if steps % 11 == 0
        players.each { |viewer| game.surface_spec(env.replay, viewer); game.game_shortcuts(env.replay, viewer) }
      end
      steps += 1
      assert(steps < 5000, "#{options}: the match did not end")
    end
    state = env.replay.state
    full = game.replay(env.session, env.events, env.repository)
    assert_equal(state[:scores], full.state[:scores], "incremental and full replay disagree")
    assert_equal(env.replay.history.map(&:text), full.history.map(&:text), "replay history differs")
    assert(env.replay.winner || env.replay.draw, "the match has no result")
    assert(game.result_text(env.replay).to_s.length > 0, "no result text")
    teams = game.with_team_assignment(options, players: players, seats: [0, 1, 0, 1])
    result = game.tournament_result(env.replay, options: teams)
    assert_equal(%w[team:0 team:1], result[:units].keys.sort, "tournament units are not the partnerships")
    assert_equal(state[:scores], result[:scores], "tournament scores differ from the match totals")
    assert(result[:draw] || result[:winners] == [env.replay.winner], "tournament winner differs from the match")
    expected = options["variant"] == "rubber" ? nil : options["boards"]
    assert_equal(expected, state[:deals].length, "wrong number of boards") if expected
  end
end

puts "PASS bridge bots: rubber, IMP and matchpoint matches end with legal actions and identical replays"
