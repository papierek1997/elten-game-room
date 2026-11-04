require_relative '../support/recordings'
require_relative '../support/audio_ball_point_audio'
require_relative '../../lib/recordings/renderer'

def cue_frame(time, scene, scores: [0,0])
  {'t'=>time,'kind'=>'frame','data'=>RecordingTest.context.merge(
    'snapshot'=>scene,'generation'=>0,'paused'=>false,'scores'=>scores)}
end

%w[prepare stop_ball goal point].each do |method|
  now=0.0
  program=nil
  meta=GameRoomRecordings::Document.metadata(game:'audio_ball',game_name:'Audio Ball',players:%w[Alice Bob])
  meta['duration_ms']=1000
  previous={'phase'=>method=='prepare' ? 'over' : 'flying','position'=>10.0,
    'turn'=>1,'shot'=>'up','goal'=>method=='prepare' ? 1 : nil,'server'=>0}
  boundary=%w[goal point].include?(method)
  prepared=previous.merge('phase'=>boundary ? 'over' : 'prepared','turn'=>2,'shot'=>nil,'goal'=>boundary ? 1 : nil)
  args,keys = case method
  when 'goal' then [[],{'viewer'=>0,'winner'=>1}]
  when 'point' then [[[0,1]],{'viewer'=>0,'winner'=>1,'sets'=>[0,0],'set_finished'=>false,'finished'=>false,'goal_at'=>0.1}]
  else [[0],{'viewer'=>0}]
  end
  value=GameRoomRecordings::Document.header(meta).merge('timeline'=>[
    cue_frame(0,previous),
    {'t'=>100,'kind'=>'audio','data'=>{'method'=>method,'args'=>args,'kwargs'=>keys}},
    cue_frame(140,prepared,scores:boundary ? [0,1] : [0,0])
  ])
  player=GameRoomRecordings::Player.new(value,clock:-> {now},renderer:->(clock) {
    program=AudioBallPointTest::Program.new
    program.define_singleton_method(:now) {clock.call}
    GameRoomRecordings::Renderer.new(GameRoomAudioBall::Audio.new(program,clock:clock))
  })
  player.play
  now=0.05;player.tick
  now=0.1;player.tick
  cue=boundary ? nil : program.sounds[method=='prepare' ? 'audio_ball_prepare' : 'audio_ball_stopped']
  RecordingTest.assert(cue.plays==1 && cue.playing?, "#{method}: the previous frame immediately cut the new cue") if cue
  RecordingTest.assert(!program.sounds['audio_ball_up'].playing?, "#{method}: the previous flight resumed during the cue")
  [0.14,0.2].each { |time| now=time;player.tick }
  RecordingTest.assert(cue.plays==1 && cue.playing?, "#{method}: the following frame lost or restarted the cue") if cue
  [100,120,140].each do |position|
    player.seek(position)
    player.play
    RecordingTest.assert(!program.sounds['audio_ball_up'].playing?, "#{method}: seeking/resuming revived the obsolete flight")
    now+=0.06;player.tick
    RecordingTest.assert(!program.sounds['audio_ball_up'].playing?, "#{method}: playback after a gap seek revived the obsolete flight")
  end
  player.close
end
puts 'PASS Audio Ball replay boundaries: preparation/stop cues, goals, scores and exact/gap seeks never render an obsolete flight'
