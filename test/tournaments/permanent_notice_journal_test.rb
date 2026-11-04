require_relative '../support/temporary_directory'
require_relative '../support/tournament_public_ui'
require_relative '../support/proposal_notice_storage'
require_relative '../../lib/tournaments/tournament_start_runtime'
include GameRoomTest::Assertions
T=GameRoomTournaments
make_notice=->(index) do
  ref={'author'=>'alice','publication_key'=>"start-#{index}"}
  T::TournamentStartNotice.metadata({'version'=>2,'backend_identity'=>'trial','publication_ref'=>ref,'recipient'=>'bob',
    'title'=>'Tournament','game'=>'chess',
    'event_id'=>Digest::SHA256.hexdigest(JSON.generate(['tournament-start-v1','trial',ref]))})
end
service=T::TournamentStartNotice.allocate
service.define_singleton_method(:inspect) { |metadata:,sender:,delivery:| {'metadata'=>T::TournamentStartNotice.metadata(metadata),'expires_at'=>0} }
service.define_singleton_method(:expired?) { |value| value!=0 && value<=1000 }
service.define_singleton_method(:retention_deadline) { 0 }
service.define_singleton_method(:assert_context!) { true }
key_for=->(notice) { Digest::SHA256.hexdigest(JSON.generate(['alice',T::Publication::Data.copy(service.delivery_identity(notice))])) }
GameRoomTest::TemporaryDirectory.create('permanent-notice-journal-') do |directory|
  program=ProposalNoticeStorageSupport::Program.new(directory).extend(T::TournamentStartRuntime)
  scope=Digest::SHA256.hexdigest(JSON.generate(%w[alice trial]))
  original=T::ProposalNoticeJournal.new(program:program,path:"tournament-start-deliveries-#{scope}.json")
  original.update do |state|
    512.times do |index|
      notice=make_notice.call(index)
      stored=index==1 ? T::TournamentStartNotice.metadata(notice.slice(*T::TournamentStartNotice::FIELDS).merge('version'=>1)) : notice
      state['operations'][key_for.call(stored)]={'descriptor'=>{'sender'=>'alice','metadata'=>stored},'state'=>index==1 ? 'sent' : 'attempted','expires_at'=>10}
    end
  end
  before=original.read
  notice=make_notice.call(0)
  partition=program.tournament_notice_journal(account:'alice',notice:notice,kind:'start')
  sends=[]
  publisher=T::TournamentStartPublisher.new(service:service,sender:-> {'Alice'},transaction:partition.method(:update),send:->(*) { sends<<true;true })
  assert_equal(:confirmation_pending,publisher.deliver(metadata:notice),'Partitioning repeated an old uncertain send')
  assert_equal([],sends)
  assert_equal(0,partition.read['operations'].values.first['expires_at'],'Imported uncertain operation expired')
  upgraded=make_notice.call(1)
  partition=program.tournament_notice_journal(account:'alice',notice:upgraded,kind:'start')
  upgraded_writer=T::TournamentStartPublisher.new(service:service,sender:-> {'Alice'},transaction:partition.method(:update),send:->(*) { sends<<true;true })
  assert_equal(:sent,upgraded_writer.deliver(metadata:upgraded),'Confirmed old format blocked remaining recipients')
  assert_equal([],sends,'A metadata upgrade resent a historical event')
  12.times do |index|
    fresh=make_notice.call(600+index)
    journal=program.tournament_notice_journal(account:'alice',notice:fresh,kind:'start')
    writer=T::TournamentStartPublisher.new(service:service,sender:-> {'Alice'},transaction:journal.method(:update),send:->(*) { sends<<true;true })
    2.times { assert_equal(:sent,writer.deliver(metadata:fresh)) }
    assert_equal(1,journal.read['operations'].size,'Permanent journal accumulated unrelated tournaments')
  end
  assert_equal(12,sends.size,'Permanent partition resent a known event')
  assert_equal(before,original.read,'Partitioning modified the old global journal')
end
puts 'PASS permanent notice journals: full old journal, separate tournament capacity, retained uncertain sends, unchanged source and durable deduplication'
