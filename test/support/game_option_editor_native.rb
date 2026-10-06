require "json"
require "stringio"
require_relative "host_source"

%w[
  ri/__ri eapi/structs eapi/keyboard eapi/speech eapi/resources eltenlink/__eltenlink
  ui/input eapi/common/input ui/form ui/controls/form_field
  ui/controls/list_box ui/controls/edit_box ui/controls/button
  ui/controls/check_box ui/controls/static ui/controls/grid_box
].each { |source| require EltenTestHost.file("src/#{source}.rb") }
Object.include(EltenAPI::UI)
Object.include(EltenAPI::Common)
Object.include(EltenAPI::Controls)
Object.include(EltenAPI::Speech)
Configuration = EltenAPI::Structs::Configuration
Configuration.keyboardscheme = :windows
Configuration.listtype = :linear
Configuration.controlspresentation = :voice_only
Configuration.soundthemeactivation = false
Configuration.linewrapping = false
Configuration.roundupforms = false
Configuration.typingecho = :none
%w[Form FormTimer ListBox EditBox Button CheckBox Static GridBox].each do |name|
  Object.const_set(name, EltenAPI::Controls.const_get(name))
end

module NativeOptionSource
  ROOT = File.expand_path("../..", __dir__)
  @loaded = {}

  class << self
    attr_reader :package_path, :loaded
    attr_accessor :old_setter

    def package=(path)
      require "zip"
      require "zstd-ruby"
      require EltenTestHost.file("src/eapi/programsigning.rb")
      @package_path = File.expand_path(path)
      @entries = {}
      Zip::File.open(@package_path) do |archive|
        manifest = JSON.parse(archive.read("__manifest.json")).fetch("payload")
        bytes = Programs::ProgramSigning.decode_package(archive.read(manifest.fetch("entry"))).fetch(:code_file)
        stream = StringIO.new(bytes)
        magic = "Elten3AppPackage"
        raise "Invalid ELTEN package header" unless stream.read(magic.bytesize) == magic

        read_size = -> { stream.read(4).unpack1("V") }
        JSON.parse(Zstd.decompress(stream.read(read_size.call)))
        until stream.eof?
          type = stream.read(1).unpack1("C")
          name = type == 3 ? "locale/#{stream.read(2)}.mo" : stream.read(stream.read(2).unpack1("v"))
          payload = stream.read(read_size.call)
          @entries[name.downcase] = type == 2 ? payload : Zstd.decompress(payload).b
        end
      end
    end

    def source_path?(path)
      relative = path.delete_prefix(ROOT + "/")
      relative == "__app.rb" || %w[lib/ games/ content/].any? { |prefix| relative.start_with?(prefix) }
    end

    def read(path)
      @entries ? @entries.fetch(path.delete_prefix(ROOT + "/").downcase).b : File.binread(path)
    end

    def load(path)
      return false if @loaded[path]

      source = read(path)
      if old_setter && path == File.join(ROOT, "lib/game_option_editor.rb")
        source = source.sub("binding[1].set_text(value.to_s)", "binding[1].text = value.to_s")
        raise "Cannot reproduce the old option setter" unless source.include?("binding[1].text = value.to_s")
      end
      @loaded[path] = true
      TOPLEVEL_BINDING.eval(source, path, 1)
      $LOADED_FEATURES << path
      true
    end

    def language_files
      paths = @entries ? @entries.keys.grep(%r{\Alocale/[^/]+[.]mo\z}) : Dir.glob("locale/*.mo", base: ROOT)
      paths.to_h { |path| [File.basename(path, ".mo").downcase, File.expand_path(path, ROOT)] }
    end
  end

  module Requires
    def require_relative(name)
      origin = File.expand_path(caller_locations(1, 1).first.path)
      path = File.expand_path(name, File.dirname(origin))
      path += ".rb" unless path.end_with?(".rb")
      return NativeOptionSource.load(path) if NativeOptionSource.source_path?(origin) && NativeOptionSource.source_path?(path)

      require path
    end
    private :require_relative
  end
end

module NativeOptionUI
  class << self
    attr_accessor :characters, :driver, :language
    attr_reader :spoken

    def speak(text)
      raise "Invalid native speech encoding: #{text.inspect}" unless text.valid_encoding?

      (@spoken ||= []) << text
    end
  end
end

module EltenWindow
  def self.keyboard_key_held?(_code); false; end
  def self.keyboard_active?; true; end
  def self.character_input_supported?; true; end
  def self.take_character(_multi)
    text = NativeOptionUI.characters.to_s
    NativeOptionUI.characters = ""
    text
  end
end

module Programs
  def self.emit_event(_event); end
end

module Log
  def self.error(message); raise message; end
  def self.warning(message); raise message; end
end

class Program
  def self.server_app(**options); @server_app_uuid = options.fetch(:uuid); end
  def self.server_app_uuid; @server_app_uuid; end
end

def _(text); text; end
def p_(_context, text)
  return text unless NativeOptionUI.language == "pl"

  { "Checkbox" => "Pole wyboru", "ticked" => "zaznaczone", "unticked" => "niezaznaczone",
    "Checked" => "Zaznaczone", "unchecked" => "niezaznaczone", "Button" => "Przycisk" }.fetch(text, text)
end
def speak(text, **_options); NativeOptionUI.speak(text); end
def speak_sequence(sequence, **_options); NativeOptionUI.speak(sequence.text); end
def espeech(text, *_arguments); NativeOptionUI.speak(text); end
def alert(text, *_arguments); NativeOptionUI.speak(text); end
def speech_stop; end
def speech_actived; false; end
def speech_output_nvda?; false; end
def play_sound(_name, **_options); end
def loop_update(*_arguments); NativeOptionUI.driver.tick(self); end

