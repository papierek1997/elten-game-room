require_relative "../../support/dice_games"
require_relative "../../../lib/game_simulation"
include DiceGamesSupport

game = GameRoomGames::DicePoker.new
repo = DiceGamesSupport::Repository.new(%w[Alice Bob])
session = dice_session(game, opener_limit: true)
events = [dice_event(1, "Alice", "roll", "1,2,3,4,5"), dice_event(2, "Alice", "stand", "1")]
replay = game.replay(session, events, repo)
check(replay.current_player == 'Bob' && replay.state[:budget] == 1, "Opener throw budget missing")
events << dice_event(3, "Bob", "roll", "2,3,4,5,6")
replay = game.replay(session, events, repo)
check(game.legal_actions(replay, 'Bob').size == 1, "Follower exceeded opener budget")
check(game.action_for({'action'=>'roll'}, replay, 'Bob').first == :roll_limit, "Roll cap bypassed")
check(game.replay(session, events + [dice_event(4, 'Bob', 'roll', '6,6,6,6,6')], repo).accepted_events.size == 3, "Replay roll cap bypassed")
events << dice_event(4, 'Bob', 'stand', '1')
replay = game.replay(session, events, repo)
check(replay.state[:scores] == {'Alice'=>0, 'Bob'=>1} && replay.current_player == 'Bob' && replay.state[:round] == 2, "Round scoring or rotated opener failed")
check(game.replay(session, events + [events.last], repo).state == replay.state, "Duplicate changed poker round")
first = game.replay(session, [], repo)
check(game.action_for({'action'=>'score', 'category'=>'stand'}, first, 'Alice').first == :roll_first, "Empty poker hand banked")
check(game.action_for({'action'=>'roll'}, first, 'Bob').first == :not_your_turn, "Guest rolled for opener")
native = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(1), server_random: true)
status, plan = game.action_for({'action'=>'roll'}, first, 'Alice', context: native)
check(status == :ok && plan.events.first.random_request.values_at('count','sides','sort') == [5,6,true], "Initial native dice request")
after_roll = game.replay(dice_session(game), events.take(1), repo)
check(game.action_for({'action'=>'roll', 'die_ids'=>'d0,d0'}, after_roll, 'Alice', context: native).first == :choose_dice, "Duplicate dice IDs accepted")
status, plan = game.action_for({'action'=>'roll', 'die_ids'=>'d0,d4'}, after_roll, 'Alice', context: native)
check(status == :ok && plan.events.first.random_request.values_at('count','keep') == [2,[2,3,4]], "Reroll discarded kept dice")

coordinator = GameRoomBots::Coordinator.new
%w[classic no_straights aces_high].each do |variant|
  [2,3].each do |throws|
    [true,false].each do |opener_limit|
      env = GameRoomSimulation::Environment.new_game(game: game, players: %w[bot:1:1:pl01 bot:1:2:pl02],
        options: {'variant'=>variant, 'throws'=>throws, 'opener_limit'=>opener_limit, 'round_limit'=>3, 'bot_delay'=>0}, seed: 27)
      100.times do
        break if env.finished?
        decision = coordinator.decide_next(game: game, replay: env.replay, context: env.context, strategy: game.bot_strategy)
        check(decision && env.legal_actions(decision.actor).include?(decision.action), "Poker bot chose an illegal action")
        check(env.step(decision.action, actor: decision.actor) == :ok, "Poker bot move rejected")
      end
      check(env.finished? && env.replay.accepted_events == env.events, "Poker bot match did not finish")
      check(env.replay == game.replay(env.session, env.events, env.repository), "Poker replay diverged")
    end
  end
end
puts "Dice poker: 12 complete bot matches, turn budgets, rotation, native rolls, stale/invalid moves and replay passed"
