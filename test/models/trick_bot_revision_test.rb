require_relative '../support/dealt_card_games'
require_relative '../../lib/game_simulation'
include GameRoomTest::Assertions

%w[hearts jass belote french_tarot].each do |id|
  game = GameRoomGames::CATALOG.build(id)
  env = GameRoomSimulation::Environment.new_game(game: game, players: %w[Alice Bob Carol Dave], seed: 307)
  random = GameRoomRandom::SeededSource.new(91)
  game.define_singleton_method(:automatic_action) do |replay, actor, context: nil|
    replay.state[:phase] == :round_complete ? nil : super(replay, actor, context: context)
  end
  identity = env.replay
  checks = 0
  150.times do
    break if env.replay.state[:phase] == :round_complete || env.finished?
    actor, replay = env.active_actor, env.replay
    actions = env.legal_actions(actor)
    scores = actions.map { |action| game.bot_action_score(replay, actor, action) }
    if replay.state[:phase] == :playing
      assert(scores.max.to_f.positive?, "#{id}: retained a card from a previous revision instead of a current legal preference")
      checks += 1
    end
    choice = GameRoomBots.choose(game.bot_strategy, actions: actions, actor: actor,
      random_source: random, game: game, replay: replay)
    assert_equal(:ok, env.step(choice, actor: actor))
    assert(identity.equal?(env.replay), "#{id}: test stopped exercising an in-place replay")
  end
  assert(checks >= 28, "#{id}: did not check repeated turns of the same actor")
end
puts 'PASS current preferred card across in-place replay revisions, same actor, every legal candidate and four production deals'
