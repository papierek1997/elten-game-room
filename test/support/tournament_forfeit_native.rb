require_relative 'temporary_directory'
require_relative 'session_runner'
require_relative 'tournament_server_plan_table'
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/ordinary_match_service'
require_relative 'tournament_legacy_forfeit_fixture'

module TournamentForfeitNative
  class Fixture
    attr_reader :h, :documents, :candidate, :match, :services, :changes
    def initialize(directory, game:GameRoomGames::TicTacToe.new, users:%w[Alice Bob], options:nil)
      @h=NativeRoomHarness.new(game:game,users:users,options:options)
      @directory=directory
      program=ProgramDouble.new(h.broker.endpoint(users.first))
      lobby=LobbyRepository.new(program,transport:h.transports[users.first],server_tables:Object.new)
      h.as(users.first) { lobby.close_table(h.table) }
      @documents=TournamentServerPlanTableSupport::Table.new(user:-> {users.first})
      @match={'match_id'=>'d'*64,'leg'=>1,'number'=>1,'players'=>users.map(&:downcase)}
      @candidate={'format'=>'round_robin','schedule_id'=>'a'*64,'publication_digest'=>'b'*64,'roster_generation'=>'c'*64,
        'game_id'=>game.id,'game_options'=>options || game.default_options,
        'publication_ref'=>{'author'=>users.first.downcase,'publication_key'=>'fixture'},
        'roster'=>users.map(&:downcase),'matches'=>[match]}
      @changes=[]
      @services=users.to_h { |user| [user,make_service(user)] }
    end
    def make_service(user)
      program=ProgramDouble.new(h.broker.endpoint(user))
      lobby=LobbyRepository.new(program,transport:h.transports.fetch(user),server_tables:Object.new)
      GameRoomTournaments::OrdinaryMatchService.new(program:program,registry:GameRoomGames::CATALOG,
        lobby:lobby,games:h.repositories.fetch(user),transport:h.transports.fetch(user),table:documents.for_user(user),
        journal:GameRoomTournaments::OperationJournal.new(directory:File.join(@directory,user),owner:user.downcase,backend_identity:'forfeit-v2-native'),
        source:-> {{'candidate'=>candidate,'tournament_id'=>5}},user:-> {user},changed:->(ref) {changes<<[user,ref]}).
        extend(GameRoomTournaments::LegacyForfeitFixture)
    end
    def start
      table=h.as(h.users.first) { services.fetch(h.users.first).open_match(match_id:match['match_id'],leg:1) }
      h.instance_variable_set(:@table,table)
      h.users.drop(1).each { |user| h.as(user) {services.fetch(user).open_match(match_id:match['match_id'],leg:1)} }
      session=h.as(h.users.first) do
        h.repositories.fetch(h.users.first).start_session(table:table,game:h.game.id,players:h.users,
          options:JSON.generate(candidate['game_options']),**services.fetch(h.users.first).start_parameters(table,players:h.users))
      end
      h.instance_variable_set(:@session,session)
      session
    end
    def preview(loser:h.users.last.downcase, user:h.users.first)
      h.as(user) {services.fetch(user).forfeit_preview(match_id:match['match_id'],leg:1,loser:loser,expected_schedule_id:candidate['schedule_id'])}
    end
    def confirm(preview,user:h.users.first)
      h.as(user) {services.fetch(user).confirm_forfeit(preview:preview)}
    end
    # Read-only historical fixture construction. Do not re-enable the removed
    # production v2 writer merely to keep testing old accepted receipts.
    def legacy_preview(loser:h.users.last.downcase, user:h.users.first)
      h.as(user) {services.fetch(user).send(:build_forfeit_preview,candidate,5,match,loser)}
    end
    def insert_historical(document,user:h.users.first)
      service=services.fetch(user)
      key=service.send(:anchor,candidate,5,match,'forfeit')
      GameRoomTournaments::ServerPlanDocument.encode(document,anchor:key).each do |part|
        documents.insert_as(part,user)
      end
      services.fetch(h.users.last).result_view
    end
    def close
      services.each_value(&:close)
    end
  end
  def self.with_fixture(**options)
    GameRoomTest::TemporaryDirectory.create('forfeit-v2-native-') do |directory|
      fixture=Fixture.new(directory,**options)
      yield fixture
    ensure
      fixture&.close
    end
  end
end
