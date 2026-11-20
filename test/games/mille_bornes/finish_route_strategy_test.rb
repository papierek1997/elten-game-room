require_relative '../../support/mille_bornes'
include MilleBornesTest

test('finite deck prefers an available finish over an unreachable extra distance') do
  fixture = Fixture.new(players:%w[Alice Bob], options:{'recycle_discard'=>false, 'counterflow'=>false})
  state = fixture.scenario
  state[:tracks][0].merge!(miles:775, moving:true, two_hundreds:0)
  state[:tracks][1].merge!(miles:225, moving:true, two_hundreds:0)
  state[:spent] = (1..10).map { |i| "25:#{i}" } + (1..6).map { |i| "100:#{i}" } + %w[75:1 75:2 go:1 go:2]
  state[:hands] = {'Alice'=>%w[200:1 100:7 75:3 50:1], 'Bob'=>%w[fuel:1 fuel:2 repairs:1 repairs:2]}
  deck = fixture.game.send(:deck_for, state[:options])
  state[:draw_pile], state[:discard] = deck - state[:spent] - state[:hands].values.flatten, []
  equal(deck.sort, (state[:spent]+state[:draw_pile]+state[:hands].values.flatten).sort, 'Conserved physical deck')
  replay = fixture.snapshot(state)
  before = Marshal.dump(state)
  action = fixture.game.bot_strategy.choose(actions:fixture.game.legal_actions(replay,'Alice'), actor:'Alice',
    game:fixture.game, replay:replay, random_source:GameRoomRandom::SeededSource.new(31))
  assert(action['action']=='play' && action['card']!='200:1', 'Do not strand at 975 with every 25 spent')
  equal(:ok, fixture.game.action_for(action,replay,'Alice',context:fixture.context).first, 'Normal validation')
  equal(before, Marshal.dump(state), 'No mutation while planning')
end
