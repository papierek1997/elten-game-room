# encoding: UTF-8
require_relative '../../../lib/darts/audio'

def assert(value, message)
  raise message unless value
end

class DartsTestSound
  attr_accessor :pan, :frequency, :position, :volume
  attr_reader :plays, :closes

  def initialize
    @pan, @frequency, @position, @volume = 0.0, 48_000.0, 0, 1.0
    @plays = @closes = 0
    @playing = false
  end

  def play; @playing = true; @plays += 1; end
  def pause; @playing = false; end
  def playing?; @playing; end
  def length; 0.4; end
  def close; @playing = false; @closes += 1; end
end

class DartsAudioProgram
  attr_accessor :locator_sound
  attr_reader :sounds, :created, :managed, :released

  def initialize
    @sounds, @created, @managed, @released = {}, [], [], []
    @locator_sound = 'round'
  end

  def create_sound_from_asset(name, loop:, sample:)
    @created << [name, loop, sample]
    @sounds[name] = DartsTestSound.new
  end

  def manage(sound); @managed << sound; end
  def release(sound); @released << sound; end

  private

  def darts_preferences; {'locator_sound' => @locator_sound}; end
end

program = DartsAudioProgram.new
audio = GameRoomDarts::Audio.new(program)
audio.load
expected = %w[darts_locator_round ding duck_note_c darts_edge darts_limit notice darts_throw darts_applause darts_consolation
  darts_hit_1 darts_hit_2 darts_hit_3 darts_hit_4 darts_hit_5]
assert(program.created.map(&:first).sort == expected.sort,
  'Darts did not allocate the locator, release, result, quality and five impact assets once')
GameRoomDarts::Preferences::LOCATOR_ASSETS.each_value do |asset|
  locator_path = File.expand_path("../../../Audio/#{asset}.opus", __dir__)
  assert(File.file?(locator_path) && File.binread(locator_path, 64).start_with?('OggS') &&
    File.binread(locator_path, 64).include?('OpusHead'), "Darts locator #{asset} is not a packaged Ogg Opus asset")
end
assert(program.managed == program.sounds.values, 'Darts left audio streams outside host resource management')
audio.update(0, 0, active: true)
round = program.sounds['darts_locator_round']
assert(round.playing? && round.volume == 1.0, 'the default locator is not fully audible in the centre')
centre_frequency = round.frequency
edge_frequencies = [[1_000, 0], [-1_000, 0], [0, 1_000], [0, -1_000]].map do |x, y|
  audio.update(x, y, active: true)
  round.frequency
end
assert(edge_frequencies.uniq.length == 1 && edge_frequencies.first < centre_frequency,
  'locator pitch still describes vertical position instead of distance from the centre')
semitone_span = 12.0 * Math.log2(centre_frequency / edge_frequencies.first)
assert((semitone_span - 16.0).abs < 0.000001, 'locator pitch does not span the agreed eight whole tones')
audio.update(500, 0, active: true)
halfway_semitones = 12.0 * Math.log2(round.frequency / edge_frequencies.first)
expected_halfway = GameRoomDarts::Audio::LOCATOR_PITCH_SPAN_SEMITONES *
  0.5**GameRoomDarts::Audio::LOCATOR_CURVE_EXPONENT
assert((halfway_semitones - expected_halfway).abs < 0.000001 && halfway_semitones.between?(5.0, 5.5),
  'locator lost its softened fractional curve near the middle of the board')
audio.update(GameRoomDarts::Scoring::BOARD_LIMIT, GameRoomDarts::Scoring::BOARD_LIMIT, active: true)
assert((round.volume - 0.55).abs < 0.000001 && round.frequency == edge_frequencies.first,
  'the locator does not retain its low, audible boundary cue outside the circular board')
program.locator_sound = 'clear'
audio.refresh_preferences
audio.update(0, 0, active: true)
assert(!round.playing? && round.closes == 1 && program.released.include?(round),
  'changing the locator left the previous stream open')
assert(program.sounds['darts_locator_clear'].playing?, 'the saved locator choice did not take effect immediately')
assert(audio.throw_dart == 0.4 && program.sounds['darts_throw'].plays == 1,
  'the release cue did not expose its duration for non-blocking impact scheduling')
