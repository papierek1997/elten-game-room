require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'
require_relative '../../../lib/game_sounds'

players = %w[Alice Bob]
repository = CatHeadTailRepository.new(players)
game = GameRoomGames::Kosciane.new
session = {'options' => JSON.generate(game.default_options)}
roll = cht_event(1, 'Alice', 'roll', '2,2,5,5,5')
score = cht_event(2, 'Alice', 'score', 'full_house')
before = game.replay(session, [roll], repository)
after = game.replay(session, [roll, score], repository)

class GeneralPlaybackProbe
  attr_accessor :enabled, :effects, :level
  attr_reader :played
  def initialize
    @enabled, @effects, @level, @played = true, true, 0.37, []
  end
  def game_room_sound_enabled?(_name); enabled; end
  def game_room_optional_sounds?; effects; end
  def game_room_sound_volume(_name); level; end
  def play_sound_from_asset(name, **options)
    played << [name, options]
    Struct.new(:volume).new(options.fetch(:volume))
  end
end

program = GeneralPlaybackProbe.new
GameRoomSounds.play_event(program, game: game, event: score, before_replay: before,
  after_replay: after, repository: repository, viewer: 'Alice')
assert(program.played.map(&:first) == ['kosciane_column_1'], 'The real General score cue was silently discarded before playback')

root = File.expand_path('../../..', __dir__)
manifest = JSON.parse(File.read(File.join(root, 'manifest.json'), encoding: 'UTF-8'))
source = File.read(File.join(root, '__app.rb'), encoding: 'UTF-8')
embedded = JSON.parse(source[/\A=begin Elten3AppInfo\s+(\{.*?\})\s+=end Elten3AppInfo/m, 1])
names = (1..6).flat_map { |column| ['', '_draw2', '_lose3', '_win1', '_win2', '_bonus', '_doubled'].map { |suffix| "kosciane_column_#{column}#{suffix}" } }
assert(GameRoomSounds::ASSET_NAMES.grep(/\Akosciane_column_/).sort == names.sort, 'Registered General cues differ from current and recorded column effects')
names.each do |name|
  assert(manifest.dig('required_assets', 'sounds').include?(name) && embedded.dig('required_assets', 'sounds').include?(name), "Required General cue missing from a manifest: #{name}")
  assert(File.binread(File.join(root, 'Audio', "#{name}.opus"), 64).include?('OpusHead'), "Missing or invalid General recording: #{name}")
  entry = GameRoomGames::HistoryEntry.new(event_id: 2, kind: :score, value: name)
  cue = GameRoomSounds.event_cue(game: game, event: score, before_replay: before,
    after_replay: after, repository: repository, viewer: 'Alice', history: [entry])
  program.played.clear
  GameRoomSounds.play(program, cue)
  assert(program.played == [[name, {volume: 0.37}]], "General cue bypassed shared playback or volume: #{name}")
end
program.played.clear
program.effects = false
GameRoomSounds.play(program, names.first)
assert(program.played.empty?, 'General ignored the optional-effects setting')
program.effects, program.enabled = true, false
GameRoomSounds.play(program, names.first)
assert(program.played.empty?, 'General ignored the sound gate')
program.enabled, program.level = true, 0.0
GameRoomSounds.play(program, names.first)
assert(program.played.empty?, 'General ignored muted volume')
program.level = 0.37
GameRoomSounds.play(program, 'kosciane_column_7')
assert(program.played.empty?, 'Registering General allowed an unknown sound')
puts 'PASS General playback: real scoring event, current and historical column cues, both manifests, shared volume, optional-effects and output gates'
