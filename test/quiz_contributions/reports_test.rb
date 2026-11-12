require_relative '../support/quiz_creator_native'
require_relative '../../lib/quiz_reports'

NativeOptionTest.language = 'en'
module Session
  class << self
    attr_accessor :name
  end
end
Session.name = 'guest'
R = GameRoomQuizReports
Q = GameRoomQuizContributions
program = EltenGameRoom.allocate
question = {'id' => 'q1', 'prompt' => 'Które drzewo ma igły?', 'answers' => %w[Dąb Buk Sosna Klon],
  'correct' => 'Sosna', 'category' => 'Przyroda', 'language' => 'pl', 'set' => 'general', 'round' => 1, 'position' => 1}
tracker = R::Tracker.new(user: 'guest', current_user: -> { Session.name })
assert(tracker.mark('current').include?('no question'), 'Can mark a nonexistent question')
assert(tracker.mark('previous').include?('no previous'), 'Can mark a nonexistent previous question')
tracker.observe('s1', question)
question['prompt'] = 'Changed outside tracker'
assert(tracker.mark('current') == 'Question marked.', 'Current bookmark failed')
assert(tracker.mark('current').include?('already'), 'Repeated bookmark not deduplicated')
assert(tracker.questions.first['prompt'] == 'Które drzewo ma igły?', 'Bookmark changed with replay')
second = question.merge('id' => 'q2', 'position' => 2, 'prompt' => 'Pytanie drugie?')
tracker.observe('s1', second)
tracker.observe('s1', second)
assert(tracker.mark('previous').include?('already'), 'Refresh replaced previous question')
assert(tracker.mark('current') == 'Question marked.', 'Next question was lost')
tracker.observe('s2', nil)
assert(tracker.mark('previous').include?('no previous'), 'Previous question leaked across matches')
assert(tracker.questions.size == 2, 'Rematch discarded pending reports')
Session.name = 'another'
assert(tracker.empty? && tracker.mark('current').include?('account'), 'Reports leaked between accounts')
Session.name = 'guest'

Message = Struct.new(:id, :sender, :receiver, :subject, :text, keyword_init: true)
Response = Struct.new(:messages, :more, keyword_init: true)
class ReportMailbox
  attr_accessor :fail, :more, :user
  attr_reader :rows, :deleted
  def initialize
    @rows, @deleted, @user, @more = [], [], 'guest', false
  end
  def messages(_client, user:, subject:, limit:)
    raise IOError if @fail == :read
    Response.new(messages: @rows.select { |m| m.subject == subject && !@deleted.include?(m.id) }, more: @more)
  end
  def send_text(_client, to:, subject:, text:)
    raise IOError if @fail == :before
    @rows << Message.new(id: @rows.size + 1, sender: @user, receiver: to, subject: subject, text: text)
    if @fail == :after
      @fail = nil
      raise IOError
    end
    true
  end
  def delete_message(_client, id)
    raise IOError if @fail == :delete
    @deleted << id
    true
  end
end
mail = ReportMailbox.new
repository = Q::Repository.new(app_uuid: 'test', user: 'guest', current_user: -> { Session.name },
  client: Object.new, api: Object.new)
delivery = R::Delivery.new(repository, messages: mail)
packet = delivery.packet(tracker.questions.first, 'Błąd próbny — nie zmieniać pytania.')
assert(delivery.send_and_clean(packet), 'Report not sent')
assert(mail.rows.size == 1 && mail.deleted == [1], 'Sender copy not removed')
assert(mail.rows.first.text.include?('Sosna') && mail.rows.first.text.include?('general'), 'Missing original question metadata')
delivery.send_and_clean(packet)
assert(mail.rows.size == 1, 'Cleanup retry resent report')
packet2 = delivery.packet(second, 'Retry test')
mail.fail = :after
begin delivery.send_and_clean(packet2); rescue IOError; end
assert(!packet2['confirmed'] && mail.rows.size == 2, 'Did not model an uncertain send')
delivery.send_and_clean(packet2)
assert(mail.rows.size == 2 && mail.deleted == [1, 2], 'Retry duplicated a delivered message')
packet3 = delivery.packet(second, 'Cleanup test')
mail.fail = :delete
begin delivery.send_and_clean(packet3); rescue IOError; end
assert(packet3['confirmed'], 'Cleanup lost confirmation')
mail.fail = nil
delivery.send_and_clean(packet3)
assert(mail.rows.size == 3 && mail.deleted == [1, 2, 3], 'Failed cleanup resent report')
mail.more = true
begin
  delivery.send_and_clean(delivery.packet(second, 'Incomplete lookup'))
  raise 'Allowed uncertain mailbox lookup'
