# Build-time only. Never distribute this tool or the source tree wholesale.
require "json"
require "fileutils"
require "pathname"
require "digest"
require "open3"

module GameRoomReleaseFiles
  ROOT_FILES = %w[__app.rb manifest.json README.md LICENSE THIRD_PARTY_NOTICES.md].freeze
  README_TRANSLATIONS = %w[EN CS ES RU].map { |language| "content/readme/#{language}.md" }.freeze
  AUDIO_EXTENSIONS = %w[.ogg .opus .wav .wave .mp3 .flac .aac .m4a .wma .spx .webm].freeze
  REQUIRED_FILES = (ROOT_FILES + README_TRANSLATIONS + %w[locale/PL.mo LICENSES/RUBY.txt LICENSES/RUBY-BSDL.txt
    lib/vendor/unicode_normalize/normalize.rb lib/vendor/unicode_normalize/tables.rb]).freeze

  def self.allowed?(relative)
    return false if relative.split("/").any? { |part| part.start_with?(".") }
    ROOT_FILES.include?(relative) || README_TRANSLATIONS.include?(relative) ||
      relative.match?(%r{\A(?:games|lib|content)/.+\.rb\z}) ||
      (relative.start_with?("Audio/") && AUDIO_EXTENSIONS.include?(File.extname(relative).downcase)) ||
      relative.match?(%r{\Alocale/[A-Za-z]{2}\.mo\z}) ||
      relative.match?(%r{\ALICENSES/.+\.txt\z}) ||
      relative.match?(%r{\Acontent/.+_(?:NOTICE|NOTICES|LICENSE|SOURCES)\.(?:md|txt)\z})
  end

  def self.files(source)
    source = File.realpath(source)
    selected = Dir.chdir(source) do
      Dir.glob("**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) && allowed?(path) }.sort
    end
    missing = REQUIRED_FILES - selected
    raise "Missing release files: #{missing.join(', ')}" unless missing.empty?
    folded = selected.map(&:downcase)
    raise "Case-insensitive release path collision" unless folded.uniq == folded
    selected.each do |relative|
      actual = File.realpath(File.join(source, relative))
      raise "Release file escapes source: #{relative}" unless actual.start_with?(source + "/")
      if relative.start_with?("Audio/")
        header = File.binread(actual, 128)
        unless File.extname(relative) == ".opus" && header.start_with?("OggS") && header.include?("OpusHead")
          raise "Release audio must be Ogg Opus (.opus), authored at 144 kb/s VBR: #{relative}"
        end
      end
    end
    ruby = selected.grep(/\.rb\z/)
    ruby.each do |relative|
      File.read(File.join(source, relative), encoding: "UTF-8").scan(/\brequire_relative\s*(?:\(\s*)?["']([^"']+)["']/).flatten.each do |dependency|
        dependency += ".rb" if File.extname(dependency).empty?
        resolved = Pathname.new(File.join(File.dirname(relative), dependency)).cleanpath.to_s.tr("\\", "/")
        raise "Release dependency is absent: #{relative} -> #{resolved}" unless ruby.include?(resolved)
      end
    end
    manifest = JSON.parse(File.read(File.join(source, "manifest.json")))
    manifest.fetch("required_assets", {}).fetch("sounds", []).each do |sound|
      matches = selected.select { |file| file.start_with?("Audio/") && File.basename(file, File.extname(file)).casecmp(sound).zero? }
      raise "Required sound must have exactly one file: #{sound}" unless matches.length == 1
    end
    selected.freeze
  end

  def self.stage(source, destination, workspace_staging: false)
    source = File.realpath(source)
    destination = File.expand_path(destination)
    raise "Release destination already exists" if File.exist?(destination)
    paths = files(source)
    # Resolve the existing parent, rejecting links back into the source tree.
    File.realpath(File.dirname(destination))
    if workspace_staging
      validate_workspace_destination(source, destination)
    else
      raise "Release destination must be outside the source tree" if within?(destination, source)
    end
    Dir.mkdir(destination)
    paths.each do |relative|
      target = File.join(destination, relative)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(source, relative), target, preserve: true)
    end
    raise "Staged release file list differs" unless files(destination) == paths
    paths.each do |relative|
      raise "Staged bytes differ: #{relative}" unless File.binread(File.join(source, relative)) == File.binread(File.join(destination, relative))
    end
    paths
  end

  def self.validate_workspace_destination(source, destination)
    workspace = File.join(source, "Workspace")
    expected = File::ALT_SEPARATOR == "\\" ? workspace.downcase : workspace
    parent = File.dirname(destination)
    parent = parent.downcase if File::ALT_SEPARATOR == "\\"
    unless parent == expected && canonical_target(workspace) == expected && File.dirname(canonical_target(destination)) == expected
      raise ArgumentError, 'Workspace staging requires a new direct subdirectory of <source>/Workspace'
    end
    return unless Pathname.new(source).ascend.any? { |directory| File.exist?(directory.join(".git")) }
    _output, status = Open3.capture2e("git", "-C", source, "check-ignore", "-q", "--", "Workspace/")
    raise 'Workspace must be ignored by Git before staging' unless status.success?
  end

  # The last components may not exist yet. Resolve their existing ancestor so
  # junctions/symlinks and Windows case aliases cannot bypass a boundary.
  def self.canonical_target(path)
    ancestor = File.expand_path(path)
    missing = []
    until File.exist?(ancestor) || File.symlink?(ancestor)
      missing.unshift(File.basename(ancestor))
      parent = File.dirname(ancestor)
      raise ArgumentError, "Missing path root: #{path}" if parent == ancestor
      ancestor = parent
    end
    resolved = File.join(File.realpath(ancestor), *missing)
    File::ALT_SEPARATOR == "\\" ? resolved.downcase : resolved
  end

  def self.within?(path, directory)
    target, root = canonical_target(path), canonical_target(directory)
    target == root || target.start_with?(root.delete_suffix('/') + '/')
  end

  def self.snapshot(source)
    rows = files(source).map do |relative|
      bytes = File.binread(File.join(source, relative))
      {path: relative, bytes: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes)}
    end
    {schema: 1, files: rows, sha256: Digest::SHA256.hexdigest(JSON.generate(rows))}
  end
end
