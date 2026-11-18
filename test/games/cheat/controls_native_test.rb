require_relative '../../support/duck_challenge_native'
require_relative '../../support/cheat'
require_relative '../../../lib/game_screen'
include GameRoomTest::CheatFixture

class CheatDialogDriver < DuckChallengeNativeDriver
  attr_reader :modal
  def initialize(keys)
    super()
    @keys, @frames = keys, 0
  end
  def tick(form)
    @frames += 1
    raise 'Cheat modal did not finish' if @frames > 12
    if form.instance_variable_get(:@wait)
      @modal ||= form
      key = @keys.shift
      raise 'Cheat modal needs another key' unless key
      snapshot(tap(key), [])
    else
      snapshot([], [])
    end
  end
end

cheat_start
actor = @replay.current_player
surface = GameSurfaces.build(@game.surface_spec(@replay, actor))
driver = DuckChallengeNativeDriver.new
outer = driver.form(surface)
emitted = []
surface.on_action { |action| emitted << action.to_h }
first = surface.fields.first
driver.frame(outer, driver.tap(0x0D, modifiers: [0x10]))
assert(emitted.empty?, 'Shift+Enter emitted a move')
selected = surface.state['selected_ids'].dup
assert_equal(1, selected.length)
first.index = 1
driver.frame(outer)
driver.frame(outer, driver.tap(0x0D))
assert_equal(1, emitted.length)
cards = JSON.parse(emitted.first['cards'])
assert_equal(2, cards.length, 'Cursor card was omitted from the packet')
assert(cards.include?(selected.first), 'Prepared card was omitted')

screen = GameScreen.allocate
screen.instance_variable_set(:@game, @game)
shortcut = @game.surface_action_shortcut(emitted.first, @replay, actor)
SpeechOutput.reset
dialog_driver = CheatDialogDriver.new([0x1B])
assert_equal(nil, screen.send(:form_shortcut_action, shortcut))
assert_equal(selected, surface.state['selected_ids'], 'Cancel erased the packet')
assert_equal(1, first.index, 'Cancel moved the hand cursor')
assert(!EltenAPI::KeyboardState.current.pressed[0x1B], 'Escape leaked to the parent')
assert_equal(1, SpeechOutput.calls.length, 'Confirmation repeated its prompt')

dialog_driver = CheatDialogDriver.new([0x0D])
action = screen.send(:form_shortcut_action, shortcut)
assert_equal(cards, JSON.parse(action['cards']))
assert_equal('A', action['choice'])
assert(!EltenAPI::KeyboardState.current.pressed[0x0D], 'Closing Enter leaked')
cheat_move(action.to_h, actor)
assert_equal(:stale_packet, @game.action_for(action.to_h, @replay, @replay.current_player).first)

without_fields = GameRoomGames::GameShortcut.new(key: 'enter', label: 'Confirm', kind: :form,
  prompt: 'Confirm?', action_kind: 'command', action_name: 'confirm')
dialog_driver = CheatDialogDriver.new([0x0D])
assert_equal('confirm', screen.send(:form_shortcut_action, without_fields).name)

cheat_start('fixed_bluff')
actor = @replay.current_player
surface = GameSurfaces.build(@game.surface_spec(@replay, actor))
emitted.clear
surface.on_action { |action| emitted << action.to_h }
surface.fields.first.trigger(:select, 0)
shortcut = @game.surface_action_shortcut(emitted.first, @replay, actor)
assert_equal(13, shortcut.fields.first.choices.length)
dialog_driver = CheatDialogDriver.new([0x28, 0x0D])
screen.instance_variable_set(:@game, @game)
action = screen.send(:form_shortcut_action, shortcut)
assert_equal('2', action['choice'], 'Native choice lost its selected declaration')
assert_equal(emitted.first['cards'], action['cards'])

menu = Object.new
commands = []
menu.define_singleton_method(:option) { |label, *_, &block| commands << [label, block] }
menu.define_singleton_method(:submenu) { |_label, &block| block.call(menu) }
surface.fields.first.context(menu)
assert(commands.any? { |label, _| label.include?('Play the current') }, 'Play is absent from the native context menu')
before = emitted.length
commands.first.last.call
assert_equal(before + 1, emitted.length, 'Context play did not emit exactly once')
cheat_start('suit')
suit = GameSurfaces.build(@game.surface_spec(@replay, @replay.current_player))
tips = suit.fields.first.get_tips.join(' ')
assert(tips.include?('Press Enter to prepare'), 'Suit lost its single-card Enter help')
assert(!tips.include?('Shift+Enter'), 'Suit advertises a multi-card packet')
puts 'PASS Cheat native controls: packet snapshots, cursor card, Enter/Escape, one prompt, local declaration, context action and closing-key cleanup'
