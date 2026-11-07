require_relative '../../support/assertions'
require_relative '../../support/mahjong_round'
require_relative '../../../games/mahjong_support/mcr_deal'
include GameRoomTest::Assertions
include MahjongRoundFixture

flow = ready_flow('123m456p789s1112z', '5z', self_draw: true)
round = GameRoomMahjong::TableRound.new(flow: flow, variant: 'riichi', dealer: 1)
actions = round.legal_actions(seat: 0)
assert(actions.frozen? && actions.all?(&:frozen?))
assert_equal(round.legal_discards.sort, actions.select { |action| action[:type] == :discard }.map { |action| action[:tile] }.sort)
assert_equal([], round.legal_actions(seat: 1))
assert_equal(nil, round.bot_action(seat: 1))
assert_raises(ArgumentError) { round.legal_actions(seat: -1) }
selected = round.bot_action(seat: 0)
assert(actions.include?(selected))
assert_equal(:riichi, selected[:type], 'A closed hand with live waits can declare Riichi')
assert([28, 31].include?(GameRoomMahjong::Tiles.kind(selected[:tile])))
next_round = round.action(**selected)
assert_equal(:reactions, next_round.flow.phase)
assert_raises(ArgumentError) { next_round.action(**selected) }
assert_equal(:discard, round.flow.phase, 'Planning and applying must preserve previous snapshots')

# Changing every opponent hand and the future wall must not change the bot's
# choice when its own hand and all public observations remain the same.
other = GameRoomMahjong::TileFlow.new(hands: [flow.hands[0]] + flow.hands.drop(1).reverse,
  wall: flow.wall.reverse, seat: 0, phase: :discard, generation: flow.generation,
  last_draw: flow.last_draw, draw_origin: :normal)
hidden_changed = GameRoomMahjong::TableRound.new(flow: other, variant: 'riichi', dealer: 1)
assert_equal(selected, hidden_changed.bot_action(seat: 0))
next_round.window.pending.each do |seat|
  response = next_round.bot_action(seat: seat)
  assert_equal([:pass], response[:choice])
  next_round = next_round.action(**response)
  assert_equal([], next_round.legal_actions(seat: seat)) if next_round.flow.phase == :reactions
end
assert_equal(:draw, next_round.flow.phase)
assert_equal(2, next_round.riichi_state.levels.fetch(0), 'The bot declaration must be accepted through the claim window')
draw = next_round.bot_action(seat: next_round.flow.seat)
assert_equal(:draw, draw[:type])
assert_equal(:discard, next_round.action(**draw).flow.phase)

%w[riichi hong_kong mcr].each do |variant|
  winning = ready_flow('123456789m1115z', '5z', self_draw: true)
  ready = GameRoomMahjong::TableRound.new(flow: winning, variant: variant, dealer: 0)
  choice = ready.bot_action(seat: 0)
  assert_equal(:win, choice[:type])
  ended = ready.action(**choice)
  assert(ended.finished?)
  assert_equal([], ended.legal_actions(seat: 0))
  assert_equal(nil, ended.bot_action(seat: 0))
end

ron = ready_flow('123456789m1115z', '5z')
ready = GameRoomMahjong::TableRound.new(flow: ron, variant: 'mcr', dealer: 0)
window = GameRoomMahjong::ClaimOffers.for_discard(ron,
  win_checker: ->(seat, _hand, _tile) { !ready.winning_result(seat).nil? })
ready = ready.with(window: window)
assert_equal([:win], ready.bot_action(seat: 0)[:choice])

# A complete autonomous internal round uses only selected legal plans through
# the same coordinator as human actions, with no direct state edits or writes.
autoplay = GameRoomMahjong::TableRound.new(flow: GameRoomMahjong::MCRDeal.shuffled(seed: 42), variant: 'mcr', dealer: 0)
steps = 0
until autoplay.finished?
  actor = autoplay.flow.phase == :reactions ? autoplay.window.pending.first : autoplay.flow.seat
  plan = autoplay.bot_action(seat: actor)
  assert(plan && autoplay.legal_actions(seat: actor).include?(plan))
  previous = autoplay
  autoplay = autoplay.action(**plan)
  assert(!previous.finished?)
  steps += 1
  raise 'Mahjong bots failed to finish the round' if steps > 600
end
assert(autoplay.result)
assert_equal(0, autoplay.result.payments.sum)
assert(steps > 10)
puts 'PASS mahjong action planning: legal owned choices, private bot observation, win/pass/draw priorities, stale rejection and immutable finish'
