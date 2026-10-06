require 'json'
def assert(value, message)
  raise message unless value
end

path = File.expand_path("../../../lib/audio_ball/audio.rb", __dir__)
assert(File.file?(path), 'Audio Ball audio implementation is missing')
require path

require_relative "../../support/localization"
GameRoomTestLocalization.use_language(:en)

def speak(text, stop:, break_sequence:)
  $audio_ball_speech << [text, stop, break_sequence]
end

class AudioBallSound
  attr_accessor :pan, :volume, :frequency
  attr_reader :plays, :seeks, :position, :closes

  def initialize
    @plays, @closes, @seeks = 0, 0, []
    @pan, @volume, @position = 0.0, 1.0, 0.0
    @playing = false
    @frequency = 48_000
  end

  def length; 0.35; end
  def finished?; !playing?; end

  def position=(value)
    @position = value
    @seeks << value
  end

  def play
    raise 'Closed sound was played' if @closes > 0
    @playing = true
    @plays += 1
  end

  def pause
    @playing = false
  end

  def playing?
    @playing
  end

  def close
    @closes += 1
    @playing = false
  end
end

class AudioBallAudioProgram
  attr_reader :sounds, :created, :managed, :released
  attr_accessor :gain, :enabled

  def initialize(missing: [])
    @missing = missing
    @sounds, @created, @managed, @released = {}, [], [], []
    @gain, @enabled = 1.0, true
  end

  def create_sound_from_asset(name, sample: false, loop: false)
    @created << [name, sample, loop]
    return nil if @missing.include?(name)
    @sounds[name] = AudioBallSound.new
  end

  def manage(sound)
    @managed << sound
  end

  def release(sound)
    @released << sound
  end

  private

  def game_room_sound_enabled?(_name)
    @enabled
  end

  def game_room_sound_volume(_name)
    @gain
  end
end

TESTS = {}
def test(name, &block)
  TESTS[name] = block
end

def audio_ball_assets
  GameRoomAudioBall::Audio::ASSETS + GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS
end

def flight(shot = 'up', position: 25.0, turn: 1)
  {'phase' => 'flying', 'position' => position, 'shot' => shot, 'turn' => turn, 'goal' => nil}
end

test('allocates managed shot loops and prepare/stop streams once') do
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  expected = %w[audio_ball_up audio_ball_left audio_ball_down audio_ball_prepare audio_ball_stopped]
  assert(GameRoomAudioBall::Audio::ASSETS.sort == expected.sort, 'The asset list does not match the default cues')
  expected += GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS
  assert(program.created.sort == expected.map { |name| [name, false, GameRoomAudioBall::Audio::SHOTS.value?(name)] }.sort,
    'Shots must loop and preparation must play once using host streams')
  audio.load
  assert(program.created.length == expected.length, 'Repeated loading leaked new sound handles')
  assert(program.managed == program.sounds.values, 'The host does not manage every stream')
  assert(program.sounds.values.none?(&:playing?), 'Audio started before a flying snapshot or a prepare cue')
end

test('tracks outgoing and incoming flight without restarting or allocating each frame') do
  [0, 1].each do |viewer|
    program = AudioBallAudioProgram.new
    audio = GameRoomAudioBall::Audio.new(program)
    sound = program.sounds.fetch('audio_ball_up')
    [25.0, 18.75, 12.5, 6.25, 0.0, 6.25, 12.5, 18.75, 25.0].each do |position|
      audio.update(flight(position: position), viewer: viewer)
      expected = (position / 25.0 * 2.0 - 1.0) * (viewer == 1 ? -1 : 1)
      assert((sound.pan - expected).abs < 0.000001, 'The ball is not panned from the listening side')
      assert(sound.playing? && sound.volume == 1.0, 'Outgoing or incoming flight is silent')
      assert(program.sounds.values.count(&:playing?) == 1, 'More than the current shot is audible')
    end
    assert(sound.plays == 1 && sound.seeks == [0], 'An unchanged flight restarted on each frame')
    assert(program.created.length == audio_ball_assets.length, 'The frame update allocated additional audio handles')
  end
