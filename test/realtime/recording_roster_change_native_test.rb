require_relative '../support/background_help_native'
require_relative '../support/recordings'
require_relative '../../lib/recordings/ui'
require_relative '../../lib/axel_pong/client'
require_relative '../../games/axel_pong'

class RecordingRosterNativeDriver
  def initialize; @serial=0; end
  def tick(_)
    @serial+=1
    EltenAPI::KeyboardState.update(raw_state:"\0"*256,events:[],now:@serial*0.01,
      pressed_implies_held:false,synthesize_repeats:false)
    $input_frame_serial=$input_frame_serial.to_i+1
    $keyboard_state_frame_serial=$input_frame_serial
    $keyboard_state_frame_thread=Thread.current
    $activecontrols=[]
  end
  def frame(form)
    tick(form)
    $activecontrols=[form,form.fields[form.index]]
    form.update
  end
end

class RecordingRosterProgram < RecordingTest::Program
  attr_reader :captures
  def initialize(root); super; @captures=[]; end
  def recording_library; nil; end
  def create_game_recording(game,players:,options:,viewer:,complete_start:,clock:,context:)
    names=players.map { |name| GameRoomContent.utf8(GameRoomParticipants.display_name(name)) }
    meta=GameRoomRecordings::Document.metadata(game:game.recording_audio_kind,game_name:game.name,
      players:names,options:options,seat:players.index(viewer),complete_start:complete_start)
    capture=GameRoomRecordings::Capture.new(program:self,metadata:meta,clock:clock,
      context:context,work:RecordingTest::Work.new)
    @captures << capture
    capture
  end
end

class RecordingRosterChannel
  attr_accessor :required_members
  def configure_p2p(_); end
  def enable_events(*,**); end
  def close; end
end

class RecordingRosterMouse
  def reset_rally; end
  def suspend; end
end

class RecordingRosterAudio < RecordingTest::Audio
  def suspend; end
end

driver=RecordingRosterNativeDriver.new
$native_tutorial_driver=driver
GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
R=GameRoomRecordings
repository=Object.new
def repository.players_for(session); session.fetch('__players'); end
def repository.actor_of(event,_session); event.fetch('actor'); end
def repository.event_id(event); event.fetch('id'); end

