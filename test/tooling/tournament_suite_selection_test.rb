require_relative '../support/temporary_directory'
require_relative '../support/tournament_execution_suite'
require_relative '../support/assertions'
require 'stringio'
require 'yaml'
include GameRoomTest::Assertions

root = TournamentExecutionSuite::ROOT
workflow = YAML.safe_load(File.read(File.join(root, '.github/workflows/tests.yml')))
matrix = workflow.fetch('jobs').fetch('test').fetch('strategy').fetch('matrix')
assert_equal(GameRoomTestSuites::NAMES.sort, (matrix.fetch('suite') + matrix.fetch('include').map { |row| row.fetch('suite') }).uniq.sort,
  'CI must execute every maintained suite')
assert_equal([1], matrix.fetch('part'))
assert_equal([1], matrix.fetch('parts'))
assert_equal((1..4).map { |part| {'suite' => 'tournaments', 'part' => part, 'parts' => 4} }, matrix.fetch('include'),
  'Every tournament shard must run exactly once')
tournaments = GameRoomTestSuites.select('tournaments')
ci_parts = matrix.fetch('include').flat_map do |row|
  GameRoomTestRunner.shard(tournaments, "#{row.fetch('part')}/#{row.fetch('parts')}").map { |job| job.fetch(:script) }
end
assert_equal(tournaments, ci_parts.sort, 'CI shard coverage must be complete and disjoint')
assert_equal(5400, GameRoomTestSuites.timeout_for('test/tournaments/individual_quiz_finish_test.rb', fallback: 180))
assert_equal(600, GameRoomTestSuites.timeout_for('test/tournaments/execution_native_suite_test.rb', fallback: 180))
assert_equal(900, GameRoomTestSuites.timeout_for('test/tournaments/local_phase_record_capacity_test.rb', fallback: 180))
assert_equal(300, GameRoomTestSuites.timeout_for('test/tournaments/fixed_team_dispatch_test.rb', fallback: 180))
assert_equal(600, GameRoomTestSuites.timeout_for('test/transport/rummy_private_cards_test.rb', fallback: 180))
assert_equal(180, GameRoomTestSuites.timeout_for('test/games/quiz/model_test.rb', fallback: 180))
paths = GameRoomTestSuites.paths(root: root)
GameRoomTestSuites::SLOW_TIMEOUTS.each_key do |name|
  matches = paths.select { |path| File.basename(path) == name }
  assert_equal(1, matches.length, "Stale or ambiguous timeout: #{name}; #{matches.inspect}")
end
families = TournamentExecutionSuite::GROUPS.keys + %w[encoding cold recovery compatibility team_cold legacy_archive]
families.each do |family|
  jobs = TournamentExecutionSuite.jobs(family)
  assert(!jobs.empty?, "Empty tournament group: #{family}")
  jobs.each { |job| assert(File.file?(File.join(root, job[:script])), "Missing entry point: #{job[:script]}") }
end
GameRoomTestSuites::PARAMETERIZED_FILES.each do |name|
  assert(paths.none? { |path| File.basename(path) == name }, "Unprepared child selected: #{name}")
end
GameRoomTestSuites::HISTORICAL_INPUT_FILES.each do |name|
  path = 'test/tournaments/' + name
  assert(!paths.include?(path), 'Private historical archive required during ordinary CI')
  assert_equal([path], GameRoomTestRunner.expand([path]).map { |entry| entry[:script] })
end
%w[execution_team_parallel_suite_test.rb readiness_refusal_suite_test.rb].each do |name|
  assert(paths.include?('test/tournaments/' + name), "Missing maintained aggregate: #{name}")
end
assert(paths.none? { |path| File.basename(path).start_with?('ft2b1_', 'ft2_runtime_cold_', 'ft2_compatibility_boundary_') },
  'Parameterized or historical children counted again')
families.each do |family|
  assert(paths.include?("test/tournaments/execution_#{family}_suite_test.rb"), "Missing aggregate: #{family}")
end
assert_equal(paths.select { |path| path.start_with?('test/tournaments/') },
  GameRoomTestRunner.expand(['test/tournaments']).map { |job| job[:script] })
historical = 'test/tournaments/ft2b1_ui_primary_test.rb'
assert_equal([historical], GameRoomTestRunner.expand([historical]).map { |job| job[:script] }, 'Explicit historical invocation lost')
assert_equal(%w[source binary].product(%w[pl en missing-new-pl]), TournamentExecutionSuite.jobs('encoding').map { |job| job[:args] })
runtime = TournamentExecutionSuite.jobs('recovery').select { |job| job[:script].include?('ft2_runtime_cold_') }
assert_equal(%w[runtime-a runtime-b], runtime.map { |job| job[:evidence_name] }, 'Cold B must use the same fixture as A')
assert(runtime.all? { |job| !job.key?(:args) }, 'Cold scripts do not take synthetic CLI phases')
native = TournamentExecutionSuite.jobs('recovery').select { |job| job[:script].include?('ft2b1_native_cold_') }
assert_equal([['A', 'suite'], ['B', 'suite']], native.map { |job| job[:args] })

GameRoomTest::TemporaryDirectory.create('tournament-suite-') do |scratch|
  jobs = TournamentExecutionSuite.entries('encoding', scratch: scratch)
  jobs.each do |job|
    env = job[:env]
    assert_equal(root, env['FT2_SOURCE'])
    assert(File.directory?(env['ENTRY_EVIDENCE']), 'Evidence directory missing')
    map = JSON.parse(File.read(File.join(env['ENTRY_EVIDENCE'], 'source-before.json')))
    assert(map.key?('lib/tournaments/entry_context.rb'), 'Binary loader has no pinned production source')
    assert_equal(Digest::SHA256.file(File.join(root, 'lib/tournaments/entry_context.rb')).hexdigest, map['lib/tournaments/entry_context.rb'])
  end
  kept = TournamentExecutionSuite.read_catalog(File.join(scratch, 'shared/missing/PL.mo'))
  removed = JSON.parse(File.read(File.join(scratch, 'shared/missing/removed.json')))
  assert_equal(33, removed.size)
  assert(removed.none? { |key| kept.key?(key.b) }, 'Missing-translation test retained new translations')
  assert_equal('Wstecz', kept.fetch('Back').force_encoding('UTF-8'), 'Old translation removed')
  current = TournamentExecutionSuite.read_catalog(File.join(root, 'locale/PL.mo'))
  assert_equal(current.size - removed.size, kept.size)
end
puts 'PASS maintained tournament groups, explicit historic invocation, real cold phases and isolated encoding fixtures'