rescue Q::Unavailable
  assert(mail.rows.size == 3, 'Sent without checking complete exact-subject lookup')
end
mail.more = false
Session.name = 'papierek'
own_repository = Q::Repository.new(app_uuid: 'test', user: 'papierek', current_user: -> { Session.name }, client: Object.new, api: Object.new)
mail.user = 'papierek'
own = R::Delivery.new(own_repository, messages: mail)
own.send_and_clean(own.packet(second, 'Self-addressed test'))
assert(mail.rows.size == 4 && mail.deleted == [1, 2, 3], 'Deleted author inbox copy')
Session.name = 'guest'

# Dispatch parameters are not press-time modifier snapshots. Supply actual
# native press/release frames; full focused-layout routing has its own test.
native_tracker = R::Tracker.new(user: 'guest', current_user: -> { Session.name })
native_tracker.observe('native', tracker.questions.first)
native_tracker.observe('native', second)
native_field = EditBox.new('Chat', text: 'Unsent chat')
native_form = GameRoomUI::Form.new([native_field], program: program, quiet: true)
consumed = []
GameRoomShortcutBindings.bind(native_form, [native_field], native_tracker.shortcuts,
  consume: ->(key) { consumed << key }) { |shortcut| native_tracker.mark(shortcut.action_name) }
press_report_key = lambda do |modifiers|
  released = "\0" * 256
  EltenAPI::KeyboardState.update(raw_state: released,
    active: true, synthesize_repeats: false)
  held = released.dup
  modifiers.each { |modifier| held.setbyte(EltenAPI::KeyboardScheme.key_code(modifier), 0x80) }
  code = 'B'.ord
  held.setbyte(code, 0x80)
  EltenAPI::KeyboardState.update(raw_state: released,
    events: [[code, true, held], [code, false, released]],
    active: true, synthesize_repeats: false)
  native_form.trigger(:key_b, false, false, false)
  EltenAPI::KeyboardState.clear_current_frame
end
press_report_key.call([])
assert(native_tracker.empty?, 'Typing B marks a question')
main = EltenAPI::KeyboardScheme.main_modifier
press_report_key.call([main])
press_report_key.call([main, :shift])
press_report_key.call([main, :shift])
assert(native_tracker.questions.map { |q| q['id'] } == %w[q2 q1], 'Native current/previous shortcut failed')
assert(consumed == %w[b b b] && native_field.text == 'Unsent chat', 'Shortcut damaged chat input')

# Native form: no default Enter submission; the report includes the set's
# designated answer, as requested, only after leaving the table.
steps = []
Form.driver = ->(form) { (steps.shift or raise 'Unexpected form').call(form) }
views = R::Views.new(program)
steps << ->(form) {
  assert(form.accept_button.nil?, 'Enter in description would send the form')
  assert(form.fields[0].text.lines.size == 6, 'Question, choices or correct answer missing')
  assert(form.fields[0].text.include?("Correct answer: #{second['correct']}"), 'Report hides the answer from the set')
  assert(form.fields[1].text == 'Initial note', 'Description lost')
  form.fields[1].set_text('Updated note')
  form.fields[2].trigger(:press)
}
assert(views.report(second, 'Initial note') == [:send, 'Updated note'], 'Send button did not submit text')
steps << ->(form) { form.cancel_button.trigger(:press) }
assert(views.report(second, '') == [:skip, ''], 'Cancel did not skip')
steps << ->(form) { form.fields.first.index = 0; form.accept_button.trigger(:press) }
review = R::Review.new(program, tracker, views: views, delivery: delivery)
review.run
assert(steps.empty? && mail.rows.size == 4, 'No still sent a report or opened editor')

# The table wrapper must prompt after leaving, not on cancelled Leave or
# on a match result; other games never acquire a report tracker.
program.define_singleton_method(:run_table_screen) do |_row|
  reports = instance_variable_get(:@question_reports)
  reports.observe('wrapper', second)
  reports.mark('current')
  assert(steps.size == 1, 'Prompt opened before table returned')
  :left
end
%w[quiz duck_racing].each do |game_id|
  steps << ->(form) { form.fields.first.index = 0; form.accept_button.trigger(:press) }
  assert(program.show_table_screen({'game' => game_id}) == :left, 'Wrapper changed return value')
  assert(program.instance_variable_get(:@question_reports).nil? && steps.empty?, 'Reports not released on exit')
end
puts "PASS ephemeral Quiz reports, native form and message retry/cleanup: #{$assertions} checks"
