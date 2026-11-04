require_relative '../support/rules_native_navigation'
require_relative '../support/assertions'
include GameRoomTest::Assertions

field = GameSurfaces::RefreshAwareEditBox.new('Chat')
field.define_singleton_method(:play_sound) { |*| }
assert(field.is_a?(EltenAPI::Controls.const_get(:EditBox)), 'Tail regression bypasses the native text editor')

['\\', 'x', 'ż', '🎲'].each do |character|
  field.set_text('Wysłana wiadomość')
  field.index = field.check = field.text.length
  receipt = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
  # The write is in flight. This is the same native insertion/change path as
  # a character arriving directly after the Enter which captured the message.
  field.einsert(character)
  assert(receipt.clear_if_current(field, session_id: 17), 'A trailing character prevented sent-message cleanup')
  assert_equal(character, field.text, 'Acknowledgement kept the sent prefix or erased new typing')
  assert_equal([character.length, character.length], [field.index, field.check], 'The new draft lost its cursor')
  assert_equal(false, receipt.clear_if_current(field, session_id: 17), 'A duplicate acknowledgement erased the new draft')
end

field.set_text('Pierwsza')
field.index = field.check = field.text.length
first = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
field.einsert(' i druga')
second = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
assert_equal(false, first.clear_if_current(field, session_id: 17), 'An older send stripped a newer submitted message')
assert_equal('Pierwsza i druga', field.text)
assert(second.clear_if_current(field, session_id: 17), 'The newer send did not clear its exact draft')

field.set_text('Wysłana')
field.index = field.check = field.text.length
receipt = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
field.einsert(' nowa wiadomość')
field.index, field.check = 10, 13
assert(receipt.clear_if_current(field, session_id: 17), 'Native tail with a selection did not clear')
assert_equal(' nowa wiadomość', field.text)
assert_equal([3, 6], [field.index, field.check], 'Selection offsets were not rebased onto the retained text')

edits = [
  -> { field.index = field.check = 2; field.einsert('x') },
  -> { field.edelete(0, field.text.length - 1); field.einsert('Wysłana i nowa') },
  -> { field.set_text('Wysłana i nowa') },
  -> { field.einsert('x'); field.edelete(field.text.length - 1, field.text.length - 1) },
  -> { field.trigger(:change) }
]
edits.each do |edit|
  field.set_text('Wysłana')
  field.index = field.check = field.text.length
  receipt = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
  edit.call
  before = [field.text.dup, field.index, field.check]
  assert_equal(false, receipt.clear_if_current(field, session_id: 17), 'An edited/replaced draft was mistaken for an appended tail')
  assert_equal(before, [field.text, field.index, field.check], 'Guarded draft or selection changed')
end

field.set_text('Kolejny stół')
field.index = field.check = field.text.length
receipt = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
field.einsert('x')
assert_equal(false, receipt.clear_if_current(field, session_id: 18), 'A different game consumed a tail')
assert_equal(false, receipt.clear_if_current(GameSurfaces::RefreshAwareEditBox.new('Other'), session_id: 17), 'A different field consumed a tail')

# The game's remembered view must retain the suffix too, not overwrite it
# with the old unconditional empty draft on its next form refresh.
screen = GameScreen.allocate
screen.instance_variable_set(:@chat_control, field)
layout = Struct.new(:chat, :session_id).new(field, 17)
screen.instance_variable_set(:@layout, layout)
field.set_text('Wysłana')
field.index = field.check = field.text.length
receipt = GameRoomUI::ChatSubmission.capture(field, session_id: 17)
field.einsert(' nowa')
assert(screen.send(:clear_chat_draft, receipt: receipt), 'GameScreen did not accept confirmed tail cleanup')
assert_equal(' nowa', screen.instance_variable_get(:@chat_text), 'The next game refresh would discard newly typed text')
assert_equal([5, 5], [screen.instance_variable_get(:@chat_index), screen.instance_variable_get(:@chat_check)])

# The ordinary waiting room uses the same captured receipt, after its send
# succeeds. Replace only its transport operation and retain the actual method.
app = EltenGameRoom.allocate
table = {'__id'=>12, '__live_session_id'=>'native-chat'}
context = {table_id:12, session_id:17, actor:Session.name, membership:Object.new}
buffer = GameRoomUI::ChatSendBuffer.new
sync = Object.new
sync.define_singleton_method(:recovery_pending?) { false }
sync.define_singleton_method(:synchronize) { |**_options, &operation| operation.call }
app.define_singleton_method(:run_network_task) { |*_arguments, **_options, &operation| operation.call }
app.define_singleton_method(:play_game_sound) { |_name| }
activity = Object.new
sent = []
activity.define_singleton_method(:append) do |**values|
  sent << values.fetch(:message)
  field.einsert('\\')
  :confirmed
end
activity.define_singleton_method(:text_for) { |*_arguments, **_options| nil }
app.instance_variable_set(:@table_activity, activity)
field.set_text('Wysłana z poczekalni')
field.index = field.check = field.text.length
assert_equal(:queued, buffer.enqueue(field, message:field.text, table:table, **context.reject { |key,_| key == :table_id }))
app.send(:send_waiting_table_chat, layout, buffer, -> { context }, sync)
assert_equal(['Wysłana z poczekalni'], sent, 'The send reread the changing editor')
assert_equal('\\', field.text, 'Waiting-room confirmation kept sent text or lost the following character')
puts 'PASS native chat tail cleanup: backslash/letters/Unicode, duplicate ACK, subsequent send, selection, replacement/deletion and context guards'