# Actual realtime client's normal before_wait adopts each normal model replay.
# The clock/roster input is synthetic: this is not a live control ACK, network
# membership trial, physical-key test or an audio-listening assertion.
Dir.mktmpdir('pg-roster-native-') do |directory|
  program=RecordingRosterProgram.new(directory)
  [false,true].each do |doubles|
    now=0.0
    game=GameRoomGames::AxelPong.new
    original=doubles ? %w[Alice Bob Carol Dave] : %w[Alice Bob]
    replacement=doubles ? %w[Alice Erin Carol Dave] : %w[Alice Erin]
    options=game.normalize_options('team_size'=>doubles ? 2 : 0)
    options['team_seats']=[0,0,1,1] if doubles
    session={'__players'=>original,'__table_owner'=>'Alice','__insertion_user'=>'Alice',
      'options'=>JSON.generate(options)}
    client=GameRoomPong::Client.new(program,game,clock:-> {now},
      channel_factory:->(**) {RecordingRosterChannel.new},audio:RecordingRosterAudio.new([],-> {now}),
      mouse:RecordingRosterMouse.new)
    client.bind_screen(session_id:1,table_id:1,owner:'Alice',viewer:'Alice',members:-> {original})
    client.before_wait(game.replay(session,[],repository),'Alice')
    capture=client.recording
    capture.frame(client.snapshot,paused:true,force:true)
    now=1.0
    client.before_wait(game.replay(session.merge('__players'=>replacement),[],repository),'Alice')
    RecordingTest.assert(client.recording.equal?(capture),'Roster change recreated the capture')
    capture.frame(client.snapshot,paused:true,force:true)
    now=2.0
    value=R::Document.parse(JSON.generate(capture.snapshot.document))
    RecordingTest.assert(value['metadata']['players']==original,'Header no longer describes the start')
    RecordingTest.assert(value['timeline'].last['data']['players']==replacement,'before_wait roster was not captured')

    # Bot IDs must be rendered exactly like the header, not leaked as labels.
    client.before_wait(game.replay(session.merge('__players'=>replacement.dup.tap { |rows| rows[1]='bot:1:1' }),[],repository),'Alice')
    RecordingTest.assert(client.recording_context['players'][1]=='Computer 1','Frame roster uses internal bot IDs')

    playback_clock=0.0
    player=R::Player.new(value,clock:-> {playback_clock},renderer:->(clock) {RecordingTest::Audio.new([],clock)})
    player.seat=1
    information=R::Information.new(player)
    controls=R::Controls.new(player,position_text:->(_) {''},speaker:->(_) {})
    form=R::UI.new(program).send(:player_form,player)
    list=form.fields.fetch(1)
    form.index=1
    form.focus
    before=list.options.dup
    SpeechOutput.reset
    player.play
    timer=GameRoomRealtime::Timer.new(clock:-> {playback_clock}) {player.tick}
    form.add_timer(timer)
    playback_clock=1.1
    driver.frame(form)
    RecordingTest.assert(information.players==replacement,'Natural playback kept the starting names')
    RecordingTest.assert(list.options==replacement,'Active native list did not follow the current frame')
    RecordingTest.assert(list.index==1 && player.seat==1 && form.index==1,'Roster refresh moved seat or focus')
    RecordingTest.assert(SpeechOutput.calls.empty?,'Roster refresh repeated speech')
    expected_server=replacement[player.frame['snapshot']['server']]
    RecordingTest.assert(information.message('server').include?(expected_server),'Server information uses an old name')
    RecordingTest.assert(controls.operations.none? { |row| row[1].include?('Bob') },'Context operations use stale names')
    if doubles
      RecordingTest.assert(information.score_labels.first=='Team A: Alice and Erin','Team labels use old partners')
    end

    # Covered/background playback updates data only, never a native control.
    player.seek(0)
    driver.frame(form)
    RecordingTest.assert(list.options==before,'Backward seek did not restore the native roster')
    $activecontrols=[]
    player.play
    playback_clock=2.2
    player.tick
    RecordingTest.assert(information.players==replacement && list.options==before,
      'Background playback failed to advance data or mutated native controls')
    driver.frame(form)
    RecordingTest.assert(list.options==replacement,'Returning UI did not catch up with the current roster')
    player.seek(0)
    driver.frame(form)
    RecordingTest.assert(list.options==before && player.seat==1,'Backward seek lost initial roster or seat')
    player.seek(1000)
    driver.frame(form)
    RecordingTest.assert(list.options==replacement && list.index==1,'Forward seek lost current roster or seat')
    SpeechOutput.reset
    3.times {driver.frame(form)}
    RecordingTest.assert(SpeechOutput.calls.empty? && form.index==1,'Unchanged frame refreshed native speech/focus')
    form.delete_timer(timer)
    player.close
    client.close
    capture.close

    # Audio Ball uses team perspectives and the same current-roster formatter.
    if doubles
      ball=R::Document.copy(value)
      ball['metadata']['game']='audio_ball'
      ball['timeline'].each do |row|
        next unless row['kind']=='frame'
        row['data']['snapshot']={'phase'=>'waiting','position'=>0.0,'turn'=>0,'shot'=>nil,'server'=>1,'goal'=>nil}
      end
      ball_player=R::Player.new(ball,renderer:->(clock) {RecordingTest::Audio.new([],clock)})
      ball_player.seek(1000)
      ball_info=R::Information.new(ball_player)
      RecordingTest.assert(ball_info.perspectives==[[0,'Alice, Erin'],[2,'Carol, Dave']],'Audio Ball perspective labels use old partners')
      RecordingTest.assert(ball_info.message('server')=='Erin serves to Dave.','Audio Ball server/receiver use an old roster')
      ball_player.close
    end
  end
  RecordingTest.assert(program.captures.size==2,'A replacement created an extra capture')
end

normal=RecordingTest.document
RecordingTest.assert(R::Document.parse(JSON.generate(normal))==normal,'Normal recording round trip changed')
legacy=R::Document.copy(normal)
legacy['timeline'].select { |row| row['kind']=='frame' }.each { |row| row['data'].delete('players') }
player=R::Player.new(legacy,renderer:->(clock) {RecordingTest::Audio.new([],clock)})
player.seek(1400)
RecordingTest.assert(R::Information.new(player).players==%w[Alice Bob],'Optional roster has no header fallback')
player.close
[nil,'Alice',[],%w[Alice Bob Carol],['Alice',1],['Alice',''],['Alice',"B\0ob"],['Alice','B'*257]].each do |invalid|
  malformed=R::Document.copy(normal)
  malformed['timeline'][0]['data']['players']=invalid
  RecordingTest.refuses {R::Document.parse(JSON.generate(malformed))}
end
puts 'PASS native recording roster: same-client before_wait/capture, display names, current server/teams/menu/list, play/seek, silent seat/focus preservation, optional strict roster and header fallback'
