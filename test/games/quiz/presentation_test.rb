require_relative "../../support/ui"
require_relative "../../../games/quiz_party"
require_relative "../../../lib/game_event_presenter"

def assert(value, message); raise message unless value; end

game = GameRoomGames::QuizParty.new
replay = GameRoomGames::Replay.new(players: %w[Alice Bob], state: {
  phase: :answering, deadline: 120, round: 1, position: 1,
  players: %w[Alice Bob], commitments: {"Alice" => "saved"}
})
surface = game.surface_spec(replay, "Alice")
assert(surface.prompt == "" && surface.value == "Answer sent.", 'Answered status is not concise')
replay.state[:phase] = :revealing
surface = game.surface_spec(replay, "Alice")
assert(surface.prompt.empty? && surface.value.empty?, 'Reveal phase announces redundant Quiz/collecting text')
replay.state[:phase] = :answering

spoken, sounds = [], []
program = Object.new
program.define_singleton_method(:play_sound_from_asset) { |name, **_options| sounds << name }
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { nil },
  program: -> { program }, viewer: -> { 'Alice' }, client: -> { nil },
  surface_state: -> { {} }, clock: -> { 0 }, covered: -> { false },
  speech: ->(text) { spoken << text }, trace: ->(*) {},
  history_changed: ->(*) {}, session_changed: -> {})
presenter.prepare_presentation_session({'id' => 1})
presenter.announce_due_timers(replay, now: 114)
assert(spoken.empty? && sounds.empty?, 'Warning before five seconds')
[115, 115, 116, 119].each { |now| presenter.announce_due_timers(replay, now: now) }
assert(spoken == ['5 seconds remain.'] && sounds == ['buzzer2'], 'Warning or UNO sound missing/repeated')
2.times { presenter.announce_due_timers(replay, now: 120) }
assert(spoken.last == 'Time is up.' && spoken.length == 2 && sounds.length == 1, 'Expired cue replays warning')
replay.state[:phase] = :revealing
presenter.announce_due_timers(replay, now: 116)
assert(sounds.length == 1, 'Closed question played countdown')
replay.state.merge!(phase: :answering, position: 2, deadline: 140)
presenter.announce_due_timers(replay, now: 135)
assert(sounds.length == 2, 'Next question warning was suppressed')
presenter.prepare_presentation_session({'id' => 2})
presenter.announce_due_timers(replay, now: 135)
assert(sounds.length == 3, 'New game warning was suppressed')

program.define_singleton_method(:game_room_sound_enabled?) { |_name| false }
replay.state[:position] = 3
presenter.announce_due_timers(replay, now: 135)
assert(sounds.length == 3 && spoken.last == '5 seconds remain.', 'Warning bypassed sound preferences')
puts 'PASS Quiz: short status, silent reveal, countdown sound once, expiry, next question/game and mute preference'
