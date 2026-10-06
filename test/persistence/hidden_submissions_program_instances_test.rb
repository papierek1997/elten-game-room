require_relative "../../lib/hidden_submissions"
require 'timeout'
require 'tmpdir'
require 'fileutils'

# Like ELTEN Program: all instances delegate to the same class-owned runtime.
class SharedHiddenProgram
  class << self
    attr_accessor :directory
    attr_reader :path_resolutions
    def data_path(path)
      @path_resolutions = (@path_resolutions || 0) + 1
      File.join(directory, path)
    end
    def read_json(*); raise 'storage reparses the package for every JSON read'; end
    def write_json(*); raise 'storage reparses the package for every JSON write'; end
  end
  def data_path(path); self.class.data_path(path); end
  def read_json(*args, **options); self.class.read_json(*args, **options); end
  def write_json(*args); self.class.write_json(*args); end
end

directory = SharedHiddenProgram.directory = Dir.mktmpdir('hidden-program-instances-')
at_exit { FileUtils.remove_entry(directory) if File.directory?(directory) }
stores = 2.times.map { HiddenSubmissions::ProgramStorage.new(SharedHiddenProgram.new) }
entered, release, second_entered = Queue.new, Queue.new, Queue.new
first = Thread.new do
  stores[0].update do |root|
    root['entries']['first'] = 1
    entered << true
    release.pop
  end
end
Timeout.timeout(2) { entered.pop }
second = Thread.new do
  stores[1].update { |root| second_entered << true; root['entries']['second'] = 2 }
end
begin
  sleep 0.05
  raise 'second Program instance entered the same file transaction' unless second_entered.empty?
ensure
  release << true
  Timeout.timeout(2) { first.value; second.value }
end
root = stores[0].read
raise 'one answer was lost' unless root['entries'] == {'first' => 1, 'second' => 2}
raise 'shared revision was not incremented twice' unless root['storage_revision'] == 2
20.times { stores.each(&:read) }
raise 'path was resolved again for another instance or read' unless SharedHiddenProgram.path_resolutions == 1
file = File.join(directory, HiddenSubmissions::ProgramStorage::DEFAULT_PATH)
external = Marshal.load(Marshal.dump(root))
external['entries']['external'] = true
File.binwrite(file, JSON.generate(external))
raise 'answers, rather than just the path, were cached' unless stores[1].read == external
File.binwrite(file, JSON.generate(root))
other_path = HiddenSubmissions::ProgramStorage.new(SharedHiddenProgram.new, path: 'other.json')
other_path.update { |data| data['entries']['other'] = true }
raise 'distinct paths were mixed' unless stores[0].read == root
class OtherHiddenProgram < SharedHiddenProgram; end
OtherHiddenProgram.directory = File.join(directory, 'other-app')
other_program = HiddenSubmissions::ProgramStorage.new(OtherHiddenProgram.new)
raise 'another application inherited stored answers' unless other_program.read['entries'].empty?
raise 'another application inherited a cached path' unless OtherHiddenProgram.path_resolutions == 1
puts 'PASS hidden submissions: serialized transactions, cached paths, fresh content, instances and applications isolated'
