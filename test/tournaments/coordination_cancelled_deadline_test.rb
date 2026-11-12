require_relative '../support/tournament_local_workspace'
require_relative '../support/tournament_server_plan_table'
require_relative '../support/tournament_notice_worker'
require_relative '../support/host_source'
require EltenTestHost.file('src/eltenlink/error.rb')
require_relative '../../lib/tournaments/server_coordination'
include TournamentLocalWorkspaceSupport
include GameRoomTest::Assertions
T = GameRoomTournaments

sandbox do |context|
  tables = T::LocalTestTables.new(directory: File.join(context.directory, 'server'),
    user: -> { context.user }, clock: -> { context.now })
  plans = TournamentServerPlanTableSupport::Table.new(user: -> { context.user })
  provider = Object.new
  provider.define_singleton_method(:fetch) { |name| name == 'tournament_plan_documents' ? plans : tables.fetch(name) }
  provider.define_singleton_method(:available?) { true }
  workspace = T::ServerWorkspace.new(program: context.program, registry: GameRoomGames::CATALOG,
    user: -> { context.user }, clock: -> { context.now }, provider_factory: -> { provider },
    alert: ->(message) { raise message })
  values = params('chess', timezone: 'UTC', registration_closes_at: 0)
  values[:draft] = values[:draft].merge('windows' => [], 'starts_at' => 1_000_000, 'deadline_at' => 0)
  assert_equal('confirmed', workspace.publish(**values)['status'])
  row = workspace.load.fetch('announcements').first
  reference = {'author' => row['__insertion_user'].downcase, 'publication_key' => row['publication_key']}
  worker = TournamentNoticeTestWorker.new
  coordinator = T::ServerCoordination.new(workspace: workspace, user: -> { context.user },
    clock: -> { context.now }, worker: worker, wake: ->(*) {})
  begin
    coordinator.changed(reference)
    2.times { coordinator.tick }
    original = coordinator.instance_variable_get(:@deadlines).dup
    assert_equal([reference], original.keys)
    read = workspace.method(:notification_context_on_worker)
    workspace.define_singleton_method(:notification_context_on_worker) { |**| raise IOError, 'Temporary test read failure' }
    coordinator.changed(reference)
    2.times { coordinator.tick }
    assert(coordinator.last_error.is_a?(IOError))
    assert_equal(original, coordinator.instance_variable_get(:@deadlines), 'Unknown read failure erased a valid timer')
    workspace.define_singleton_method(:notification_context_on_worker, read)
    context.now += 30
    2.times { coordinator.tick }
    assert_equal(nil, coordinator.last_error)
    assert_equal(original, coordinator.instance_variable_get(:@deadlines), 'Recovery did not preserve the actual next change')
    assert_equal('confirmed', workspace.delete_tournament(row['__id'], 'cancel',
      T::RegistrationProjection.publication_generation(row))['status'])
    coordinator.changed(reference)
    2.times { coordinator.tick }
    assert_equal(nil, coordinator.send(:presentation_snapshot, reference).dig('directory', 'publication'))
    assert_equal({}, coordinator.instance_variable_get(:@deadlines), 'Verified cancellation retained the old timer')
    starts = worker.starts
    context.now = original.fetch(reference)
    2.times { coordinator.tick }
    assert_equal(starts, worker.starts, 'A cancelled future tournament started unnecessary work')
  ensure
    coordinator.close
  end
end
puts 'PASS coordination deadlines: actual verified cancellation retires the timer; failed reads retain it and ordinary recovery reschedules the real next change'
