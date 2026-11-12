require_relative '../support/temporary_directory'
require_relative '../support/session_runner'
require_relative '../support/tournament_server_plan_table'
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/ordinary_match_service'
require_relative '../../lib/tournaments/server_match_window'
T=GameRoomTournaments
GameRoomTest::TemporaryDirectory.create('deadline-binding-') do |directory|
  h=NativeRoomHarness.new(game:GameRoomGames::TicTacToe.new, users:%w[Alice Peterman])
  docs=TournamentServerPlanTableSupport::Table.new(user:-> {'Alice'})
  candidate={'format'=>'round_robin','schedule_id'=>'a'*64,'publication_digest'=>'b'*64,'roster_generation'=>'c'*64,
    'game_id'=>h.game.id,'game_options'=>h.game.default_options,'publication_ref'=>{'author'=>'alice','publication_key'=>'fixture'},
    'starts_at'=>100,'windows'=>[], 'roster'=>%w[alice peterman],
    'matches'=>[{'match_id'=>'d'*64,'leg'=>1,'number'=>1,'players'=>%w[alice peterman]},
      {'match_id'=>'e'*64,'leg'=>2,'number'=>2,'players'=>%w[alice peterman]}]}
  initial=Marshal.dump(candidate)
  now=200
  source={'candidate'=>candidate,'tournament_id'=>1}
  programs={}; lobbies={}; services={}
  build=->(user) do
    programs[user] ||= ProgramDouble.new(h.broker.endpoint(user))
    lobbies[user] ||= LobbyRepository.new(programs[user],transport:h.transports[user],server_tables:Object.new)
    T::OrdinaryMatchService.new(program:programs[user],registry:GameRoomGames::CATALOG,lobby:lobbies[user],
      games:h.repositories[user],transport:h.transports[user],table:docs.for_user(user),
      journal:T::OperationJournal.new(directory:File.join(directory,user),owner:user.downcase,backend_identity:'deadline-test'),
      source:-> {source},user:-> {user},entry_guard:->(c,_,_) {T::ServerMatchWindow.current(c,now,deadline_at:source['deadline_at'])})
  end
  services['Alice']=build.call('Alice')
  h.as('Alice') {lobbies['Alice'].close_table(h.table)}
  if ARGV.include?('--legacy-v6')
    # Create the old marker through the actual writer, then restore today's
    # default before a fresh service reads the unchanged existing binding.
    current_policy=T::GameResult::CURRENT_RESULT_POLICY
    T::GameResult.send(:remove_const,:CURRENT_RESULT_POLICY)
    T::GameResult.const_set(:CURRENT_RESULT_POLICY,T::GameResult::SELECTED_SMALL_RESULT_POLICY)
  end
  begin
    table=h.as('Alice') {services['Alice'].open_match(match_id:'d'*64,leg:1)}
  ensure
    if current_policy
      T::GameResult.send(:remove_const,:CURRENT_RESULT_POLICY)
      T::GameResult.const_set(:CURRENT_RESULT_POLICY,current_policy)
    end
  end
  binding=services['Alice'].instance_variable_get(:@bindings).fetch(table['__id']).first
  expected_policy=ARGV.include?('--legacy-v6') ? 'game-owned-result-v6' : 'game-owned-result-v8'
  assert_equal(expected_policy,binding.fetch('result_policy'))
  existing=Marshal.dump(docs.rows)
  services.delete('Alice').close
  source=source.merge('usernames'=>{'alice'=>'Alice','peterman'=>'Peterman'},'deadline_at'=>300)
  services['Alice']=build.call('Alice')
  reused=h.as('Alice') {services['Alice'].open_match(match_id:'d'*64,leg:1)}
  assert_equal(table['__live_session_id'], reused['__live_session_id'])
  assert_equal(['Peterman'], services['Alice'].invitation_players(reused))
  assert_equal(existing, Marshal.dump(docs.rows), 'Name preservation rewrote a legacy binding')
  now=300
  [:open,:start,:new_table].each do |operation|
    writes=docs.insert_count
    rooms=h.broker.cores.size
    error=assert_raises(T::Publication::Invalid) do
      h.as('Alice') do
        if operation==:start
          services['Alice'].start_parameters(table,players:%w[Alice Peterman])
        else
          services['Alice'].open_match(match_id:operation==:open ? 'd'*64 : 'e'*64,leg:operation==:open ? 1 : 2)
        end
      end
    end
    assert_equal(:deadline_passed,error.code)
    assert_equal(writes,docs.insert_count,'Expired start wrote a claim/binding/start intent')
    assert_equal(rooms,h.broker.cores.size,'Expired start created a native table')
  end
  services['Peterman']=build.call('Peterman')
  h.as('Peterman') do
    writes=docs.insert_count
    error=assert_raises(T::Publication::Invalid) { services['Peterman'].open_match(match_id:'d'*64,leg:1) }
    assert_equal(:deadline_passed,error.code)
    assert_equal(nil,lobbies['Peterman'].current_table_for('Peterman'),'Inspection retained a member in an expired, never-started table')
    assert_equal(writes,docs.insert_count,'Expired inspection wrote a tournament document')
  end
  # Start before expiry, then return after expiry: the same match stays usable.
  now=299
  h.as('Peterman') {services['Peterman'].open_match(match_id:'d'*64,leg:1)}
  h.as('Alice') do
    parameters=services['Alice'].start_parameters(table,players:%w[Alice Peterman])
    h.repositories['Alice'].start_session(table:table,game:h.game.id,options:JSON.generate(h.game.default_options),**parameters)
  end
  now=301
  before=Marshal.dump(docs.rows)
  h.as('Peterman') {assert_equal(table['__live_session_id'],services['Peterman'].open_match(match_id:'d'*64,leg:1)['__live_session_id'])}
  h.as('Peterman') do
    lobbies['Peterman'].leave_table(table,'Peterman')
    assert_equal([],h.transports['Peterman'].game_sessions(table,force:true),
      'The departed client still has native history access; this would not test a real rejoin')
    assert_equal(table['__live_session_id'],services['Peterman'].open_match(match_id:'d'*64,leg:1)['__live_session_id'])
  end
  assert_equal(before,Marshal.dump(docs.rows),'Rejoining a running match changed tournament records')
  assert_equal(initial,Marshal.dump(candidate),'Addressing/deadline changed candidate identities')
ensure
  services&.each_value(&:close)
end
puts 'PASS existing tournament binding remains byte-identical; correct invitation name; exact deadline blocks new tables/starts but permits return to running game'
