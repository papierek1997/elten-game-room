require_relative '../../support/cheat'
require_relative '../../../lib/game_sounds'
require_relative '../../../lib/game_sound_output'
require_relative '../../../lib/game_event_presenter'
require_relative '../../support/cheat_sound'
include GameRoomTest::CheatFixture

cheat_start
program = CheatSoundProgram.new
actor = @replay.current_player
cheat_move(cheat_play(@replay.state[:hands].fetch(actor).first(3)))
before = @replay
cheat_move(cheat_command('challenge'))
event = @replay.accepted_events.last
data = {game: @game, event: event, before_replay: before, after_replay: @replay, repository: @repository, viewer: @players.last}
GameRoomSounds.play_event(program, **data)
truth = before.state[:last_packet][:cards].all? { |card| card.start_with?('A') }
expected = ['buzzer2', 'war_open', truth ? 'quiz_wrong_answer' : 'win1', 'draw']
assert_equal(expected, program.played.map(&:first))
assert(program.played.all? { |_name, volume| volume > 0 && volume <= 0.4 }, 'Game volume was not applied')
program.played.clear
program.optional = false
GameRoomSounds.play_event(program, **data)
assert_equal([], program.played, 'Optional effects ignored the setting')
program.optional = true
program.volume = 0
GameRoomSounds.play_event(program, **data)
assert_equal([], program.played, 'Muted game emitted cues')
program.volume = 0.4
covered = true
output = GameRoomSoundOutput.new(program, audio_game: false, covered: -> { covered })
begin
  GameRoomSounds.play_event(program, **data)
  assert(program.played.all? { |_name, volume| volume == 0 }, 'Background audio leaked')
  covered = false
  output.tick
  assert(output.instance_variable_get(:@voices).keys.all? { |voice| voice.volume == 0 }, 'Old effects became audible on return')
ensure
  output.close
end
assert_equal(nil, GameRoomSoundOutput.current(program))
manifest = JSON.parse(File.read(File.expand_path('../../../manifest.json', __dir__), encoding: 'UTF-8'))
embedded = File.read(File.expand_path('../../../__app.rb', __dir__), encoding: 'UTF-8').match(/=begin Elten3AppInfo\s*(.*?)\s*=end Elten3AppInfo/m)[1]
required = [manifest, JSON.parse(embedded)].map { |item| item.fetch('required_assets').fetch('sounds') }
(expected + %w[shuffle play skip]).each do |name|
  assert(GameRoomSounds::ASSET_NAMES.include?(name), 'Cue is not registered')
  assert(required.all? { |items| items.include?(name) }, 'Cue is not in both required-assets manifests')
end
serial = CheatSoundProgram.new
spoken = []
presenter = GameRoomEventPresenter.new(game: -> { @game }, repository: -> { @repository }, program: -> { serial },
  viewer: -> { 'Observer' }, client: -> { nil }, surface_state: -> { {} }, clock: -> { 0.0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
presenter.process_new_events(before, session: @session)
presenter.process_new_events(@replay, session: @session)
assert_equal(expected.take(1), serial.played.map(&:first))
assert_equal([], spoken, 'Challenge resolution was spoken before its reveal cue')
assert_equal(before.accepted_events, presenter.event_presentation.visible_replay.accepted_events, 'A future challenge state appeared before the reveal stages')
3.times do |index|
  serial.voices.last.done = true
  presenter.event_presentation.advance
  assert_equal(expected.take(index + 2), serial.played.map(&:first))
end
assert(!spoken.empty?, 'The resolved challenge has no speech equivalent')
serial.voices.last.done = true
presenter.event_presentation.advance
assert(!presenter.event_presentation_busy?, 'Challenge sound queue did not finish')
presenter.process_new_events(@replay, session: @session)
assert_equal(expected, serial.played.map(&:first), 'Unchanged history replayed challenge effects')
puts 'PASS Cheat actual sound-output boundary: compound challenge/reveal/outcome/collection cues, real assets/manifests, volume, optional effects, background gate and cleanup; no listening claim'
