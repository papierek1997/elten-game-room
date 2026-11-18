require_relative '../support/duck_challenge_native'
require_relative '../../lib/local_name_dialog'
require_relative '../support/assertions'
include GameRoomTest::Assertions

class ReceiverInputMemory
  def initialize; @data = {}; end
  def read_json(path, default: nil); @data.fetch(path, default); end
  def write_json(path, value); @data[path] = value; end
end

class ReceiverDialogDriver < DuckChallengeNativeDriver
  attr_reader :opened, :edit
  def initialize(commands, held: [])
    super()
    @commands, @opened, @frames, @held = commands, 0, 0, held
  end
  def tick(form)
    @frames += 1
    raise 'Receiver modal did not close' if @frames > 20
    if form.instance_variable_get(:@wait)
      unless @edit
        @opened += 1
        @edit = form.fields.first
        assert(@edit.instance_of?(EditBox) && @edit.header.to_s.empty?, 'Input is labeled or not a native editor')
        assert(form.index == 0, 'Editor did not receive focus')
      end
      command = @commands.shift
      raise 'Receiver modal needs another action' unless command
      if command.first == :text
        EltenWindow.duck_characters = command.last
        snapshot([], @held)
      elsif command.first == :reset
        form.fields[1].press
        snapshot([], @held)
      else
        snapshot(tap(command[1], modifiers: command[2].to_a), @held)
      end
    else
      snapshot([], [])
    end
  end
end

runtime = ReceiverInputMemory.new
service = GameRoomLocalNamePresentation.new(runtime: runtime, account: 'Alice')
program = Object.new
program.define_singleton_method(:local_name_presentation) { service }
DuckChallengeNativeDriver.new
list = ListBox.new(%w[First Second Third], header: 'Parent', index: 1, quiet: true)
chat = EditBox.new('Chat', text: 'Keep this text', quiet: true)
parent = GameRoomUI::Form.new([list, chat], program: program, quiet: true)
parent.instance_variable_set(:@game_room_waiting, true)
parent.focus
changes = 0
parent.on(:local_presentation_changed) { changes += 1 }
foreground = GameRoomBackgroundPolicy.method(:window_foreground?)
GameRoomBackgroundPolicy.define_singleton_method(:window_foreground?) { true }
codes = GameRoomUI::ReceiverInput::CODES
begin
  driver = ReceiverDialogDriver.new([[:text, 'Grzegorz Żółć Nowak'], [:key, 0x0D]])
  driver.snapshot(driver.tap(codes.last, modifiers: codes[0...-1]), codes)
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal(1, driver.opened)
  assert_equal('Grzegorz Żółć Nowak', service.value)
  assert_equal(1, list.index, 'Modal changed parent selection')
  assert_equal(1, changes)
  assert(!EltenAPI::KeyboardState.current.pressed[0x0D], 'Modal Enter leaked')
  driver.snapshot([], [])
  $lastactivecontrols = [parent, list]
  parent.update

  driver = ReceiverDialogDriver.new([[:key, 0x1B]], held: codes)
  presses = codes.each_with_index.map { |code, position| [code, true, driver.raw(codes.take(position + 1))] }
  driver.snapshot(presses, codes)
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal(1, driver.opened)
  driver.snapshot([], codes)
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal(1, driver.opened, 'Held chord opened another modal')
  driver.snapshot([], [])
  $lastactivecontrols = [parent, list]
  parent.update

  driver = ReceiverDialogDriver.new([[:key, 0x41, [0x11]], [:text, 'One'], [:key, 0x0D], [:key, 0x1B]])
  driver.snapshot(driver.tap(codes.last, modifiers: codes[0...-1]), codes)
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal('Grzegorz Żółć Nowak', service.value, 'Invalid Enter or Escape changed the value')
  assert_equal('One', driver.edit.text, 'Invalid input was lost instead of remaining editable')
  assert_equal(1, changes)
  assert_equal(1, list.index)

  driver = ReceiverDialogDriver.new([])
  driver.snapshot([], [])
  $lastactivecontrols = [parent, list]
  parent.update
  driver.snapshot(driver.tap(codes.last, modifiers: codes[0...-2]), codes[0...-1])
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal(0, driver.opened, 'Incomplete chord opened the input')
  parent.index = 1
  driver.snapshot(driver.tap(codes.last, modifiers: codes[0...-1]), codes)
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal(0, driver.opened, 'Chord intercepted an editable field')
  assert_equal('Keep this text', chat.text)

  parent.index = 0
  driver = ReceiverDialogDriver.new([[:reset]])
  driver.snapshot([], [])
  $lastactivecontrols = [parent, list]
  parent.update
  driver.snapshot(driver.tap(codes.last, modifiers: codes[0...-1]), codes)
  $lastactivecontrols = [parent, list]
  parent.update
  assert_equal(nil, service.value)
  assert_equal(2, changes)
  [false, true].each do |foreign|
    driver = ReceiverDialogDriver.new([])
    driver.snapshot([], [])
    $lastactivecontrols = [parent, list]
    parent.update
    GameRoomBackgroundPolicy.define_singleton_method(:window_foreground?) { foreign }
    other_form = GameRoomUI::Form.new([Button.new('Other')], quiet: true)
    $activecontrols = []
    $lastactivecontrols = foreign ? [parent, list, other_form] : [parent, list]
    driver.snapshot(driver.tap(codes.last, modifiers: codes[0...-1]), codes)
    parent.update
    assert_equal(0, driver.opened, 'Background or foreign form accepted the chord')
  end
ensure
  GameRoomBackgroundPolicy.define_singleton_method(:window_foreground?, foreground)
  $activecontrols = []
  EltenAPI::KeyboardState.reset
end
puts 'PASS local input native: six simultaneous keys, latch/release, editable Unicode, Ctrl+A, invalid Enter, Escape, reset, parent selection and chat isolation'
