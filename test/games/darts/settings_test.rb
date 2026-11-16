# encoding: UTF-8
require_relative '../../support/ui'

class CheckBox < FakeControl
  attr_accessor :label, :checked
  def initialize(label, checked: false); super(); @label, @checked = label, checked; end
end unless defined?(CheckBox)

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
assert(preferences.normalize(nil) == {'locator_sound'=>'round', 'public_rankings'=>false}, 'missing Darts preferences changed the default')
assert(preferences.normalize('locator_sound'=>'clear', 'public_rankings'=>true) ==
  {'locator_sound'=>'clear', 'public_rankings'=>true}, 'valid Darts preferences were rejected')
[nil, 3, 'warm', '../bright', 'BRIGHT'].each do |value|
  assert(preferences.normalize('locator_sound'=>value, 'public_rankings'=>'true') ==
    {'locator_sound'=>'round', 'public_rankings'=>false}, 'invalid Darts preference escaped normalization')
end

old_wait = Form.instance_method(:wait)
driver = nil
Form.send(:define_method, :wait) { driver.call(self) }
begin
  program = DartsSettingsProgram.new
  withdrawn = 0
  publish_prompts = 0
  withdrawal_prompts = 0
  driver = lambda do |form|
    locator, public_rankings, preview, withdraw, = form.fields
    assert(locator.header == 'Aiming sound (only for you)', 'Darts sound choice has an unclear label')
    assert(locator.options == %w[Rounded Clear Bright] && locator.index == 0, 'Darts sound choices or default changed')
    assert(!public_rankings.checked, 'public Darts rankings were enabled without the player opting in')
    assert(public_rankings.label == 'Publish new Darts records in the public rankings',
      'Darts publication setting does not distinguish new results from existing public ones')
    assert(withdraw.label == 'Remove my results from the public Darts rankings',
      'Darts settings do not expose public-result withdrawal')
    withdraw.trigger(:press)
    locator.index = 2
    public_rankings.checked = true
    preview.trigger(:press)
    asset, options, sound = program.created.last
    assert(asset == 'darts_locator_bright' && options == {loop: false, sample: false}, 'preview loaded the wrong asset or mode')
    assert(sound.volume == 1.0 && sound.plays == 1, 'preview did not use the audible game level')
    form.accept_button.trigger(:press)
  end
  result = GameRoomDarts::Settings.new({}, program: program,
    withdraw:-> { withdrawn += 1; true }, confirm_withdraw:-> { withdrawal_prompts += 1; true },
    confirm_publish:-> { publish_prompts += 1; true }, notify:->(_message) {}).wait
  assert(result.values == {'locator_sound'=>'bright', 'public_rankings'=>true} && result.publish_saved,
    'Darts settings did not return the opt-in and saved-record publication choice')
  assert(withdrawn == 1 && withdrawal_prompts == 1 && publish_prompts == 1,
    'Darts settings did not independently confirm withdrawal and existing-record publication')
  assert(program.released == program.managed && program.managed.first.closes == 1, 'preview stream leaked after saving')

  driver = lambda do |form|
    form.fields.first.index = 1
    form.cancel_button.trigger(:press)
  end
  assert(GameRoomDarts::Settings.new({'locator_sound'=>'bright', 'public_rankings'=>true}, program: program,
    confirm_publish:-> { raise 'unchanged publication prompted again' }).wait == nil,
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
