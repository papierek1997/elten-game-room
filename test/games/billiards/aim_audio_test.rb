require_relative '../../support/billiards_native'

class Sound
  attr_accessor :volume
  attr_reader :stream, :plays, :closes, :spatial_position
  def initialize(stream:)
    @stream, @plays, @closes = stream, 0, 0
    self.class.instances << self
  end
  def self.instances; @instances ||= []; end
  def opened?; true; end
  def closed?; @closes > 0; end
  def finished?; closed?; end
  def play; @plays += 1; end
  def close; @closes += 1; end
  def spatialize(position:)
    raise 'HRTF unavailable' if self.class.instance_variable_get(:@spatial_error)
    @spatial_position = position
    self
  end
end

module BilliardsAimAudioTest
  extend GameRoomTest::Assertions
  B = GameRoomBilliards
  class Program
    attr_accessor :optional, :enabled, :volume, :hrtf
    attr_reader :pool
    def initialize
      @pool, @optional, @enabled, @volume, @hrtf = NativeAimPool.new, true, true, 0.4, true
    end
    def sound_pool; @pool; end
    def game_room_optional_sounds?; @optional; end
    def game_room_sound_enabled?(_name); @enabled; end
    def game_room_sound_volume(_name); @volume; end
    def game_room_hrtf?(_game); @hrtf == true; end
  end
  class NativeAimPool
    attr_reader :sounds
    def initialize; @sounds = []; end
    def play(sound); @sounds << sound; sound.play; end
    def remove(sound); @sounds.delete(sound); end
  end
  def self.run
    [-1.0, -0.5, 0.0, 0.5, 1.0].zip([500, 2750, 5000, 2750, 500]).each do |offset, hz|
      assert_equal(hz, B::AimAudio.frequency(kind: :ball, offset: offset))
      wave = B::AimAudio.wave(hz)
      assert_equal(['RIFF', 'WAVE'], [wave[0,4], wave[8,4]])
      assert_equal([48_000, 1, 16], [wave[24,4].unpack1('V'), wave[22,2].unpack1('v'), wave[34,2].unpack1('v')])
      samples = wave[44..].unpack('s<*')
      assert_equal([0, 0, 1920], [samples.first, samples.last, samples.size])
      assert(samples.max <= 4915 && samples.min >= -4915, 'Tone clips')
      crossings = samples.each_cons(2).count { |a,b| a <= 0 && b > 0 }
      assert((crossings / 0.04 - hz).abs < 26, 'Synthesized tone has the wrong pitch')
    end
    [nil, {kind: :rail}].each { |contact| assert_equal(nil, B::AimAudio.frequency(contact)) }
    assert_equal(3000, B::AimAudio.frequency(kind: :pocket))
    driver, match, program = BilliardsNativeDriver.new, BilliardsFixture::Match.new, Program.new
    surface = GameSurfaces.build(match.game.surface_spec(match.replay, 'Alice'))
    form = GameRoomUI::Form.new(surface.fields, program: program, quiet: true)
    surface.attach_form(form)
    allowed, actions = true, []
    surface.action_guard = -> { allowed }
    surface.on_action { |action| actions << action }
    cue = surface.fields.first
    driver.frame(cue, [0x25])
    first = program.pool.sounds.last
    assert(first && first.plays == 1 && first.volume == 0.4, 'Arrow failed to play at the game volume')
    assert_equal(nil, first.spatial_position, 'A short arrow cue entered the delayed HRTF pipeline')
    driver.frame(cue, [0x25], repeat: 0x25)
    assert(first.closed? && program.pool.sounds.size == 1, 'Aiming voices accumulated')
    driver.frame(cue)
    assert(!program.pool.sounds.last.closed?, 'Release speech cancelled the short cue')
    surface.send(:adjust, 'angle', 9000)
    assert_equal([], program.pool.sounds, 'Tone continued beyond the ball')
    surface.send(:adjust, 'angle', -9200)
    assert_equal(1, program.pool.sounds.size)
    cue.blur
    assert_equal([], program.pool.sounds, 'Chat/focus change left a tone playing')
    program.optional = false
    surface.send(:adjust, 'angle', 1)
    assert_equal([], program.pool.sounds)
    program.optional, program.enabled = true, false
    surface.send(:adjust, 'angle', 1)
    assert_equal([], program.pool.sounds)
    program.enabled, program.volume = true, 0
    surface.send(:adjust, 'angle', 1)
    assert_equal([], program.pool.sounds)
    program.volume, allowed = 0.4, false
    surface.send(:adjust, 'angle', 1)
    assert_equal([], program.pool.sounds, 'Stale view played a tone')
    allowed, muted = true, true
    output = GameRoomSoundOutput.new(program, audio_game: false, covered: -> { false })
    output.define_singleton_method(:muted?) { muted }
    surface.send(:adjust, 'angle', 1)
    assert_equal([], program.pool.sounds, 'Covered/muted game played an aiming tone')
    muted = false
    surface.send(:adjust, 'angle', 1)
    assert_equal(1, program.pool.sounds.size)
    driver.dialog = ->(dialog) { assert_equal([], program.pool.sounds, 'Editor kept the aiming sound'); dialog.cancel_button.trigger(:press) }
    surface.handle_command('parameters')
    assert_equal([], actions, 'Local aiming wrote a game move')
    assert_equal([], match.events)
    warnings, logger = [], Log.method(:warning)
    Log.define_singleton_method(:warning) { |message| warnings << message }
    directional = B::AimAudio.new(program)
    program.hrtf = true
    Sound.instance_variable_set(:@spatial_error, true)
    [{kind: :ball, offset: 0}, {kind: :pocket}].each do |contact|
      directional.update(contact)
      assert(program.pool.sounds.last.plays == 1 && program.pool.sounds.last.spatial_position.nil?, 'HRTF silenced a short aiming cue')
    end
    assert_equal([], warnings, 'Aiming attempted to initialize HRTF')
    directional.stop
    Sound.instance_variable_set(:@spatial_error, false)
    warnings.clear
    broken = B::AimAudio.new(program)
    opener = Sound.method(:new)
    attempts = 0
    Sound.define_singleton_method(:new) { |**_options| attempts += 1; raise 'Audio device unavailable' }
    3.times { broken.update({kind: :ball, offset: 0.0}) }
    assert_equal([1, 1], [attempts, warnings.size], 'An audio failure was repeatedly retried')
    puts 'Billiards aiming audio: measured 500–5000 Hz PCM, native arrows/repeats, bounded voices, release speech, misses, focus/dialogs, volume/mute/stale guards and no game writes passed.'
  ensure
    Sound.define_singleton_method(:new, opener) if opener
    Sound.instance_variable_set(:@spatial_error, false)
    directional&.stop
    Log.define_singleton_method(:warning, logger) if logger
    cue&.blur
    output&.close
  end
end
BilliardsAimAudioTest.run if $PROGRAM_NAME == __FILE__
