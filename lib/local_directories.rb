require 'fileutils'
require 'thread'

# Resolve the host's storage identity once, before any interactive game starts.
# The adapter belongs to this application's Runtime only, never to the global
# host or another program. A reload gets a new Runtime and fresh directories.
module GameRoomLocalDirectories
  LOCK = Mutex.new

  def self.ready?(runtime)
    runtime.is_a?(PreparedPaths) && runtime.instance_variable_get(:@game_room_local_settings_cleaned) == true
  end

  def self.prepare(runtime)
    LOCK.synchronize do
      return if ready?(runtime)

      unless runtime.is_a?(PreparedPaths)
        roots = {data: runtime.data_dir.dup.freeze, cache: runtime.cache_path.dup.freeze}.freeze
        roots.each_value { |path| FileUtils.mkdir_p(path) }
        runtime.instance_variable_set(:@game_room_directory_roots, roots)
        runtime.extend(PreparedPaths)
      end
      # Run once in the existing finite startup task. Re-read under the host's
      # JSON lock so removing an obsolete key cannot overwrite a concurrent edit.
      settings = runtime.read_json('settings.json', default: nil)
      if settings.is_a?(Hash) && settings.key?('display_name')
        runtime.update_json('settings.json', default: {}) do |current|
          current.delete('display_name') if current.is_a?(Hash)
        end
      end
      runtime.instance_variable_set(:@game_room_local_settings_cleaned, true)
    end
  end

  module PreparedPaths
    def data_dir
      @game_room_directory_roots.fetch(:data).dup
    end

    # Keep the native cache_path normalization, containment and parent-creation
    # contract. Native data_path/read_json/write_json already use data_dir, so
    # they retain their own validation while sharing the prepared data root.
    def cache_path(path = '')
      path = normalize_name(path)
      root = @game_room_directory_roots.fetch(:cache)
      return root.dup if path.empty?

      full = File.expand_path(EltenPath.join(root, path))
      root = File.expand_path(root)
      unless full == root || full.start_with?(root + File::SEPARATOR)
        raise Programs::ProgramError, "Unsafe app cache path #{path.inspect}"
      end
      FileUtils.mkdir_p(File.dirname(full)) unless File.directory?(File.dirname(full))
      full
    end
  end

  module Entry
    def prepare_local_directories
      runtime = self.class.app_runtime
      return if GameRoomLocalDirectories.ready?(runtime)

      EltenAPI::Tasks.run(title: 'Power Games', ui: :none, cancellable: false) do
        GameRoomLocalDirectories.prepare(runtime)
      end
    end
  end
end
