require_relative '../support/recordings'
require_relative '../support/pong_audio'
require_relative '../../lib/recordings/renderer'
include RecordingTest

# The live client asks for the opening cue again after each rally. The live
# renderer guards it, so these are not three audible presentation events.
Dir.mktmpdir('pg-recording-opening-') do |directory|
  now=0.0
  capture=GameRoomRecordings::Capture.new(program:RecordingTest::Program.new(directory),
    metadata:GameRoomRecordings::Document.metadata(game:'axel_pong',game_name:'Axel Pong',players:%w[Alice Bob]),
    clock:-> {now},context:-> {RecordingTest.context},work:RecordingTest::Work.new)
  sounds=PongAudioProgram.new
  audio=GameRoomPong::Audio.new(sounds,clock:-> {now})
  audio.load
  client=Struct.new(:recording).new(capture)
  tap=GameRoomRecordings::AudioTap.new(audio,client)
  3.times do
    tap.reset
    tap.update(RecordingTest.scene,viewer:0,paused:false)
    tap.start_match
    now+=1
  end
  value=capture.snapshot.document
  assert(sounds.sounds['pong_gamestart'].plays==1,'Live opening cue was repeated')
  count=value['timeline'].count { |row| row.dig('data','method')=='start_match' }
  assert(count==1,"Recorder retained #{count} opening cues for one audible cue")
ensure
  audio&.close
  capture&.close
end

# A passive file may contain those repeated calls. Seeking creates a fresh
# renderer, which must not mistake a later request for a new match beginning.
value=RecordingTest.document
frame=value['timeline'].first['data']
value['timeline']=[
  {'t'=>0,'kind'=>'frame','data'=>frame},
  {'t'=>100,'kind'=>'audio','data'=>{'method'=>'start_match','args'=>[],'kwargs'=>{}}},
  {'t'=>200,'kind'=>'audio','data'=>{'method'=>'reset','args'=>[],'kwargs'=>{}}},
  {'t'=>250,'kind'=>'frame','data'=>frame.merge('rally'=>1,'generation'=>1)},
  {'t'=>400,'kind'=>'audio','data'=>{'method'=>'start_match','args'=>[],'kwargs'=>{}}},
  {'t'=>600,'kind'=>'audio','data'=>{'method'=>'start_match','args'=>[],'kwargs'=>{}}}]
programs=[]
now=0.0
player=GameRoomRecordings::Player.new(value,clock:-> {now},renderer:->(clock) {
  program=PongAudioProgram.new;programs<<program
  audio=GameRoomPong::Audio.new(program,clock:clock);audio.load
  GameRoomRecordings::Renderer.new(audio)
})
player.play
now=0.15;player.tick
assert(programs.last.sounds['pong_gamestart'].plays==1,'The actual recorded opening cue is missing')
player.seek(300)
now+=0.5;player.tick
assert(programs.last.sounds['pong_gamestart'].plays==0,'Seeking replayed Game on after the opening')
player.seek(0)
now+=0.7;player.tick
assert(programs.last.sounds['pong_gamestart'].plays==1,'Replaying from zero lost or repeated the opening cue')
prepared=GameRoomRecordings::Prepared.copy(value)
assert(prepared.actions.length==1,'Repeated opening calls became phantom navigation actions')
player.close
puts 'PASS opening cue: recorded once, repeated calls ignored after seek, actual beginning preserved and no phantom action markers'
