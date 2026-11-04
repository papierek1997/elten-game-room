require_relative '../support/ui'
require_relative '../support/recordings'
require_relative '../../lib/recordings/controls'
require_relative '../../lib/game_surfaces'
include RecordingTest

value=document
frame=value['timeline'].first['data']
value['timeline']= [{'t'=>0,'kind'=>'frame','data'=>frame}]
[[0,1],[1,1],[2,1]].each_with_index do |scores,index|
  at=1000+1000*index
  value['timeline'] << {'t'=>at,'kind'=>'audio','data'=>{'method'=>'goal','args'=>[],'kwargs'=>{'viewer'=>0,'winner'=>0}}}
  value['timeline'] << {'t'=>at+200,'kind'=>'audio','data'=>{'method'=>'point','args'=>[scores],'kwargs'=>{'viewer'=>0,'winner'=>0,'finished'=>false}}}
  value['timeline'] << {'t'=>at+400,'kind'=>'frame','data'=>frame.merge('scores'=>scores,'rally'=>index+1)}
end

[:action,:point].each do |kind|
  now=0.0
  player=GameRoomRecordings::Player.new(value,clock:-> {now},renderer:->(clock) {RecordingTest::Audio.new([],clock)})
  player.seek(4500);player.play
  positions=[]
  while player.navigable?(kind,-1)
    player.navigate(kind,-1)
    positions << player.position
    break if player.position.zero?
    # Playback crosses the selected cue before the next navigation press.
    now+=0.3
    player.tick
    raise 'Previous is stuck on an already selected cue' if positions.size>10
  end
  assert(positions==positions.sort.reverse.uniq && positions.last==0,"#{kind}: cannot rewind to the opening")
  assert(player.frame['scores']==[0,0],"#{kind}: opening score was not restored")
  assert(!player.navigable?(kind,-1),'Previous remains available at the start')
  player.close
end

player=GameRoomRecordings::Player.new(value,renderer:->(clock) {RecordingTest::Audio.new([],clock)})
messages=[]
controls=GameRoomRecordings::Controls.new(player,position_text:->(_) {'Position only'},speaker:->(text) {messages<<text})
actions=-> {controls.operations.map(&:first)}
assert(actions.call.include?(:play) && !actions.call.include?(:pause),'Paused menu has the wrong playback action')
assert(!actions.call.include?(:back) && !actions.call.include?(:previous_point) && !actions.call.include?(:beginning),'Opening menu has unusable backward actions')
assert(!actions.call.include?(:previous_set) && !actions.call.include?(:next_set),'Pong menu offers unavailable sets')
assert(controls.operations.all? { |_,_,key| key.is_a?(Symbol) },'Playback shortcuts still require Ctrl')
assert(controls.operations.find { |row| row[0]==:play }[2]==:space,'Playback advertises a different key than Space')
assert(controls.operations.find { |row| row[0]==:forward }[2]==:right,'Forward advertises a different key than Right arrow')
controls.perform(:play)
assert(actions.call.include?(:pause) && !actions.call.include?(:play),'Playing menu still offers Play')
controls.perform(:pause)
controls.perform(:end)
assert(!player.playing && !actions.call.include?(:forward) && !actions.call.include?(:end) && !actions.call.include?(:next_point),'End menu offers forward actions')
controls.perform(:scores)
assert(messages.last=='Alice, 2. Bob, 1','Seeking after the last point lost the final score')
player.seek(1250)
assert(player.frame['scores']==[0,1],'Seeking between a point and its next frame reports the old score')
controls.perform(:scores)
spec=GameSurfaces::PongSpec.new(players:%w[Alice Bob],scores:[0,1],viewer:nil)
surface=GameSurfaces::PongSurface.new(spec)
surface.present(player.frame['snapshot'],'')
$spoken_messages.clear;surface.handle_command('scores')
assert(messages.last==$spoken_messages.last,'Replay scores differ from the live Pong formatter')
controls.perform(:server);surface.handle_command('server')
assert(messages.last==$spoken_messages.last,'Replay serve readout differs from live Pong')
assert(controls.perform([:perspective,1]) && player.seat==1,'Second perspective is not selectable')
assert(!actions.call.include?([:perspective,1]) && !controls.perform([:perspective,3]),'Unavailable perspective is actionable')
controls.perform(:information)
assert(messages.last=='Position only','Position shortcut announces a different action')
player.close

ball=document
ball['metadata']['game']='audio_ball'
ball['metadata']['game_name']='Audio Ball'
ball['timeline'].each do |event|
  if event['kind']=='frame'
    event['data']['snapshot']={'phase'=>'waiting','position'=>0.0,'turn'=>0,'shot'=>nil,'server'=>1,'goal'=>nil}
    event['data']['sets']=[1,0]
  elsif event['data']['method']=='point'
    event['data']['kwargs'].merge!('sets'=>[1,0],'set_finished'=>true)
  end
end
player=GameRoomRecordings::Player.new(ball,renderer:->(clock) {RecordingTest::Audio.new([],clock)})
controls=GameRoomRecordings::Controls.new(player,position_text:->(_) {''},speaker:->(text) {messages<<text})
assert(controls.operations.any? { |row| row[0]==:next_set },'A recorded set is missing from the menu')
controls.perform(:scores)
spec=GameSurfaces::AudioBallSpec.new(players:%w[Alice Bob],scores:[0,0],sets:[1,0],teams:[0,1])
surface=GameSurfaces::AudioBallSurface.new(spec)
surface.present(player.frame['snapshot'],'')
surface.handle_command('scores')
assert(messages.last==$spoken_messages.last,'Replay omits Audio Ball sets or changes its score formatter')
controls.perform(:server);surface.handle_command('server')
assert(messages.last==$spoken_messages.last,'Replay serve readout differs from live Audio Ball')
player.close

%w[axel_pong audio_ball].each do |game|
  data=game=='axel_pong' ? document : GameRoomRecordings::Document.copy(ball)
  data['metadata']['players']=%w[Alice Bob Carol Dave]
  data['timeline'].select { |event| event['kind']=='frame' }.each do |event|
    event['data']['teams']=[0,1,0,1]
    next if game=='audio_ball'
    event['data']['snapshot'].merge!('p'=>[10,20,30,40],'shields'=>[0,0,0,0],
      'edges'=>[0,0,0,0],'teams'=>[0,1,0,1],'receiver'=>1)
  end
  player=GameRoomRecordings::Player.new(data,renderer:->(clock) {RecordingTest::Audio.new([],clock)})
  info=GameRoomRecordings::Information.new(player)
  assert(info.perspectives.size==(game=='axel_pong' ? 4 : 2),'Perspective menu does not match the renderer capability')
  assert(info.message('scores').include?('Carol') && info.message('scores').include?('Dave'),'Team score omits a partner')
  player.close
end
puts 'PASS replay controls: contextual actions, plain keys, shared scores/serve, sets, doubles, exact seek state and repeated backward navigation to 0:0'
