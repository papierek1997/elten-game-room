require_relative "../../lib/hidden_submissions"
require "timeout"
require "tmpdir"

class SharedHiddenProgram
  class << self
    attr_accessor :directory
    attr_reader :path_resolutions

    def data_path(path)
      @path_resolutions = (@path_resolutions || 0) + 1
      File.join(directory, path)
    end

    def read_json(*)
      raise "storage reparses the package for every JSON read"
    end

    def write_json(*)
      raise "storage reparses the package for every JSON write"
    end
  end

  def data_path(path)
    self.class.data_path(path)
  end

  def read_json(*args, **options)
    self.class.read_json(*args, **options)
  end

  def write_json(*args)
    self.class.write_json(*args)
  end
end

class OtherHiddenProgram < SharedHiddenProgram; end

Dir.mktmpdir("hidden-program-instances-") do |directory|
  SharedHiddenProgram.directory = File.join(directory, "first-app")
  OtherHiddenProgram.directory = File.join(directory, "second-app")
  stores = 2.times.map { HiddenSubmissions::ProgramStorage.new(SharedHiddenProgram.new) }
  entered, release, second_started, second_entered = Queue.new, Queue.new, Queue.new, Queue.new
  first = Thread.new do
    stores[0].update do |root|
      root["entries"]["first"] = 1
      entered << true
      release.pop
    end
  end
  second = nil
  begin
    Timeout.timeout(2) { entered.pop }
    second = Thread.new do
      second_started << true
      stores[1].update { |root| second_entered << true; root["entries"]["second"] = 2 }
    end
    Timeout.timeout(2) do
      second_started.pop
      Thread.pass while second.status == "run"
    end
    raise "second Program instance entered the same file transaction" unless second_entered.empty?
  ensure
    release << true
    Timeout.timeout(2) { first.value; second&.value }
  end
  root = stores[0].read
  raise "one answer was lost" unless root["entries"] == {"first" => 1, "second" => 2}
  raise "shared revision was not incremented twice" unless root["storage_revision"] == 2
  20.times { stores.each(&:read) }
  raise "path was resolved again for another instance or read" unless SharedHiddenProgram.path_resolutions == 1
  file = File.join(SharedHiddenProgram.directory, HiddenSubmissions::ProgramStorage::DEFAULT_PATH)
  external = Marshal.load(Marshal.dump(root))
  external["entries"]["external"] = true
  File.binwrite(file, JSON.generate(external))
  raise "answers, rather than just the path, were cached" unless stores[1].read == external
  File.binwrite(file, JSON.generate(root))
  other_path = HiddenSubmissions::ProgramStorage.new(SharedHiddenProgram.new, path: "other.json")
  other_path.update { |data| data["entries"]["other"] = true }
  raise "distinct paths were mixed" unless stores[0].read == root
  raise "distinct paths did not resolve separately" unless SharedHiddenProgram.path_resolutions == 2
  other_program = HiddenSubmissions::ProgramStorage.new(OtherHiddenProgram.new)
  raise "another application inherited stored answers" unless other_program.read["entries"].empty?
  raise "another application inherited a cached path" unless OtherHiddenProgram.path_resolutions == 1
end
puts "PASS hidden submissions: serialized transactions, cached paths, fresh content, instances and applications isolated"
