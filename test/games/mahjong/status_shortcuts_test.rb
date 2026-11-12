require_relative '../../support/assertions'
require_relative '../../support/mahjong_table_game'
require_relative '../../support/mahjong_game'
require_relative '../../support/mahjong_round'
require_relative '../../../games/mahjong'
include GameRoomTest::Assertions
include MahjongRoundFixture
include MahjongTableGameTest

def shortcut(game, replay, key)
  game.game_shortcuts(replay, replay.players.first).find { |item| item.key == key && item.modifiers.to_a.empty? }
end

[['solitaire',1], ['hong_kong',4], ['riichi',4], ['riichi',3], ['mcr',4]].each do |variant,seats|
  game = GameRoomGames::Mahjong.new
  options = game.normalize_options('variant'=>variant, 'riichi_seats'=>seats.to_s,
    'hong_kong_winds'=>'0', 'riichi_winds'=>'0', 'mcr_winds'=>'0')
  repo = MahjongTableGameTest::Repository.new
  session = {'id'=>45, 'players'=>%w[Alice Bob Carol Dave].first(seats), 'options'=>JSON.generate(options)}
  initial = game.replay(session, [], repo)
  assert_equal(0, initial.state[:hand_number]) unless variant == 'solitaire'
  assert(shortcut(game, initial, 's').message.include?(variant == 'riichi' ? '30000' : '0'))
  assert_equal(nil, shortcut(game, initial, 'm'))
  context = GameRoomGames::ActionContext.new(session_id:45, random_source:MahjongTableGameTest::RandomSource.new)
  _, plan = game.action_for(game.automatic_action(initial,'Alice'), initial,'Alice',context:context)
  event = {'id'=>1,'actor'=>'Alice','action'=>plan.events.first.action,'value'=>plan.events.first.value}
  dealt = game.incremental_replay(initial,session,[event],repo)
  assert_equal(:announcement, shortcut(game,dealt,'s').kind)
  assert_equal(:announcement, shortcut(game,dealt,'m').kind)
  if variant == 'solitaire'
    assert(shortcut(game,dealt,'m').message.include?('144'))
    _, plan = game.action_for(game.legal_actions(dealt,'Alice').first,dealt,'Alice',context:context)
    moved = game.incremental_replay(dealt,session,[{'id'=>2,'actor'=>'Alice','action'=>plan.events.first.action,'value'=>plan.events.first.value}],repo)
    assert_equal('Alice: 1',shortcut(game,moved,'s').message)
    assert(shortcut(game,moved,'m').message.include?('142'))
    assert(shortcut(game,dealt,'m').message.include?('144'), 'Readout changed an earlier board')
  else
    assert_equal(1, dealt.state[:hand_number], 'The first accepted public hand must be numbered one')
    assert_equal(nil, JSON.parse(event.fetch('value'))['h'], 'A single-hand deal must keep its unscoped wire format')
    assert(shortcut(game, dealt, 'r').message.include?('Hand number: 1.'))
    cold = GameRoomGames::Mahjong.new.replay(session, [event], repo)
    assert_equal(dealt.state[:hand_number], cold.state[:hand_number])
    assert_equal(round_snapshot(dealt.state[:round]), round_snapshot(cold.state[:round]))
    repeated = game.incremental_replay(dealt, session, [event], repo)
    assert_equal(1, repeated.state[:hand_number], 'A duplicate deal cannot advance the hand counter')
    assert_equal(0, initial.state[:hand_number], 'Dealing must not mutate the initial checkpoint')
    assert(shortcut(game,dealt,'m').message.include?(dealt.state[:round].flow.wall.length.to_s))
    assert(shortcut(game,dealt,'s').message.include?(variant == 'riichi' ? '30000' : '0'))
  end
end

# The public status key reads accepted deposits rather than the original
# 30,000 balance, and never exposes concealed hands in either announcement.
game = GameRoomGames::Mahjong.new
flow = ready_flow('123m456p789s1112z','5z',self_draw:true)
round = GameRoomMahjong::TableRound.new(flow:flow,variant:'riichi',dealer:0)
round = round.action(seat:0,type: :riichi,tile:round.riichi_discards.first,generation:flow.generation)
round.window.pending.dup.each do |seat|
  round = round.action(seat:seat,type: :claim,choice:[:pass],generation:round.flow.generation)
end
replay = GameRoomGames::Replay.new(players:%w[Alice Bob Carol Dave],state:{profile:{'variant'=>'riichi'},phase: :playing,
  session_id:77,round:round,match:nil},accepted_events:[],history:[])
assert(shortcut(game,replay,'s').message.include?('Alice: 29000'))
assert(!shortcut(game,replay,'m').message.include?('Alice'))
assert_equal(1,round.riichi_state.sticks)

match=GameRoomMahjong::MatchState.new(variant:'riichi')
flow=ready_flow('123456789m1115z','5z',self_draw:true)
round=GameRoomMahjong::TableRound.new(flow:flow,variant:'riichi',dealer:0,
  riichi_state:GameRoomMahjong::RiichiState.new(points:match.points))
finished=round.action(seat:0,type: :win,generation:flow.generation)
advanced=match.advance(round:finished,hand_number:1)
replay=GameRoomGames::Replay.new(players:%w[Alice Bob Carol Dave],state:{profile:{'variant'=>'riichi'},phase: :between_hands,
  session_id:77,round:finished,match:advanced},accepted_events:[],history:[])
message=shortcut(game,replay,'s').message
assert(message.include?("Alice: #{advanced.points.first}"))
assert(advanced.points.first>30000, 'Winning hand failed to settle before the readout')
assert(!message.include?("Alice: #{advanced.scores.first};"), 'S announced only the gain instead of the current balance')
puts 'PASS Mahjong S/M: all variants, sanma, no key collision, live wall/layout count, Solitaire progress and accepted Riichi deposit'
