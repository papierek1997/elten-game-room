require_relative "../../support/bingo"
require_relative "../../../lib/game_simulation"

class BingoSimulation < GameRoomSimulation::Environment
  def context
    super.tap { |value| value.now = 1000 + events.length * 31 }
  end
end

players = %w[bot:1:1:pl01 bot:1:2:pl02]
coordinator = GameRoomBots::Coordinator.new
%w[30 75 80 90].each do |variant|
  %w[automatic manual].each do |marking|
    patterns = %w[75 80].include?(variant) ? %w[line corners full] : ["line"]
    patterns.each do |pattern|
      game = GameRoomGames::Bingo.new
      env = BingoSimulation.new_game(game: game, players: players, options: {"variant" => variant, "marking" => marking, "pattern" => pattern, "bot_delay" => 0}, seed: 382)
      1000.times do
        break if env.finished?
        decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
        raise "Missing bingo bot input #{variant}/#{marking}" unless decision
        raise "Illegal bingo bot input" unless env.legal_actions(decision.actor).include?(decision.action)
        raise "Rejected bingo bot input" unless env.step(decision.action, actor: decision.actor) == :ok
      end
      raise "Bingo match did not finish #{variant}/#{marking}/#{pattern}" unless env.finished?
      raise "Bingo replay rejected an event" unless env.replay.accepted_events == env.events
      calls = env.replay.state[:called]
      raise "Repeated/out-of-pool call" unless calls.uniq == calls && calls.all? { |n| n.between?(1, variant.to_i) }
      raise "Missing 90-ball stages" if variant == "90" && env.replay.state[:awards].map { |a| a[:goal] } != %w[line two_lines full]
      first = Marshal.dump(env.replay)
      random_reference = env.random_source.dup
      rebuilt = game.replay(env.session, env.events, env.repository)
      raise "Replay changed a finished match" unless env.replay == rebuilt && first == Marshal.dump(env.replay)
      raise "Replay consumed the caller's future RNG" unless env.random_source.roll(count: 3, sides: 1000).values == random_reference.roll(count: 3, sides: 1000).values
      raise "Claimed no final pattern" unless env.replay.state[:awards].last[:players].all? do |player|
        GameRoomBingo.winning?(variant, env.replay.state[:awards].last[:goal], env.replay.state[:tickets][player], env.replay.state[:marks][player])
      end
      puts "bingo/#{variant}/#{marking}/#{pattern}: complete production bot/action/replay match passed"
    end
  end
end
