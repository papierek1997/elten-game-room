require_relative '../../support/mille_bornes'
include MilleBornesTest

def position(cure: 'end_counterflow:1', speed_limit: false, two_hundreds: 2, miles: 975,
  distances: %w[50:1 75:2])
  fixture = Fixture.new(options: {'counterflow' => true, 'include_instant_repairs' => true})
  state = fixture.scenario
  state[:tracks][0].merge!(miles: miles, moving: true, counterflow: true,
    two_hundreds: two_hundreds, speed_limit: speed_limit)
  state[:hands] = {'Alice' => distances + [cure].compact,
    'Bob' => %w[fuel:1 fuel:2 fuel:3], 'Carol' => %w[repairs:1 repairs:2 repairs:3]}
  state[:spent] = %w[go:1 200:1 200:2 100:1 100:2 100:3 100:4 100:5 75:1 counterflow:1]
  state[:draw_pile] = []
  state[:discard] = fixture.game.send(:deck_for, state[:options]) - state[:hands].values.flatten - state[:spent]
  [fixture, state]
end

def choose(fixture, state)
  replay = fixture.snapshot(state)
  before = Marshal.dump(replay)
  action = fixture.game.bot_strategy.choose(actions: fixture.game.legal_actions(replay, 'Alice'),
    game: fixture.game, replay: replay, actor: 'Alice', random_source: GameRoomRandom::SeededSource.new(42))
  equal(before, Marshal.dump(replay), 'Planning must leave the replay unchanged')
  equal(:ok, fixture.game.action_for(action, replay, 'Alice').first, 'Selected action must be legal')
  action
end

test('known own reverse-cure-forward finish beats stranding the car short of the finish') do
  fixture, state = position
  physical = state[:hands].values.flatten + state[:spent] + state[:discard]
  equal(fixture.game.send(:deck_for, state[:options]).sort, physical.sort, 'Physical cards are conserved')
  %w[50:1 end_counterflow:1 75:2].each do |card|
    action = choose(fixture, state)
    equal(['play', card], action.values_at('action', 'card'), 'Bounded own-hand plan')
    equal(:ok, fixture.play(state, 'Alice', 'play', card), 'Normal reducer accepts the selected move')
    while ![:round_complete, :finished].include?(state[:phase]) && state[:current_player] != 'Alice'
      actor = state[:current_player]
      discard = fixture.game.legal_actions(fixture.snapshot(state), actor).find { |item| item['action'] == 'discard' }
      assert(discard, 'Same noninterfering opponent policy must have a legal discard')
      equal(:ok, fixture.play(state, actor, 'discard', discard['card']), 'Opponent normal action')
    end
  end
  equal(1000, state[:tracks][0][:miles], 'Exact finish is reached')
  equal(0, state[:round_winner], 'The acting unit wins the round')
  equal(2100, state[:round_scores][0], 'Normal finish and empty-pile bonuses are unchanged')
end

test('ordinary instant repair and Driving Ace can also complete the known plan') do
  %w[instant_repair:1 driving_ace:1].each do |cure|
    fixture, state = position(cure: cure)
    equal(['play', '50:1'], choose(fixture, state).values_at('action', 'card'),
      'Do not cure away a known exact finish before reversing')
  end
end

test('an already held finish after curing beats an unnecessary reverse detour') do
  fixture, state = position(miles: 950, distances: %w[25:1 50:1 75:2])
  equal(['play', 'end_counterflow:1'], choose(fixture, state).values_at('action', 'card'),
    'The two-turn cure and finish must beat a three-turn detour')
end

test('no speculation without a held cure and legal remaining finish') do
  cases = [
    {cure: nil},
    {distances: %w[50:1 100:1]},
    {speed_limit: true},
    {miles: 850, distances: %w[50:1 200:3]},
    {miles: 825, two_hundreds: 1, distances: %w[25:1 200:3]}
  ]
  cases.first(4).each do |options|
    fixture, state = position(**options)
    action = choose(fixture, state)
    assert(action['action'] != 'play' || action['card'] != '50:1',
      'Impossible or unprepared reverse-finish must not be preferred')
  end
  fixture, state = position(**cases.last)
  equal(['play', '25:1'], choose(fixture, state).values_at('action', 'card'),
    'One remaining 200-mile allowance permits the known finish')
end

test('foreign hands and future deck order cannot influence this bounded plan') do
  fixture, state = position
  alternative = Marshal.load(Marshal.dump(state))
  alternative[:hands]['Bob'], alternative[:hands]['Carol'] = alternative[:hands]['Carol'], alternative[:hands]['Bob']
  state[:draw_pile] = %w[25:1 25:2 25:3]
  alternative[:draw_pile] = state[:draw_pile].reverse
  equal(choose(fixture, state), choose(fixture, alternative), 'Only own cards and public track constrain the plan')
end