end

test('switches the active shot and rewinds a new attack of the same type') do
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  %w[up left down up].each_with_index do |shot, turn|
    audio.update(flight(shot, turn: turn), viewer: 0)
    active = program.sounds.select { |_, sound| sound.playing? }.keys
    assert(active == ["audio_ball_#{shot}"], 'The previous attack continued under the new attack')
  end
  sound = program.sounds.fetch('audio_ball_up')
  sound.position = 0.25
  before = sound.seeks.length
  audio.update(flight('up', turn: 4), viewer: 0)
  assert(sound.position == 0 && sound.seeks.length == before + 1, 'A new attack reused the old playback position')
end

test('holds silent after defense, during pauses, at goals and for missing snapshots or shots') do
  program = AudioBallAudioProgram.new(missing: ['audio_ball_left'])
  audio = GameRoomAudioBall::Audio.new(program)
  silent = %w[waiting prepared over].map { |phase| flight.merge('phase' => phase) }
  silent += [nil, flight('unknown'), flight('left'), flight.merge('goal' => 0)]
  silent.each do |snapshot|
    audio.update(flight, viewer: 0)
    assert(program.sounds.fetch('audio_ball_up').playing?, 'Test flight did not start')
    3.times { audio.update(snapshot, viewer: 0) }
    assert(program.sounds.values.none?(&:playing?), 'An inactive or unavailable flight kept playing')
  end
  audio.update(flight, viewer: 1)
  3.times { audio.update(flight, viewer: 1, paused: true) }
  assert(program.sounds.values.none?(&:playing?), 'Paused flight remained audible')
  audio.update(flight, viewer: 1)
  assert(program.sounds.fetch('audio_ball_up').playing?, 'Flight did not resume after the pause')
end

test('uses current private Game Room gain and mute without reallocating the loop') do
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  sound = program.sounds.fetch('audio_ball_down')
  program.gain = 0.35
  audio.update(flight('down', position: 12.5), viewer: 0)
  assert(sound.volume == 0.35 && sound.playing?, 'Shared Game Room volume was ignored')
  program.gain = 0.8
  audio.update(flight('down', position: 12.5), viewer: 0)
  assert(sound.volume == 0.8 && sound.plays == 1, 'A live gain change restarted the flight')
  program.enabled = false
  audio.update(flight('down'), viewer: 0)
  assert(sound.volume == 0.0 && !sound.playing?, 'Disabled game sound is still playing')
  program.enabled = true
  program.gain = 0.0
  audio.update(flight('down'), viewer: 0)
  assert(!sound.playing?, 'Zero volume kept the loop running')
  program.gain = 1.0
  audio.update(flight('down'), viewer: 0)
  assert(sound.playing? && sound.volume == 1.0, 'Unmuting failed to resume the current flight')
  assert(program.created.length == audio_ball_assets.length, 'Volume controls reallocated sounds')
end

