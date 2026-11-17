require_relative '../../support/assertions'
require_relative '../../../games/mahjong_support/table_round'
include GameRoomTest::Assertions
M = GameRoomMahjong

# An undeclared hand with a legal Riichi opportunity, not an already locked
# Riichi hand with invented alternative discards. All physical tiles are unique.
kinds = [23,23,21,26,26,26,30,30,30,18,19,20,9,9]
copies = Hash.new(0)
own = kinds.map { |kind| tile = kind * 4 + copies[kind]; copies[kind] += 1; tile }
rest = M::Tiles.set - own - [16]
hands = [own] + Array.new(3) { rest.shift(13) }
reserve = rest.shift(14)
rest << reserve[4]
reserve[4] = 16
flow = M::TileFlow.new(hands: hands, wall: rest, reserve: reserve, seat: 0, phase: :discard,
  replacement_source: :riichi, last_draw: own.last, draw_origin: :normal)
round = M::TableRound.new(flow: flow, variant: 'riichi', dealer: 1)
actions = round.legal_actions(seat: 0)
before = Marshal.dump(flow)
policy = M::Bot::Policy.new(flow.observation(viewer: 0), seat: 0, dealer: 1,
  variant: 'riichi', round_wind: 27, riichi_levels: [0,0,0,0])
move = policy.choose(actions)
assert(actions.include?(move), 'Value-aware bot left the real legal-action set')
assert_equal(18, M::Tiles.kind(move.fetch(:tile)), 'Equal-width ready choices ignored the more valuable hand')
assert(round.legal_action?(move), 'The scoring-aware choice is not a legal round action')
analysis = policy.instance_variable_get(:@analysis)
evaluations = [23, 18].map do |discard|
  hand = kinds.dup
  hand.delete_at(hand.index(discard))
  analysis.rest(hand, [], kind: discard)
end
assert_equal([0,0], evaluations.map(&:distance))
assert_equal([4,4], evaluations.map(&:acceptance))
assert_equal([5200.0,8000.0], evaluations.map(&:value), 'Value must come from real scoring and payments')
assert_equal(before, Marshal.dump(flow), 'Policy changed tile ownership')

# A cheap narrow wait does not automatically justify pushing into Riichi.
view = flow.observation(viewer: 0).merge(discard_history: [[1, 33 * 4]])
defence = M::Bot::Policy.new(view, seat: 0, dealer: 1, variant: 'riichi', round_wind: 27, riichi_levels: [0,1,0,0])
evaluation = M::Bot::Efficiency::Evaluation.new(18, 0, 2, 2, false, 0, 0, 1000)
assert(!defence.send(:push_hand?, evaluation), 'Cheap two-tile wait pushes regardless of public danger')
evaluation.value, evaluation.acceptance = 12000, 4
assert(defence.send(:push_hand?, evaluation), 'Expensive live ready hand cannot push a moderate public threat')
assert_equal(0.0, defence.send(:danger, 33), 'Public Riichi genbutsu ceased to be safe')
puts 'PASS Mahjong real legal value-aware wait (5200 to 8000, four live tiles), push/fold, genbutsu and immutable ownership'
