# encoding: UTF-8
require_relative '../../support/assertions'
require_relative '../../../lib/game_simulation'
require_relative '../../../games/spades'
include GameRoomTest::Assertions

plans = %w[Alus Aluś].map do |actor|
  game = GameRoomGames::Spades.new
  environment = GameRoomSimulation::Environment.new_game(game: game,
    players: ['Human', actor, 'Third'], seed: 71)
  3.times do
    break if environment.active_actor == actor
    assert_equal(:ok, environment.step(environment.legal_actions.first))
  end
  assert_equal(actor, environment.active_actor)
  state = environment.replay.state
  planner = SpadesPlanning::RoundPlanner.new(game)
  key = planner.send(:rollout_cache_key, state, actor, 0, false, 8)
  assert_equal(Encoding::BINARY, key.encoding)
  assert_equal(Encoding::UTF_8, actor.encoding, 'Building a cache key must not relabel the participant name')
  assert_equal(32, planner.send(:exact_state_key, state).bytesize, 'Keep the bounded binary digest')
  information = game.bot_decision_context(environment.replay, actor, plan_round: false)
  plan = planner.plan(state: state, actor: actor, information: information)
  assert_equal(nil, planner.last_failure)
  assert(!plan.fetch(:scores).empty?, 'A named bot silently fell back instead of planning legal bids')
  assert_equal(environment.legal_actions.map { |action| action['bid'] }.sort, plan[:scores].keys.sort)
  plan
end
assert_equal(plans.first[:scores], plans.last[:scores], 'The same seats and deal must not become weaker with a non-ASCII name')
assert_equal(plans.first[:raw_scores], plans.last[:raw_scores])
puts 'PASS Spades: non-ASCII actor keeps binary cache identity and the same legal full-round plan without fallback'
