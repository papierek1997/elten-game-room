require_relative "../../support/host_source"
require_relative "../../support/audio_ball_native_keys"
host = EltenTestHost.root
require File.join(host, 'src/eapi/program')

# The fixture is the exact keyboard.rb from 2006bfce (also shipped in the
# signed 237 before the fast-input update). Optional arguments exercise the
# actual old and replacement installer records, with no source fallback.
def keyboard_reload_sources(package = nil)
  paths = %w[lib/audio_ball/keyboard.rb lib/game_surfaces/audio_ball_surface.rb]
  dependencies = %w[lib/game_room_plural_rule.rb lib/game_room_localization.rb lib/host_bridge.rb lib/game_surfaces/specifications.rb lib/audio_ball/rotation.rb lib/game_surfaces/realtime_information.rb]
  return (dependencies + paths).to_h { |path| [path, File.binread(File.expand_path("../../../#{path}", __dir__))] } unless package
  require 'json'
  require 'zip'
  require 'zstd-ruby'
  require 'stringio'
  host = EltenTestHost.root
  require File.join(host, 'src/eapi/programsigning')
  found = {}
  Zip::File.open(package) do |zip|
    manifest = JSON.parse(zip.read('__manifest.json')).fetch('payload')
    io = StringIO.new(Programs::ProgramSigning.decode_package(zip.read(manifest.fetch('entry'))).fetch(:code_file))
    magic = 'Elten3AppPackage'
    raise 'Invalid package header' unless io.read(magic.bytesize) == magic
    u32 = -> { io.read(4).unpack1('V') }
    io.read(u32.call)
    until io.eof?
      type = io.read(1).unpack1('C')
      name = type == 3 ? "locale/#{io.read(2)}.mo" : io.read(io.read(2).unpack1('v'))
      payload = io.read(u32.call)
      found[name] = Zstd.decompress(payload).b if (dependencies + paths).include?(name)
    end
  end
  needed = paths.dup
  needed = dependencies.first(2) + needed if found.fetch(paths.last).include?('game_room_localization')
  needed.unshift('lib/host_bridge.rb') if found.fetch(paths.first).include?('host_bridge')
  needed.unshift('lib/game_surfaces/specifications.rb') if found.fetch(paths.last).include?('specifications')
  needed.unshift('lib/audio_ball/rotation.rb') if found.fetch(paths.last).include?('../audio_ball/rotation')
  if found.fetch(paths.last).include?("require_relative 'realtime_information'")
    needed.insert(needed.index(paths.first), 'lib/game_surfaces/realtime_information.rb')
  end
  needed.to_h { |path| [path, found.fetch(path)] }
end

ReloadManifest = Struct.new(:namespace_name)
ReloadRuntime = Struct.new(:manifest, :namespace)

def keyboard_reload_runtime(sources)
  runtime = ReloadRuntime.new(ReloadManifest.new('GameRoomKeyboardReloadTest'))
  backend = Programs::Execution::RuntimeBackend.new(runtime)
  runtime.namespace = backend.namespace
  # These dependencies are evaluated explicitly below. Keep the allowlist
  # exact; the host itself supplies namespace creation/disposal.
  runtime.namespace.define_singleton_method(:require_relative) do |path|
    raise "Unexpected runtime dependency: #{path}" unless %w[../audio_ball/keyboard ../audio_ball/rotation ../game_room_localization game_room_plural_rule ../host_bridge specifications realtime_information].include?(path)
    true
  end
  surfaces = runtime.namespace.const_set(:GameSurfaces, Module.new)
  surfaces.const_set(:ActionEmitter, GameSurfaces::ActionEmitter)
  sources.each do |path, code|
    backend.evaluate(code, File.expand_path("../../../#{path}", __dir__))
  end
  [backend, runtime.namespace.const_get(:GameRoomAudioBall)::Keyboard, surfaces]
end

def reload_key_frame(field = nil, events: [], held: [], **options)
  raw = "\0" * 256
  held.each { |code| raw.setbyte(code, 0x80) }
  $reload_key_time = $reload_key_time.to_f + 0.016
  result = EltenAPI::KeyboardState.update(raw_state: raw, events: events, now: $reload_key_time,
    pressed_implies_held: false, synthesize_repeats: false, **options)
  $input_frame_serial = $input_frame_serial.to_i + 1
  $keyboard_state_frame_serial = $input_frame_serial
  $keyboard_state_frame_thread = Thread.current
  field.update if field
  result
end

