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
  attr_reader :sounds, :created, :managed, :released

  def initialize
    @sounds, @created, @managed, @released = {}, [], [], []
  end

  def create_sound_from_asset(name, loop:, sample:)
    @created << [name, loop, sample]
    @sounds[name] = DartsTestSound.new
  end

  def manage(sound); @managed << sound; end
  def release(sound); @released << sound; end
end

program = DartsAudioProgram.new
audio = GameRoomDarts::Audio.new(program)
audio.load
expected = %w[pong_ball ding notice darts_throw darts_applause darts_consolation darts_hit_1 darts_hit_2 darts_hit_3 darts_hit_4 darts_hit_5]
assert(program.created.map(&:first).sort == expected.sort,
  'Darts did not allocate the locator, release, result, quality and five impact assets once')
assert(program.managed == program.sounds.values, 'Darts left audio streams outside host resource management')
assert(audio.throw_dart == 0.4 && program.sounds['darts_throw'].plays == 1,
  'the release cue did not expose its duration for non-blocking impact scheduling')

{
  [500, 0] => 'darts_hit_1', [500, 500] => 'darts_hit_2', [0, 500] => 'darts_hit_3',
  [-500, 500] => 'darts_hit_4', [-500, 0] => 'darts_hit_5'
}.each do |(x, y), asset|
  before = program.sounds[asset].plays
  audio.impact(GameRoomDarts::Scoring.points(x, y), x: x, y: y)
  assert(program.sounds[asset].plays == before + 1, "wrong impact recording for #{x},#{y}")
  assert(program.sounds[asset].pan == x.to_f / GameRoomDarts::Scoring::BOARD_LIMIT,
    'physical board impact lost its horizontal placement')
end
assert(program.sounds['notice'].plays == 5, 'a scored impact did not also announce its quality')

impact_plays = program.sounds.select { |name, _sound| name.start_with?('darts_hit_') }.values.sum(&:plays)
audio.impact(0, x: 1_000, y: 1_000)
assert(program.sounds.select { |name, _sound| name.start_with?('darts_hit_') }.values.sum(&:plays) == impact_plays,
  'a dart outside the circular board made a board-impact sound')
assert(program.sounds['notice'].plays == 6 && program.sounds['notice'].frequency < 48_000,
  'a miss lost its separate low quality cue')
audio.result(won: true)
audio.result(won: false)
assert(program.sounds['darts_applause'].plays == 1 && program.sounds['darts_consolation'].plays == 1,
  'winner and consolation applause were not distinct')

audio.close
assert(program.released == program.managed && program.sounds.values.all? { |sound| sound.closes == 1 },
  'Darts leaked or double-closed a sound stream')
puts 'PASS Darts audio: five sector impacts, spatial placement, separate quality cue and cleanup'
