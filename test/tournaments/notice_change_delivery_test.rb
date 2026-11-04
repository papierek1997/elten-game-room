require_relative '../support/settings_widget'
require_relative '../support/tournament_public_ui'
require_relative '../support/tournament_notice_worker'
require_relative '../../lib/tournaments/server_coordination_runtime'
include GameRoomTest::Assertions
T=GameRoomTournaments
row=TournamentPublicUI.publication(11).merge('__insertion_user'=>'Alice','__insertion_time'=>900,'timezone'=>'UTC',
  'schema_version'=>2,'registration_opens_at'=>950,'registration_closes_at'=>0,
  'schedule_json'=>JSON.generate({'starts_at'=>0,'deadline_at'=>0,'windows'=>[]}))
ref={'author'=>'alice','publication_key'=>row['publication_key']}
state={'publication'=>row,'members'=>[{'account'=>'alice'}],'people'=>['alice'],'senders'=>%w[alice bob],
  'usernames'=>{'alice'=>'Alice'},'pairs'=>[],'pair_requests'=>[],
  'invitations'=>[{'account'=>'bob','username'=>'BoB','status'=>'pending'}]}
workspace=Object.new
reads=0
workspace.define_singleton_method(:read_operation) { |&work| work.call }
workspace.define_singleton_method(:notification_context_on_worker) { |**| reads+=1;state }
wakes=[]
worker=TournamentNoticeTestWorker.new
coordinator=T::ServerCoordination.new(workspace:workspace,user:-> {'Alice'},clock:-> {1000},worker:worker,
  wake:->(*arguments) { wakes<<arguments })
coordinator.changed(ref,broadcast:true)
2.times { coordinator.tick }
assert_equal([['BoB',ref]],wakes,'Pending non-member did not receive change wake with exact registered name')
assert_equal([ref],coordinator.take_observed_references)
assert_equal([],coordinator.take_observed_references,'Observation was delivered twice')
20.times { coordinator.tick }
assert_equal(1,reads,'Idle coordination polled notice state')
coordinator.close

# Exercise the application composition, not only the coordinator's queue.
app=Class.new { extend T::ServerCoordinationRuntime }
original_name=Session.method(:name)
original_token=Session.token
original_account=Session.instance_variable_get(:@name)
Session.define_singleton_method(:name) { 'Alice' }
Session.name='Alice'
Session.token='notice-change-fixture'
assert(Session.logged?,'Native session fixture is not logged in')
refreshed=[]
inbox=Object.new
inbox.define_singleton_method(:refresh) { |reference| refreshed<<reference }
inbox.define_singleton_method(:close) {}
coordinator=T::ServerCoordination.new(workspace:workspace,user:-> {Session.name},clock:-> {1000},worker:TournamentNoticeTestWorker.new,wake:->(*) {})
app.instance_variable_set(:@tournament_runtime_program,Object.new)
app.instance_variable_set(:@tournament_runtime_account,'alice')
app.instance_variable_set(:@tournament_coordinator,coordinator)
app.instance_variable_set(:@tournament_event_inboxes,{'registration'=>inbox})
begin
  coordinator.changed(ref)
  2.times do
    app.instance_variable_set(:@tournament_coordination_tick_at,nil)
    app.tournament_coordination_tick
  end
  assert_equal([ref],refreshed,'Verified tournament change was not connected to notice refresh')
  5.times { app.tournament_coordination_tick }
  assert_equal([ref],refreshed,'Idle UI pump rechecked notices')
ensure
  app.stop_tournament_coordination
  Session.define_singleton_method(:name,original_name)
  Session.name=original_account
  Session.token=original_token
end
puts 'PASS notice change wiring: pending non-members, exact delivery case, coordinator observation, runtime inbox refresh and no idle reads'
