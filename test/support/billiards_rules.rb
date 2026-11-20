require_relative 'billiards'
require_relative '../../lib/billiards/rules'

module BilliardsRulesFixture
  B = GameRoomBilliards
  R = B::Rules
  def self.state(discipline = 'eight', race_to: 1)
    state = {options: {'discipline'=>discipline, 'race_to'=>race_to, 'rack_seed'=>123},
      racks: [0, 0], scores: [0, 0], rack_number: 0, revision: 0, shots: 0}
    R.setup(state)
    state
  end
  def self.result(state, first: 1, pots: [], rails: [], crossings: [1, 2, 3])
    balls = state[:balls].map(&:dup)
    events = Array(first).map { |id| {kind: :ball, a: 0, b: id, t: 0.1} }
    events.concat(rails.map { |id| {kind: :rail, a: id, rail: :right, t: 0.2} })
    pots.each do |id, pocket|
      balls.find { |b| b.id == id }.status = :potted
      events << {kind: :pocket, a: id, pocket: pocket || 0, t: 0.3}
    end
    B::ShotResult.new(balls: balls, events: events, steps: 1, duration: 1.0, head_crossings: crossings)
  end
  def self.apply(state, result, call: 1, pocket: 0, mode: 0)
    before = Marshal.load(Marshal.dump(state))
    state[:balls] = result.balls.map(&:dup)
    data = {'call'=>call, 'pocket'=>pocket, 'mode'=>mode, 'shot'=>{'angle'=>0, 'power'=>200, 'top'=>0, 'side'=>0}}
    R.resolve_shot(state, before, result, data)
    state
  end
end
