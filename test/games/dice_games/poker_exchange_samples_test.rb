require_relative '../../../games/poker'
require_relative '../../support/private_simulation'
require_relative '../../support/assertions'
include GameRoomTest::Assertions

class CompleteHandPoker < GameRoomGames::Poker
  attr_reader :ranked_samples

  def five_card_rank(cards)
    raise "Exchange planner ranked #{cards.length} cards instead of five" unless cards.length == 5
    @ranked_samples = @ranked_samples.to_i + 1
    super
  end
end

[['nine', false, 4], ['full', false, 4], ['nine', true, 3]].each do |deck, draw_five, count|
  game = CompleteHandPoker.new
  env = GameRoomTest::PrivateSimulation.new_game(game: game, players: %w[Alice Bob Carol Dave].first(count),
    options: {'deck'=>deck, 'variant'=>'draw', 'draw_five'=>draw_five, 'blind_interval'=>'never'}, seed: 992)
  count.times do
    break if env.replay.state[:phase] == :exchange
    selection = env.legal_actions.find { |item| %w[call check].include?(item['action']) }
    assert(selection, 'No ordinary opening call/check')
    assert_equal(:ok, env.step(selection))
  end
  assert_equal(:exchange, env.replay.state[:phase])
  actor = env.active_actor
  before = Marshal.dump(env.replay)
  actions = env.legal_actions
  scores = actions.map { |action| game.bot_action_score(env.replay, actor, action) }
  assert(scores.all? { |score| score.is_a?(Numeric) && score.finite? })
  assert(game.ranked_samples.to_i >= 96 * (count - 1), 'The real opponent sampler was not exercised')
  assert_equal(before, Marshal.dump(env.replay), 'Planning mutated the accepted deal')
  selected = GameRoomBots.choose(game.bot_strategy, actions: actions, actor: actor,
    random_source: GameRoomRandom::SeededSource.new(17), game: game, replay: env.replay)
  assert(actions.include?(selected), 'The real bot strategy did not choose a legal exchange')
  assert_equal(:ok, env.step(selected, actor: actor))
  assert(env.replay.state[:hands].values.all? { |hand| hand.length == 5 }, 'Exchange changed an actual hand size')
  assert_equal(env.replay, game.replay(env.session, env.events, env.repository))
end
puts 'PASS Poker exchange samples: complete five-card worlds for short/full decks, both exchange caps, finite scores, legal strategy and unchanged replay'
