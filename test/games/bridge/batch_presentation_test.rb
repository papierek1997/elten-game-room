require_relative "../../support/bridge"
require_relative "../../../lib/game_event_presenter"
include GameRoomTest::Assertions

table = GameRoomTest::BridgeTable.new(%w[Alice Bob Carol Dave], {"variant"=>"duplicate", "boards"=>4})
game = table.game
messages, cues = [], []
program = Object.new
program.define_singleton_method(:normalized_settings) { {} }
presenter = GameRoomEventPresenter.new(game: -> { game }, repository: -> { table.repository }, program: -> { program },
  viewer: -> { "Alice" }, client: -> {}, surface_state: -> { {} }, clock: -> { 0.0 }, covered: -> { false },
  speech: ->(text) { messages << text }, trace: ->(*_) {}, history_changed: ->(*) {}, session_changed: -> {})
play = GameRoomSounds.method(:play)
# Intentionally never-finished sound: Bridge must not wait for it.
sound = Object.new
sound.define_singleton_method(:finished?) { false }
sound.define_singleton_method(:length) { 3.0 }
GameRoomSounds.define_singleton_method(:play) { |_program, cue, **_| cues << cue; sound }
begin
  session = table.session.merge("__id"=>7)
  presenter.process_new_events(table.replay, session: session)
  expected, score_lines = [], []
  2.times do |round|
    table.calls(round.zero? ? "1H" : "2N", "P", "P", "P")
    while table.state[:phase] == :playing
      table.play_lowest_legal
      expected.concat(game.describe_event_for_display(table.events.last, table.repository, table.replay, "Alice"))
    end
    score_lines << game.send(:spoken_deal_result, table.state)
    table.deal
  end
  assert(score_lines.uniq.size == 2, "Fixture did not provide distinct deal results")
  messages.clear
  presenter.process_new_events(table.replay, session: session)
  assert(!presenter.event_presentation_busy?, "Bridge started waiting for sounds between moves")
  score_lines.each { |line| assert_equal(1, messages.count(line), "Catch-up repeated the latest score for an older board") }
  expected.each { |line| assert(messages.include?(line), "Catch-up used another deal's card/dummy/score: #{line}") }
  assert(messages.grep(/Dummy's hand is exposed/).size == 2, "Missing/duplicate dummy exposure")
  count = messages.size
  cue_count = cues.size
  presenter.process_new_events(table.replay, session: session)
  assert_equal(count, messages.size, "Unchanged snapshot repeated speech")
  assert_equal(cue_count, cues.size, "Unchanged snapshot repeated sounds")
  assert_equal(table.replay.state, presenter.event_presentation.visible_replay.state, "View stopped before the latest board")
  puts "PASS Bridge batch presentation: two boards, event-time cards/dummy/scores, immediate queue, no repeated snapshots"
ensure
  GameRoomSounds.define_singleton_method(:play, play)
end
