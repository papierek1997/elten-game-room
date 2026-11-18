require_relative '../../support/cheat'
require_relative '../../support/sequence_random'
include GameRoomTest::CheatFixture

%w[ascending descending neighbour fixed_bluff suit].each do |variant|
  cheat_start(variant)
  steps = 0
  source = GameRoomTest::CheatFixture::RandomSource.new(19)
  until @replay.finished?
    actor = @replay.current_player
    actions = @game.legal_actions(@replay, actor)
    assert(actions.length <= 800, 'Bot expands too many packet candidates')
    observation = @game.bot_observation(@replay, actor)
    choice = GameRoomBots.choose(@game.bot_strategy,
      {actions: actions, actor: actor, random_source: source, game: @game, replay: @replay}) { observation }
    assert(choice, 'Bot has no decision')
    cheat_move(choice, actor)
    steps += 1
    assert(steps < 2_000, "Bot match did not finish: #{variant}")
  end
  puts "PASS Cheat bot match #{variant}: #{steps} accepted decisions"
end

cheat_start
actor = @replay.current_player
cheat_move(cheat_play(@replay.state[:hands].fetch(actor).first(4)))
viewer = @replay.current_player
original = @game.bot_observation(@replay, viewer)
actions = @game.legal_actions(@replay, viewer)
changed = Marshal.load(Marshal.dump(@replay))
others = changed.players.reject { |player| player == viewer }
changed.state[:hands][others[0]][0], changed.state[:hands][others[1]][0] =
  changed.state[:hands][others[1]][0], changed.state[:hands][others[0]][0]
changed.state[:last_packet][:cards] = changed.state[:last_packet][:cards].reverse.map { |card| card == 'AC' ? 'KD' : card }
changed.state[:seed] = 'f' * 32
changed.accepted_events = []
assert_equal(original, @game.bot_observation(changed, viewer), 'Foreign secrets affect the bot view')
assert_equal(actions, @game.legal_actions(changed, viewer), 'Foreign secrets affect candidates')
sources = 2.times.map { GameRoomRandom::SequenceSource.new([20, 80, 3, 7]) }
decisions = [@replay, changed].each_with_index.map do |replay, index|
  GameRoomBots.choose(@game.bot_strategy,
    {actions: @game.legal_actions(replay, viewer), actor: viewer, random_source: sources[index], game: @game, replay: replay}) do
    @game.bot_observation(replay, viewer)
  end
end
assert_equal(decisions.first, decisions.last)
assert_equal(sources.first.roll(count: 1, sides: 100), sources.last.roll(count: 1, sides: 100))

cheat_start('fixed_bluff')
actor = @replay.current_player
@replay.state[:hands] = @players.to_h { |player| [player, []] }
@replay.state[:hands][actor] = @game.send(:standard_deck).first(50)
@replay.state[:hands][(@players - [actor]).first] = [@game.send(:standard_deck)[50]]
@replay.state[:hands][(@players - [actor]).last] = [@game.send(:standard_deck)[51]]
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
20.times { assert(@game.legal_actions(@replay, actor).length <= 800, 'Large hand enumerates subsets') }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
assert(elapsed < 2.0, "Large-hand planning took #{elapsed} seconds")
custom = cheat_play(@replay.state[:hands][actor].values_at(2, 11, 23, 47), 'K')
assert_equal(:ok, @game.action_for(custom, @replay, actor).first, 'Heuristic candidates restrict human packets')
puts 'PASS Cheat bots: complete matches, explicit observation-only strategy, secret invariance, RNG continuation and bounded 50-card planning'
