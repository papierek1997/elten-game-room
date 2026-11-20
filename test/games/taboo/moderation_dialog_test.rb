require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"

def assert(value, message); raise message unless value; end

# Keep the production GameRoomUI::Form constructor/wait; only drive the fake host wait.
module TabooDialogHostInput
  def wait
    super
    $taboo_dialog_input.call(self)
  end
end
Form.prepend(TabooDialogHostInput)
program = Object.new
spec = GameSurfaces::TabooSpec.new(token: 'turn:1', phase: :review, lines: [], status: 'Review',
  master: true, review: [{word: 'word', forbidden: ['forbidden'], label: 'Skipped'}],
  results: [['correct', 'Correct'], ['skipped', 'Skipped']])
surface = GameSurfaces::TabooSurface.new(spec)
surface.program = program
events = []
surface.on_action { |event| events << event }
forms = []
$taboo_dialog_input = lambda do |form|
  forms << form
  assert(form.is_a?(GameRoomUI::Form) && form.game_room_program.equal?(program), 'dialog bypassed production Form/program')
  assert(form.index == 0, 'dialog initial index')
  form.fields.first.index = 0
  form.accept_button.trigger(:press)
end
surface.fields.first.trigger(:select)
assert(events.last.name == 'correct_result' && events.last.payload == {'index' => 0, 'result' => 'correct', 'token' => 'turn:1'}, 'card correction did not emit selected result')
$taboo_dialog_input = ->(form) { forms << form; form.fields.first.index = 1; form.accept_button.trigger(:press) }
surface.fields.last.trigger(:press)
assert(events.last.name == 'restart_turn' && events.last.payload['token'] == 'turn:1', 'restart confirmation did not emit action')
assert(forms.length == 2 && forms.all? { |form| form.is_a?(GameRoomUI::Form) }, 'both moderator dialogs must open')
count = events.length
$taboo_dialog_input = ->(form) { form.resume }
surface.fields.first.trigger(:select)
surface.fields.last.trigger(:press)
assert(events.length == count, 'cancel emitted a moderator action')
$taboo_dialog_input = lambda do |form|
  surface.update_spec(spec.dup.tap { |replacement| replacement.token = 'turn:2' })
  form.fields.first.index = 1
  form.accept_button.trigger(:press)
end
surface.fields.last.trigger(:press)
assert(events.length == count, 'stale restart confirmation emitted action')
puts 'Taboo: both production moderator dialogs, selection, cancellation and stale token OK'
