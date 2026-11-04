require_relative '../support/tournament_public_ui'
require_relative '../../lib/tournaments/proposal_notice_inbox'
require_relative '../../lib/tournaments/tournament_event_notice'
require_relative '../support/tournament_notice_worker'
include GameRoomTest::Assertions
T=GameRoomTournaments
now=1000
row=TournamentPublicUI.publication(11).merge('__insertion_user'=>'Alice','__insertion_time'=>900,'timezone'=>'UTC',
  'schema_version'=>2,'registration_opens_at'=>950,'registration_closes_at'=>0,
  'schedule_json'=>JSON.generate({'starts_at'=>0,'deadline_at'=>0,'windows'=>[]}))
reference={'author'=>'alice','publication_key'=>row['publication_key']}
scope={'account'=>'alice','account_epoch'=>'one','backend_identity'=>'trial'}
value={'publication'=>row,'members'=>[{'account'=>'alice'}],'people'=>['alice'],
  'invitations'=>[{'account'=>'bob','status'=>'pending','operation_key'=>'invite-one','invited_at'=>990}],
  'results'=>{'completed'=>true,'completed_at'=>990},'winners'=>['Alice'],
  'places'=>{'alice'=>1,'bob'=>2},'team_mode'=>false}
reads=0
source_error=nil
make=->(kind) { T::TournamentEventNotice.new(kind:kind,source:->(_ref) { reads+=1;raise source_error if source_error;value },context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG) }
sent=make.call('registration').notices(publication_ref:reference,recipient:'Bob',invitation_key:'invite-one').first
scope=scope.merge('account'=>'bob','account_epoch'=>'two')
service=make.call('registration')
worker=TournamentNoticeTestWorker.new
inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,metadata:T::TournamentEventNotice.method(:metadata))
assert(inbox.receive(id:1,metadata:sent,sender:'Alice'))
inbox.tick
assert_equal(1,inbox.tick.size,"Registration verification failed: #{inbox.last_error&.message}")
assert_equal(0,inbox.verified(1).first['expires_at'])
value['invitations'].first['status']='declined'
inbox.refresh(reference)
inbox.tick; inbox.tick
assert(inbox.dismissed?(sent['event_id']),'Resolved permanent registration invitation remained current')
assert_equal(nil,inbox.verified(1))
assert_equal([1],inbox.take_revoked)
calls=reads
20.times { inbox.tick }
assert_equal(calls,reads,'Idle ticks started notification polling')

value['invitations'].first['status']='pending'
retry_clock=0
worker=TournamentNoticeTestWorker.new
inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,metadata:T::TournamentEventNotice.method(:metadata),clock:-> {retry_clock})
assert(inbox.receive(id:3,metadata:sent,sender:'Alice'))
inbox.tick; inbox.tick
source_error=IOError.new('Temporary network failure')
inbox.refresh(reference)
inbox.tick; inbox.tick
assert(!inbox.dismissed?(sent['event_id']),'A network failure was treated as a resolved invitation')
source_error=T::Publication::Invalid.new(:missing_publication)
retry_clock=2
inbox.tick; inbox.tick
assert(inbox.dismissed?(sent['event_id']),'Confirmed publication removal left a permanent invitation active')
source_error=nil

scope=scope.merge('account'=>'alice','account_epoch'=>'three')
value['people']=['alice','bob']
finished=make.call('finished')
notice=finished.notices(publication_ref:reference).last
assert_equal(2,notice['place'])
assert_equal(['Alice'],notice['winners'])
assert_equal(0,finished.inspect(metadata:notice,sender:'Alice',delivery:true)['expires_at'])
assert_equal(0,finished.remaining_seconds(0))
assert(!finished.expired?(0),'Permanent result expired')
assert_raises(T::ProposalNotice::Stale) { finished.inspect(metadata:notice.merge('place'=>1),sender:'Alice',delivery:true) }
assert_raises(T::ProposalNotice::Stale) { finished.inspect(metadata:notice.merge('winners'=>['Mallory']),sender:'Alice',delivery:true) }
scope=scope.merge('account'=>'bob','account_epoch'=>'four')
service=make.call('finished')
worker=TournamentNoticeTestWorker.new
inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,metadata:T::TournamentEventNotice.method(:metadata))
now+=90*86400
assert(inbox.receive(id:2,metadata:notice,sender:'Alice'))
inbox.tick
assert_equal(1,inbox.tick.size,'Old final could not be read')
assert(service.presentable?(inbox.verified(2).first))
calls=reads
inbox.refresh(reference)
10.times { inbox.tick }
assert_equal(calls,reads,'Informational final was needlessly rechecked after a tournament change')
assert(service.retain_stale_notice?(notice,sender:'Alice'),'Historical final would be withdrawn after tournament retention')
assert(!service.retain_stale_notice?(notice,sender:'Mallory'),'Foreign sender retained a historical final')
assert_equal(2,service.description(metadata:notice,sender:'Alice')['place'],'Cold history lost recipient placement')
assert_equal(0,service.retention_deadline)
puts 'PASS permanent tournament events: resolved invitation cleanup, finite reads, personal result snapshot, forgery checks and no time-based expiry'
