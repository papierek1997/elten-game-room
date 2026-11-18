require_relative '../support/duck_challenge_native'
require_relative '../support/cheat'
require_relative '../../games/tic_tac_toe'
require_relative '../../lib/local_game_presentation'
require_relative '../../lib/game_event_presenter'
include GameRoomTest::Assertions

class ReceiverSerialGame < GameRoomGames::TicTacToe
  def serial_event_presentation?; true; end
  def event_presentation_stages(event, repository, _before, after, viewer)
    [{descriptions: describe_event(event, repository, after, viewer), delay: 1, wait_for_sounds: false}]
  end
end

runtime = Object.new
runtime.define_singleton_method(:read_json) { |_path, default: nil| default }
runtime.define_singleton_method(:write_json) { |_path, _value| true }
names = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
names.save('Anna Żółć')
game = ReceiverSerialGame.new
renderer = GameRoomLocalGamePresentation.new(game, names)
repository = GameRoomTest::CheatFixture::Repository.new(%w[Alice Bob])
session = {'options' => '{}'}
events = [
  {'id' => 1, 'actor' => 'Alice', 'action' => 'place', 'value' => '1,1'},
  {'id' => 2, 'actor' => 'Bob', 'action' => 'place', 'value' => '2,1'},
  {'id' => 3, 'actor' => 'Alice', 'action' => 'place', 'value' => '3,1'}]
first = game.replay(session, events.take(1), repository)
view = renderer.replay(session, events, repository, boundary: first)
assert_equal(first.board, view.board, 'A historical view advanced to the latest model')
assert_equal(first.accepted_events, view.accepted_events)
assert(!view.history.any? { |entry| entry.text.include?('C1') }, 'Future history leaked through presentation')
time, spoken, cues = 0, [], []
original = GameRoomSounds.method(:play)
GameRoomSounds.define_singleton_method(:play) { |_program, cue, **_| cues << cue; nil }
begin
  presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { repository },
    display_game: -> { names.value ? renderer.game : game },
    display_replay: ->(replay, _session) { renderer.replay(session, events, repository, boundary: replay) },
    program: -> { nil }, viewer: -> { 'Viewer' }, client: -> { nil }, surface_state: -> { {} },
    clock: -> { time }, covered: -> { false }, speech: ->(message) { spoken << message },
    trace: ->(*) {}, history_changed: ->(*) {}, session_changed: -> {})
  presenter.process_new_events(game.replay(session, [], repository), session: session)
  presenter.process_new_events(game.replay(session, events, repository), session: session)
  assert(spoken.any? { |text| text.include?('Anna A1') }, 'First serial announcement lost the local name')
  names.save('Jan Kowalski')
  time = 1
  presenter.event_presentation.advance
  assert_equal(events.take(2), presenter.event_presentation.visible_replay.accepted_events)
  names.reset
  time = 2
  presenter.event_presentation.advance
  assert(spoken.any? { |text| text.include?('Alice C1') }, 'Reset retained a prebuilt local announcement')
  assert(!spoken.any? { |text| text.include?('Anna C1') }, 'An old name survived in the pending queue')
  time = 3
  presenter.event_presentation.advance
  assert(!presenter.event_presentation_busy?, 'Refreshing a local name restarted the queue')
  assert_equal(3, spoken.count { |text| text.match?(/[ABC]1/) })
  assert_equal(3, presenter.turn_history_entries.length, 'Name refresh discarded turn history')
ensure
  GameRoomSounds.define_singleton_method(:play, original)
end
puts 'PASS exact local presentation prefixes and serial save/reset: canonical queued models, refreshed pending speech, retained turn history and no replayed events'
