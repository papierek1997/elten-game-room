require_relative '../../support/game_option_editor_native'
require_relative '../../support/assertions'
require_relative '../../support/mahjong_round'
include GameRoomTest::Assertions
include MahjongRoundFixture

%w[en pl cs es ru].each do |language|
  NativeOptionTest.language=language
  %w[hong_kong riichi mcr].each do |variant|
    game=EltenGameRoom::GAME_REGISTRY.build('mahjong')
    flow=ready_flow('123456m23455p67s','8s',self_draw:true)
    round=GameRoomMahjong::TableRound.new(flow:flow,variant:variant,dealer:1)
    state={session_id:77,hand_number:1,phase: :playing,profile:{'variant'=>variant},round:round,match:nil}
    before=GameRoomGames::Replay.new(players:%w[Alice Bob Carol Dave],state:state,accepted_events:[],history:[])
    stock=game.game_shortcuts(before,'Alice').find { |item| item.key=='m' }
    scores=game.game_shortcuts(before,'Alice').find { |item| item.key=='s' }
    assert(stock && scores, 'S/M missing from the actual game shortcut list')
    assert(stock.label.encoding==Encoding::UTF_8 && stock.label.valid_encoding?)
    assert(stock.label!='read the number of tiles left in the wall') unless language=='en'
    assert(scores.message.include?(variant=='riichi' ? '30000' : '0'))
    round=round.action(seat:0,type: :discard,tile:flow.hands[0].first,generation:flow.generation)
    round.window.pending.dup.each { |seat| round=round.action(seat:seat,type: :claim,choice:[:pass],generation:round.flow.generation) }
    round=round.action(seat:1,type: :draw,generation:round.flow.generation)
    after=GameRoomGames::Replay.new(players:before.players,state:state.merge(round:round),accepted_events:[],history:[])
    heard=[]
    screen=GameScreen.allocate
    screen.instance_variable_set(:@game,game)
    screen.define_singleton_method(:speak) { |text,**_options| heard << text }
    updated=screen.send(:refreshed_game_shortcut,stock,after,'Alice')
    assert(updated.message!=stock.message, 'Stock announcement retained the pre-draw count')
    assert(updated.message.include?(round.flow.wall.length.to_s))
    assert_equal(nil,screen.send(:activate_game_shortcut,updated,nil,replay:after))
    assert_equal([updated.message],heard)
    assert_equal(flow.wall.length,before.state[:round].flow.wall.length)
  end
end
puts 'PASS native Mahjong S/M EN/PL/CS/ES/RU: localized help, public balances, current wall after accepted draw and read-only GameScreen announcement'