test('plays preparation once on the preparing side and preserves its tail while prepared') do
  [0, 1].each do |viewer|
    [0, 1].each do |side|
      program = AudioBallAudioProgram.new
      program.gain = 0.4
      audio = GameRoomAudioBall::Audio.new(program)
      audio.update(flight, viewer: viewer)
      audio.prepare(side, viewer: viewer)
      sound = program.sounds.fetch('audio_ball_prepare')
      assert(sound.playing? && sound.plays == 1, 'Preparation did not start one sound')
      assert(sound.pan == (side == viewer ? 1.0 : -1.0), 'Preparation is on the wrong listening side')
      assert(sound.volume == 0.4, 'Preparation ignored Game Room gain')
      3.times { audio.update(flight.merge('phase' => 'prepared'), viewer: viewer) }
      assert(sound.playing? && sound.plays == 1, 'Prepared frames interrupted or repeated the one-shot')
      assert(program.sounds.values.count(&:playing?) == 1, 'Preparation left the old flight audible')
      program.gain = 0.2
      audio.update(flight.merge('phase' => 'prepared'), viewer: viewer)
      assert(sound.volume == 0.2, 'Preparation ignored a live gain change')
      sound.pause
      audio.update(flight.merge('phase' => 'prepared'), viewer: viewer)
      assert(sound.plays == 1, 'The completed prepare cue started again')
      audio.prepare(side, viewer: viewer)
      assert(sound.plays == 2 && sound.position == 0, 'The next explicit preparation did not restart')
      audio.update(flight, viewer: viewer)
      assert(!sound.playing?, 'Preparation continued under the attack')
    end
  end
end

test('falls back to listener-ordered default Elten speech when recordings are missing') do
  $audio_ball_speech = []
  [0, 1].each do |viewer|
    now = 0.0
    program = AudioBallAudioProgram.new(missing: GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS)
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { now })
    audio.update(flight, viewer: viewer)
    count = $audio_ball_speech.length
    audio.point([4, 7], sets: [0, 1], set_finished: false, winner: 1, viewer: viewer, finished: false)
    assert(program.sounds.values.none?(&:playing?), 'Point speech left the flight audible')
    assert($audio_ball_speech.length == count, 'Fallback score skipped the goal pause')
    now = 3.0
    audio.tick
    assert(program.created.length == audio_ball_assets.length, 'The point allocated new sounds')
    audio.close
  end
  assert($audio_ball_speech == [['Score: 4 to 7.', false, false], ['Score: 7 to 4.', false, false]],
    'The point did not use listener-ordered non-interrupting Elten speech')
end

test('speaks complete set and match information after the score fallback') do
  [
    [1, false, [2, 1], 'Score: 5 to 7. You lose the set. Sets: 1 to 2.'],
    [0, true, [3, 1], 'Score: 7 to 5. You win the set. Sets: 3 to 1. You win the match.'],
    [1, true, [3, 1], 'Score: 5 to 7. You lose the set. Sets: 1 to 3. You lose the match.'],
    [nil, true, [3, 1], 'Score: 7 to 5. Player 1 wins the set. Sets: 3 to 1. Player 1 wins the match.']
  ].each do |viewer, finished, sets, expected|
    spoken, now = [], 0.0
    program = AudioBallAudioProgram.new(missing: GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS)
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { now }, speaker: ->(text) { spoken << text })
    audio.point([7, 5], sets: sets, set_finished: true, winner: 0, viewer: viewer, finished: finished)
    assert(spoken.empty?, 'Set/match speech skipped the point pause')
    now = 3.0
    2.times { audio.tick }
    assert(spoken.length == 2 && spoken.join(' ') == expected, 'Score fallback or set/match result is incomplete or out of order')
    audio.close
  end
end

test('announces all five sets using ordinal English source strings') do
  spoken = []
  audio = GameRoomAudioBall::Audio.new(AudioBallAudioProgram.new, speaker: ->(text) { spoken << text })
  (1..5).each { |number| audio.announce_set(number) }
  assert(spoken == ['First set.', 'Second set.', 'Third set.', 'Fourth set.', 'Fifth set.'],
    'A set announcement used the wrong ordinal')
  [0, 6, nil].each { |number| audio.announce_set(number) }
  assert(spoken.length == 5, 'An invalid set announced the wrong ordinal')
end

test('speaks the named ten-second warning without a recorded cue') do
  $audio_ball_speech = []
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  audio.hurry('Player One')
  assert($audio_ball_speech == [['Player One, you have 10 seconds left.', false, false]],
    'The ten-second warning did not use non-interrupting speech')
  assert(program.sounds.values.none?(&:playing?), 'A recorded sample replaced the ten-second warning')
