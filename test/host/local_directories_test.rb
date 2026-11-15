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
    attr_reader :calls, :root_threads, :settings_writes, :settings_write_threads
    def initialize(root)
      super('directory-fixture')
      @entry_id = root
      @calls, @root_threads = Hash.new(0), []
      @settings_writes = 0
      @settings_write_threads = []
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
  def write_json_file(file, data)
    if File.basename(file) == 'settings.json'
      @settings_writes += 1
      @settings_write_threads << Thread.current
    end
    super
  end

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
  FileUtils.mkdir_p(File.join(root, 'entry', 'data'))
  File.write(File.join(root, 'entry', 'data', 'settings.json'),
    JSON.generate({'display_name'=>'Old', 'keep'=>false}))
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
    assert_equal({'keep'=>false}, fresh.read_json('settings.json'), 'Startup entry retained the old alias')
    assert_equal(1, fresh.settings_writes, 'Startup entry did not clean settings exactly once')
    assert(fresh.settings_write_threads.none? { |thread| thread.equal?(Thread.current) },
      'Obsolete settings cleanup ran on the UI thread')
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

  # An update removes the retired preference without an explicit Settings Save.
  # Native update_json must keep the latest other keys, not the opening snapshot.
  obsolete = Programs::DirectoryFixture.new(File.join(root, 'obsolete'))
  obsolete.write_json('settings.json', {'display_name'=>'Stara nazwa', 'game_sounds'=>false,
    'other'=>{'value'=>17}})
  writes = obsolete.settings_writes
  GameRoomLocalDirectories.prepare(obsolete)
  assert_equal({'game_sounds'=>false, 'other'=>{'value'=>17}}, obsolete.read_json('settings.json'),
    'Startup did not remove only the obsolete alias')
  assert_equal(writes + 1, obsolete.settings_writes, 'Startup did not use one native settings write')
  GameRoomLocalDirectories.prepare(obsolete)
  assert_equal(writes + 1, obsolete.settings_writes, 'Prepared entry wrote settings again')

  clean = Programs::DirectoryFixture.new(File.join(root, 'clean'))
  clean.write_json('settings.json', {'game_sounds'=>false, 'custom'=>[1,2]})
  clean_bytes = File.binread(clean.data_path('settings.json'))
  writes = clean.settings_writes
  GameRoomLocalDirectories.prepare(clean)
  assert_equal(writes, clean.settings_writes, 'Startup rewrote already clean settings')
  assert_equal(clean_bytes, File.binread(clean.data_path('settings.json')))
  missing = Programs::DirectoryFixture.new(File.join(root, 'missing-settings'))
  GameRoomLocalDirectories.prepare(missing)
  assert(!File.exist?(missing.data_path('settings.json')), 'Startup created unnecessary settings')

  corrupt = Programs::DirectoryFixture.new(File.join(root, 'corrupt-settings'))
  File.write(corrupt.data_path('settings.json'), '{"display_name":broken')
  GameRoomLocalDirectories.prepare(corrupt)
  assert_equal('{"display_name":broken', File.binread(corrupt.data_path('settings.json')),
    'Cleanup replaced malformed settings with defaults')
  assert_equal(0, corrupt.settings_writes)

  concurrent = Programs::DirectoryFixture.new(File.join(root, 'concurrent-settings'))
  concurrent.write_json('settings.json', {'display_name'=>'Old', 'counter'=>1})
  original_update = concurrent.method(:update_json)
  concurrent.define_singleton_method(:update_json) do |path, **options, &edit|
    write_json(path, {'display_name'=>'Newer old value', 'counter'=>2, 'new_key'=>false})
    original_update.call(path, **options, &edit)
  end
  GameRoomLocalDirectories.prepare(concurrent)
  assert_equal({'counter'=>2, 'new_key'=>false}, concurrent.read_json('settings.json'),
    'Cleanup overwrote a newer settings snapshot')

  retry_cleanup = Programs::DirectoryFixture.new(File.join(root, 'retry-cleanup'))
  retry_cleanup.write_json('settings.json', {'display_name'=>'Old', 'untouched'=>123})
  original_update = retry_cleanup.method(:update_json)
  retry_cleanup.define_singleton_method(:update_json) { |*| raise IOError, 'write refused' }
  begin
    GameRoomLocalDirectories.prepare(retry_cleanup)
    raise 'A failed cleanup was acknowledged'
  rescue IOError
    assert(!GameRoomLocalDirectories.ready?(retry_cleanup), 'Failed cleanup prevented retry')
    assert_equal('Old', retry_cleanup.read_json('settings.json')['display_name'])
  end
  retry_cleanup.define_singleton_method(:update_json, original_update)
  GameRoomLocalDirectories.prepare(retry_cleanup)
  assert_equal({'untouched'=>123}, retry_cleanup.read_json('settings.json'))
  [obsolete, clean, missing, corrupt, concurrent, retry_cleanup].each(&:close)
end
puts 'PASS startup directories and obsolete settings: once per runtime, background entry, native paths, atomic cleanup, concurrent edits, unchanged/missing/corrupt files and retry'
