require_relative '../../support/cheat'
require_relative '../../support/cheat_sound'
require_relative '../../../lib/local_game_presentation'
require_relative '../../../lib/game_event_presenter'
include GameRoomTest::CheatFixture

cheat_start
memory = Object.new
memory.define_singleton_method(:read_json) { |_path, default: nil| default }
memory.define_singleton_method(:write_json) { |_path, _value| true }
names = GameRoomLocalNamePresentation.new(runtime: memory, account: @players.first)
names.save('Anna Żółć')
renderer = GameRoomLocalGamePresentation.new(@game, names)
program, spoken = CheatSoundProgram.new, []
presenter = GameRoomEventPresenter.new(game: -> { @game }, repository: -> { @repository },
  display_game: -> { renderer.game },
  display_replay: ->(replay, session) { renderer.replay(session, @events, @repository, boundary: replay) },
  raw_input: ->(_session) { @events }, program: -> { program }, viewer: -> { @players.first },
  client: -> { nil }, surface_state: -> { {} }, clock: -> { 0.0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
presenter.process_new_events(@replay, session: @session)
cheat_move(cheat_play(@replay.state[:hands].fetch(@replay.current_player).first(3)))
cheat_move(cheat_command('accept'))
before = @replay
presenter.process_new_events(before, session: @session)
program.voices.each { |voice| voice.done = true }
presenter.event_presentation.advance
cheat_move(cheat_command('challenge'))
challenged = @replay
presenter.process_new_events(challenged, session: @session)
assert(challenged.presentation_events.frozen?, 'The queued source log is mutable')
assert(GameRoomSnapshot.copy(challenged).presentation_events.equal?(challenged.presentation_events),
  'Copying a queued replay duplicated its immutable input log')
assert_equal('buzzer2', program.played.last.first)
# New actions can arrive while the challenge's four sound stages are pending.
cheat_move(cheat_play(@replay.state[:hands].fetch(@replay.current_player).first(2)))
presenter.process_new_events(@replay, session: @session)
@events = @events.map { |event| event.merge('created_at' => 1234) }
names.save('Jan Kowalski')
renderer = GameRoomLocalGamePresentation.new(@game, names)
4.times do
  program.voices.each { |voice| voice.done = true }
  presenter.event_presentation.advance
end
program.voices.each { |voice| voice.done = true }
presenter.event_presentation.advance
assert(!presenter.event_presentation_busy?)
assert_equal(@replay.accepted_events, presenter.event_presentation.visible_replay.accepted_events)
assert_equal(1, program.played.count { |cue, _| cue == 'buzzer2' })
assert(spoken.any? { |text| text.include?('Jan') }, 'Pending speech retained the earlier local name')
corrected = @game.replay(@session, @events, @repository)
presenter.process_new_events(corrected, session: @session)
local = renderer.replay(@session, @events, @repository, boundary: corrected)
assert_equal(@events, local.accepted_events, 'The current view did not adopt corrected native rows')
assert_equal(1, program.played.count { |cue, _| cue == 'buzzer2' }, 'Timestamp correction replayed challenge effects')
altered = GameRoomSnapshot.copy(challenged)
altered.state[:sequence] += 1
assert_raises(ArgumentError) { renderer.replay(@session, @events, @repository, boundary: altered) }
original_actor = @repository.method(:actor_of)
@repository.define_singleton_method(:actor_of) do |event, session = nil|
  event['action'] == 'challenge' ? 'Unauthorized actor' : original_actor.call(event, session)
end
assert_raises(ArgumentError) { renderer.replay(@session, @events, @repository, boundary: challenged) }
puts 'PASS local Cheat deferred challenge: later actions, name change, exact historical states and one challenge cue'
