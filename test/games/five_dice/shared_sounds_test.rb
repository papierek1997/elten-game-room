require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'
require_relative '../../../games/balut'
require_relative '../../../lib/game_sounds'

sounds = GameRoomFiveDiceSounds
assert(sounds.roll([1, 2, 3, 4, 5]) == 'roll', 'Ordinary roll has an unrelated effect')
assert(sounds.roll([6] * 5) == %w[roll five_dice_bonus], 'Five equal dice have no common cue')
assert(sounds.roll([nil] * 5) == 'roll', 'An incomplete roll gained a success cue')
assert(sounds.score(zero: true) == %w[five_dice_record five_dice_zero], 'Zero is not distinct from a normal record')
assert(sounds.score(effect: :bonus) == %w[five_dice_record five_dice_bonus], 'A bonus is not distinct from zero')
(1..6).each do |column|
  assert(sounds.score(column: column) == "kosciane_column_#{column}", 'The common column recording changed')
  sounds::EFFECTS.each do |effect, suffix|
    assert(sounds.score(column: column, effect: effect) == "kosciane_column_#{column}_#{suffix}", 'A combined recording lost its timing')
  end
end
failure = 'kosciane_column_1_lose3'
assert(sounds.score(recording: failure, zero: true) == failure, 'A school failure plays a second loss effect')

players = %w[Alice Bob]
repository = CatHeadTailRepository.new(players)
class FiveDiceSoundProbe
  attr_reader :played
  attr_accessor :effects
  def initialize; @played, @effects = [], true; end
  def game_room_optional_sounds?; effects; end
  def game_room_sound_volume(_name); 0.37; end
  def play_sound_from_asset(name, **options)
    @played << [name, options]
    Struct.new(:volume).new(options.fetch(:volume))
  end
end

[GameRoomGames::Yahtzee.new, GameRoomGames::Kosciane.new, GameRoomGames::Balut.new].each do |game|
  session = {'options'=>JSON.generate(game.default_options)}
  roll = cht_event(1, 'Alice', 'roll', '6,6,6,6,6')
  before = game.replay(session, [], repository)
  after = game.replay(session, [roll], repository)
  program = FiveDiceSoundProbe.new
  saved = Marshal.dump([roll, before, after])
  GameRoomSounds.play_event(program, game: game, event: roll, before_replay: before,
    after_replay: after, repository: repository, viewer: 'Alice')
  assert(program.played == [['roll', {volume: 0.37}], ['five_dice_bonus', {volume: 0.37}]], "#{game.id}: real roll bypassed common output")
  assert(saved == Marshal.dump([roll, before, after]), "#{game.id}: selecting sounds mutated replay")
  program.played.clear
  program.effects = false
  GameRoomSounds.play_event(program, game: game, event: roll, before_replay: before,
    after_replay: after, repository: repository, viewer: 'Alice')
  assert(program.played.empty?, "#{game.id}: common cues ignored the optional-sounds gate")

  events = 3.times.map { |index| cht_event(index + 1, 'Alice', 'roll', '1,1,1,1,2') }
  category = {'yahtzee'=>'full_house', 'kosciane'=>'cross:full_house', 'balut'=>'straight'}.fetch(game.id)
  score = cht_event(4, 'Alice', 'score', category)
  before = game.replay(session, events, repository)
  after = game.replay(session, events + [score], repository)
  assert(after.accepted_events.length == 4, "#{game.id}: zero fixture was refused")
  cue = GameRoomSounds.event_cue(game: game, event: score, before_replay: before,
    after_replay: after, repository: repository, viewer: 'Alice')
  expected = game.id == 'yahtzee' ? %w[five_dice_record five_dice_zero] : %w[kosciane_column_1 five_dice_zero]
  assert(cue == expected, "#{game.id}: actual zero lost its column or short zero cue: #{cue.inspect}")
  program.effects = true
  program.played.clear
  GameRoomSounds.play_event(program, game: game, event: score, before_replay: before,
    after_replay: after, repository: repository, viewer: 'Alice')
  assert(program.played.map(&:first) == expected, "#{game.id}: the zero recording did not reach asset playback")
  assert(program.played.all? { |_name, options| options == {volume:0.37} }, "#{game.id}: zero bypassed shared volume")
end

root = File.expand_path('../../..', __dir__)
manifest = JSON.parse(File.read(File.join(root, 'manifest.json')))
embedded = JSON.parse(File.read(File.join(root, '__app.rb'))[/\A=begin Elten3AppInfo\s+(\{.*?\})\s+=end Elten3AppInfo/m, 1])
%w[five_dice_zero five_dice_record five_dice_bonus five_dice_doubled].each do |name|
  assert(manifest.dig('required_assets', 'sounds').include?(name) &&
    embedded.dig('required_assets', 'sounds').include?(name), 'A replacement cue is absent from an installer manifest')
  assert(File.binread(File.join(root, "Audio/#{name}.opus"), 64).include?('OpusHead'), 'Missing Opus replacement cue')
end

yahtzee = GameRoomGames::Yahtzee.new
state = yahtzee.send(:initial_state, players, yahtzee.default_options)
state[:sheets]['Alice'].update('ones'=>3, 'twos'=>6, 'threes'=>9, 'fours'=>12, 'fives'=>15)
state.update(turn_rolls: 1, dice: [6] * 5)
before = GameRoomGames::Replay.new(players: players, current_player: 'Alice', state: Marshal.load(Marshal.dump(state)))
event = cht_event(2, 'Alice', 'score', 'sixes')
history = []
assert(yahtzee.send(:apply_score, state, event, 'Alice', repository, history), 'Upper bonus fixture was refused')
after = GameRoomGames::Replay.new(players: players, current_player: 'Bob', state: state, history: history)
assert(GameRoomSounds.event_cue(game: yahtzee, event: event, before_replay: before,
  after_replay: after, repository: repository, viewer: 'Alice') == %w[five_dice_record five_dice_bonus], 'Yahtzee upper bonus lacks the common success cue')
misery = GameRoomGames::HistoryEntry.new(kind: :score, value: 0)
assert(yahtzee.event_sound_cues(event: {'action'=>'score', 'value'=>'misery'}, before_replay: before,
  after_replay: after, history: [misery], viewer: 'Alice', random_variant: nil) == 'five_dice_record', 'A perfect Misery result sounds like a failed combination')

general = GameRoomGames::Kosciane.new
events = [cht_event(1, 'Alice', 'roll', '2,2,3,3,3'), cht_event(2, 'Alice', 'score', 'full_house')]
session = {'options'=>JSON.generate(general.default_options.merge('double_first'=>true))}
before = general.replay(session, events.first(1), repository)
after = general.replay(session, events, repository)
assert(GameRoomSounds.event_cue(game:general, event:events.last, before_replay:before,
  after_replay:after, repository:repository, viewer:'Alice') == 'kosciane_column_1_doubled',
  'The existing doubled-first-roll action did not use the new combined recording')
puts 'PASS shared score-sheet sounds: three actual games, columns, five equal dice, zero versus school failure, Yahtzee bonus/Misery, playback gates and immutable input'