end

test('normalizes binary-loaded translations and player names to UTF-8 before speech') do
  binary = Module.new
  %w[preferences sound_pack].each do |name|
    dependency = File.expand_path("../../../lib/audio_ball/#{name}.rb", __dir__)
    binary.module_eval(File.binread(dependency), dependency, 1)
  end
  point_path = File.expand_path("../../../lib/audio_ball/point_audio.rb", __dir__)
  binary.module_eval(File.binread(point_path), point_path, 1)
  binary.module_eval(File.binread(path), path, 1)
  spoken = []
  now = 0.0
  program = AudioBallAudioProgram.new(missing: GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS)
  audio = binary::GameRoomAudioBall::Audio.new(program, clock: -> { now }, speaker: ->(text) { spoken << text })
  GameRoomTestLocalization.use_language(:pl)
  audio.point([2, 3], sets: [0, 0], set_finished: false, winner: 1, viewer: 0, finished: false)
  now = 3.0
  audio.tick
  assert(spoken.last == 'Wynik: 2 do 3.' && spoken.last.encoding == Encoding::UTF_8, 'Binary point speech was not translated to UTF-8')
  audio.announce_set(1)
  assert(spoken.last == 'Pierwszy set.' && spoken.last.encoding == Encoding::UTF_8, 'Binary set speech was not normalized')
  audio.hurry('Żaneta')
  assert(spoken.last == 'Żaneta, zostało 10 sekund na uderzenie.' && spoken.last.encoding == Encoding::UTF_8,
    'A translated warning corrupted a Unicode name')
  audio.point([7, 3], sets: [1, 0], set_finished: true, winner: 0, viewer: 0, finished: false)
  now += 3.0
  2.times { audio.tick }
  assert(spoken.last.include?('Wygrywasz set.') && spoken.last.encoding == Encoding::UTF_8,
    'Game Room translations have incompatible encodings')
ensure
  GameRoomTestLocalization.use_language(:en)
end

test('reset rewinds only flight/preparation and forgets the previous flight without reallocating') do
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  audio.update(flight, viewer: 0)
  program.sounds.each_value { |sound| sound.position = 0.2 }
  audio.reset
  assert(program.sounds.values.none?(&:playing?), 'Reset left a stream playing')
  assert(GameRoomAudioBall::Audio::ASSETS.all? { |name| program.sounds[name].position == 0 }, 'Reset retained a flight/preparation position')
  assert(GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS.all? { |name| program.sounds[name].position == 0.2 }, 'Reset rewound a point recording')
  before = program.sounds.fetch('audio_ball_up').seeks.length
  audio.update(flight, viewer: 0)
  assert(program.sounds.fetch('audio_ball_up').seeks.length == before + 1, 'Reset retained the previous flight identity')
  assert(program.created.length == audio_ball_assets.length, 'Reset reallocated streams')
end

