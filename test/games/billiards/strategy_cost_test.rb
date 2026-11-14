require_relative '../../support/billiards'

fixture = BilliardsFixture::Match.new(players: %w[Alice Bob], options: {'discipline'=>'nine', 'rack_seed'=>41})
state = fixture.replay.state
action = fixture.game.legal_actions(fixture.replay, 'Alice').find { |move| move['action'] == 'shot' }
raise 'Fixture has no legal shot' unless action
result = GameRoomBilliards::Physics.simulate(GameRoomBilliards::Rules.table(state[:options]), state[:balls], action.fetch('shot'),
  accurate: state[:options]['accurate'])
strategy = GameRoomBilliards::Strategy.new
before = Marshal.dump(state)
expected = strategy.score(state, result, action)
raise 'Scoring modified the real position' unless Marshal.dump(state) == before

# This bookkeeping is deliberately not marshalable: a rule simulation must
# not traverse it at all. The real replay continues to own all its evidence.
unrelated = Object.new
def unrelated._dump(_depth); raise 'A candidate copied replay bookkeeping'; end
large_seen = 10_000.times.to_h { |index| ["event-#{index}", true] }
expanded = state.merge(seen: large_seen, last: unrelated, last_shot: unrelated, undo: unrelated)
raise 'History changed the sporting evaluation' unless strategy.score(expanded, result, action) == expected
raise 'Scoring consumed replay identities' unless expanded[:seen].equal?(large_seen) && large_seen.size == 10_000
raise 'Scoring replaced the previous real outcome' unless expanded[:last].equal?(unrelated)
puts 'PASS billiards candidate score: same position/result, no mutation and no copying of growing replay IDs or prior contact/undo traces'
