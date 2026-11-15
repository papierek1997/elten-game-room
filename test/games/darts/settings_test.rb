# encoding: UTF-8
require_relative '../../support/ui'
require_relative '../../../lib/darts/settings'
require_relative '../../../lib/darts/client'

def assert(value, message)
  raise message unless value
end

class DartsSettingsSound
  attr_accessor :volume
  attr_reader :plays, :closes

  def initialize
    @plays = @closes = 0
  end

  def play; @plays += 1; end
  def pause; end
  def close; @closes += 1; end
end

class DartsSettingsProgram
  attr_reader :created, :managed, :released

  def initialize
    @created, @managed, @released = [], [], []
  end

  def create_sound_from_asset(asset, **options)
    sound = DartsSettingsSound.new
    @created << [asset, options, sound]
    sound
  end

  def manage(sound); @managed << sound; end
  def release(sound); @released << sound; end
end

preferences = GameRoomDarts::Preferences
assert(preferences.normalize(nil) == {'locator_sound'=>'round'}, 'missing Darts preferences changed the default')
assert(preferences.normalize('locator_sound'=>'clear') == {'locator_sound'=>'clear'}, 'valid Darts locator was rejected')
[nil, 3, 'warm', '../bright', 'BRIGHT'].each do |value|
  assert(preferences.normalize('locator_sound'=>value) == {'locator_sound'=>'round'}, 'invalid locator escaped normalization')
end

old_wait = Form.instance_method(:wait)
driver = nil
Form.send(:define_method, :wait) { driver.call(self) }
begin
  program = DartsSettingsProgram.new
  driver = lambda do |form|
    locator, preview, = form.fields
    assert(locator.header == 'Aiming sound (only for you)', 'Darts sound choice has an unclear label')
    assert(locator.options == %w[Rounded Clear Bright] && locator.index == 0, 'Darts sound choices or default changed')
    locator.index = 2
    preview.trigger(:press)
    asset, options, sound = program.created.last
    assert(asset == 'darts_locator_bright' && options == {loop: false, sample: false}, 'preview loaded the wrong asset or mode')
    assert(sound.volume == 1.0 && sound.plays == 1, 'preview did not use the audible game level')
    form.accept_button.trigger(:press)
  end
  result = GameRoomDarts::Settings.new({}, program: program).wait
  assert(result == {'locator_sound'=>'bright'}, 'Darts sound choice was not returned for saving')
  assert(program.released == program.managed && program.managed.first.closes == 1, 'preview stream leaked after saving')

  driver = lambda do |form|
    form.fields.first.index = 1
    form.cancel_button.trigger(:press)
  end
  assert(GameRoomDarts::Settings.new({'locator_sound'=>'bright'}, program: program).wait == nil,
    'Cancel changed the Darts sound choice')
ensure
  Form.send(:define_method, :wait, old_wait)
end

class DartsSettingsGuardAudio
  attr_reader :silences, :refreshes
  def initialize; @silences = @refreshes = 0; end
  def silence; @silences += 1; end
  def refresh_preferences; @refreshes += 1; end
  def close; end
end

class DartsSettingsGuardMouse
  attr_reader :suspends
  def initialize; @suspends = 0; end
  def suspend; @suspends += 1; [[], false]; end
end

audio, mouse = DartsSettingsGuardAudio.new, DartsSettingsGuardMouse.new
program = Object.new
client = GameRoomDarts::Client.new(program, Object.new, audio: audio, mouse: mouse)
ticks = 0
program.define_singleton_method(:show_darts_settings) do |tick:, clock:|
  assert(client.instance_variable_get(:@settings_open), 'Darts input remained active inside its settings')
  2.times { tick.call; ticks += 1 }
end
program.singleton_class.send(:private, :show_darts_settings)
client.show_settings
assert(ticks == 2 && !client.instance_variable_get(:@settings_open), 'Darts settings did not keep or release the client frame')
assert(audio.refreshes == 1 && audio.silences >= 1 && mouse.suspends >= 2,
  'Darts settings did not silence aiming, suspend input and refresh the saved sound')

puts 'PASS Darts settings: three validated sounds, preview cleanup, Cancel and active-game input guard'