test('close releases every stream once and prevents late sound or speech callbacks') do
  spoken = []
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program, speaker: ->(text) { spoken << text })
  audio.update(flight, viewer: 0)
  audio.close
  audio.close
  audio.reset
  audio.load
  audio.update(flight, viewer: 0)
  audio.prepare(0, viewer: 0)
  audio.announce_set(1)
  audio.hurry('Player One')
  audio.point([1, 0], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
  assert(program.released == program.managed, 'Close leaked or double-released a managed stream')
  assert(program.sounds.values.all? { |sound| sound.closes == 1 && !sound.playing? }, 'Close did not dispose of every stream once')
  assert(program.created.length == audio_ball_assets.length && spoken.empty?, 'A late callback revived closed audio or speech')
end

test('does not revive a muted prepare cue when volume is restored') do
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  audio.prepare(0, viewer: 0)
  program.enabled = false
  audio.update(flight.merge('phase' => 'prepared'), viewer: 0)
  sound = program.sounds.fetch('audio_ball_prepare')
  assert(sound.volume == 0 && !sound.playing?, 'A muted prepare stream kept playing')
  program.enabled = true
  audio.update(flight.merge('phase' => 'prepared'), viewer: 0)
  assert(!sound.playing? && sound.plays == 1, 'Unmuting revived a stale prepare cue')
  program.gain = 0
  audio.prepare(0, viewer: 0)
  assert(sound.plays == 1, 'An explicit muted preparation still played')
end

test('ships Ogg Opus cues preserving original channel counts without raw Ogg copies') do
  GameRoomAudioBall::Audio::ASSETS.each do |name|
    asset = File.expand_path("../../../Audio/#{name}.opus", __dir__)
    assert(File.file?(asset), "Missing encoded Audio Ball asset: #{name}")
    header = File.binread(asset, 128)
    offset = header.index('OpusHead')
    assert(header.start_with?('OggS') && offset, "Not Ogg Opus: #{name}")
    channels = name == 'audio_ball_stopped' ? 2 : 1
    assert(header.getbyte(offset + 9) == channels, "Changed the supplied cue's channel count: #{name}")
    assert(header.byteslice(offset + 12, 4).unpack1('V') == 48_000, "Wrong authoring sample rate: #{name}")
    assert(!File.exist?(asset.sub(/[.]opus$/, '.ogg')), "A raw Ogg copy would fail release validation: #{name}")
  end
end

test('missing preparation or all assets degrade to silence without losing speech') do
  [ ['audio_ball_prepare'], GameRoomAudioBall::Audio::ASSETS ].each do |missing|
    spoken, now = [], 0.0
    program = AudioBallAudioProgram.new(missing: missing + GameRoomRealtime::ScoreAnnouncements::ANNOUNCEMENTS)
    audio = GameRoomAudioBall::Audio.new(program, clock: -> { now }, speaker: ->(text) { spoken << text })
    audio.update(flight, viewer: 0)
    audio.prepare(0, viewer: 0)
    assert(program.sounds.values.none?(&:playing?), 'A missing preparation used an unrelated placeholder sound')
    audio.update(flight('left'), viewer: 1)
    audio.update(nil, viewer: 1)
    audio.point([1, 0], sets: [0, 0], set_finished: false, winner: 0, viewer: 0, finished: false)
    now = 3.0
    audio.tick
    assert(spoken == ['Score: 1 to 0.'], 'Missing recordings disabled normal score speech')
    audio.reset
    audio.close
    audio.close
    assert(program.managed == program.released, 'Missing assets broke resource cleanup')
  end
end

test('works with a host that has no optional management or gain hooks') do
  program = Object.new
  sounds = []
  program.define_singleton_method(:create_sound_from_asset) do |_name, sample: false, loop:|
    sounds << AudioBallSound.new
    sounds.last
  end
  audio = GameRoomAudioBall::Audio.new(program)
  audio.update(flight, viewer: 0)
  assert(sounds[0].playing? && sounds[0].volume == 1.0, 'Missing optional gain hooks did not default to unity')
  audio.close
  assert(sounds.all? { |sound| sound.closes == 1 }, 'Missing optional management hooks prevented close')
end

test('pausing or finishing stops an in-progress preparation') do
  program = AudioBallAudioProgram.new
  audio = GameRoomAudioBall::Audio.new(program)
  audio.prepare(0, viewer: 0)
  audio.update(flight.merge('phase' => 'prepared'), viewer: 0, paused: true)
  assert(program.sounds.values.none?(&:playing?), 'Pausing left preparation audible')
  audio.prepare(1, viewer: 0)
  audio.update(flight.merge('phase' => 'over'), viewer: 0)
  assert(program.sounds.values.none?(&:playing?), 'The completed game left preparation audible')
end

test('documents current default recordings without borrowing historical files attribution') do
  notice = File.read(File.expand_path("../../../THIRD_PARTY_NOTICES.md", __dir__), encoding: 'UTF-8')
  recordings = JSON.parse(File.read(File.expand_path("../../fixtures/audio_ball/recordings.json", __dir__), encoding: 'UTF-8'))
  recordings.each do |name, expected|
    asset = File.expand_path("../../../Audio/#{name}", __dir__)
    assert(Digest::SHA256.file(asset).hexdigest == expected.fetch('sha256'), "Changed recording: #{name}")
    assert(notice.include?(name) && notice.include?(expected.fetch('source')), "Missing current provenance: #{name}")
  end
  assert(notice.include?('kyles') && notice.include?('https://freesound.org/s/452549/') &&
    notice.include?('https://creativecommons.org/publicdomain/zero/1.0/'), 'Preparation attribution is missing')
  %w[221227 ChrisGrundlingh StephenSaldanha].each do |author|
    assert(notice.include?(author), "Missing supplied flight source attribution: #{author}")
  end
  assert(notice.include?('https://creativecommons.org/licenses/by/4.0/'), 'Supplied flight license link is missing')
  assert(notice.include?('0.5 L + 0.5 R') && notice.include?('adjustment of dynamics and loudness'),
    'The flight recording changes are not disclosed')
  %w[discUp.ogg discCenter.ogg discDown.ogg rocketReady.ogg rocketStop.ogg rocketGoal.ogg].each do |source|
    assert(notice.include?(source), "Missing Audiodisc provenance: #{source}")
  end
  notice_text = notice.gsub(/\s+/, ' ')
  assert(notice_text.include?('the mapping between recordings, authors and licenses needs confirmation') &&
    notice_text.include?('No source identifiers or author/license information were supplied for these seven files.'),
    'Unconfirmed recording licenses were presented as confirmed')
end

test('follows real engine prepare, flight, defense and miss transitions for both listeners') do
  require_relative "../../../lib/audio_ball/engine"
  [0, 1].each do |viewer|
    program = AudioBallAudioProgram.new
    audio = GameRoomAudioBall::Audio.new(program)
    engine = GameRoomAudioBall::Engine.new
    %w[up left down].each do |shot|
      holder = engine.holder
      assert(engine.press(holder, 'prepare'), 'Engine did not accept preparation')
      audio.prepare(holder, viewer: viewer)
      audio.update(engine.snapshot, viewer: viewer)
      assert(program.sounds.fetch('audio_ball_prepare').playing?, 'Real prepared snapshot cut its cue')
      assert(engine.press(holder, shot), 'Engine did not accept the attack')
      audio.update(engine.snapshot, viewer: viewer)
      sound = program.sounds.fetch("audio_ball_#{shot}")
      assert(sound.playing? && sound.pan == (holder == viewer ? 1.0 : -1.0), 'Real outgoing or incoming attack is misplaced')
      plays = sound.plays
      engine.step(engine.duration * 0.96)
      audio.update(engine.snapshot, viewer: viewer)
      assert(sound.plays == plays, 'A real moving flight restarted the loop')
      assert(engine.press(engine.receiver, shot), 'Engine did not accept defense near the endpoint')
      3.times { audio.update(engine.snapshot, viewer: viewer) }
      assert(program.sounds.values.none?(&:playing?), 'Real successful defense did not hold silent')
    end
    holder = engine.holder
    engine.press(holder, 'prepare')
    engine.press(holder, 'up')
    audio.update(engine.snapshot, viewer: viewer)
    engine.step(engine.duration)
    audio.update(engine.snapshot, viewer: viewer)
    assert(engine.phase == :over && program.sounds.values.none?(&:playing?), 'A real miss did not stop audio')
    audio.close
  end
end

TESTS.each do |name, body|
  body.call
  puts "PASS #{name}"
end
puts "PASS Audio Ball audio: #{TESTS.length} cases (fake host handles; no device playback)"
