require_relative '../support/recordings'
include RecordingTest
R=GameRoomRecordings
Dir.mktmpdir('pg-recording-capture-') do |temporary|
  now=100.0
  program=RecordingTest::Program.new(temporary)
  meta=R::Document.metadata(game:'axel_pong',game_name:'Axel Pong',players:%w[Alice Bob])
  capture=R::Capture.new(program:program,metadata:meta,clock:-> {now},context:-> {context},work:RecordingTest::Work.new)
  150.times do |i|
    now=100+i*0.05
    state=scene
    state['tick']=i
    capture.frame(state,paused:false)
    state['p'][0]=999
  end
  capture.audio('point',[[1,0]],{viewer:0,winner:0,finished:true,goal_at:now-1})
  saved=capture.snapshot
  # Appending later frames must not mutate an already selected export boundary.
  now+=1
  capture.frame(scene,paused:true)
  value=saved.document
  assert(value['timeline'].count { |row| row['kind']=='frame' }==150)
  assert(value['timeline'].first['data']['snapshot']['p'][0]==25.0,'Capture retained a mutable engine snapshot')
  assert(value['timeline'].last['data']['kwargs']['goal_at']<8,'Absolute process clock leaked into playback')
  assert(value['metadata']['complete_end']==true)
  assert(value['metadata']['duration_ms']>=value['timeline'].last['t']+10_000,'Final score recordings were cut off when saving immediately')
  capture.close
end
now=0.0
calls=[]
player=R::Player.new(document,clock:-> {now},renderer:->(clock) { RecordingTest::Audio.new(calls,clock) })
assert(!player.playing)
player.play
now=1.05;player.tick
assert(calls.count { |row| row[0]==:goal }==1)
assert(calls.find { |row| row[0]==:goal }[1]==1.0)
player.pause
now+=5;player.tick
assert(player.position==1050,'A paused recording advanced')
goals=calls.count { |row| row[0]==:goal }
player.seek(1300)
assert(calls.count { |row| row[0]==:goal }==goals,'Seeking replayed historical goal cues')
player.seat=1
player.seek(900);player.play
now+=0.4;player.tick
assert(calls.reverse.find { |row| row[0]==:goal }[3][:viewer]==1)
player.seek(0);player.navigate(:point,1)
assert(player.position==1199,'Point navigation skipped its own audible event')
player.speed=2.0
now+=0.5;player.tick
assert(player.position==2199)
player.close

prepared=R::Prepared.load(JSON.generate(document))
assert(prepared.frozen? && prepared.document.frozen? && prepared.frames.frozen?, 'Prepared indexes are mutable')
assert(prepared.document['timeline'].first['data']['snapshot'].frozen?, 'Prepared frame retained mutable nested state')
assert(prepared.points.length==1 && prepared.actions.length>=2, 'Prepared indexes omitted events')
assert(prepared.markers.frozen? && prepared.markers.values.all?(&:frozen?), 'Navigation markers were not prepared immutably off the UI thread')
assert(prepared.markers[:point]==[0,1200], 'Point navigation has no opening boundary')
player=R::Player.new(prepared,clock:-> {now},renderer:->(clock) { RecordingTest::Audio.new([],clock) })
player.seek(0);player.navigate(:point,1)
assert(player.position==1199, 'Prepared point navigation differs from parsed playback')
player.close

# A passive recorder can fail without changing the live renderer's calls.
faulty=Object.new
def faulty.recording; raise IOError,'Temporary recording failure'; end
calls=[]
tap=R::AudioTap.new(RecordingTest::Audio.new(calls,-> {0}),faulty)
tap.start_match
tap.update(scene,viewer:0,paused:false)
tap.tick
raise 'Recorder failure blocked live sound' unless calls.map(&:first)==%i[start_match update tick]
puts 'PASS audio capture/player: immutable background chunks, export boundary, virtual clocks, offline pause/seek/speed/perspective and exact event replay'
