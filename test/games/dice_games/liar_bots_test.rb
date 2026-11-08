require_relative "../../../games/liars_dice"
require_relative "../../support/private_simulation"

coordinator = GameRoomBots::Coordinator.new
%w[rdr classic perudo].each do |variant|
  [false,true].each do |calza|
    [1,3,5].each do |count|
      game = GameRoomGames::LiarsDice.new
      env = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[bot:1:1:pl01 bot:1:2:pl02 bot:1:3:pl03],
        options: {'variant'=>variant, 'starting_dice'=>count, 'calza'=>calza, 'bot_delay'=>0}, seed: 61)
      800.times do
        break if env.finished?
        before = Marshal.dump(env.replay)
        decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
        raise "Missing liar bot decision #{variant}" unless decision && env.legal_actions(decision.actor).include?(decision.action)
        raise 'Bot decision mutated replay' unless Marshal.dump(env.replay) == before
        raise 'Rejected liar bot move' unless env.step(decision.action, actor: decision.actor) == :ok
      end
      raise "Liar bot match unfinished #{variant}/#{count}/#{calza}" unless env.finished?
      raise 'Replay rejected private protocol' unless env.replay.accepted_events == env.events
      reference = env.random_source.dup
      raise 'Replay is not deterministic' unless game.replay(env.session, env.events, env.repository) == env.replay
      raise 'Replay consumed RNG' unless env.random_source.roll(count:3,sides:1000).values == reference.roll(count:3,sides:1000).values
      raise 'Wrong survivor' unless env.replay.state[:counts].count { |_, value| value > 0 } == 1 && env.replay.state[:counts][env.replay.winner] > 0
      puts "liars_dice/#{variant}/#{count}/calza=#{calza}: complete private bot match passed"
    end
  end
end
