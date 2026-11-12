require_relative '../support/duck_challenge_native'
require_relative '../support/assertions'
include GameRoomTest::Assertions

begin
  driver = DuckChallengeNativeDriver.new
  make_spec = lambda do |token, label|
    GameSurfaces::TypingSpec.new(round: 1, enabled: false, status: 'Waiting',
      commands: [GameSurfaces::Command.new(id: 'save_cancel', label: label,
        payload: {'save_id' => token})])
  end
  original_token, changed_token = 'a' * 32, 'b' * 32
  [['Cancel save B', changed_token], ['Cancel save A', changed_token],
   ['Cancel save B', original_token]].each do |label, token|
    original = GameSurfaces.build(make_spec.call(original_token, 'Cancel save A'))
    updated = GameSurfaces.reconcile(make_spec.call(token, label), previous: original, state: original.state)
    assert(!updated.equal?(original), 'A changed command definition reused a stale native button')
    actions = []
    updated.on_action { |action| actions << action.to_h }
    form = driver.form(updated)
    form.index = form.fields.index(updated.fields.last)
    form.focus
    driver.frame(form, [[0x0d, true, driver.raw([0x0d])]], held: [0x0d])
    driver.frame(form, [[0x0d, false]])
    assert_equal(label, updated.fields.last.label, 'The button still describes the previous command')
    assert_equal([{'kind' => 'command', 'action' => 'save_cancel', 'save_id' => token}], actions,
      'Native Enter emitted the command captured by an earlier spec')
  end

  original = GameSurfaces.build(make_spec.call(original_token, 'Cancel save A'))
  fields = original.fields.dup
  equivalent = make_spec.call(original_token, 'Cancel save A')
  equivalent.status = 'Still waiting'
  updated = GameSurfaces.reconcile(equivalent, previous: original, state: original.state)
  assert(updated.equal?(original), 'An unchanged definition unnecessarily rebuilt the typing surface')
  assert_equal(fields, updated.fields, 'A status-only refresh replaced the native controls')
  assert_equal('Still waiting', updated.fields.first.text)
  puts 'PASS native typing command reuse: changed labels/payloads rebuild, equivalent definitions preserve controls, Enter emits only the current save ID'
ensure
  $activecontrols = []
end
