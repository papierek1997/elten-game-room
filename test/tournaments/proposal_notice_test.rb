require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/native_room_harness'
require_relative '../../lib/tournaments/proposal_notice_inbox'
include GameRoomTest::Assertions
T = GameRoomTournaments
scope = {'account'=>'alice', 'account_epoch'=>'session-1', 'backend_identity'=>'trusted-test'}
notice = {'version'=>1, 'backend_identity'=>'trusted-test', 'publication_ref'=>{'author'=>'owner','publication_key'=>'fixture'},
  'schedule_id'=>'a'*64, 'match_id'=>'b'*64, 'leg'=>1, 'token'=>'c'*64, 'recipient'=>'alice'}
proof = {'status'=>'confirmed', 'metadata'=>notice, 'players'=>%w[alice bob], 'accepted'=>[], 'sender'=>'owner',
  'revision'=>'proposal-1', 'window'=>{'opens'=>100,'closes'=>200}}
now = 150
reads, writes = [], []
backend = Object.new
backend.define_singleton_method(:lookup_proposal){|notice:| reads << notice; proof}
backend.define_singleton_method(:respond_proposal){|**options| writes << options; :confirmed}
service = T::ProposalNotice.new(backend:backend,context:-> {scope},clock:-> {now})
shown = service.inspect(metadata:notice,sender:'owner')
assert(shown.frozen? && shown['metadata'].frozen?)
assert_equal(:confirmed,service.respond(metadata:notice,sender:'owner',displayed:shown,accept:true))
assert_equal('proposal-1',writes.first[:expected_revision])
proof['revision']='proposal-2'
assert_raises(T::ProposalNotice::Stale){service.respond(metadata:notice,sender:'owner',displayed:shown,accept:false)}
assert_equal(1,writes.size)
proof['revision']='proposal-1'
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice,sender:'intruder')}
proof['accepted']=['intruder']
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice,sender:'owner')}
proof['accepted']=[]
now=200
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice,sender:'owner')}
assert_equal(false,service.presentable?(shown))
now=150
other=notice.merge('recipient'=>'bob')
before=reads.size
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:other,sender:'owner')}
assert_equal(before,reads.size)
assert_raises(T::Publication::Invalid){service.inspect(metadata:notice.merge('endpoint'=>'http://invalid'),sender:'owner')}
scope['account_epoch']='session-2'
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice,sender:'owner')}
scope['account_epoch']='session-1'
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice,sender:'owner')}
fresh=T::ProposalNotice.new(backend:backend,context:-> {scope},clock:-> {now})
unavailable=T::ProposalNotice.new(backend:nil,context:-> {scope},clock:-> {now})
before=reads.size
assert_raises(T::ProposalNotice::Unavailable){unavailable.inspect(metadata:notice,sender:'owner')}
assert_equal(before,reads.size)

worker=Class.new do
  attr_reader :starts
  def initialize; @starts=0; end
  def start(&block); @starts+=1; @operation=block; true; end
  def busy?; !!@operation; end
  def take
    return unless @operation
    operation,@operation=@operation,nil
    begin; [operation.call,nil]; rescue StandardError=>error; [nil,error]; end
  end
  def close; @operation=nil; end
end.new
inbox=T::ProposalNoticeInbox.new(service:fresh,worker:worker)
assert_equal(false,inbox.work_pending?,'A fresh inbox schedules idle work')
assert(inbox.receive(id:1,metadata:notice,sender:'owner'))
assert(inbox.work_pending?,'A received notice did not wake the inbox')
assert_equal(false,inbox.receive(id:2,metadata:notice,sender:'owner'),'Duplicate delivery with another notification ID')
assert_equal([],inbox.tick)
assert(inbox.work_pending?,'An in-flight verification was reported idle')
assert_equal(1,inbox.tick.size)
assert_equal(false,inbox.work_pending?,'A drained verification kept the inbox awake')
10.times{assert_equal([],inbox.tick)}
assert_equal(1,worker.starts,'Idle ticks must not poll')
assert_equal([1],inbox.forget(notice['token']))
assert_equal([],inbox.pending,'Accepted invitation remains selectable')
assert_equal(false,inbox.receive(id:3,metadata:notice,sender:'owner'),'Dismissed invitation returned')
pending_notice=notice.merge('token'=>'d'*64)
proof['metadata']=pending_notice
assert(inbox.receive(id:4,metadata:pending_notice,sender:'owner'))
inbox.tick
inbox.forget(pending_notice['token'])
assert_equal([],inbox.tick,'A late verification restored a dismissed invitation')
assert_equal(nil,inbox.verified(4))
active_notice=notice.merge('token'=>'e'*64)
proof['metadata']=active_notice
assert(inbox.receive(id:5,metadata:active_notice,sender:'owner'))
inbox.tick
assert_equal(1,inbox.tick.size)
inbox.refresh(active_notice['publication_ref'])
inbox.tick
assert_equal([],inbox.tick,'A still valid invitation was announced twice on refresh')
assert_equal(1,inbox.pending.size)
# Cancellation during an earlier verification must trigger a fresh read.
inbox.refresh(active_notice['publication_ref'])
inbox.tick
inbox.refresh(active_notice['publication_ref'])
assert_equal([],inbox.tick,'A pre-change snapshot was delivered')
backend.define_singleton_method(:lookup_proposal){|notice:|raise T::ProposalNotice::Stale,'Cancelled'}
assert_equal([],inbox.tick)
assert_equal([],inbox.pending,'A remotely cancelled invitation remains selectable')
assert(inbox.work_pending?,'A pending native revocation was reported idle')
assert_equal([5],inbox.take_revoked)
assert_equal(false,inbox.work_pending?,'A drained native revocation kept the inbox awake')
assert_equal([],inbox.take_revoked)
assert_equal(false,inbox.receive(id:6,metadata:active_notice,sender:'owner'))
# A connection failure does not mean cancellation.
backend.define_singleton_method(:lookup_proposal){|notice:|proof}
retained_notice=notice.merge('token'=>'f'*64)
proof['metadata']=retained_notice
inbox.receive(id:7,metadata:retained_notice,sender:'owner')
inbox.tick
inbox.tick
backend.define_singleton_method(:lookup_proposal){|notice:|raise IOError,'Offline'}
inbox.refresh(retained_notice['publication_ref'])
inbox.tick
inbox.tick
assert_equal(1,inbox.pending.size)
assert_equal([],inbox.take_revoked)
inbox.close
assert_equal(nil,inbox.verified(1))
assert_equal(false,inbox.receive(id:3,metadata:notice,sender:'owner'))
assert_equal(1,writes.size,'Receiving notices must not consent or create tables')
puts 'PASS tournament proposal notices: authenticated lookup, explicit readiness, fresh conditional consent, account epochs, expiry, forged/stale rejection, deduplication and no polling/automatic response'
