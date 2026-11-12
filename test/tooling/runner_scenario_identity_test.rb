require_relative '../support/tournament_execution_suite'
require_relative '../support/temporary_directory'
require_relative '../support/assertions'
require 'stringio'
include GameRoomTest::Assertions

root = GameRoomTestRunner::ROOT
relative = 'test/games/quiz/pack_builder_test.rb'
absolute = File.join(root, relative)
selected = GameRoomTestRunner.expand([relative, absolute])
assert_equal(1, selected.size, 'Relative and absolute selections duplicated one scenario')
assert_equal(relative, selected.first.fetch(:script), 'The first selected spelling was not retained')
assert_equal(absolute, GameRoomTestRunner.expand([absolute, relative]).first.fetch(:script))

# These are the actual six parameterized jobs used by the maintained encoding
# suite. Merely using the filename as a tie-breaker gives different membership
# when the caller enumerates these variants in the opposite order.
jobs = TournamentExecutionSuite.jobs('encoding')
parts = (1..2).map { |index| GameRoomTestRunner.shard(jobs, "#{index}/2") }
assert_equal(parts, (1..2).map { |index| GameRoomTestRunner.shard(jobs.reverse, "#{index}/2") },
  'Parameterized shard membership depends on input order')
assert_equal(jobs.map { |job| job.fetch(:args) }.sort,
  parts.flatten.map { |job| job.fetch(:args) }.sort, 'A parameterized variant was lost or duplicated')

GameRoomTest::TemporaryDirectory.create('runner-identity-') do |directory|
  script = File.join(directory, 'scenario_test.rb')
  File.write(script, 'puts [ARGV, ENV["RUNNER_IDENTITY"]].inspect')
  local = File.basename(script)
  defaults = {script: local, args: [], ruby_args: [], env: {}}
  options = {script: local, args: ['one'], env: {'RUNNER_IDENTITY' => 'A', 'UNUSED' => nil}}
  same = {env: {'UNUSED' => nil, 'RUNNER_IDENTITY' => 'A'}, args: ['one'], script: script}
  different = options.merge(args: ['two'])
  other_env = options.merge(env: {'RUNNER_IDENTITY' => 'B', 'UNUSED' => nil})
  preload = options.merge(ruby_args: ['-w'])
  entries = [local, script, defaults, options, same, different, other_env, preload]
  before = Marshal.dump(entries)
  expanded = GameRoomTestRunner.expand(entries, root: directory)
  assert_equal(5, expanded.size, 'Selection confused duplicate defaults with distinct execution variants')
  assert_equal(before, Marshal.dump(entries), 'Selection mutated the caller\'s entries')
  forward = (1..2).map { |index| GameRoomTestRunner.shard(entries, "#{index}/2", root: directory) }
  # Keep the representative spelling unchanged here: expand intentionally keeps
  # the first spelling, while partition membership must follow its identity.
  reversed = (1..2).map { |index| GameRoomTestRunner.shard(expanded.reverse, "#{index}/2", root: directory) }
  assert_equal(forward, reversed, 'Arguments, environment or hash insertion order changed the shard')
  results = GameRoomTestRunner.run(entries, root: directory, output: StringIO.new)
  assert(GameRoomTestRunner.success?(results), results.inspect)
  assert_equal(5, results.size, 'The runner executed a duplicate or lost a distinct variant')
  assert_equal(1, results.count { |row| row.fetch(:output).include?('[["two"], "A"]') })
  assert_equal(1, results.count { |row| row.fetch(:output).include?('[["one"], "B"]') })
end
puts 'PASS runner scenario identity: overlapping paths, defaults, isolated variants and deterministic parameterized shards'
