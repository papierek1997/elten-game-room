require_relative '../../support/bouillabaisse_bot'
require_relative '../../../lib/game_simulation'
include GameRoomTest::Assertions

card_ids = BouillabaissePlanning::Round::CARD_IDS
shortened = 0
(2..8).each do |count|
  [true, false].each do |all_or_nothing|
    game = GameRoomGames::Bouillabaisse.new
    players = Array.new(count) { |index| "Seat#{index + 1}" }
    env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: count * 172,
      options: {'all_or_nothing'=>all_or_nothing})
    6.times do |index|
      round = BouillabaissePlanning::Round.new(env.observation(env.active_actor))
      shadow = round.initial.branch
      # Inject the concrete deal ONLY in this parity fixture so both models
      # see the same cards. The real planner starts from sampled worlds.
      shadow.hands = players.map { |player| env.replay.state[:hands].fetch(player).map { |card| card_ids.fetch(card) } }
      scores_before = env.replay.state[:scores].dup
      until round.finished?(shadow)
        actor = env.active_actor
        assert_equal(players.fetch(shadow.turn), actor, 'Simulated trick winner/turn diverged')
        actions = env.legal_actions(actor)
        assert_equal(actions.map { |action| card_ids.fetch(action['card']) }, round.legal(shadow), 'Simulation must follow the real follow-suit rule')
        selection = actions.first
        round.play(shadow, card_ids.fetch(selection['card']))
        assert_equal(:ok, env.step(selection, actor: actor))
        assert_equal(round.finished?(shadow), env.finished? || env.replay.state[:round] != index + 1,
          'Simulated round ended at a different trick')
      end
      shortened += 1 unless shadow.unplayed.empty?
      raw = players.each_with_index.to_h { |player, seat| [player, shadow.raw[seat]] }
      simulated = BouillabaissePlanning::Scoring.additions(raw, round: index + 1, all_or_nothing: all_or_nothing)
      real = env.replay.state[:scores].to_h { |player, score| [player, score - scores_before.fetch(player)] }
      assert_equal(real, simulated, 'Simulated end-of-round score differs from the real model')
    end
    assert(env.finished?, 'Did not finish all six rounds')
  end
end
assert(shortened.positive?, 'Did not exercise a round with unplayed non-scoring cards')
puts 'PASS Bouillabaisse planner model: legal cards, trick order, early endings and exact scoring, 2–8 seats with both sweep settings'
