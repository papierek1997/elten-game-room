require "json"
require_relative "ui"
require_relative "elten_array_shuffle"
require_relative "host_source"

# ELTEN evaluates decompressed sources as binary strings, unlike Ruby's
# ordinary require. Reproduce that boundary without installing or running UI.
module BinaryRulesLoad
  ROOT = File.expand_path("../..", __dir__)
  @loaded = {}

  def self.read(path)
    relative = path.delete_prefix(ROOT + "/")
    # Test/support code belongs to the checkout, not the player installer.
    # Production code/data MUST still come from the package: no disk fallback
    # for a missing runtime record, which would hide an incomplete release.
    development_source = relative.start_with?("test/", "tools/")
    @entries && !development_source ? @entries.fetch(relative.downcase).b : File.binread(path)
  end

  def self.package=(path)
    require "zip"
    require "zstd-ruby"
    require "stringio"
    require EltenTestHost.file('src/eapi/programsigning.rb')
    @entries = {}
    Zip::File.open(path) do |zip|
      manifest = JSON.parse(zip.read("__manifest.json")).fetch("payload")
      data = Programs::ProgramSigning.decode_package(zip.read(manifest.fetch("entry"))).fetch(:code_file)
      io = StringIO.new(data)
      magic = "Elten3AppPackage"
      raise "Invalid code header" unless io.read(magic.bytesize) == magic
      u32 = -> { io.read(4).unpack1("V") }
      @metadata = JSON.parse(Zstd.decompress(io.read(u32.call)))
      until io.eof?
        type = io.read(1).unpack1("C")
        name = type == 3 ? "locale/#{io.read(2)}.mo" : io.read(io.read(2).unpack1("v"))
        payload = io.read(u32.call)
        @entries[name.downcase] = type == 2 ? payload : Zstd.decompress(payload).b
      end
    end
  end

  def self.load(path)
    path = File.expand_path(path)
    development_source = path.start_with?(ROOT + "/test/", ROOT + "/tools/")
    return false if @loaded[path] || (development_source && $LOADED_FEATURES.include?(path))
    @loaded[path] = true
    # Do not force UTF-8 here: that was precisely what hid the build-209 bug.
    TOPLEVEL_BINDING.eval(read(path), path, 1)
    $LOADED_FEATURES << path if development_source
    true
  end

  def self.catalog
    bytes = read(File.join(ROOT, "locale/PL.mo"))
    count, originals, translations = bytes.byteslice(8, 12).unpack("V3")
    count.times.to_h do |index|
      length, offset = bytes.byteslice(originals + index * 8, 8).unpack("V2")
      source = bytes.byteslice(offset, length).force_encoding("UTF-8")
      length, offset = bytes.byteslice(translations + index * 8, 8).unpack("V2")
      [source, bytes.byteslice(offset, length).force_encoding("UTF-8")]
    end
  end

  def self.localization_runtime(language)
    paths = @entries ? @entries.keys.grep(%r{\Alocale/[^/]+[.]mo\z}) : Dir.glob("*.mo", base: File.join(ROOT, "locale")).map { |name| File.join(ROOT, 'locale', name) }
    files = paths.to_h { |path| [File.basename(path, ".mo").downcase, File.expand_path(path, ROOT)] }
    GameRoomTestLocalization.runtime(language, files: files, reader: method(:read))
  end

  def self.source_path?(path)
    relative = path.delete_prefix(ROOT + "/")
    relative == "__app.rb" || %w[games/ lib/ content/ test/ tools/].any? { |prefix| relative.start_with?(prefix) }
  end

  module Requires
    def require_relative(name)
      origin = File.expand_path(caller_locations(1, 1).first.path)
      if BinaryRulesLoad.source_path?(origin)
        path = File.expand_path(name, File.dirname(origin))
        path += ".rb" unless path.end_with?(".rb")
        return BinaryRulesLoad.load(path) if BinaryRulesLoad.source_path?(path)
      end
      require File.expand_path(name, File.dirname(origin))
    end
    private :require_relative
  end
end

BinaryRulesLoad.package = ARGV.first if ARGV.first
RULES_CATALOG = BinaryRulesLoad.catalog
def n_(singular, plural, count)
  _(count.to_i == 1 ? singular : plural)
end

class Program
  def self.server_app(**_options); end
end

Kernel.prepend(BinaryRulesLoad::Requires)
require_relative "localization"
module Programs
  def self.current_runtime
    Thread.current[:game_room_test_runtime] || (@binary_localization_runtime ||= BinaryRulesLoad.localization_runtime(:pl))
  end
end
BinaryRulesLoad.load(File.join(BinaryRulesLoad::ROOT, "__app.rb"))
