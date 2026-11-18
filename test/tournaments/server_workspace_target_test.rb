require_relative '../support/binary_rules_load' if ARGV.first
require_relative '../support/tournament_local_workspace'
require_relative '../support/tournament_server_plan_table'
require_relative '../support/host_source'
require EltenTestHost.file('src/eltenlink/error.rb')
require_relative '../../lib/tournaments/server_workspace'
include TournamentLocalWorkspaceSupport
include GameRoomTest::Assertions
T=GameRoomTournaments
assert_equal('468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80',T::ServerWorkspace::APP_UUID)
sandbox do |c|
  tables=T::LocalTestTables.new(directory:File.join(c.directory,'sdk-double'),user:-> {c.user},clock:-> {c.now})
  plans=TournamentServerPlanTableSupport::Table.new(user:-> {c.user})
  provider=Object.new
  provider.define_singleton_method(:fetch){|name|name=='tournament_plan_documents' ? plans : tables.fetch(name)}
  provider.define_singleton_method(:available?){true}
  workspace=T::ServerWorkspace.new(program:c.program,registry:GameRoomGames::CATALOG,user:-> {c.user},alert:->(message){c.alerts<<message},clock:-> {c.now},provider_factory:-> {provider})
  assert_equal(false,workspace.experimental_ui?)
  record=workspace.publish(**params(timezone:'UTC'))
  assert_equal('confirmed',record['status'])
  assert_equal(1,workspace.load['members'].size,'Official composition lost creator enrollment')
  assert_equal(T::ServerWorkspace::IDENTITY,workspace.instance_variable_get(:@journal).backend_identity,'Publication journal points to the trial application')
  assert_equal([],c.alerts)
  %w[apps.tables.stamp_required apps.tables.forbidden auth.unauthorized].each do |code|
    result = workspace.send(:access) { raise EltenLink::Error.new('Test refusal', code:code) }
    assert_equal(nil, result, 'A refused tournament operation claimed success')
    message = c.alerts.last
    assert(message.start_with?('Tournaments are unavailable without server table access.'), 'The backend bypassed the common tournament explanation')
    assert(message.include?('developer mode'), 'The backend refusal omitted developer-mode guidance')
    assert(message.include?(code == 'apps.tables.stamp_required' ? 'most likely' : 'If you are using'),
      'A launcher refusal and an inconclusive access check shared a false diagnosis')
  end
  assert_equal(1,workspace.load['members'].size, 'A permission failure changed the confirmed tournament')
end
puts 'PASS official workspace target, no experimental UI, normal publication and own-account enrollment using SDK doubles'