NativeOptionSource.old_setter = ARGV.delete("--reproduce-old-setter") != nil
raise "Expected at most one optional .eltsetup path" if ARGV.length > 1
NativeOptionSource.package = ARGV.first if ARGV.first
Kernel.prepend(NativeOptionSource::Requires)
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, "__app.rb"))
require_relative "localization"

module NativeOptionTest
  class << self
    attr_reader :checks

    def assert(condition, message)
      @checks = @checks.to_i + 1
      raise message unless condition
    end

    def native_method(type, method, relative)
      path, line = type.instance_method(method).source_location
      assert(File.expand_path(path) == EltenTestHost.file(relative), "#{type}##{method} is not native: #{path}:#{line}")
    end

    def language=(language)
      NativeOptionUI.language = language
      runtime = GameRoomTestLocalization.runtime(language, files: NativeOptionSource.language_files, reader: NativeOptionSource.method(:read))
      GameRoomLocalization.boot(runtime: runtime, host_language: language, known_languages: [])
      assert(GameRoomLocalization.primary_language == language, "Requested #{language} translation was not loaded")
    end
  end

  class Program < EltenGameRoom
    attr_reader :writes, :remembers, :alerts

    def initialize
      @writes, @remembers, @alerts = [], [], []
    end

    def read_json(_path, default:); default; end
    def update_json(path, default:); @writes << [path, yield(default)]; end

    def remember_multiple_choice_options(game, definitions, options)
      @remembers << [game.id, options.dup]
      super
    end

    def alert(message); @alerts << message; end
  end

  class Driver
    attr_reader :form, :result, :program, :game, :frames

    def initialize(game, **options)
      @game, @program = game, Program.new
      @raw_keys, @frames = [], 0
      NativeOptionUI.driver = self
      @fiber = Fiber.new { @program.send(:configure_game_options, game, **options) }
      @form = @fiber.resume
      NativeOptionTest.assert(@fiber.alive? && @form.instance_of?(GameRoomUI::Form), "Editor did not enter the real native form")
      @fields = @form.fields.dup
      NativeOptionTest.assert(form.game_room_program.equal?(program), "Editor lost its owning program")
      pristine
    end

    def tick(owner)
      NativeOptionTest.assert(owner.is_a?(GameRoomUI::Form), "Unexpected nested UI loop: #{owner.class}")
      keys, characters = owner.instance_variable_get(:@wait) == true ? Fiber.yield(owner) : [[], ""]
      state = "\0" * 256
      keys.each { |code| state.setbyte(code, 0x80) }
      events = (@raw_keys - keys).map { |code| [code, false] } + (keys - @raw_keys).map { |code| [code, true] }
      @frames += 1
      EltenAPI::KeyboardState.update(raw_state: state, events: events, now: @frames * 0.1,
        pressed_implies_held: false, synthesize_repeats: false)
      @raw_keys = keys
      NativeOptionUI.characters = characters
      $input_frame_serial = $input_frame_serial.to_i + 1
      $keyboard_state_frame_serial = $input_frame_serial
      $keyboard_state_frame_thread = Thread.current
      $activecontrols = []
    end

    def control(key)
      definition = game.effective_option_definitions.find { |entry| entry.key == key }
      raise "Missing option #{key}" unless definition

      form.fields.find { |field| (field.respond_to?(:label) ? field.label : field.header) == definition.label } || raise("Missing native field #{key}")
    end

    def visible?(field)
      field = control(field) if field.is_a?(String)
      !form.instance_variable_get(:@hidden)[form.fields.index(field)]
    end

    def focus(field)
      field = control(field) if field.is_a?(String)
      NativeOptionTest.assert(visible?(field), "Cannot navigate to hidden field")
      form.fields.length.times do
        return field if form.fields[form.index].equal?(field)

        press(form.index > form.fields.index(field) ? [16, 9] : [9])
      end
      raise "Native Tab navigation did not reach the requested field"
    end

    def toggle(key)
      field = focus(key)
      previous = field.checked
      press([32])
      NativeOptionTest.assert(field.checked != previous, "Native Space did not change #{key}")
      NativeOptionTest.assert(form.fields[form.index].equal?(field), "Changing #{key} stole focus")
      pristine
    end

    def number(key, value)
      field = focus(key)
      press([17, 65])
      NativeOptionTest.assert(field.index != field.check, "Native Ctrl+A did not select #{key}")
      value.to_s.each_char { |character| press([character.ord], character) }
      NativeOptionTest.assert(field.text == value.to_s, "Native numeric input failed for #{key}: #{field.text.inspect}")
      NativeOptionTest.assert(form.fields[form.index].equal?(field), "Numeric input stole focus")
      pristine
    end

    def press(keys, characters = "")
      advance(keys, characters)
      advance([], "") if @fiber.alive?
    end

    def pristine
      NativeOptionTest.assert(program.writes.empty? && program.remembers.empty?, "Options were stored before submission")
      NativeOptionTest.assert(form.fields == @fields, "Editor rebuilt or reordered native controls")
    end

    def finished
      NativeOptionTest.assert(!@fiber.alive?, "Native submit/cancel did not close the editor")
      NativeOptionTest.assert(!form.game_room_hotkeys_active?, "Native form left hotkeys active")
      NativeOptionTest.assert(!EltenAPI::KeyboardState.current.held.any?, "Native resume left a key held")
      result
    end

    private

    def advance(keys, characters)
      outcome = @fiber.resume([keys, characters])
      if @fiber.alive?
        NativeOptionTest.assert(outcome.equal?(form), "Option callback replaced the native form")
      else
        @result = outcome
      end
    end
  end
end
