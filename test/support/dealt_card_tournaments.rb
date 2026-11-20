require 'tmpdir'
require_relative 'private_card_games'
require_relative 'tournament_server_plan_table'
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/ordinary_match_service'

module DealtCardTournamentTest
  module_function
  def verify(id, teams: false)
    users=teams ? %w[Alice Bob Carol Dave] : %w[Alice Bob]
    game=GameRoomGames::CATALOG.build(id)
    options=game.normalize_options(teams ? {'team_size'=>2,'score_limit'=>1,'two_point_lead'=>false} : {'bot_delay'=>0})
    h=NativeRoomHarness.new(game:game,users:users,options:options,clock:ClockEventContract::ManualTime.new)
    programs=users.to_h { |user| [user,ProgramDouble.new(h.broker.endpoint(user))] }
    lobbies=users.to_h { |user| [user,LobbyRepository.new(programs[user],transport:h.transports[user],server_tables:Object.new)] }
    h.as('Alice') { lobbies['Alice'].close_table(h.table) }
    documents=TournamentServerPlanTableSupport::Table.new(user:-> { 'Alice' })
    candidate={'schedule_id'=>'a'*64,'publication_digest'=>'b'*64,'roster_generation'=>'c'*64,
      'game_id'=>id,'publication_ref'=>{'author'=>'alice','publication_key'=>id},
      'format'=>'round_robin','players_per_match'=>users.size,'game_options'=>options,
      'roster'=>users.map(&:downcase),'matches'=>[{'match_id'=>'d'*64,'leg'=>1,'number'=>1,'players'=>users.map(&:downcase)}]}
    if teams
      candidate.merge!('team_template'=>[0,1,0,1], 'membership'=>{'version'=>1,'kind'=>'fixed-teams','units'=>[
        {'unit_id'=>'red','accounts'=>%w[alice bob]}, {'unit_id'=>'blue','accounts'=>%w[carol dave]}]})
      candidate['matches'].first['unit_ids']=%w[red blue]
    end
    Dir.mktmpdir('new-card-tournament-') do |directory|
      services=users.to_h do |user|
        journal=GameRoomTournaments::OperationJournal.new(directory:File.join(directory,user),owner:user.downcase,backend_identity:id)
        [user,GameRoomTournaments::OrdinaryMatchService.new(program:programs[user],registry:GameRoomGames::CATALOG,
          lobby:lobbies[user],games:h.repositories[user],transport:h.transports[user],table:documents.for_user(user),
          journal:journal,source:-> { {'candidate'=>candidate,'tournament_id'=>5} },user:-> { user })]
      end
      runners={}
      begin
        room=h.as('Alice') { services['Alice'].open_match(match_id:'d'*64,leg:1) }
        h.instance_variable_set(:@table,room)
        users.drop(1).each { |user| h.as(user) { services[user].open_match(match_id:'d'*64,leg:1) } }
        native_options=JSON.parse(room['game_options'])
        parameters=services['Alice'].start_parameters(room,players:users,options:native_options)
        h.as('Alice') do
          h.instance_variable_set(:@session,h.repositories['Alice'].start_session(table:room,game:id,players:users,
            options:JSON.generate(native_options),**parameters))
        end
        runners=users.to_h do |user|
          [user,h.as(user) do
            runner=GameRoomSessionRunner.new(program:programs[user],transport:h.transports[user],repository:h.repositories[user],
              game:game,session:h.session,table:room,owner:'Alice',viewer:user,
              context:GameRoomGames::ActionContext.new(random_source:GameRoomRandom::LocalSecureSource.new),
              room_snapshot_provider:-> { lobbies[user].snapshot_for(room) },covered:-> { true },
              completion_observer:->(session,replay,events) { services[user].observe(room,session,replay,events) })
            runner.instance_variable_set(:@clock,h.clock.session_clock)
            runner
          end]
        end
        700.times do
          PrivateCardGamesTest.tick(h,runners)
          current=h.replay('Alice')
          raise "#{id}: private audit failed" if current.state[:private_error]
          break if current.finished?
          actor=current.current_player
          next unless actor
          PrivateCardGamesTest.submit(h,runners,actor,game.legal_actions(h.replay(actor),actor).first)
        end
        assert(h.replay('Alice').finished?,"#{id}: tournament did not finish")
        PrivateCardGamesTest.tick(h,runners)
        deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+5
        loop do
          services.each_value { |service| raise error if (error=service.take_error) }
          break if services.values.all? { |service| service.result_view['results'].size==1 }
          raise "#{id}: no result receipt" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
          sleep 0.01
        end
        views=services.values.map(&:result_view)
        assert(views.uniq.size==1,"#{id}: result differs")
        expected=teams ? %w[blue red] : users.map(&:downcase)
        assert(views.first['standings'].map { |row| row['unit'] }.sort==expected.sort,'wrong tournament sides')
        assert(views.first['standings'].all? { |row| row['played']==1 },'game scored twice')
        assert(h.replay('Alice').state[:round]==6,'six rounds skipped') if id=='bouillabaisse'
        puts "PASS #{id} tournament: full private game, #{teams ? 'fixed teams' : 'individual'}, one converged result and standings"
      ensure
        runners.each_value(&:close)
        services.each_value(&:close)
      end
    end
  end
end
