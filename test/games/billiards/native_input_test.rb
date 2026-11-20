require_relative '../../support/billiards_native'

module BilliardsNativeInputTest
  extend GameRoomTest::Assertions
  def self.run
    driver = BilliardsNativeDriver.new
    match = BilliardsFixture::Match.new
    surface = GameSurfaces.build(match.game.surface_spec(match.replay, 'Alice'))
    cue = surface.fields.first
    form = GameRoomUI::Form.new(surface.fields, quiet: true)
    surface.attach_form(form)
    allowed, actions = true, []
    surface.action_guard = -> { allowed }
    surface.on_action { |action| actions << action }
    SpeechOutput.reset
    driver.frame(cue, [0x25])
    driver.frame(cue, [0x25], repeat: 0x25)
    assert_equal(200, surface.state['shot']['angle'], 'Held arrow did not use native repeats')
    assert_equal([], SpeechOutput.calls, 'Holding an arrow flooded speech')
    driver.frame(cue)
    assert_equal(1, SpeechOutput.calls.length, 'Release did not announce one final angle')
    assert(SpeechOutput.calls.last.first.include?('Ball 1'), 'Released aim omitted its first contact')
    driver.frame(cue, [0x10, 0x27])
    driver.frame(cue)
    assert_equal(190, surface.state['shot']['angle'])
    press = "\0" * 256
    [0x11, 0x27].each { |code| press.setbyte(code, 0x80) }
    driver.frame(cue, [], events: [[0x11, true], [0x27, true, press], [0x27, false], [0x11, false]])
    assert_equal(189, surface.state['shot']['angle'], 'Quick Ctrl+Right lost its press-time modifier')
    driver.frame(cue, [0x10, 0x26])
    driver.frame(cue)
    assert_equal(351, surface.state['shot']['power'])
    driver.frame(cue, [0x11, 0x0d])
    driver.frame(cue)
    assert_equal([], actions, 'Modified Enter fired a shot')
    driver.frame(cue, [0x20])
    driver.frame(cue)
    assert_equal(1, actions.length)
    assert_equal(:ok, match.game.action_for(actions.first, match.replay, 'Alice').first)

    before = surface.state
    driver.dialog = ->(dialog) { dialog.fields.first.set_text('12,34'); dialog.cancel_button.trigger(:press) }
    surface.handle_command('parameters')
    assert_equal(before, surface.state, 'Cancelling the editor changed the draft')
    driver.dialog = ->(dialog) { dialog.fields.first.set_text('12,34'); dialog.accept_button.trigger(:press) }
    surface.handle_command('parameters')
    assert_equal(1234, surface.state['shot']['angle'])
    before = surface.state
    driver.dialog = ->(dialog) { dialog.fields.first.set_text('44'); allowed = false; dialog.accept_button.trigger(:press) }
    surface.handle_command('parameters')
    assert_equal(before, surface.state, 'A stale dialog applied a draft')
    allowed = true
    driver.dialog = ->(dialog) { dialog.cancel_button.trigger(:press) }
    surface.handle_command('predict')
    assert_equal(1, actions.length, 'Prediction wrote a move')
    assert_equal(before, surface.state, 'Prediction changed the draft')
    assert_equal([], match.events, 'Preview mutated game history')
    puts 'Billiards native input: arrow repeats, release speech, press-time modifiers, Space, modal apply/cancel/stale view and read-only prediction passed.'
  end
end
BilliardsNativeInputTest.run if $PROGRAM_NAME == __FILE__
