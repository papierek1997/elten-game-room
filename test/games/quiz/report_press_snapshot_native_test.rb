require_relative '../../support/duck_challenge_native'
require_relative '../../../games/base'
require_relative '../../../lib/game_shortcut_bindings'
require_relative '../../../lib/quiz_reports'

tracker = GameRoomQuizReports::Tracker.new(user: 'Alice', current_user: -> { 'Alice' })
first = {'id'=>'q1', 'round'=>1, 'position'=>1, 'prompt'=>'First?',
  'answers'=>%w[A B C D], 'correct'=>'A', 'language'=>'en', 'set'=>'general', 'category'=>'Example'}
tracker.observe('same-session', first)
tracker.observe('same-session', first.merge('id'=>'q2', 'position'=>2, 'prompt'=>'Second?'))

driver = DuckChallengeNativeDriver.new
spec = GameSurfaces::PawnTrackSpec.new(id: 'cards', header: 'Cards', items: [
  GameSurfaces::PawnTrackItem.new(id: 'A', label: 'Example')])
layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: spec))
field = layout.chat
field.set_text('Keep my unsent chat.')
form = layout.form
consumed = []
GameRoomShortcutBindings.bind(form, layout.shortcut_fields, tracker.shortcuts,
  consume: ->(key) { consumed << key }) { |shortcut| tracker.mark(shortcut.action_name) }
form.index = form.fields.index(field)
form.focus

driver.frame(form, driver.tap(0x42))
assert(tracker.empty?, 'An unmodified native B press marked a question')
driver.frame(form, [])
driver.frame(form, driver.tap(0x42, modifiers: [0x11]))
assert(tracker.questions.map { |question| question['id'] } == ['q2'], 'Native Ctrl+B did not mark current question')
driver.frame(form, [])
driver.frame(form, driver.tap(0x42, modifiers: [0x11, 0x10]))
assert(tracker.questions.map { |question| question['id'] } == %w[q2 q1], 'Native Ctrl+Shift+B did not mark previous question')
driver.frame(form, [])
driver.frame(form, driver.tap(0x42, modifiers: [0x11, 0x10]))
assert(tracker.questions.size == 2 && consumed == %w[b b b], 'Repeated report lost deduplication or key consumption')
assert(field.text == 'Keep my unsent chat.', 'Bookmark modified the native edit field')

$activecontrols = []
puts 'PASS Quiz report shortcuts: actual native press/release, focused chat, current/previous, deduplication and retained draft'
