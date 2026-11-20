require "json"
require "fileutils"
require "thread"

# Only declared analytics files use this adapter. Resolve the host's authorized
# data directory lazily, once per runtime; resolving an installed app can parse
# its whole signed archive. Never do that on a UI/replay callback or each tick.
class GameRoomAnalyticsStorage
  FILES = %w[statistics-pending.json room-presence-client.json sports-rankings-pending.json darts-rankings-pending.json].freeze

  def initialize(program)
    @program = program
    @lock = Mutex.new
  end

  def read_json(name, default: nil)
    access(name) { |path| read(path, default) }
  end

  def update_json(name, default: nil)
    access(name) do |path|
      value = read(path, default)
      yield value
      payload = JSON.generate(value).encode(Encoding::UTF_8)
      temporary = "#{path}.tmp-#{$$}-#{Thread.current.object_id}"
      begin
        File.open(temporary, "wb") { |file| file.write(payload); file.flush; file.fsync }
        FileUtils.mv(temporary, path)
      ensure
        File.delete(temporary) if File.exist?(temporary)
      end
      value
    end
  end

  private

  def access(name)
    raise ArgumentError, "Unknown analytics file" unless FILES.include?(name)
    @lock.synchronize do
      @root ||= @program.data_path.to_s.dup.freeze
      raise IOError, "Missing analytics directory" if @root.empty?
      path = File.join(@root, name)
      # The stable lock file also protects another process using this profile;
      # locking the replaced JSON inode would not protect an atomic rename.
      File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        raise IOError, "Cannot lock analytics file" unless lock.flock(File::LOCK_EX)
        begin
          yield path
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end
  end

  def read(path, default)
    JSON.parse(File.binread(path))
  rescue Errno::ENOENT
    JSON.parse(JSON.generate(default))
  end
end
