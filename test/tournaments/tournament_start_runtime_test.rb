require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/settings_widget'
require_relative '../support/native_notification_mute'
require_relative '../support/app_notification_models'
require_relative '../support/tournament_public_ui'
require File.join(EltenTestHost.root,'src/eapi/notificationgroups')
T=GameRoomTournaments
runtime=TestTaskRuntime.new('start-notice-runtime')
EltenGameRoom.define_singleton_method(:app_runtime){runtime}
module Programs
  class << self
    attr_accessor :notice_runtime
    def notification_program(_uuid);EltenGameRoom;end
    def runtime_for(_program);notice_runtime;end
  end
end
Programs.notice_runtime=runtime
module EltenAPI::NotificationService
  class << self
    attr_accessor :rows
    def active_notifications;rows || [];end
  end
end
GameRoomLocalization.boot(settings:{'interface_language'=>'pl','known_languages'=>['pl']})
scope={'account'=>'alice','account_epoch'=>'epoch-one','backend_identity'=>'trial'}
now=Time.utc(2026,10,15,18).to_i
publications=[11,12,13,14].map{|id|TournamentPublicUI.publication(id).merge('__insertion_user'=>'Alice','timezone'=>'UTC')}
reads=[]
source=->(reference){reads<<[Thread.current,Programs.current_runtime];
  {'complete'=>true,'participants'=>%w[alice bob],'publication'=>publications.find{|row|row['publication_key']==reference['publication_key']}}}
notices=publications.map do |publication|
  reference={'author'=>'alice','publication_key'=>publication['publication_key']}
  T::TournamentStartNotice.metadata({'version'=>2,'backend_identity'=>'trial','publication_ref'=>reference,'recipient'=>'alice',
    'title'=>publication['title'],'game'=>publication['game'],
    'event_id'=>Digest::SHA256.hexdigest(JSON.generate(['tournament-start-v1','trial',reference]))})
end
uuid=EltenGameRoom.server_app_uuid
make_row=->(id,notice){Struct.new(:id,:cat,:app_uuid,:date,:revoked,:payload,:alert,keyword_init:true).new(id:id,cat:'app',app_uuid:uuid,
  date:now,revoked:false,alert:'',payload:{'sender'=>'Alice','type'=>T::TournamentStartNotice::TYPE,'metadata'=>notice})}
