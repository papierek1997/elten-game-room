require_relative '../support/recordings'
require_relative '../support/pong_audio'
require_relative '../../lib/recordings/renderer'
require_relative '../../lib/recordings/information'

module PongRecordingValidationTest
  module_function

  def document(players: 2)
    value = RecordingTest.document
    value['timeline'].select! { |event| event['kind']=='frame' }
    if players==4
      value['metadata']['players']=%w[Alice Bob Carol Dave]
      value['timeline'].each do |event|
        event['data']['players']=value['metadata']['players'].dup
        event['data']['teams']=[0,0,1,1]
        event['data']['snapshot'].merge!('p'=>[15.0]*4,'shields'=>[0]*4,'edges'=>[0]*4,
          'teams'=>[0,0,1,1],'receiver'=>2)
      end
    end
    value
  end

  def rejects_before_renderer(value)
    calls=0
    RecordingTest.refuses do
      GameRoomRecordings::Player.new(value,renderer:->(_clock) { calls+=1; raise 'Invalid document reached renderer' })
    end
    RecordingTest.assert(calls.zero?,'Invalid imported document created playback resources')
    RecordingTest.refuses { GameRoomRecordings::Prepared.load(JSON.generate(value)) }
  end
end

checks=0
required=GameRoomPong::SnapshotEffects::PLAYER_REQUIRED
[2,4].each do |players|
  required.each do |kind|
    [nil,-1,players,players+5,0.5,'0',true].each do |owner|
      value=PongRecordingValidationTest.document(players:players)
      value['timeline'].first['data']['snapshot']['fx']=[[1,kind,owner,15.0,20.0]]
      PongRecordingValidationTest.rejects_before_renderer(value)
      checks+=1
    end
  end
  # Optional owners must still belong to this actual roster when provided.
  %w[step edge wall invisible goal future_ignored_cue].each do |kind|
    value=PongRecordingValidationTest.document(players:players)
    value['timeline'].first['data']['snapshot']['fx']=[[1,kind,players,15.0,20.0]]
    PongRecordingValidationTest.rejects_before_renderer(value)
    checks+=1
  end

  # Real passive Player and Pong Audio, every perspective: legitimate contact
  # indices and ownerless non-contact effects must still render and seek.
  value=PongRecordingValidationTest.document(players:players)
  first=GameRoomRecordings::Document.copy(value['timeline'].first)
  events=[first]
  sequence=0
  GameRoomPong::SnapshotEffects::KINDS.each do |kind|
    owners=required.include?(kind) ? (0...players).to_a : [nil,*(0...players).to_a]
    owners.each do |owner|
      sequence+=1
      event=GameRoomRecordings::Document.copy(first)
      event['t']=sequence*10
      event['data']['snapshot']['fx']=[[sequence,kind,owner,15.0,20.0]]
      events << event
    end
  end
  value['timeline']=events
  GameRoomRecordings::Document.validate(value)
  players.times do |seat|
    now=0.0
    program=PongAudioProgram.new
    player=GameRoomRecordings::Player.new(value,clock:-> {now},renderer:->(clock) {
      audio=GameRoomPong::Audio.new(program,clock:clock)
      audio.load
      GameRoomRecordings::Renderer.new(audio)
    })
    begin
      player.seat=seat
      player.play
      now=2.0
      player.tick
      message=GameRoomRecordings::Information.new(player).message('server')
      RecordingTest.assert(message.include?('Alice'),'Valid server announcement was lost')
      RecordingTest.assert(message.include?('Carol'),'Valid doubles receiver was lost') if players==4
      player.seek(0)
      player.play
      now+=2.0
      player.tick
    ensure
      player.close
    end
    RecordingTest.assert(program.sounds.values.all?(&:closed),'Playback did not release its sound handles')
  end
end

[nil,-1,4,99,1.5,'2',false].each do |receiver|
  value=PongRecordingValidationTest.document(players:4)
  value['timeline'].first['data']['snapshot']['receiver']=receiver
  PongRecordingValidationTest.rejects_before_renderer(value)
  checks+=1
end
%w[axel_pong audio_ball].each do |game|
  [2,4].each do |players|
    [true,false,{},[],[0],['0',1],[0,1.0],[0,0],[1,0],[0,0,1,nil],[0,0,1,'1'],[0,0,1,1.0],[0,0,0,1]].each do |teams|
      %w[frame snapshot].each do |location|
        value=PongRecordingValidationTest.document(players:players)
        if game=='audio_ball'
          value['metadata']['game']=game
          value['timeline'].each do |event|
            event['data']['snapshot']={'phase'=>'flying','position'=>10.0,'turn'=>1,'shot'=>'up','server'=>0,'goal'=>nil}
          end
        end
        frame=value['timeline'].first['data']
        (location=='frame' ? frame : frame['snapshot'])['teams']=teams
        PongRecordingValidationTest.rejects_before_renderer(value)
        checks+=1
      end
    end
  end
end

# Audio Ball normally has no fx, but shared indexing/rendering still reads that
# field when provided. It cannot bypass the passive effect shape contract.
[nil,true,false,{},'effect',[nil],[[1]],[[1,'hit',nil,15,20]],[[1,'wall',nil,'x',20]]].each do |effects|
  value=PongRecordingValidationTest.document
  value['metadata']['game']='audio_ball'
  value['timeline'].each do |event|
    event['data']['snapshot']={'phase'=>'flying','position'=>10.0,'turn'=>1,'shot'=>'up','server'=>0,'goal'=>nil}
  end
  value['timeline'].first['data']['snapshot']['fx']=effects
  PongRecordingValidationTest.rejects_before_renderer(value)
  checks+=1
end

# Valid snapshot-only team layouts must drive audio events and readouts in the
# same way. The former Player used a different hard-coded layout when the
# optional frame-level mapping was absent (Information already preferred scene).
[[0,1],[0,0,1,1],[0,1,1,0]].each do |teams|
  value=PongRecordingValidationTest.document(players:teams.size)
  value['timeline'].each do |event|
    event['data'].delete('teams')
    event['data']['snapshot']['teams']=teams
  end
  value['timeline'] << {'t'=>2000,'kind'=>'audio',
    'data'=>{'method'=>'goal','args'=>[],'kwargs'=>{'viewer'=>0,'winner'=>1}}}
  teams.each_index do |seat|
    now=0.0
    calls=[]
    player=GameRoomRecordings::Player.new(value,clock:-> {now},renderer:->(clock) { RecordingTest::Audio.new(calls,clock) })
    begin
      player.seat=seat
      RecordingTest.assert(GameRoomRecordings::Information.new(player).teams==teams,'Readout lost snapshot team mapping')
      player.play
      now=2.1
      player.tick
      goal=calls.reverse.find { |row| row[0]==:goal }
      RecordingTest.assert(goal && goal[3][:viewer]==teams[seat],'Audio event used a different team mapping from the frame')
    ensure
      player.close
    end
  end
end
puts "PASS #{checks} malformed audio recording cases rejected before rendering; valid singles/doubles effects, perspectives, readouts, seek and sound cleanup"
