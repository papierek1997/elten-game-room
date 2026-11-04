require 'tmpdir'
require 'json'
require 'monitor'
require_relative '../support/native_tasks'
require_relative '../support/assertions'
require_relative '../../lib/local_directories'
include GameRoomTest::Assertions

module EltenPath
  def self.join(*parts); File.join(*parts); end
end unless defined?(EltenPath)

module Programs
  class ProgramError < StandardError; end unless const_defined?(:ProgramError)
  class DirectoryFixture < TestTaskRuntime
    ProgramError = Programs::ProgramError
    attr_reader :calls, :root_threads
    def initialize(root)
      super('directory-fixture')
      @entry_id = root
      @calls, @root_threads = Hash.new(0), []
      @json_file_monitors_guard, @json_file_monitors = Mutex.new, {}
    end
  end
  def self.app_data_dir(entry); File.join(entry, 'data'); end
  def self.app_cache_dir(entry); File.join(entry, 'cache'); end
end

# Execute the real required host's path/JSON methods. Only its storage-identity
# boundary is counted below; loading an installed application is not needed.
source = File.read(EltenTestHost.file('src/eapi/program.rb'), encoding:'UTF-8').gsub("\r\n", "\n")
%w[data_dir data_path cache_path normalize_name read_json write_json update_json json_file_monitor read_json_file write_json_file duplicate_json_value write_binary_file].each do |name|
  body = source[/^    def #{Regexp.escape(name)}(?:\(|\s*\n).*?^    end\n/m]
  raise "Missing native method: #{name}" unless body
  Programs::DirectoryFixture.class_eval(body, EltenTestHost.file('src/eapi/program.rb'))
end
module CountDirectoryResolution
  def data_dir
    @calls[:data] += 1
    @root_threads << Thread.current
    super
  end
  def cache_path(path='')
    @calls[:cache] += 1
    @root_threads << Thread.current
    super
  end
end
Programs::DirectoryFixture.prepend(CountDirectoryResolution)

Dir.mktmpdir('pg-directory-contract-') do |root|
  current = Programs::DirectoryFixture.new(root)
  callers = 4.times.map { Thread.new { GameRoomLocalDirectories.prepare(current) } }
  callers.each(&:value)
  assert_equal({data:1,cache:1}, current.calls, 'Concurrent preparation resolved roots more than once')
  assert(GameRoomLocalDirectories.ready?(current), 'Prepared roots not published')
  data_root, cache_root = current.data_dir, current.cache_path
  data_root.replace('modified by caller')
  cache_root.replace('modified by caller')
  assert_equal(File.join(root,'data'), current.data_dir, 'Caller changed shared data root')
  assert_equal(File.join(root,'cache'), current.cache_path, 'Caller changed shared cache root')
  200.times do
    current.data_path('recordings/żółć/example.txt')
    current.cache_path('recordings/żółć/chunk.jsonl')
  end
  current.write_json('settings.json', {'answer'=>41})
  current.update_json('settings.json') { |state| state['answer'] += 1 }
  assert_equal({'answer'=>42}, current.read_json('settings.json'), 'Native JSON helpers stopped using the data folder')
  assert_equal({data:1,cache:1}, current.calls, 'Gameplay/JSON paths rediscovered the installed package')

  untouched = Programs::DirectoryFixture.new(root)
  ['','plain','./plain','nested/file','nested\\file','../escape','nested/../../escape','/rooted',nil,123].each do |path|
    [:data_path,:cache_path].each do |method|
      results = [untouched,current].map do |runtime|
        begin [:ok,runtime.public_send(method,path)]
        rescue StandardError=>error; [:error,error.class,error.message]
        end
      end
      assert_equal(results.first, results.last, "Cached #{method} changed the native path contract for #{path.inspect}")
    end
  end
  assert(!GameRoomLocalDirectories.ready?(untouched), 'Adapter affected another runtime')
  reloaded = Programs::DirectoryFixture.new(File.join(root,'reloaded'))
  GameRoomLocalDirectories.prepare(reloaded)
  assert_equal(File.join(root,'reloaded','cache'), reloaded.cache_path, 'Reload reused the previous runtime root')

  # The entry uses one existing finite task, not a permanent worker or polling.
  fresh = Programs::DirectoryFixture.new(File.join(root,'entry'))
  program_class = Class.new do
    include GameRoomLocalDirectories::Entry
    class << self; attr_accessor :app_runtime; end
  end
  program_class.app_runtime = fresh
  original = EltenAPI::Tasks.method(:run)
  tasks = []
  EltenAPI::Tasks.define_singleton_method(:run) do |**options,&operation|
    tasks << options
    Thread.new(&operation).value
  end
  begin
    program_class.new.prepare_local_directories
    program_class.new.prepare_local_directories
    assert_equal(1, tasks.size, 'Every window prepared directories again')
    assert_equal(:none, tasks.first[:ui], 'Startup opened an unnecessary dialog')
    assert_equal(false, tasks.first[:cancellable], 'Partial preparation can be cancelled')
    assert(fresh.root_threads.none? { |thread| thread.equal?(Thread.current) }, 'Directory resolution ran on the UI thread')
  ensure
    EltenAPI::Tasks.define_singleton_method(:run, original)
  end
  [current,untouched,reloaded,fresh].each(&:close)

  failed_root = File.join(root,'retry')
  FileUtils.mkdir_p(failed_root)
  File.write(File.join(failed_root,'cache'),'not a directory')
  failed = Programs::DirectoryFixture.new(failed_root)
  begin
    GameRoomLocalDirectories.prepare(failed)
    raise 'Invalid cache root was accepted'
  rescue Errno::EEXIST
    assert(!GameRoomLocalDirectories.ready?(failed), 'Failed preparation published partial roots')
  end
  File.delete(File.join(failed_root,'cache'))
  GameRoomLocalDirectories.prepare(failed)
  assert(GameRoomLocalDirectories.ready?(failed), 'A failed initialization could not be retried')
  failed.close
end
puts 'PASS shared startup directories: once per runtime, background entry, concurrent callers, native path/JSON behavior, caller ownership, other apps and reload isolation'
