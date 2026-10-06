require_relative "../support/binary_rules_load" if ARGV.first
require "tmpdir"
require_relative "../support/assertions"
require_relative "../support/host_source"
require EltenTestHost.file("src/bootstrap.rb")
require EltenTestHost.file("src/eapi/resources.rb")
require EltenTestHost.file("src/eapi/program.rb")
require_relative "../../lib/hidden_submissions"
include GameRoomTest::Assertions

module Log
  def self.debug(_message); end
end

def native_hidden_program(directory)
  runtime = Programs::Runtime.allocate
  runtime.instance_variable_set(:@json_file_monitors, {})
  runtime.instance_variable_set(:@json_file_monitors_guard, Monitor.new)
  runtime.define_singleton_method(:data_dir) { directory }
  runtime.define_singleton_method(:path_resolutions) { @path_resolutions ||= [] }
  runtime.define_singleton_method(:data_path) do |path|
    path_resolutions << path
    super(path)
  end
  program = Programs.with_runtime(runtime) { Class.new(Program) }
  program.instance_variable_set(:@app_runtime, runtime)
  [program, runtime]
end

Dir.mktmpdir("hidden-build245-native-") do |directory|
  program, runtime = native_hidden_program(File.join(directory, "native-app"))
  primary = HiddenSubmissions::ProgramStorage::DEFAULT_PATH
  identity = {session_id: 245, round_id: "1:1", user: "Alice"}
  legacy_storage = HiddenSubmissions::MemoryStorage.new
  legacy_vault = HiddenSubmissions::Vault.new(legacy_storage)
  original = legacy_vault.prepare(**identity, payload: {"answer" => "Zażółć gęślą jaźń"})
  program.write_json(primary, legacy_storage.read)
  runtime.path_resolutions.clear
  program.define_singleton_method(:read_json) { |*| raise "Host JSON read reparses the package" }
  program.define_singleton_method(:write_json) { |*| raise "Host JSON write reparses the package" }

  stores = 2.times.map { HiddenSubmissions::ProgramStorage.new(program.allocate) }
  vaults = stores.map { |storage| HiddenSubmissions::Vault.new(storage) }
  assert_equal(original.commitment, vaults.first.reveal(**identity).commitment)
  edited = vaults.first.prepare(**identity, payload: {"answer" => "Żółw"})
  assert_equal(edited.commitment, vaults.last.reveal(**identity).commitment)
  assert_equal(original.payload, vaults.last.reveal(**identity, commitment: original.commitment).payload)
  assert(vaults.last.verify(edited), "Stored UTF-8 changed the commitment")
  snapshot = stores.first.read
  assert_equal(1, snapshot.fetch("storage_revision"))
  20.times { stores.last.read }
  assert_equal([primary], runtime.path_resolutions, "Native path was not cached across Program instances")

  path = File.join(runtime.data_dir, primary)
  recovery = path + ".recovery.json"
  File.binwrite(recovery, JSON.generate({"entries" => {}, "storage_revision" => 2}))
  assert(vaults.first.reveal(**identity).nil?, "Cached answers ignored a newer recovery snapshot")
  fresh_program, fresh_runtime = native_hidden_program(runtime.data_dir)
  fresh_storage = HiddenSubmissions::ProgramStorage.new(fresh_program.allocate)
  assert_equal(2, fresh_storage.read.fetch("storage_revision"), "Reload resurrected an old answer")
  assert_equal([primary], fresh_runtime.path_resolutions)
  replacement = vaults.last.prepare(**identity, payload: {"answer" => "Nowa odpowiedź"})
  assert_equal(3, fresh_storage.read.fetch("storage_revision"))
  assert_equal(replacement.commitment, HiddenSubmissions::Vault.new(fresh_storage).reveal(**identity).commitment)
  assert_equal(3, JSON.parse(File.binread(path)).fetch("storage_revision"))
  assert_equal([primary], runtime.path_resolutions, "A write resolved the native path again")

  distinct = HiddenSubmissions::ProgramStorage.new(program.allocate, path: "nested/other.json")
  distinct.update { |root| root["entries"]["separate"] = true }
  assert_equal({"separate" => true}, distinct.read.fetch("entries"))
  assert_equal([primary, "nested/other.json"], runtime.path_resolutions)
  assert_equal(replacement.commitment, vaults.first.reveal(**identity).commitment)

  foreign_program, = native_hidden_program(File.join(directory, "another-app"))
  foreign_storage = HiddenSubmissions::ProgramStorage.new(foreign_program.allocate)
  assert_equal({}, foreign_storage.read.fetch("entries"), "Applications shared answers")
  ["../outside.json", "../../outside.json", "..\\outside.json"].each do |unsafe|
    storage = HiddenSubmissions::ProgramStorage.new(program.allocate, path: unsafe)
    assert_raises(Programs::ProgramError) { storage.update { |root| root["entries"]["unsafe"] = true } }
  end
  assert(!File.exist?(File.join(directory, "outside.json")), "Host path validation was bypassed")
  assert(Dir.glob(File.join(directory, "**", "*.tmp-*")).empty?, "Temporary snapshot files leaked")
end

puts "PASS build245 hidden storage: native Program/Runtime path validation and caching, UTF-8 legacy migration, fresh snapshots, revisions, app/path isolation"
