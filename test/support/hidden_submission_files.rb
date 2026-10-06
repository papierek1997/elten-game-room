require "json"
require "fileutils"
require "tmpdir"
require_relative "../../lib/hidden_submissions"

# Real private files; replacement faults are injected at the storage boundary.
# All paths belong to a disposable test directory, never a real user profile.
class HiddenSubmissionFiles
  class Storage < HiddenSubmissions::ProgramStorage
    private

    def write_snapshot_file(path, value)
      @program.before_hidden_write(File.basename(path))
      super
    end
  end

  attr_reader :directory, :writes, :path_resolutions
  attr_accessor :blocked

  def initialize(directory = nil)
    if directory == nil
      directory = Dir.mktmpdir("game-room-hidden-fixture-")
      at_exit { FileUtils.remove_entry(directory) if File.directory?(directory) }
    end
    @directory = directory
    @writes = []
    @blocked = []
    @path_resolutions = 0
  end

  def data_path(name = "")
    @path_resolutions += 1
    File.join(directory, name)
  end

  def storage
    Storage.new(self)
  end

  def before_hidden_write(name)
    writes << name
    raise Errno::EACCES, "simulated replacement lock" if blocked.include?(name)
  end

  def read_json(name, default:)
    path = File.join(directory, name)
    File.file?(path) ? JSON.parse(File.binread(path)) : default
  end

  def write_json(name, value)
    storage.send(:write_snapshot_file, File.join(directory, name), value)
    true
  end

  def retry_now
    instance_variable_get(:@game_room_hidden_submission_stores)&.each_value { |s| s[:retry_at] = 0.0 }
  end
end
