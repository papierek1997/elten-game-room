require_relative '../support/temporary_directory'
require 'tmpdir'
require 'rbconfig'
require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/native_room_harness'
require_relative '../support/proposal_notice_storage'
require_relative '../../lib/tournaments/proposal_notice_journal'
include GameRoomTest::Assertions
T=GameRoomTournaments
GameRoomTest::TemporaryDirectory.create('notice-journal-') do |directory|
  program=ProposalNoticeStorageSupport::Program.new(directory)
  journal=T::ProposalNoticeJournal.new(program:program,path:'corrupt.json')
  filename=program.data_path('corrupt.json')
  ['{broken','null','{"version":1,"operations":{},"operations":{}}'].each do |bytes|
    File.binwrite(filename,bytes)
    calls=0
    begin
      journal.update{calls+=1}
      raise 'Corrupt JSON was accepted'
    rescue T::Publication::Invalid,T::ProposalNotice::Unavailable
    end
    assert_equal(0,calls,'The transaction edit must not see a corrupt fallback')
    assert_equal(bytes,File.binread(filename),'Corrupt state was overwritten')
  end
  # Two processes race, then a cold third process reads the already sent claim.
  probe=File.expand_path('../support/proposal_notice_publish_process.rb',__dir__)
  command=[RbConfig.ruby,probe,directory]
  command << ARGV.first if ARGV.first
  children=2.times.map{Process.spawn(*command)}
  statuses=children.map{|pid|Process.waitpid2(pid).last}
  assert(statuses.all?(&:success?),'Concurrent publisher failed')
  assert_equal(1,File.readlines(File.join(directory,'sent.txt')).size,'Two processes sent one start event twice')
  system(*command)
  assert($?.success?,'Cold publisher failed')
  assert_equal(1,File.readlines(File.join(directory,'sent.txt')).size,'Cold publisher resent a confirmed start event')
end
puts 'PASS actual notification journal: SDK corrupt fallback/duplicate JSON refused without overwrite, cross-process claim and cold restart without duplicate delivery'
