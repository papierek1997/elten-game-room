require_relative 'billiards_rules'
require_relative '../../lib/billiards/pyramid'

module BilliardsPyramidFixture
  B = GameRoomBilliards
  E = B::Pyramid
  def self.state(breaking: false)
    state = BilliardsRulesFixture.state('eight')
    state[:options]['discipline'] = 'pyramid'
    state[:balls] = E.rack(state[:options], 0)
    E.setup(state)
    state[:breaking], state[:hand] = breaking, breaking ? :kitchen : nil
    state
  end
  def self.data(cue = 0)
    {'call'=>0, 'pocket'=>0, 'mode'=>0, 'cue'=>cue,
      'shot'=>{'angle'=>0, 'power'=>350, 'top'=>0, 'side'=>0}}
  end
  def self.event(kind, a, values = {})
    {kind: kind, a: a, t: 0.1}.merge(values)
  end
  def self.result(state, events)
    balls = state[:balls].map(&:dup)
    events.each_with_index do |event, index|
      event[:t], event[:order] = index / 10.0, index
      balls.find { |b| b.id == event[:a] }.status = :potted if [:pocket, :off].include?(event[:kind])
    end
    B::ShotResult.new(balls: balls, events: events, steps: 1, duration: 1.0, head_crossings: [])
  end
  def self.apply(state, events, cue: 0)
    before = Marshal.load(Marshal.dump(state))
    result = result(state, events)
    state[:balls] = result.balls.map(&:dup)
    E.resolve(state, before, result, data(cue))
    [before, result]
  end
  def self.conserved?(state)
    state[:scores].sum + state[:balls].count(&:on_table?) == 16 &&
      state[:pyramid_scored].map(&:length) == state[:scores] && state[:pyramid_scored].flatten.uniq.length == state[:scores].sum
  end
end
