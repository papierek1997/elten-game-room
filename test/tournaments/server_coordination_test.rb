require_relative '../support/tournament_local_workspace'
require_relative '../support/readiness_plan_table'
require_relative '../support/session_runner'
require_relative '../support/host_source'
require EltenTestHost.file('src/eltenlink/error.rb')
require_relative '../../lib/tournaments/server_coordination'
include TournamentLocalWorkspaceSupport
include GameRoomTest::Assertions
T=GameRoomTournaments

sandbox do |c|
  ordinary=T::LocalTestTables.new(directory:File.join(c.directory,'server'),user:-> {c.user},clock:-> {c.now})
  plans=ReadinessPlanTableSupport::Table.new(user:-> {c.user},clock:-> {c.now})
  request_counts=Hash.new(0)
  stage='setup'
  plans.on_select=-> {request_counts[stage]+=1}
  original_read=ordinary.method(:select_rows)
  ordinary.define_singleton_method(:select_rows) do |*args,**keywords|
    request_counts[stage]+=1
    original_read.call(*args,**keywords)
  end
  provider=Object.new
  provider.define_singleton_method(:fetch){|name|name=='tournament_plan_documents' ? plans : ordinary.fetch(name)}
  provider.define_singleton_method(:available?){true}
  build=-> {T::ServerWorkspace.new(program:c.program,registry:GameRoomGames::CATALOG,user:-> {c.user},
    alert:->(message){raise message},clock:-> {c.now},readiness_clock:-> {c.now},provider_factory:-> {provider})}
  owner=build.call
  record=owner.publish(**params(GameRoomGames::TicTacToe.new.id,timezone:'UTC'))
  id=record.fetch('evidence').fetch('canonical_id')
  row=owner.load.fetch('announcements').find{|item|item['__id']==id}
  ref=T::ServerCoordination.reference({'author'=>row['__insertion_user'],'publication_key'=>row['publication_key']})
  c.user='SecondPlayer'
  guest=build.call
  guest.join(id)
  c.now=Time.utc(2026,10,15,12).to_i
  c.user='RealOwner'
  source=owner.shared_schedule(publication_ref:ref)
  match=source.fetch('candidate').fetch('matches').first
  args={publication_ref:ref,match_id:match['match_id'],leg:match['leg']}
  wakes,starts,finishes=[],[],[]
  worker=Object.new
  worker.define_singleton_method(:close){}
  c.user='RealOwner'
  coordinator=T::ServerCoordination.new(workspace:owner,user:-> {c.user},clock:-> {c.now},worker:worker,
    wake:->(*values){wakes<<values},started:->(reference){starts<<reference},finished:->(reference){finishes<<reference})
  writes=plans.rows.size
  stage='initial-coordination'
  coordinator.coordinate(ref,broadcast:true)
  assert_equal(writes,plans.rows.size,'Coordination wrote readiness or reservations')
  assert_equal([['SecondPlayer',ref]],wakes)

  h=NativeRoomHarness.new(game:GameRoomGames::TicTacToe.new,users:%w[RealOwner SecondPlayer])
  program=ProgramDouble.new(h.broker.endpoint('RealOwner'))
  lobby=LobbyRepository.new(program,transport:h.transports['RealOwner'],server_tables:Object.new)
  h.as('RealOwner'){lobby.close_table(h.table)}
  creator=owner.ordinary_service(publication_ref:ref,lobby:lobby,games:h.repositories['RealOwner'],transport:h.transports['RealOwner'])
  stage='create-table'
  table=h.as('RealOwner'){creator.open_match(**args.except(:publication_ref))}
  h.instance_variable_set(:@table,table)
  stage='table-ready-coordination'
  coordinator.coordinate(ref)
  assert_equal(1,starts.length,'Start announcement work repeated')
  c.user='SecondPlayer'
  guest_program=ProgramDouble.new(h.broker.endpoint('SecondPlayer'))
  guest_lobby=LobbyRepository.new(guest_program,transport:h.transports['SecondPlayer'],server_tables:Object.new)
  joiner=guest.ordinary_service(publication_ref:ref,lobby:guest_lobby,games:h.repositories['SecondPlayer'],transport:h.transports['SecondPlayer'])
  stage='join-table'
  h.as('SecondPlayer') do
    joiner.attach_table(table)
    guest_lobby.join_table(table,'SecondPlayer')
  end
  writes=plans.rows.size
  stage='explicit-coordination-checks'
  10.times do
    c.now+=30
    c.user='RealOwner'
    coordinator.coordinate(ref,timed:true)
  end
  assert_equal(writes,plans.rows.size,'An open table renewed a participant reservation')
  assert_equal({},coordinator.instance_variable_get(:@deadlines),'Active match left a renewal timer')
  stage='play-and-result'
  c.user='RealOwner'
  h.as('RealOwner') do
    started=h.repositories['RealOwner'].start_session(table:table,game:h.game.id,players:h.users,
      options:JSON.generate(h.game.default_options),**creator.start_parameters(table,players:h.users))
    h.instance_variable_set(:@session,started)
  end
  9.times do
    replay=h.replay('RealOwner')
    break if replay.finished?
    h.submit(replay.current_player,h.game.legal_actions(replay,replay.current_player).first)
  end
  assert(h.replay('RealOwner').finished?)
  # The non-creator also records the real terminal replay. The creator need
  # not remain online to finalize this result.
  c.user='SecondPlayer'
  joiner.observe(table,h.session,h.replay('SecondPlayer'))
  deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+5
  loop do
    error = joiner.take_error
    raise error if error
    break if guest.coordination_view_on_worker(publication_ref:ref)['results']['completed']
    raise 'Guest result did not arrive' if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
    Thread.pass
  end
  c.user='RealOwner'
  final_view=coordinator.coordinate(ref)
  assert_equal(true,final_view['completed'])
  assert_equal(1,final_view['results']['results'].size)
  2.times{coordinator.coordinate(ref)}
  assert_equal([ref],finishes,'Completion callback was repeated')
  owner.define_singleton_method(:coordination_view_on_worker){|**|raise 'Notice attempted sporting phase advancement'}
  writes=plans.rows.size
  notice_source=owner.event_notice_source_on_worker(publication_ref:ref,kind:'finished')
  assert_equal(writes,plans.rows.size,'Notice wrote to server plans')
  assert_equal(true,notice_source['results']['completed'])
  assert(notice_source['results']['completed_at'].positive?)
  assert(!notice_source['winners'].empty?)
  assert_equal(%w[realowner secondplayer],notice_source.fetch('places').keys.sort)
  assert_equal([1,2],notice_source.fetch('places').values.sort)
  assert(h.users.include?(notice_source['winners'].first),'Final notice lost registered username case')
  assert_equal(1,notice_source['places'].fetch(notice_source['winners'].first.downcase))
  assert_equal(false,notice_source['team_mode'])
  assert_equal({},coordinator.instance_variable_get(:@deadlines))
  puts "SDK reads by stage: #{request_counts.inspect}"
ensure
  coordinator&.close
  creator&.close
  joiner&.close
end
puts 'PASS server coordination: no readiness/consent/leases, ordinary native entry, no renewal timer, guest result and completion'
