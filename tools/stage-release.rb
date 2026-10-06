require 'optparse'
require_relative "support/release_files"

module GameRoomReleaseStage
  module_function

  def run(source:, destination: nil, manifest: nil, check: false, workspace_staging: false)
    raise ArgumentError, 'Workspace staging needs a destination' if workspace_staging && !destination
    raise ArgumentError, 'Check needs an existing manifest and no destination' if check && (!manifest || destination)
    expected = GameRoomReleaseFiles.snapshot(source)
    if check
      stored = JSON.parse(File.read(manifest), symbolize_names: true)
      raise 'Runtime inventory differs from the recorded snapshot' unless stored == expected
      return expected
    end
    if manifest
      raise "Manifest already exists: #{manifest}" if File.exist?(manifest)
      if destination && GameRoomReleaseFiles.within?(manifest, destination)
        raise ArgumentError, 'The inventory sidecar must remain outside the runtime staging directory'
      end
      raise ArgumentError, 'Manifest parent directory does not exist' unless File.directory?(File.dirname(File.expand_path(manifest)))
    end
    if destination
      # Native ELTEN packaging on Windows has a short-path constraint. Leave
      # room for its own temporary files and the longest runtime relative path.
      raise 'Use a short staging directory (at most 80 characters on Windows)' if /mswin|mingw/ =~ RUBY_PLATFORM && File.expand_path(destination).length > 80
      GameRoomReleaseFiles.stage(source, destination, workspace_staging: workspace_staging)
      raise 'Source changed while staging' unless GameRoomReleaseFiles.snapshot(destination) == expected
    end
    File.binwrite(manifest, JSON.pretty_generate(expected) + "\n") if manifest
    expected
  end
end

if $PROGRAM_NAME == __FILE__
  options = {source: File.expand_path('..', __dir__)}
  OptionParser.new do |parser|
    parser.on('--source DIRECTORY') { |value| options[:source] = File.expand_path(value) }
    parser.on('--destination NEW_DIRECTORY') { |value| options[:destination] = File.expand_path(value) }
    parser.on('--workspace-staging') { options[:workspace_staging] = true }
    parser.on('--manifest NEW_FILE') { |value| options[:manifest] = File.expand_path(value) }
    parser.on('--check') { options[:check] = true }
  end.parse!
  abort 'Unexpected arguments' unless ARGV.empty?
  result = GameRoomReleaseStage.run(**options)
  puts JSON.generate(files: result.fetch(:files).length, sha256: result.fetch(:sha256))
end
