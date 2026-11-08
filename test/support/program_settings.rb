class Program
  # Match the host's class-level storage API without loading its installer.
  # Fixtures that need persistent settings can attach a runtime or their own store.
  unless respond_to?(:read_json)
    def self.read_json(path, default: nil)
      @app_runtime ? @app_runtime.read_json(path, default: default) : default
    end
  end
end