rows=notices.each_with_index.map{|notice,index|make_row.call(index+1,notice)}
EltenAPI::NotificationService.rows=rows
settings=EltenGameRoom::DEFAULT_SETTINGS.merge('invitation_notifications'=>'nobody','invitation_sounds'=>true)
EltenGameRoom.define_singleton_method(:normalized_settings){settings}
sounds=[]
EltenGameRoom.define_singleton_method(:play_sound_from_asset){|name,**options|sounds<<[name,options]}
events=[]
$notifications_callback=->(event){events<<event}
begin
  assert(Programs.receive_app_notification(rows[0]).last.default_suppressed?,'Disconnected start reader exposed metadata')
  EltenGameRoom.configure_tournament_starts(source:source,context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)
  assert(!EltenGameRoom.respond_to?(:with_tournament_area),'Obsolete tournament-only mute wrapper remained')
  assert(Programs.receive_app_notification(rows[0]).last.default_suppressed?,'Unverified start was announced')
  EltenGameRoom.tournament_starts_tick
  worker=EltenGameRoom.instance_variable_get(:@tournament_start_inbox).instance_variable_get(:@worker)
  wait_background_work(worker) or raise 'Start verification did not finish'
  EltenGameRoom.tournament_starts_tick
  assert_equal(1,events.size,'Verified start was not presented')
  assert_equal([['notice',{volume:1.0}]],sounds,'Start sound did not use the notification volume')
  duplicate=make_row.call(99,notices[0])
  assert(Programs.receive_app_notification(duplicate).last.default_suppressed?,'Duplicate start bypassed verification')
  EltenGameRoom.tournament_starts_tick
  assert_equal(1,reads.size,'Duplicate start caused another read')
  assert_equal(1,events.size,'Duplicate start caused another announcement')
  settings['invitation_sounds']=false
  Programs.receive_app_notification(rows[1])
  EltenGameRoom.tournament_starts_tick
  wait_background_work(worker) or raise 'Start verification did not finish'
  EltenGameRoom.tournament_starts_tick
  assert(events.size==2 && events[1]['type']==T::TournamentStartNotice::TYPE,'Second start not presented')
  assert(events[1]['alert'].include?(publications[1]['title']),'Real tournament title missing')
  assert(events[1]['sound'].nil? && sounds.size==1,'Sound preference ignored')
  assert(reads.first[0]!=Thread.current && reads.first[1]==runtime,'Verification ran on UI or wrong runtime')
  Programs.receive_app_notification(rows[2])
  EltenGameRoom.tournament_starts_tick
  wait_background_work(worker) or raise 'Raced verification did not finish'
  settings['invitation_sounds']=true
  EltenGameRoom.tournament_starts_tick
  assert(!Programs.map_app_notification(rows[2]).last.default_suppressed?,'Verified notice unexpectedly muted')
  10.times{EltenGameRoom.tournament_starts_tick}
  assert_equal(3,events.size)
  assert_equal(3,reads.size)
  assert_equal(2,sounds.size,'Idle ticks repeated the notification sound')
  GameRoomTest::NativeNotificationMute.with_mode(1) do
    Programs.receive_app_notification(rows[3])
    EltenGameRoom.tournament_starts_tick
    wait_background_work(worker) or raise 'Do-not-disturb verification did not finish'
    EltenGameRoom.tournament_starts_tick
  end
  EltenGameRoom.tournament_starts_tick
  assert_equal(3,events.size,'Do not disturb was ignored')
  assert_equal(2,sounds.size,'Do not disturb played or postponed the sound')
  original_text=events[1]['alert']
  reader=Object.new.extend(NotificationGroups)
  label=->(row) do
    presentation=Programs.map_app_notification(row).last
    group=NotificationGroups::NotificationGroup.new(cat:'app',category:'Power Games',presentation:presentation)
    [presentation,reader.group_label(group)]
  end
  before_reads=reads.size
  presentation,listed=label.call(rows[1])
  assert_equal('Power Games: '+original_text,listed,'List description differs from the delivered text')
  assert_equal(2,sounds.size,'List rendering replayed a notification sound')
  now+=1800
  assert_equal('Power Games: '+original_text,label.call(rows[1]).last,'Expired event lost its description')
  EltenGameRoom.configure_tournament_starts(source:source,context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)
  assert_equal('Power Games: '+original_text,label.call(rows[1]).last,'Cold runtime lost the recorded event description')
  assert(label.call(rows[1]).first.default_suppressed?,'Description alone authorized a new announcement')
  assert_equal(before_reads,reads.size,'List rendering performed a server read')
  %w[en pl cs es ru].each do |language|
    GameRoomLocalization.boot(settings:{'interface_language'=>language,'known_languages'=>[language]})
    text=label.call(rows[1]).last
    assert(text.include?(publications[1]['title']),'Localized history lost the original tournament title')
  end
  forged=make_row.call(90,notices[1])
  forged.payload=forged.payload.merge('sender'=>'Mallory')
  assert(!label.call(forged).last.include?(publications[1]['title']),'Foreign sender supplied a start description')
  scope['account_epoch']='new-epoch'
  assert(Programs.map_app_notification(rows[1]).last.default_suppressed?,'Old account epoch stayed visible')
  GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
  now-=1800
  phase={'schedule_id'=>'a'*64,'format'=>'groups_knockout'}
  next_phase={'format'=>'knockout','knockout'=>{'round'=>1,'seeds'=>%w[alice bob],'players_per_match'=>2}}
  event_reads=[]
  event_source=->(reference,kind,phase_id) do
    event_reads<<[kind,Thread.current,Programs.current_runtime]
    {'publication'=>publications.first,'people'=>%w[alice bob],'members'=>[],
      'transition'=>{'phase_id'=>phase_id,'phase'=>phase,'next_phase'=>next_phase,'completed_at'=>now},
      'results'=>{'completed'=>true,'completed_at'=>now},'winners'=>['alice'],
      'places'=>{'alice'=>1,'bob'=>2},'team_mode'=>false}
  end
  EltenGameRoom.configure_tournament_events(source:event_source,context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)
  %w[phase_finished finished].each_with_index do |kind,index|
    service=EltenGameRoom.instance_variable_get(:@tournament_event_services).fetch(kind)
    reference={'author'=>'alice','publication_key'=>publications.first['publication_key']}
    notice=service.notices(publication_ref:reference,phase_id:kind=='phase_finished' ? phase['schedule_id'] : nil).first
    row=make_row.call(101+index,notice)
    row.payload=row.payload.merge('type'=>T::TournamentEventNotice::TYPES.fetch(kind))
    EltenAPI::NotificationService.rows<<row
    before=events.size
    before_sounds=sounds.size
    assert(Programs.receive_app_notification(row).last.default_suppressed?,'Unverified phase/result was announced')
    EltenGameRoom.tournament_starts_tick
    event_worker=EltenGameRoom.instance_variable_get(:@tournament_event_inboxes).fetch(kind).instance_variable_get(:@worker)
    wait_background_work(event_worker) or raise 'Event verification did not finish'
    EltenGameRoom.tournament_starts_tick
    assert_equal(before+1,events.size)
    assert_equal(before_sounds+1,sounds.size)
    presentation=Programs.map_app_notification(row).last
    assert_equal(kind=='phase_finished' ? :open_tournament_phase_standings : :open_tournament_standings,presentation.action)
    assert(presentation.body.include?(kind=='phase_finished' ? 'Next: Final.' : 'Winner: alice'),'Missing phase/winner description')
    assert(presentation.body.include?('Your place: 1.'),'Final notice omitted personal place') if kind=='finished'
    count=event_reads.size
    5.times{Programs.receive_app_notification(row);EltenGameRoom.tournament_starts_tick}
    assert_equal(count,event_reads.size,'Duplicate notice repeated source reads')
    assert_equal(before+1,events.size,'Duplicate event was announced')
    assert(event_reads.last[1]!=Thread.current && event_reads.last[2]==runtime,'Event verification lost its owning background runtime')
    if kind=='finished'
      expected={'en'=>'Your place: 1.','pl'=>'Twoje miejsce: 1.','cs'=>'Vaše umístění: 1.',
        'es'=>'Tu puesto: 1.','ru'=>'Ваше место: 1.'}
      expected.each do |language,place_text|
        GameRoomLocalization.boot(settings:{'interface_language'=>language,'known_languages'=>[language]})
        assert(Programs.map_app_notification(row).last.body.include?(place_text),"Missing personal result translation: #{language}")
      end
      GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})
      EltenGameRoom.configure_tournament_starts(source:source,context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)
      EltenGameRoom.configure_tournament_events(source:->(*) { raise T::Publication::Invalid,:missing_publication },context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)
      text=Programs.map_app_notification(row).last.body
      assert(text.include?('Your place: 1.') && text.include?('Winner: alice'),'Cold history lost its recorded result')
      before=events.size
      Programs.receive_app_notification(row)
      EltenGameRoom.tournament_starts_tick
      cold_worker=EltenGameRoom.instance_variable_get(:@tournament_event_inboxes).fetch('finished').instance_variable_get(:@worker)
      wait_background_work(cold_worker) or raise 'Historical verification did not finish'
      EltenGameRoom.tournament_starts_tick
      assert_equal(before,events.size,'Unverifiable history was announced as a fresh result')
      assert(EltenGameRoom.game_room_notification_current?(Programs.app_notification_from(row)),'Retained historical result was discarded')
      assert(Programs.map_app_notification(row).last.body.include?('Your place: 1.'),'Tournament retention erased the recorded personal result')
    end
  end
ensure
  EltenGameRoom.stop_tournament_starts
  $notifications_callback=nil
  runtime.close
end
puts 'PASS native start-notice runtime: no tournament-area muting, one delivery per event, actual title/game, finite owning-runtime read, enabled/disabled sound, unchanged list text, epoch/cleanup guards and no polling'
