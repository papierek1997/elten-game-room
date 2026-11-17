require_relative '../../../games/three_five_eight'
require_relative '../../../lib/game_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions
checks = 0
GameRoomGames::ThreeFiveEight::CONTRACTS.each_with_index do |contract, index|
  game = GameRoomGames::ThreeFiveEight.new
  game.define_singleton_method(:automatic_action) do |replay, actor, context: nil|
    replay.state[:phase] == :round_complete ? nil : super(replay, actor, context: context)
  end
  env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob Carol], seed: 381 + index)
  200.times do
    break if env.finished? || env.replay.state[:phase] == :round_complete
    actor, replay = env.active_actor, env.replay
    actions = env.legal_actions
    if replay.state[:phase] == :choosing_contract
      move = actions.find { |action| action['contract'] == contract }
    else
      choose = lambda do |position|
        GameRoomBots.choose(game.bot_strategy, actions: actions, actor: actor,
          random_source: GameRoomRandom::SeededSource.new(91), game: game, replay: position)
      end
      before = Marshal.dump(replay)
      move = choose.call(replay)
      if replay.state[:phase] == :playing && replay.state[:hands][actor].size <= 4
        masked = Marshal.load(Marshal.dump(replay))
        masked.state[:hands].each do |player, hand|
          masked.state[:hands][player] = ['concealed'] * hand.size unless player == actor
        end
        masked.state[:kitty].reverse!
        assert_equal(move, choose.call(masked), 'Late plan inspected an actual foreign hand or kitty order')
        checks += 1
      end
      assert_equal(before, Marshal.dump(replay), 'Forecast changed the production replay')
    end
    assert(actions.include?(move), 'Endgame selector returned a nonexistent action')
    assert_equal(:ok, env.step(move, actor: actor))
  end
  assert(env.replay.state[:phase] == :round_complete || env.finished?, "Incomplete #{contract} deal")
end
assert(checks >= 60, 'Did not test the short tail of every contract')
puts "PASS 3-5-8 #{checks} late decisions, all six contracts, production acceptance, private-hand/kitty isolation and nonmutation"
