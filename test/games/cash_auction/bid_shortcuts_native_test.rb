require_relative '../../support/cash_auction_native'
require_relative '../../../lib/game_screen'
require EltenTestHost.file('src/ui/controls/menu.rb')
require EltenTestHost.file('src/eapi/mainmenu.rb')
Object.const_set(:Menu, EltenAPI::Controls.const_get(:Menu)) unless defined?(Menu)

# Native copy runs against an isolated test clipboard, never the user's one.
module Clipboard; end unless defined?(Clipboard)
class << Clipboard
  attr_accessor :text
end
module SpeechOutput
  def self.list; []; end
end

def native_context_copy(form, driver)
  # The host dispatches native edit-menu shortcuts from keyprocs, outside
  # Form.update. Use that real dispatcher instead of invoking Copy ourselves.
  driver.frame(form, [[0x11, true], [0x43, true, driver.raw([0x11, 0x43])]], held: [0x11, 0x43])
  form.send(:keyprocs)
  driver.frame(form, [[0x43, false], [0x11, false]])
end

baseline_driver = CashAuctionNative::Driver.new
baseline_field = EditBox.new('Baseline', text: 'baseline', quiet: true)
baseline_form = GameRoomUI::Form.new([baseline_field])
baseline_field.index, baseline_field.check = 0, 8
Clipboard.text = 'not copied'
native_context_copy(baseline_form, baseline_driver)
raise 'Baseline native edit-menu Ctrl+C dispatch failed' unless Clipboard.text == 'baseline'

f = CashAuctionNative::Fixture.new
begin
  f.type('125')
  before = Marshal.dump(f.state)
  spoken = []
  screen = GameScreen.allocate
  screen.define_singleton_method(:speak) { |message, **_options| spoken << message }
  f.layout.begin_bindings
  shortcuts = f.game.game_shortcuts(f.replay, 'Alice')
  screen.send(:bind_game_shortcuts, f.form, f.layout.game_help_fields,
    GameRoomShortcutBindings.normalize(shortcuts)) do |shortcut|
    screen.send(:activate_game_shortcut, shortcut, f.surface, replay: f.replay)
  end
  driver = f.instance_variable_get(:@driver)
  [['p', []], ['t', []], ['h', []], ['d', []], ['d', [:shift]], ['s', [:shift]]].each do |key, modifiers|
    expected = shortcuts.find { |shortcut| shortcut.key == key && shortcut.modifiers.to_a == modifiers }
    raise "Missing #{modifiers.inspect}+#{key} information shortcut" unless expected && expected.kind == :announcement
    saved = [f.input.text.dup, f.input.index, f.input.check, f.input.game_room_edit_generation]
    codes = modifiers.map { |modifier| {shift: 0x10}.fetch(modifier) }
    code = key.upcase.ord
    held = codes + [code]
    events = codes.map { |modifier| [modifier, true] } + [[code, true, driver.raw(held)]]
    driver.frame(f.form, events, held: held, characters: modifiers.include?(:shift) ? key.upcase : key)
    driver.frame(f.form, [[code, false]] + codes.reverse.map { |modifier| [modifier, false] })
    raise "#{modifiers.inspect}+#{key} did not announce exactly its own information" unless spoken.last == expected.message
    raise "#{modifiers.inspect}+#{key} changed the bid draft, selection or generation" unless [f.input.text, f.input.index, f.input.check, f.input.game_room_edit_generation] == saved
  end
  raise 'Information keys announced more than once per press' unless spoken.length == 6
  driver.frame(f.form, [[0x53, true, driver.raw([0x53])]], held: [0x53], characters: 's')
  driver.frame(f.form, [[0x53, false]])
  raise 'Plain S stopped editing the bid' unless f.input.text == '125s' && spoken.length == 6
  f.press(0x41, modifiers: [0x11])
  raise 'Ctrl+A was consumed by the all-in input or a game shortcut' unless [f.input.index, f.input.check].minmax == [0, 4]
  Clipboard.text = 'not the bid'
  native_context_copy(f.form, driver)
  raise 'Native Ctrl+C no longer copies the selected bid' unless Clipboard.text == '125s'
  raise 'Native editing announced game information' unless spoken.length == 6
  raise 'Information/editing keys emitted a game action' unless f.actions.empty? && f.replay.accepted_events.empty?
  raise 'Information/editing keys changed the model' unless Marshal.dump(f.state) == before
  answer = CashAuctionNative::Fixture.new(phase: :answering)
  answer.layout.begin_bindings
  answer_shortcuts = answer.game.game_shortcuts(answer.replay, 'Alice')
  screen.send(:bind_game_shortcuts, answer.form, answer.layout.game_help_fields,
    GameRoomShortcutBindings.normalize(answer_shortcuts)) do |shortcut|
    screen.send(:activate_game_shortcut, shortcut, answer.surface, replay: answer.replay)
  end
  scores = answer_shortcuts.find { |shortcut| shortcut.key == 's' && shortcut.modifiers.to_a.empty? }
  raise 'Question scores still require Shift' unless scores
  answer.press(0x53)
  raise 'S did not read question scores' unless spoken.length == 7 && spoken.last == scores.message
  answer.press(0x53, modifiers: [0x10])
  raise 'Question shortcuts retained the bidding Shift+S binding' unless spoken.length == 7
  raise 'Reading question scores answered the question' unless answer.actions.empty?
  puts 'PASS native Cash bid information shortcuts P/T/H/D/Shift+D/Shift+S, character consumption, plain S, Ctrl+A/C and no actions or model writes'
ensure
  answer&.close
  f&.close
end
