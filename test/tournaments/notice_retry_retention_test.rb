require_relative '../support/native_room_harness'
require_relative '../../lib/tournaments/proposal_notice_inbox'
require_relative '../../lib/tournaments/tournament_start_publisher'
include GameRoomTest::Assertions
T=GameRoomTournaments
class NoticeAuditWorker
  attr_reader :starts
  def initialize;@starts=0;end
  def start(&block);return false if busy?;@operation=block;@starts+=1;true;end
  def busy?;!!@operation;end
  def take
    return unless @operation
    operation,@operation=@operation,nil
    begin;[operation.call,nil];rescue StandardError=>error;[nil,error];end
  end
  def close;@operation=nil;end
end
notice={'version'=>1,'backend_identity'=>'audit','publication_ref'=>{'author'=>'owner','publication_key'=>'fixture'},
  'schedule_id'=>'a'*64,'match_id'=>'b'*64,'leg'=>1,'token'=>'c'*64,'recipient'=>'alice'}
now=0.0
failure=IOError.new('Offline')
calls=0
service=Object.new
service.define_singleton_method(:inspect) do |metadata:,sender:|
  calls+=1
  raise failure if failure
  {'metadata'=>metadata,'players'=>%w[alice bob]}
end
service.define_singleton_method(:presentable?){|_|true}
service.define_singleton_method(:refresh_on_change?){|_metadata,proof:nil|true}
service.define_singleton_method(:retain_stale_notice?){|_metadata,sender:|false}
worker=NoticeAuditWorker.new
inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,clock:-> {now})
inbox.receive(id:1,metadata:notice,sender:'owner')
2.times{inbox.tick}
20.times{inbox.tick}
assert_equal(1,calls,'Read retried without backoff')
failure=nil
now=2
inbox.tick
assert_equal(1,inbox.tick.size,'Transient failure permanently hid the invitation')
assert_equal(1,inbox.pending.size)
20.times{assert_equal([],inbox.tick)}
assert_equal(2,calls,'Successful verification started polling')
failure=IOError.new('Offline again')
inbox.refresh(notice['publication_ref'])
2.times{inbox.tick}
inbox.refresh(notice['publication_ref'])
assert_equal(3,calls)
inbox.forget(notice['token'])
now+=100
3.times{inbox.tick}
assert_equal(3,calls,'Dismissal did not cancel scheduled retry')
assert_equal([],inbox.pending)

worker=NoticeAuditWorker.new
inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,clock:-> {now})
inbox.receive(id:2,metadata:notice,sender:'owner')
12.times{inbox.tick;now+=1000}
assert_equal(4,worker.starts,'Retry budget was not finite')
failure=nil
assert(inbox.receive(id:3,metadata:notice,sender:'owner'),'Exhausted transient failure suppressed explicit redelivery')
inbox.tick
assert_equal(1,inbox.tick.size)
inbox.close

[NoMethodError.new('programming bug'),T::ProposalNotice::Stale.new('Expired')].each do |error|
  failure=error
  worker=NoticeAuditWorker.new
  inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,clock:-> {now})
  inbox.receive(id:4,metadata:notice,sender:'owner')
  12.times{inbox.tick;now+=1000}
  assert_equal(1,worker.starts,'Permanent failure was retried')
  assert_equal([],inbox.pending)
  inbox.close
end
failure=IOError.new('HTTP 429 Too many requests')
failure.define_singleton_method(:retry_after){60}
worker=NoticeAuditWorker.new
inbox=T::ProposalNoticeInbox.new(service:service,worker:worker,clock:-> {now})
inbox.receive(id:5,metadata:notice,sender:'owner')
2.times{inbox.tick}
now+=59
inbox.tick
assert_equal(1,worker.starts,'Ignored server retry_after')
inbox.close
now+=10
assert_equal([],inbox.tick)
assert_equal(1,worker.starts,'Closed inbox continued retrying')

# Historical finite-lifetime journal fixture. This deliberately retains the
# original 1800-second policy, independent of today's permanent start notices.
now=1000
starts={}
# Keep the production metadata/identity contract while isolating the clock
# and source reads needed by the retention fixture.
service=T::TournamentStartNotice.allocate
service.define_singleton_method(:retention_deadline){now+1800}
service.define_singleton_method(:expired?){|expiry|now>=expiry}
service.define_singleton_method(:assert_context!){true}
service.define_singleton_method(:inspect) do |metadata:,sender:,delivery:|
  metadata=T::TournamentStartNotice.metadata(metadata)
  start=starts.fetch(metadata['event_id'])
  raise T::ProposalNotice::Stale,'Expired' if now>=start+300
  {'metadata'=>metadata,'expires_at'=>start+1800}
end
make_notice=->(index) do
  ref={'author'=>'alice','publication_key'=>"start#{index}"}
  T::TournamentStartNotice.metadata({'version'=>1,'backend_identity'=>'audit','publication_ref'=>ref,'recipient'=>'bob',
    'event_id'=>Digest::SHA256.hexdigest(JSON.generate(['tournament-start-v1','audit',ref]))})
end
state={'version'=>1,'operations'=>{}}
transaction=->(&block) do
  copy=Marshal.load(Marshal.dump(state))
  block.call(copy)
  state=copy
end
sent=[]
publisher=T::TournamentStartPublisher.new(service:service,sender:-> {'alice'},transaction:transaction,send:->(metadata,_){sent<<metadata;true})
T::TournamentStartPublisher::LIMIT.times do |index|
  item=make_notice.call(index)
  starts[item['event_id']]=0
  key=publisher.send(:delivery_key,'alice',item)
  state['operations'][key]={'descriptor'=>{'sender'=>'alice','metadata'=>item},'state'=>index.even? ? 'sent' : 'attempted'}
end
item=make_notice.call(512)
starts[item['event_id']]=now
assert_raises(T::ProposalNotice::Unavailable){publisher.deliver(metadata:item)}
assert(state['operations'].values.all?{|row|row['expires_at']==2800},'Full legacy journal never saved migration')
assert_equal([],sent)
now=2801
item=make_notice.call(513)
starts[item['event_id']]=now
assert_equal(:sent,publisher.deliver(metadata:item))
assert_equal(1,state['operations'].size,'Expired historical deliveries still consumed capacity')
assert_equal(:sent,publisher.deliver(metadata:item))
assert_equal(1,sent.size,'Live confirmed delivery was repeated')
other=make_notice.call(514)
starts[other['event_id']]=now
uncertain=T::TournamentStartPublisher.new(service:service,sender:-> {'alice'},transaction:transaction,send:->(*){sent<<:unknown;raise IOError,'Lost response'})
assert_raises(IOError){uncertain.deliver(metadata:other)}
assert_equal(:confirmation_pending,publisher.deliver(metadata:other))
assert_equal(2,sent.size,'Uncertain delivery was sent again')
now+=1801
assert_raises(T::ProposalNotice::Stale){publisher.deliver(metadata:other)}
fresh=make_notice.call(515)
starts[fresh['event_id']]=now
assert_equal(:sent,publisher.deliver(metadata:fresh))
assert_equal(1,state['operations'].size)
puts 'PASS finite notice read retries, backoff, cancellation, stale/programmer errors, redelivery, start journal migration/expiry and uncertain-send protection'
