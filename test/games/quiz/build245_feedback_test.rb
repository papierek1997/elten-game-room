if ARGV.first
  require_relative "../../support/binary_rules_load"
  GameRoomTestLocalization.use_language("en")
end
require_relative "../../support/quiz_party_review_regressions"
require_relative "../../support/assertions"
require_relative "../../../lib/game_sounds"
include GameRoomTest::Assertions

def submit_feedback_answer(fixture, player, correct:)
  replay = fixture.h.replay(player)
  choice = fixture.game.send(:correct_option_index, replay.state)
  choice = (choice + 1) % GameRoomGames::QuizParty::OPTION_COUNT unless correct
  fixture.h.submit(player, {
    "kind" => "question", "action" => "submit",
    "question_id" => fixture.game.send(:question_surface_id, replay.state), "answer" => choice.to_s
  }, context: fixture.contexts.fetch(player))
end

def assert_feedback_sound(fixture, event, before, after, viewer, expected)
  actual = GameRoomSounds.event_cue(
    game: fixture.game, event: event, before_replay: before, after_replay: after,
    repository: fixture.h.repositories.fetch("Alice"), viewer: viewer
  )
  assert_equal(expected, actual, "Unexpected sound for #{event.fetch('action')}/#{viewer}")
end

fixture = QuizReviewFixture.new
game = fixture.game
initial = fixture.h.replay("Alice")
deadline = initial.state.fetch(:deadline)
assert_equal(:single_choice, game.surface_spec(initial, "Alice").mode)
assert_equal([], game.timer_announcements(initial, "Alice", now: deadline - 6))
warning = game.timer_announcements(initial, "Alice", now: deadline - 5)
assert_equal(1, warning.length)
assert_equal(["5 seconds remain.", "buzzer2"], warning.first.drop(1))
[4, 3, 2, 1].each do |remaining|
  assert_equal(warning, game.timer_announcements(initial, "Bob", now: deadline - remaining))
end
expired = game.timer_announcements(initial, "Alice", now: deadline)
assert_equal(1, expired.length)
assert_equal(["Time is up."], expired.first.drop(1))
assert_equal(expired, game.timer_announcements(initial, "Alice", now: deadline + 1))
assert(warning.first.first != expired.first.first, "Timer announcement identities collide")

submit_feedback_answer(fixture, "Alice", correct: true)
after_answer = fixture.h.replay("Alice")
surface = game.surface_spec(after_answer, "Alice")
assert_equal(:information, surface.mode)
assert_equal("", surface.prompt)
assert_equal("Answer sent.", surface.value)
observer = game.surface_spec(after_answer, "Observer")
assert_equal("Waiting for the players to answer.", observer.value)
assert_equal(:single_choice, game.surface_spec(after_answer, "Bob").mode)
assert_feedback_sound(fixture, fixture.h.events("Alice").last, initial, after_answer, "Alice", nil)
submit_feedback_answer(fixture, "Bob", correct: false)
submit_feedback_answer(fixture, "Dave", correct: true)
fixture.advance(deadline + GameRoomGames::QuizParty::DEADLINE_SUBMISSION_GRACE)
fixture.auto("Alice")
revealing = fixture.h.replay("Alice")
assert_equal(:revealing, revealing.state.fetch(:phase))
%w[Alice Bob Carol Dave Observer].each do |viewer|
  surface = game.surface_spec(revealing, viewer)
  assert_equal(:information, surface.mode)
  assert_equal("", surface.prompt)
  assert_equal("", surface.value)
  assert_equal([], game.timer_announcements(revealing, viewer, now: deadline + 4))
end
%w[Alice Bob Dave].each { |player| fixture.auto(player) }
before_score = fixture.h.replay("Alice")
fixture.auto("Alice")
after_score = fixture.h.replay("Alice")
event = fixture.h.events("Alice").last
assert_equal("question_finished", event.fetch("action"))
assert_equal({"Alice" => 1, "Bob" => 0, "Carol" => 0, "Dave" => 1}, after_score.state.fetch(:scores))
{"Alice" => "replay", "alice" => "replay", "Bob" => "quiz_wrong_answer",
 "Carol" => "quiz_wrong_answer", "Dave" => "replay", "Observer" => nil}.each do |viewer, cue|
  assert_feedback_sound(fixture, event, before_score, after_score, viewer, cue)
end
fixture.h.assert_converged("build245 first-question feedback")

fixture.advance(after_score.state.fetch(:resume_at))
fixture.auto("Alice")
second = fixture.h.replay("Alice")
assert_equal(:answering, second.state.fetch(:phase))
next_warning = game.timer_announcements(second, "Alice", now: second.state.fetch(:deadline) - 5)
assert_equal(["5 seconds remain.", "buzzer2"], next_warning.first.drop(1))
assert(warning.first.first != next_warning.first.first, "A new question reused the old warning identity")
fixture.h.users.each { |player| submit_feedback_answer(fixture, player, correct: player != "Alice") }
fixture.auto("Alice")
fixture.h.users.each { |player| fixture.auto(player) }
before_score = fixture.h.replay("Alice")
fixture.auto("Alice")
after_score = fixture.h.replay("Alice")
event = fixture.h.events("Alice").last
assert_feedback_sound(fixture, event, before_score, after_score, "Alice", "quiz_wrong_answer")
assert_feedback_sound(fixture, event, before_score, after_score, "Bob", "replay")
assert_equal(8, after_score.history.count { |entry| entry.kind == :answer_result })
fixture.h.assert_converged("build245 second-question feedback")

puts "PASS build245 quiz feedback: committed/silent information surfaces, timer boundaries and identities, four-client scoring, correct/wrong/missing/observer cues, event-local history"
