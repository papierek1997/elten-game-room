require_relative '../../support/assertions'
require_relative '../../../games/duck_racing_support/numeric_bot'
require_relative '../../../games/duck_racing_support/settlement'
include GameRoomTest::Assertions

engine, bot = GameRoomDuckRacing::NumericChallenges, GameRoomDuckRacing::NumericBot
state = engine.start('blackjack', seats: [0, 1], seed: 5, now_ms: 0)
first = state[:participants].fetch(state[:turn_index])
second = ([0, 1] - [first]).first
assert(engine.submit(state, seat: first, action: {kind: :hit, press_id: 1}, now_ms: 1))
view = engine.public_view(state, viewer: second)
assert_equal(23, view[:completed_totals][first])
assert_equal(12, view[:own][:total])
before = Marshal.dump(view)
assert_equal(:stand, bot.choose(view, seat: second, random: Random.new(1))[:kind])
assert_equal(before, Marshal.dump(view))
assert(engine.submit(state, seat: second, action: {kind: :stand, press_id: 1}, now_ms: 2))
paid = GameRoomDuckRacing::Settlement.difference(balances: {0 => 50, 1 => 50}, scores: state[:scores], ceiling: 21)
assert_equal(second, paid.winner)
assert_equal(11, paid.transfers.first.amount)

# A finished initial hand is still private until its public hand announcement.
state = engine.start('blackjack', seats: [0, 1, 2], seed: 8, now_ms: 0)
hidden = state[:players].keys.find { |seat| !state[:players][seat][:hand_announced] }
assert(hidden)
state[:players][hidden].merge!(done: true, total: 21)
assert(!engine.public_view(state, viewer: nil)[:completed_totals].key?(hidden))
state[:players][hidden][:hand_announced] = true
assert_equal(21, engine.public_view(state, viewer: nil)[:completed_totals][hidden])

# A public winning target changes the risk decision; hidden deck order does not.
view = {type: 'risky_dice', participants: [0, 1], finished: false, turn_seat: 0,
  completed_totals: {1 => 26}, own: {done: false, total: 12, rolls: [[6], [6]], die: {die_sides: 6}}}
assert_equal(:save, bot.choose(view, seat: 0, random: Random.new(1))[:kind])
view[:completed_totals] = {1 => 24}
assert_equal(:roll, bot.choose(view, seat: 0, random: Random.new(1))[:kind])
view[:deck], view[:answer] = [1], 24
assert_equal(:roll, bot.choose(view, seat: 0, random: Random.new(1))[:kind])
puts 'PASS numeric public target, guaranteed win, fixed-ace settlement and privacy'
