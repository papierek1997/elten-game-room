if ARGV[1]
  package=ARGV.delete_at(1)
  ARGV.unshift(package)
  require_relative 'binary_rules_load'
  ARGV.shift
end
require_relative 'proposal_notice_storage'
require_relative 'tournament_public_ui'
require_relative '../../lib/tournaments/proposal_notice_journal'
require_relative '../../lib/tournaments/tournament_start_publisher'
directory=ARGV.fetch(0)
T=GameRoomTournaments
scope={'account'=>'owner','account_epoch'=>'epoch-1','backend_identity'=>'trial'}
publication=TournamentPublicUI.publication.merge('__insertion_user'=>'owner')
reference={'author'=>'owner','publication_key'=>publication.fetch('publication_key')}
source=->(ref) do
  raise 'Wrong start reference' unless ref==reference
  {'complete'=>true,'publication'=>publication,'participants'=>%w[owner alice]}
end
service=T::TournamentStartNotice.new(source:source,context:-> {scope},
  clock:-> {Time.utc(2026,10,15,18).to_i},registry:GameRoomGames::CATALOG)
notice=service.notices(publication_ref:reference).find{|value|value['recipient']=='alice'}
program=ProposalNoticeStorageSupport::Program.new(directory)
journal=T::ProposalNoticeJournal.new(program:program,path:'deliveries.json')
publisher=T::TournamentStartPublisher.new(service:service,sender:-> {'owner'},transaction:journal.method(:update),
  send:->(_notice,_closes){File.open(File.join(directory,'sent.txt'),'a'){|file|file.puts(Process.pid)};true})
raise 'Delivery did not reconcile' unless [:sent,:confirmation_pending].include?(publisher.deliver(metadata:notice))
