require_relative "../../../games/blackjack"
require_relative "../../../games/blackjack_dice"
require_relative "../../../lib/game_simulation"

players = %w[bot:1:1:pl01 bot:1:2:pl02]
coordinator = GameRoomBots::Coordinator.new
[GameRoomGames::Blackjack.new, GameRoomGames::BlackjackDice.new].each do |game|
  variants = game.id == "blackjack" ? %w[simple extended] : %w[two_dice one_die]
  variants.each do |variant|
    options = game.default_options.merge("variant" => variant, "round_limit" => 2, "score_limit" => 1, "bot_delay" => 0)
    env = GameRoomSimulation::Environment.new_game(game: game, players: players, options: options, seed: 421)
    if game.id == "blackjack" && !env.finished?
      masked = Marshal.load(Marshal.dump(env.replay))
      masked.state[:deck].reverse!
      masked.state[:dealer][1] = "5:AC"
      random = GameRoomRandom::SeededSource.new(103)
      reference = random.dup
      actor = env.active_actor
      arguments = {actions: env.legal_actions, actor: actor, game: game, context: env.context}
      first = GameRoomBots.choose(game.bot_strategy, arguments.merge(replay: env.replay, random_source: random))
      second = GameRoomBots.choose(game.bot_strategy, arguments.merge(replay: masked, random_source: reference))
      raise "Bot consulted hidden cards" unless first == second
      raise "Hidden cards changed bot RNG state" unless random.roll(count: 4, sides: 1000).values == reference.roll(count: 4, sides: 1000).values
    end
    500.times do
      break if env.finished?
      decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
      raise "No bot decision: #{game.id}/#{variant}" unless decision
      raise "Illegal bot choice" unless env.legal_actions(decision.actor).include?(decision.action)
      raise "Bot action rejected" unless env.step(decision.action, actor: decision.actor) == :ok
    end
    raise "Bot match did not finish: #{game.id}/#{variant}" unless env.finished?
    raise "Replay rejected a bot event" unless env.replay.accepted_events == env.events
    puts "#{game.id}/#{variant}: bot choices and normal action/replay path completed"
  end
end

%w[two_dice one_die].each do |variant|
  game = GameRoomGames::BlackjackDice.new
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 87,
    options: game.normalize_options("variant" => variant, "scoring" => "chips", "starting_chips" => 30, "stake" => 10, "round_limit" => 3, "bot_delay" => 0))
  500.times do
    break if env.finished?
    decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
    raise "Missing chip bot action" unless decision
    raise "Chip bot action rejected" unless env.step(decision.action, actor: decision.actor) == :ok
    raise "Bot round changed chip supply" unless env.replay.state[:chips].values.sum + env.replay.state[:pot] == 60
  end
  raise "Chip bot match did not finish" unless env.finished?
  raise "Chip bot replay rejected an event" unless env.replay.accepted_events == env.events
  puts "blackjack_dice/#{variant}/chips: bot stake, dice and settlement completed"
end

%w[simple extended].each do |variant|
  game = GameRoomGames::Blackjack.new
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 421,
    options: game.new_game_options("variant" => variant, "round_limit" => 2, "bot_delay" => 0))
  raise "New card game bypassed ante or betting" unless env.replay.state[:phase] == :betting && env.events.map { |e| e["action"] } == ["ante"]
  500.times do
    break if env.finished?
    decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
    raise "Missing card betting bot action" unless decision
    raise "Card betting bot action rejected" unless env.step(decision.action, actor: decision.actor) == :ok
  end
  raise "Card betting bot match did not finish" unless env.finished?
  raise "Missing opening contributions" unless env.events.count { |e| e["action"] == "ante" } == 2
  raise "Card betting replay rejected an event" unless env.replay.accepted_events == env.events
  puts "blackjack/#{variant}/auction: bot calls, ante and complete matches passed"
end

%w[two_dice one_die].each do |variant|
  game = GameRoomGames::BlackjackDice.new
  env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 87,
    options: game.new_game_options("variant" => variant, "scoring" => "chips", "starting_chips" => 30, "stake" => 10, "round_limit" => 3, "bot_delay" => 0))
  500.times do
    break if env.finished?
    decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
    raise "Missing auction dice bot action" unless decision
    raise "Dice auction bot action rejected" unless env.step(decision.action, actor: decision.actor) == :ok
    raise "Dice auction changed chip supply" unless env.replay.state[:chips].values.sum + env.replay.state[:pot] == 60
  end
  raise "Dice auction bot match did not finish" unless env.finished? && env.replay.accepted_events == env.events
  puts "blackjack_dice/#{variant}/auction: ante, matching, dice and settlements passed"
end