edge_path = File.expand_path('../../../Audio/darts_edge.opus', __dir__)
assert(File.file?(edge_path) && File.binread(edge_path, 64).start_with?('OggS') &&
  File.binread(edge_path, 64).include?('OpusHead'), 'Darts edge cue is not a packaged Ogg Opus asset')
assert(audio.edge && program.sounds['darts_edge'].plays == 1 && program.sounds['darts_edge'].pan == 0,
  'the board edge did not have one centred, non-spatial cue')
limit_path = File.expand_path('../../../Audio/darts_limit.opus', __dir__)
assert(File.file?(limit_path) && File.binread(limit_path, 64).start_with?('OggS') &&
  File.binread(limit_path, 64).include?('OpusHead'), 'Darts hard-limit cue is not a packaged Ogg Opus asset')
assert(audio.limit && program.sounds['darts_limit'].plays == 1 && program.sounds['darts_limit'].pan == 0,
  'the hard cursor limit did not have one centred, non-spatial cue')

warning_frequencies = [3, 2, 1].map do |seconds|
  assert(audio.deadline_warning(seconds), "missing #{seconds}-second deadline warning")
  program.sounds['duck_note_c'].frequency
end
assert(warning_frequencies.each_cons(2).all? { |earlier, later| earlier < later } &&
  warning_frequencies.last == 48_000 && program.sounds['duck_note_c'].plays == 3,
  'deadline warnings were not three full-volume low rising cues')

{
  [500, 0] => 'darts_hit_1', [500, 500] => 'darts_hit_2', [0, 500] => 'darts_hit_3',
  [-500, 500] => 'darts_hit_4', [-500, 0] => 'darts_hit_5'
}.each do |(x, y), asset|
  before = program.sounds[asset].plays
  delay = audio.impact(GameRoomDarts::Scoring.points(x, y), x: x, y: y)
  assert(program.sounds[asset].plays == before + 1, "wrong impact recording for #{x},#{y}")
  ratio = 1.0 + y.to_f / GameRoomDarts::Scoring::BOARD_LIMIT * 0.12
  expected_delay = GameRoomDarts::Audio::IMPACT_ATTACK_SECONDS.fetch(asset) / ratio +
    GameRoomDarts::Audio::IMPACT_QUALITY_LEAD_SECONDS
  assert((delay - expected_delay).abs < 0.000001,
    'impact did not expose its measured audible lead')
  assert(program.sounds[asset].pan == x.to_f / GameRoomDarts::Scoring::BOARD_LIMIT,
    'physical board impact lost its horizontal placement')
  before_quality = program.sounds['notice'].plays
  audio.quality(GameRoomDarts::Scoring.points(x, y))
  assert(program.sounds['notice'].plays == before_quality + 1,
    'the score-quality sound was not a separate presentation phase')
end
assert(program.sounds['notice'].plays == 5, 'a scored impact did not also announce its quality')

impact_plays = program.sounds.select { |name, _sound| name.start_with?('darts_hit_') }.values.sum(&:plays)
assert(audio.impact(0, x: 1_000, y: 1_000).zero?, 'a miss reserved time for a nonexistent board impact')
assert(program.sounds.select { |name, _sound| name.start_with?('darts_hit_') }.values.sum(&:plays) == impact_plays,
  'a dart outside the circular board made a board-impact sound')
audio.quality(0)
assert(program.sounds['notice'].plays == 6 && program.sounds['notice'].frequency < 48_000,
  'a miss lost its separate low quality cue')
quality_frequencies = [1, 20, 40, 60, 80, 100].map do |points|
  audio.quality(points)
  program.sounds['notice'].frequency
end
assert(quality_frequencies.each_cons(2).all? { |lower, higher| lower < higher },
  'continuous scores do not produce progressively higher quality cues')
assert(audio.result(won: true) == 0.4 && audio.result(won: false) == 0.4,
  'result recordings do not expose their tails to the non-blocking end-of-game presentation')
assert(program.sounds['darts_applause'].plays == 1 && program.sounds['darts_consolation'].plays == 1,
  'winner and consolation applause were not distinct')

audio.close
assert(program.released.tally == program.managed.tally && program.sounds.values.all? { |sound| sound.closes == 1 },
  'Darts leaked or double-closed a sound stream')
puts 'PASS Darts audio: locator, low countdown, board edge, hard limit, ordered impact/quality cues and cleanup'
