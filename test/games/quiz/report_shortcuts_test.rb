require_relative '../../support/quiz_party_review_regressions'
require_relative '../../../lib/quiz_reports'

fixture = QuizReviewFixture.new(%w[Alice Bob])
replay = fixture.h.replay('Alice')
game = fixture.game
reports = GameRoomQuizReports::Tracker.new(user: 'Alice', current_user: -> { 'Alice' })
data = game.reportable_question(replay)
assert(data['answers'] == game.send(:shuffled_options, replay.state), 'Report does not preserve displayed answer order')
assert(data['correct'] == game.send(:current_question, replay.state)['correct'], 'Wrong source answer')
assert(!data.key?('reveals') && !data.key?('commitments'), 'Copied private player answers')
phase = replay.state[:phase]
[:starting, :choosing, :drawing, :finished].each do |intermission|
  replay.state[:phase] = intermission
  assert(game.reportable_question(replay).nil?, 'Intermission replaced the last displayed question')
end
replay.state[:phase] = phase

screen = GameScreen.allocate
screen.instance_variable_set(:@game, game)
screen.instance_variable_set(:@session, fixture.h.session)
screen.instance_variable_set(:@repository, fixture.h.repository('Alice')) if fixture.h.respond_to?(:repository)
repository = Object.new
repository.define_singleton_method(:session_id) { |_session| 's1' }
screen.instance_variable_set(:@repository, repository)
screen.instance_variable_set(:@question_reports, reports)
bound = nil
screen.define_singleton_method(:bind_game_shortcuts) { |_form, _fields, list, &handler| bound = [list, handler] }
layout = Struct.new(:surface, :form, :history, :shortcut_fields).new(Object.new, Object.new, Object.new, [])
wait = GameScreen::WaitState.new(replay: replay, revision: 123)
screen.send(:bind_wait_shortcuts, wait, layout, -> { raise 'Bookmark moved the cursor' })
definitions, handler = bound
marks = definitions.select { |shortcut| shortcut.action_kind == 'question_report' }
assert(marks.map { |s| [s.key, s.modifiers] } == [['b', [:control]], ['b', [:control, :shift]]], 'Incorrect bookmark keys')
handler.call(marks.first)
handler.call(marks.last)
assert(wait.action.nil? && wait.revision == 123, 'Bookmark resumes game or changes revision')
assert(reports.questions.size == 1, 'Current question not marked')
# Native press-time routing, focused chat and key consumption are exercised
# by report_press_snapshot_native_test.rb, not a removed private matcher.
puts 'PASS Quiz bookmarks use visible replay without move, cursor or timer changes'
