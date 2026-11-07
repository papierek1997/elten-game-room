require_relative '../../support/bouillabaisse_bot'
require_relative '../../../lib/game_simulation'
include GameRoomTest::Assertions

game = GameRoomGames::Bouillabaisse.new
players = %w[A B C D]
env = GameRoomSimulation::Environment.new_game(game: game, players: players, seed: 80263)
20.times { assert_equal(:ok, env.step(env.legal_actions(env.active_actor).first, actor: env.active_actor)) }
replay = env.replay
actor = env.active_actor
source = env.random_source
expected_rng = source.dup.roll(count: 8, sides: 1000).values
observation = game.bot_observation(replay, actor)
before = Marshal.dump(replay.state)
legal = env.legal_actions(actor)
first = game.bot_strategy.choose(actions: legal, observation: observation, random_source: source)
assert(legal.include?(first), 'Planner returned a non-legal card')
assert_equal(before, Marshal.dump(replay.state), 'Planning mutated the live replay')
assert_equal(expected_rng, source.dup.roll(count: 8, sides: 1000).values, 'Planning consumed the deal RNG')

# Foreign hand values cannot be inspected, even to seed the hypothetical worlds.
size_only = Struct.new(:size)
hidden = replay.state[:hands].transform_keys(&:dup).transform_values { |hand| size_only.new(hand.size) }
hidden[actor] = replay.state[:hands].fetch(actor).dup
scrubbed = replay.dup
scrubbed.state = replay.state.merge(hands: hidden)
scrubbed.accepted_events = replay.accepted_events.map { |event| event['action'] == 'deal' ? event.merge('value'=>'different secret seed') : event }
assert_equal(observation, game.bot_observation(scrubbed, actor), 'Observation depends on foreign hand contents or deal seed')
assert_equal(first, game.bot_strategy.choose(actions: legal, observation: game.bot_observation(scrubbed, actor)),
  'Same public information must give the same decision')

round = BouillabaissePlanning::Round.new(observation)
worlds = round.worlds(GameRoomGames::BouillabaisseStrategy::WORLD_LIMIT)
assert(worlds.size.between?(1, GameRoomGames::BouillabaisseStrategy::WORLD_LIMIT), 'No bounded consistent worlds')
worlds.each do |world|
  assert_equal(round.initial.unplayed.sort, world.hands.flatten.sort, 'Hypothetical deal lost/duplicated a card')
  assert_equal(round.initial.counts, world.hands.map(&:size), 'Hypothetical hand size changed')
  assert_equal(round.initial.hands[round.root], world.hands[round.root], 'The known hand was resampled')
  world.hands.each_with_index do |hand, player|
    assert(hand.none? { |card| round.void?(world, player, card % 4) }, 'A known void was contradicted')
  end
end
assert((round.absence(10, 2, 3) - 7.0/15).abs < 0.000001, 'Void probability is not a draw without replacement')
strategy = game.bot_strategy
assert(strategy.send(:reliable_gain, [-30, -30, 250, -30, -30, -30], [0] * 6).negative?,
  'One unusually favorable world must not outweigh five bad continuations')
assert_equal(10.0, strategy.send(:reliable_gain, [10] * 6, [0] * 6), 'Reliable gains were discarded')

full = game.replay(env.session, env.events, env.repository)
assert_equal(observation, game.bot_observation(full, actor), 'Full and incremental replay produce different knowledge')

# At a replacement boundary use the projected current seat, not the original
# log author's nickname. The previous deal must not add current-round voids.
fixture = GameRoomTest::BouillabaisseBot
game, replay = fixture.position(hands: {'A'=>%w[AC 2D], 'B'=>%w[QH 4D], 'C'=>%w[AH 5D]}, round: 2,
  taken: {'A'=>%w[KC KH QD]}, plays: [['A','KC'], ['B','KH'], ['C','QD']])
projected = replay.accepted_events.dup
projected[2] = projected[2].merge('actor'=>'Old player', '__replay_actor'=>'b')
projected.unshift({'action'=>'play', 'actor'=>'A', 'value'=>'KH'})
GameRoomParticipantDecisionEvents.attach(replay, projected)
public = game.bot_observation(replay, 'a')
assert_equal({'A'=>[], 'B'=>['C'], 'C'=>['C']}, BouillabaissePlanning::Information.void_suits(public),
  'Void deductions leaked across deals or lost a replaced seat')
assert_equal('Old player', projected[3]['actor'], 'Projection modified the public source event')
puts 'PASS Bouillabaisse fair planning: public-only observation, deterministic worlds, counts, voids, replay and RNG'
