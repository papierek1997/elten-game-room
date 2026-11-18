require 'tmpdir'
require 'json'
require_relative '../support/assertions'
require_relative '../../lib/local_name_presentation'
include GameRoomTest::Assertions

class ReceiverNameStorage
  attr_reader :paths
  def initialize(root); @root, @paths = root, []; end
  def read_json(name, default: nil)
    @paths << name
    path = File.join(@root, name)
    File.exist?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : default
  rescue JSON::ParserError
    default
  end
  def write_json(name, value)
    @paths << name
    File.write(File.join(@root, name), JSON.generate(value), encoding: 'UTF-8')
  end
end

Dir.mktmpdir('receiver-names') do |directory|
  runtime = ReceiverNameStorage.new(directory)
  own = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Grzegorz123')
  other = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Bob')
  assert_equal('Grzegorz123', own.format('Grzegorz123', form: :full))
  own.save("  Grzegorz\u00a0  Turek  Nowak  ")
  assert_equal('Grzegorz Turek Nowak', own.format('grzegorz123', form: :full))
  assert_equal('Grzegorz', own.format('Grzegorz123', form: :first))
  assert_equal('Bob', own.format('Bob', form: :first))
  assert_equal('Grzegorz123', other.format('Grzegorz123', form: :full))
  assert_equal('Grzegorz123', GameRoomParticipants.display_name('Grzegorz123'))
  restarted = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'GRZEGORZ123')
  assert_equal('Grzegorz Turek Nowak', restarted.value)
  restarted.save('Елена Żółć-李')
  assert_equal('Елена', restarted.format('Grzegorz123', form: :first))
  assert_equal('Елена Żółć-李', restarted.value)
  ['', 'One', "A\nB", "A\tB", "A\rB", "A\0 B", "A\u2028B", "A\u202EB", 'A ' + 'x' * 120].each do |invalid|
    before = restarted.value
    assert_raises(ArgumentError) { restarted.save(invalid) }
    assert_equal(before, restarted.value, 'Invalid input altered the saved value')
  end
  restarted.reset
  restarted.save('A ' + 'x' * 118)
  assert_equal(120, restarted.value.length)
  before_failure = restarted.value
  revision = restarted.revision
  original_write = runtime.method(:write_json)
  runtime.define_singleton_method(:write_json) { |_path, _value| raise IOError, 'fixture failure' }
  assert_raises(IOError) { restarted.save('B Nowak') }
  assert_equal(before_failure, restarted.value)
  assert_equal(revision, restarted.revision)
  runtime.define_singleton_method(:write_json, original_write)
  restarted.reset
  assert_equal('Grzegorz123', restarted.format('Grzegorz123', form: :first))
  assert_equal(nil, GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Grzegorz123').value)
  assert(runtime.paths.none? { |path| path == 'settings.json' || path.include?('Grzegorz123') }, 'Names entered synchronized or unscoped settings')
  path = File.join(directory, runtime.paths.first)
  File.write(path, JSON.generate({'version' => 1, 'name' => ['wrong']}))
  assert_equal(nil, GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Grzegorz123').value)
end
puts 'PASS local receiver names: canonical identity, full/first forms, Unicode, normalization, refusal, restart, reset and account isolation'
