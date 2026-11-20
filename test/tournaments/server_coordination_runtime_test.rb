require_relative '../support/settings_widget'
require_relative '../support/assertions'
include GameRoomTest::Assertions

# The shared application fixture supplies a fixed account name. Restore the
# host's reader here so its real Session.logged? also covers incomplete login.
original_name = Session.method(:name)
original_token = Session.token
original_account = Session.instance_variable_get(:@name)
Session.singleton_class.attr_accessor :name
original_warning = Log.method(:warning)
workspace_constructor = GameRoomTournaments::ServerWorkspace.method(:new)
coordinator_constructor = GameRoomTournaments::ServerCoordination.method(:new)
warnings, workspaces, coordinators, directory_reads = [], [], [], []
runtime = TestTaskRuntime.new('tournament-startup')
app = Class.new(EltenGameRoom)
app.define_singleton_method(:app_runtime) { runtime }
program = app.new
Log.define_singleton_method(:warning) { |message| warnings << message }
GameRoomTournaments::ServerWorkspace.define_singleton_method(:new) do |**arguments|
  workspace_constructor.call(**arguments).tap { |value| workspaces << value }
end
GameRoomTournaments::ServerCoordination.define_singleton_method(:new) do |**arguments|
  coordinator_constructor.call(**arguments).tap do |value|
    coordinators << value
    # Only the directory data source is isolated. Initialization, the native
    # managed worker, account guards and cleanup are production implementations.
    value.define_singleton_method(:directory) do
      directory_reads << Session.name
      {'deadlines' => []}
    end
  end
end

workers = -> { runtime.managed_resources.size }
begin
  Session.name = Session.token = nil
  app.start_tournament_coordination(program)
  10.times { app.tournament_coordination_tick }
  assert_equal([], warnings, 'Starting before login produced a warning')
  assert_equal([], workspaces, 'Starting before login constructed a workspace')
  assert_equal(0, workers.call, 'Starting before login retained workers')

  Session.name = ''
  Session.token = ''
  app.tournament_coordination_tick
  Session.name = 'Alice'
  app.configure_tournament_coordination
  app.tournament_coordination_tick
  assert_equal([], workspaces, 'An account name without a token started tournaments')
  assert_equal([], warnings, 'Incomplete login produced a warning')

  Session.token = 'fixture-token'
  app.tournament_coordination_tick
  first = coordinators.fetch(0)
  first_worker = first.instance_variable_get(:@worker)
  assert(wait_background_work(first_worker), 'The first logged-in bootstrap did not finish')
  first_epoch = app.instance_variable_get(:@tournament_runtime_epoch)
  first_notice = app.instance_variable_get(:@tournament_start_service)
  first_inbox = app.instance_variable_get(:@tournament_start_inbox)
  assert_equal('Alice', workspaces.first.actor)
  assert_equal('alice', app.instance_variable_get(:@tournament_runtime_account))
  assert_equal(['Alice'], directory_reads, 'Login did not bootstrap once')
  10.times { app.tournament_coordination_tick }
  assert_equal(1, coordinators.size, 'Ordinary ticks recreated the coordinator')
  assert_equal(1, workspaces.size, 'Ordinary ticks recreated the workspace')

  Session.name = 'ALICE'
  app.tournament_coordination_tick
  assert_equal(1, coordinators.size, 'Display-name casing recreated the coordinator')

  Session.name = 'Bob'
  app.tournament_coordination_tick
  second = coordinators.fetch(1)
  second_worker = second.instance_variable_get(:@worker)
  assert(wait_background_work(second_worker), 'The new account did not bootstrap')
  assert(first_worker.closed?, 'An account change left the old worker open')
  assert_equal(nil, first_inbox.instance_variable_get(:@running))
  assert(first_inbox.instance_variable_get(:@worker).closed?, 'An account change left the old notice inbox open')
  assert_equal('Bob', workspaces.last.actor)
  assert(first_epoch != app.instance_variable_get(:@tournament_runtime_epoch), 'An account change reused its epoch')
  assert_raises(GameRoomTournaments::ProposalNotice::Stale) { first_notice.assert_context! }

  # Losing authentication must stop the old account even if its name remains
  # visible during logout. No anonymous worker or warning should replace it.
  Session.token = nil
  app.tournament_coordination_tick
  assert(second_worker.closed?, 'Logout did not close the coordinator')
  assert_equal(nil, app.instance_variable_get(:@tournament_coordinator))
  assert_equal(nil, app.instance_variable_get(:@tournament_start_service))
  assert_equal(nil, app.instance_variable_get(:@tournament_runtime_account))
  assert_equal(0, workers.call, 'Logout retained managed resources')
  Session.name = nil
  10.times { app.tournament_coordination_tick }
  assert_equal(2, coordinators.size, 'Logged-out ticks recreated the coordinator')
  assert_equal([], warnings, 'Login or logout produced a setup warning')

  # Reloading the extension after authentication must still initialize it
  # immediately, without waiting for another login or requiring a UI action.
  Session.name = 'Bob'
  Session.token = 'fixture-token-two'
  app.start_tournament_coordination(program)
  assert_equal(3, coordinators.size, 'An authenticated extension reload did not initialize')
  assert_equal('bob', app.instance_variable_get(:@tournament_runtime_account))
  app.stop_tournament_coordination
  assert_equal(0, workers.call, 'Stopping the extension retained workers')

  # A genuine initialization defect must remain visible, not be mistaken for
  # a normal logged-out session or hidden by the new authentication boundary.
  GameRoomTournaments::ServerWorkspace.define_singleton_method(:new) do |**|
    raise GameRoomTournaments::Publication::Invalid, :invalid_json
  end
  app.start_tournament_coordination(program)
  assert_equal(1, warnings.size, 'A genuine setup error was hidden')
  assert(warnings.first.start_with?('Tournament setup unavailable:'), 'The setup diagnostic was lost')
ensure
  app.stop_tournament_coordination
  runtime.close
  Session.name = original_account
  Session.token = original_token
  Session.define_singleton_method(:name, original_name)
  Log.define_singleton_method(:warning, original_warning)
  GameRoomTournaments::ServerWorkspace.define_singleton_method(:new, workspace_constructor)
  GameRoomTournaments::ServerCoordination.define_singleton_method(:new, coordinator_constructor)
end
puts 'PASS tournament startup: native authentication, deferred bootstrap, account changes, logout, reload and genuine diagnostics'