old = keyboard_reload_sources(ARGV[0])
old['lib/audio_ball/keyboard.rb'] = File.binread(File.expand_path("../../fixtures/audio_ball_legacy_keyboard.rb", __dir__)) unless ARGV[0]
current = keyboard_reload_sources(ARGV[1])
target = EltenAPI::KeyboardState.singleton_class
EltenAPI::KeyboardState.reset
legacy_runtime, legacy, legacy_surfaces = keyboard_reload_runtime(old)
legacy.install
reload_key_frame
if legacy.respond_to?(:activate)
  # Newer installers capture only while their game field is active. Model
  # an actual focused field rather than expecting global key collection.
  legacy_field = legacy_surfaces::AudioBallField.new('Previous Audio Ball').extend(EltenAPI::UI)
  legacy_field.focus
end
reload_key_frame(events: [[0x26, true]], held: [0x26])
assert(legacy.frame.is_a?(Array), 'old installer did not produce keyboard metadata')
old_format = if legacy.frame.respond_to?(:held)
  target.instance_variable_get(:@game_room_audio_ball_keyboard_bridge) == true ? 'Frame with boolean marker' : 'Frame with rebindable bridge'
else
  'legacy Array'
end
legacy_runtime.dispose
legacy.define_singleton_method(:capture) { |*| raise 'Retired application observer was called' }
assert(!EltenPrograms.const_defined?(:GameRoomKeyboardReloadTest, false), 'host did not unload the old app namespace')

# An unrelated host extension must neither be replaced nor unwrapped.
other = Module.new do
  define_method(:update) do |*args, **options, &block|
    $reload_unrelated_calls = $reload_unrelated_calls.to_i + 1
    super(*args, **options, &block)
  end
end
target.prepend(other)
depth = target.ancestors.length
runtime, keyboard, surfaces = keyboard_reload_runtime(current)
field = surfaces::AudioBallField.new('Upgrade without restarting ELTEN').extend(EltenAPI::UI)
field.focus
# This line produced the reported Array#held exception before the fix.
reload_key_frame(field)
assert(field.take_input.empty?, 'upgrade replayed a key from the previous application')
assert(keyboard.frame.is_a?(keyboard::Frame), 'observer still belongs to the old namespace')
assert(target.ancestors.length == depth, 'upgrade stacked another keyboard observer')

20.times do |iteration|
  3.times { keyboard.install }
  assert(target.ancestors.length == depth, 'repeated install grew the host ancestor chain')
  keyboard::KEYS.each do |code, command|
    reload_key_frame(field, events: [[code, true], [code, false]])
    assert(field.take_input == [command], "fresh input lost after reload #{iteration}: #{code}")
    # A second adjacent quick tap is not required to be native `pressed`.
    reload_key_frame(field, events: [[code, true], [code, false]])
    assert(field.take_input == [command], "fast repress lost after reload #{iteration}: #{code}")
    field.update
    assert(field.take_input.empty?, 'same frame replayed twice')
  end
  reload_key_frame(field, events: [[0x11, true], [0x57, true], [0x57, false], [0x11, false]])
  assert(field.take_input.empty?, 'modified command leaked into gameplay')
  reload_key_frame(field, events: [[0x26, true]], held: [0x26])
  field.take_input
  EltenAPI::KeyboardState.suppress_held_until_release
  runtime.dispose
  previous_keyboard = keyboard
  previous_keyboard.define_singleton_method(:capture) { |*| raise 'Retired application observer was called' }
  runtime, keyboard, surfaces = keyboard_reload_runtime(current)
  field = surfaces::AudioBallField.new('Reloaded Audio Ball').extend(EltenAPI::UI)
  field.focus
  reload_key_frame(field, events: [[0x26, true]], held: [0x26])
  assert(field.take_input.empty?, 'host-suppressed held key leaked after namespace replacement')
  reload_key_frame(field, events: [[0x26, false], [0x26, true], [0x26, false]])
  assert(field.take_input == ['up'], 'real release/repress remained blocked after reload')
  assert(keyboard.frame.is_a?(keyboard::Frame) && !keyboard.frame.is_a?(previous_keyboard::Frame), 'old namespace captured a new frame')
  assert(target.ancestors.length == depth, 'namespace reload grew the host ancestor chain')
end
assert($reload_unrelated_calls.to_i > 300, 'upgrade detached an unrelated extension')

# Stale legacy/foreign metadata is ignored, never treated as a new command.
result = reload_key_frame
result.instance_variable_set(keyboard::FRAME, [[0x26, false]].freeze)
assert(keyboard.frame.nil?, 'legacy Array metadata was exposed to the new field')
field.update
assert(field.take_input.empty?, 'stale legacy metadata replayed a command')
runtime.dispose
puts "PASS Audio Ball real host namespace unload/reload: #{old_format} -> current Frame, 20 reloads, no retired observer or bridge growth, quick taps, modifiers, host suppression, stale metadata, unrelated extension preserved"
