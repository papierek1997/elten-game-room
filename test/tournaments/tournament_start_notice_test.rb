require_relative '../support/temporary_directory'
require 'tmpdir'
require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/tournament_public_ui'
require_relative '../support/proposal_notice_storage'
require_relative '../../lib/tournaments/tournament_start_publisher'
require_relative '../../lib/tournaments/proposal_notice_journal'
include GameRoomTest::Assertions
T=GameRoomTournaments
u=TournamentPublicUI
starts=Time.utc(2026,10,15,18).to_i
now=starts-1
row=u.publication(11).merge('__insertion_user'=>'Alice','timezone'=>'UTC')
people=%w[alice bob]
complete=true
scope={'account'=>'alice','account_epoch'=>'epoch-one','backend_identity'=>'trusted-trial'}
source=->(reference){raise 'Wrong reader reference' unless reference=={'author'=>'alice','publication_key'=>row['publication_key']};
  {'complete'=>complete,'publication'=>row,'participants'=>people}}
make=-> {T::TournamentStartNotice.new(source:source,context:-> {scope},clock:-> {now},registry:GameRoomGames::CATALOG)}
service=make.call
reference={'author'=>'Alice','publication_key'=>row['publication_key']}
assert_raises(T::ProposalNotice::Stale){service.notices(publication_ref:reference)}
now=starts
notices=service.notices(publication_ref:reference)
assert_equal(%w[alice bob],notices.map{|notice|notice['recipient']})
notice=notices.last
assert_equal(2,notice['version'])
assert_equal(row['title'],notice['title'])
assert_raises(T::ProposalNotice::Stale){service.inspect(metadata:notice.merge('title'=>'Forged title'),sender:'Alice',delivery:true)}
assert_equal(row['title'],service.inspect(metadata:notice,sender:'Alice',delivery:true)['title'])
GameRoomTest::TemporaryDirectory.create('start-notice-') do |directory|
  program=ProposalNoticeStorageSupport::Program.new(directory)
  journal=-> {T::ProposalNoticeJournal.new(program:program,path:'starts.json')}
  sent=[]
  sender=-> {scope['account']}
  deliver=->(_metadata,_expires){sent<<:attempt;raise IOError,'Notification acknowledgement lost'}
  publisher=T::TournamentStartPublisher.new(service:service,sender:sender,transaction:journal.call.method(:update),send:deliver)
  assert_raises(IOError){publisher.deliver(metadata:notice)}
  cold=T::TournamentStartPublisher.new(service:make.call,sender:sender,transaction:journal.call.method(:update),send:->(*){sent<<:duplicate;true})
  assert_equal(:confirmation_pending,cold.deliver(metadata:notice))
  assert_equal([:attempt],sent)
  alice_notice=notices.first
  assert_equal(:sent,cold.deliver(metadata:alice_notice))
  assert_equal(:sent,cold.deliver(metadata:alice_notice))
  assert_equal([:attempt,:duplicate],sent,'Confirmed start sent again')
end
GameRoomTest::TemporaryDirectory.create('start-notice-upgrade-') do |directory|
  program=ProposalNoticeStorageSupport::Program.new(directory)
  journal=T::ProposalNoticeJournal.new(program:program,path:'starts.json')
  sent=[]
  legacy=T::TournamentStartNotice.metadata(notice.slice(*T::TournamentStartNotice::FIELDS).merge('version'=>1))
  # Seed the old writer's exact key, not a legacy record made by the new writer.
  key=Digest::SHA256.hexdigest(JSON.generate(['alice',legacy]))
  journal.update do |state|
    state['operations'][key]={'descriptor'=>{'sender'=>'alice','metadata'=>legacy},'state'=>'sent'}
  end
  cold=T::TournamentStartPublisher.new(service:make.call,sender:-> {'alice'},transaction:journal.method(:update),
    send:->(*) {sent<<:duplicate;true})
  assert_equal(:sent,cold.deliver(metadata:notice))
  assert_equal([],sent,'Adding a description resent an already delivered start')
  assert_equal(:sent,cold.deliver(metadata:notices.first),'A legacy journal blocked a different recipient')
  assert_equal([:duplicate],sent)
end
scope={'account'=>'bob','account_epoch'=>'bob-epoch','backend_identity'=>'trusted-trial'}
recipient=make.call
assert_equal('chess',recipient.inspect(metadata:notice,sender:'Alice')['game'])
assert_equal({'title'=>row['title'],'game'=>'chess'},recipient.description(metadata:notice,sender:'Alice'))
assert_equal(nil,recipient.description(metadata:notice,sender:'Mallory'))
assert_equal(nil,recipient.description(metadata:notice.merge('recipient'=>'carol'),sender:'Alice'))
assert_equal(nil,recipient.description(metadata:notices.first,sender:'Alice'))
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Mallory')}
people=['alice']
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Alice')}
people=%w[alice bob]
complete=false
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Alice')}
complete=true
now=starts+90*86400
assert(recipient.presentable?(recipient.inspect(metadata:notice,sender:'Alice')),'Start information expired')
assert_equal(0,recipient.remaining_seconds(0))
assert_equal(0,recipient.retention_deadline)
assert_equal(row['title'],recipient.description(metadata:notice,sender:'Alice')['title'],'Historical description expired like a live delivery')
now=starts
scope=scope.merge('account_epoch'=>'changed-epoch')
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Alice')}
scope=scope.merge('account_epoch'=>'bob-epoch')
assert_raises(T::ProposalNotice::Stale){recipient.inspect(metadata:notice,sender:'Alice')}
puts 'PASS tournament start notices: actual game/title, registered recipients, permanent lifetime, sender/epoch/complete-source guards and durable once-only attempts'
