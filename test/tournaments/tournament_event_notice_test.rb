require_relative '../support/tournament_public_ui'
require_relative '../support/proposal_notice_storage'
require_relative '../../lib/tournaments/tournament_event_notice'
require_relative '../../lib/tournaments/tournament_start_publisher'
require_relative '../../lib/tournaments/proposal_notice_journal'
include GameRoomTest::Assertions
T=GameRoomTournaments
now=1000
row=TournamentPublicUI.publication(11).merge('__insertion_user'=>'Alice','__insertion_time'=>900,'timezone'=>'UTC',
  'schema_version'=>2,'registration_opens_at'=>950,'registration_closes_at'=>0,
  'schedule_json'=>JSON.generate({'starts_at'=>0,'deadline_at'=>0,'windows'=>[]}))
row['settings_json']=JSON.generate(JSON.parse(row['settings_json']).merge('participant_limit'=>2))
value={'publication'=>row,'members'=>[{'account'=>'alice'}],'people'=>['alice']}
scope={'account'=>'alice','account_epoch'=>'one','backend_identity'=>'trial'}
make=->(kind){T::TournamentEventNotice.new(kind:kind,source:->(_ref){value},context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)}
reference={'author'=>'alice','publication_key'=>row['publication_key']}
service=make.call('registration')
notice=service.notices(publication_ref:reference,recipient:'Bob').first
assert_equal('bob',notice['recipient'])
assert_raises(T::ProposalNotice::Stale){service.notices(publication_ref:reference,recipient:'alice')}
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice.merge('title'=>'Forged'),sender:'alice',delivery:true)}
scope=scope.merge('account'=>'bob','account_epoch'=>'two')
recipient=make.call('registration')
assert(recipient.presentable?(recipient.inspect(metadata:notice,sender:'Alice')))
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Mallory')}
value['members']<<{'account'=>'carol'}
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Alice')}
value['members'].pop
value['people']<<'bob'
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Alice')}
scope=scope.merge('account'=>'alice','account_epoch'=>'three')
finished=make.call('finished')
value['results']={'completed'=>false,'completed_at'=>now}
value['winners']=['alice','bob']
value['places']={'alice'=>1,'bob'=>1}
value['team_mode']=false
assert_raises(T::ProposalNotice::Stale){finished.notices(publication_ref:reference)}
value['results']['completed']=true
notices=finished.notices(publication_ref:reference)
assert_equal(%w[alice bob],notices.map{|n|n['recipient']})
notice=notices.last
assert_equal(%w[alice bob],finished.inspect(metadata:notice,sender:'alice',delivery:true)['winners'])
state={'version'=>1,'operations'=>{}}
sent=[]
publisher=T::TournamentStartPublisher.new(service:finished,sender:-> {scope['account']},transaction:->(&block){block.call(state)},send:->(*args){sent<<args;true})
2.times{assert_equal(:sent,publisher.deliver(metadata:notice))}
assert_equal(1,sent.size,'Completed tournament was announced twice')
now+=T::TournamentEventNotice::LIFETIME
assert_equal(:sent,publisher.deliver(metadata:notice))
assert_equal(1,sent.size,'A permanent result was resent after seven days')
puts 'PASS tournament notices: explicit registration, full/already joined refusal, sender checks, real completion, ties and durable once-only delivery'

now=2_000_000
value['people']=['alice']
value['members']=[{'account'=>'alice'}]
scope=scope.merge('account'=>'alice','account_epoch'=>'four')
service=make.call('registration')
late=service.notices(publication_ref:reference,recipient:'bob').first
assert_equal(now+T::TournamentEventNotice::LIFETIME,service.inspect(metadata:late,sender:'alice',delivery:true)['expires_at'],
  'Invitation lifetime was counted from tournament creation instead of sending')

before={'schedule_id'=>'a'*64,'format'=>'groups_knockout'}
after={'schedule_id'=>'b'*64,'format'=>'knockout','knockout'=>{'round'=>1,'seeds'=>%w[alice bob carol dave],'players_per_match'=>2}}
value['transition']={'phase_id'=>before['schedule_id'],'phase'=>before,'next_phase'=>after,'completed_at'=>now}
phase=T::TournamentEventNotice.new(kind:'phase_finished',source:->(_ref,_phase_id){value},context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)
phase_notice=phase.notices(publication_ref:reference,phase_id:before['schedule_id']).first
assert_equal('Group stage',T::PhaseDescription.label(phase.inspect(metadata:phase_notice,sender:'alice',delivery:true)['phase']))
forged=phase_notice.merge('phase_id'=>'c'*64)
forged['event_id']=T::TournamentEventNotice.event_id(forged)
assert_raises(T::ProposalNotice::Stale){phase.inspect(metadata:forged,sender:'alice',delivery:true)}
state={'version'=>1,'operations'=>{}}
sent=[]
publisher=T::TournamentStartPublisher.new(service:phase,sender:-> {'alice'},transaction:->(&block){block.call(state)},send:->(*args){sent<<args;true})
2.times{assert_equal(:sent,publisher.deliver(metadata:phase_notice))}
assert_equal(1,sent.size,'Phase finish was announced twice')
replay=Marshal.load(Marshal.dump(after))
replay['schedule_id']='c'*64
source={'phase_history'=>[{'candidate'=>after,'view'=>{'progress_times'=>[now]}}],'candidate'=>replay}
assert_equal([],T::PhaseDescription.transitions(source),'Replay/series was announced as a new phase')
oversized=after.merge('matches'=>Array.new(1000){'unneeded schedule for notification'})
compact=T::PhaseDescription.label_data(oversized)
assert_equal(T::PhaseDescription.label(after),T::PhaseDescription.label(compact))
assert(!compact.key?('matches'),'Notice proof retained the complete schedule')
puts 'PASS registration lifetime and phase notices: authenticated phase link, forged phase rejection, durable delivery and no same-phase replay announcement'
