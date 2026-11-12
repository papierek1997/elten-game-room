require_relative "../../support/audio_ball_native_keys"

native_state = EltenAPI::KeyboardState
original_update = native_state.method(:update)
original_update = original_update.super_method until original_update.owner == native_state.singleton_class

failures = []
[[0x10, 0x53], [0x11, 0x57]].each do |modifier, code|
  h = AudioBallNativeKeys.new
  begin
    h.approach('left', 0.3)
    h.tap(0x25); h.advance
    h.tap(code, modifiers: [modifier]); h.advance
    assert(EltenAPI::KeyboardState.pressed?(code) && !EltenAPI::KeyboardState.held?(modifier) &&
      EltenAPI::KeyboardState.state_when_pressed(code)[modifier], 'released chord setup lost its native press-time modifier')
    h.advance(30)
    assert(h.clients['Bob'].engine.holder == 1, "released modified chord #{modifier}/#{code} changed the selected left lane")
  rescue RuntimeError => error
    failures << error.message
  ensure
    h.close
  end
end

[[0x28, 0x26], [0x53, 0x57]].each do |first, last|
  h = AudioBallNativeKeys.new
  begin
    h.approach('up', 0.3)
    h.tap(first); h.tap(last); h.advance
    assert(EltenAPI::KeyboardState.pressed?(first) && EltenAPI::KeyboardState.pressed?(last), 'ordered taps were not in the same native frame')
    h.advance(30)
    assert(h.clients['Bob'].engine.holder == 1, "native taps #{first}->#{last} did not keep the chronologically last up lane")
  rescue RuntimeError => error
    failures << error.message
  ensure
    h.close
  end
end
raise failures.join("\n") unless failures.empty?
puts 'PASS Audio Ball native keyboard: released Shift+S/Ctrl+W and Down->Up/S->W in one frame'

class AudioBallKeyboardProbe
  attr_reader :field
  def initialize
    EltenAPI::KeyboardState.reset
    @field = GameSurfaces::AudioBallField.new('Native keyboard probe')
    @field.extend(EltenAPI::UI)
    @now = 0.0
    @field.focus
  end

  def state(*codes)
    bytes = "\0" * 256
    codes.each { |code| bytes.setbyte(code, 0x80) }
    bytes
  end

  def tap(code, modifier = nil)
    [[code, true, state(code, *Array(modifier))], [code, false]]
  end

  def frame(events = [], held: [], update: true, **options)
    @now += 0.016
    result = EltenAPI::KeyboardState.update(raw_state: state(*held), events: events,
      now: @now, pressed_implies_held: false, synthesize_repeats: false, **options)
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    @field.update if update
    result
  end

  def input
    @field.take_input
  end
end

failures = []
[[0x10, 0x53], [0x11, 0x57]].each do |modifier, code|
  [:same_frame, :previous_frame, :released_before_key].each do |timing|
    probe = AudioBallKeyboardProbe.new
    probe.frame([[modifier, true]], held: [modifier]) unless timing == :same_frame
    events = [[code, true], [code, false], [modifier, false]]
    events.unshift([modifier, true]) if timing == :same_frame
    events.unshift(events.pop) if timing == :released_before_key
    probe.frame(events)
    expected = timing == :released_before_key ? [GameSurfaces::AudioBallField::KEYS.fetch(code)] : []
    actual = probe.input
    failures << "snapshot-free #{modifier}/#{code} #{timing}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
  end
end
raise failures.join("\n") unless failures.empty?
puts 'PASS snapshot-free native chords: same-frame and prior-frame modifiers block lanes; release before a plain key permits it'

mapping = GameSurfaces::AudioBallField::KEYS
mapping.keys.permutation(2).each do |first, last|
  probe = AudioBallKeyboardProbe.new
  probe.frame(probe.tap(first) + probe.tap(last))
  assert(probe.input == [mapping.fetch(first), mapping.fetch(last)], "native order lost for #{first}->#{last}")
  probe.field.update
  assert(probe.input.empty?, 'the same native frame replayed a released tap')
end
puts 'PASS native ordering: all eight controls in both orders, including preparation; one consumption per field/frame'

mapping.each do |code, command|
  [0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA2, 0xA3].each do |modifier|
    probe = AudioBallKeyboardProbe.new
    probe.frame([[modifier, true]] + probe.tap(code, modifier) + [[modifier, false]])
    assert(probe.input.empty?, "released native modifier #{modifier} leaked control #{code}")
    assert(probe.field.send(:keyboard_modifier_held_when_pressed?, code,
      {0x10 => :shift, 0x11 => :control, 0x12 => :option, 0x5B => :command, 0x5C => :command, 0xA2 => :control, 0xA3 => :control}.fetch(modifier)),
      'observer damaged the host press-time modifier state')
  end
  probe = AudioBallKeyboardProbe.new
  probe.frame(probe.tap(code) + probe.tap(code, 0x10))
  assert(probe.input == [command], 'a later modified repetition erased an earlier legitimate press')
  probe.frame
  probe.frame(probe.tap(code, 0x10) + probe.tap(code))
  assert(probe.input == [command], 'an earlier modified repetition became a second legitimate press')
end
probe = AudioBallKeyboardProbe.new
probe.frame(probe.tap(0x28) + probe.tap(0x26) + probe.tap(0x28))
assert(probe.input == %w[down up down], 'same-key release/repress within a frame lost chronological order')
puts 'PASS native modifiers and repeated same-key taps: per-event snapshots, all controls, Shift/Ctrl/Alt/Command'

[:clear_current_frame, :reset].each do |operation|
  probe = AudioBallKeyboardProbe.new
  probe.frame(probe.tap(0x28) + probe.tap(0x26), update: false)
  assert(EltenAPI::KeyboardState.public_send(operation) == true, 'observer changed host clear/reset return')
  probe.field.update
  assert(probe.input.empty?, "#{operation} left replayable metadata")
  probe.frame(probe.tap(0x25))
  assert(probe.input == ['left'], "#{operation} prevented the next fresh key")
end
probe = AudioBallKeyboardProbe.new
probe.frame(probe.tap(0x26))
assert(probe.input == ['up'], 'fresh press setup failed')
probe.frame(probe.tap(0x26))
assert(!EltenAPI::KeyboardState.pressed?(0x26) && probe.input == ['up'],
  'Audio Ball lost a physical quick tap or changed host suppression globally')
probe.frame([], held: [0x25])
probe.input
EltenAPI::KeyboardState.suppress_held_until_release
probe.frame([[0x25, true]], held: [0x25])
assert(probe.input.empty?, 'observer bypassed native held-key suppression')
probe.frame([[0x25, false]])
probe.frame(probe.tap(0x25))
assert(probe.input == ['left'], 'release after host suppression did not re-enable the key')
probe.frame(probe.tap(0x28), active: false)
assert(probe.input.empty?, 'inactive native frame accepted input')
puts 'PASS native clear/reset/inactive and core press suppression'

probe = AudioBallKeyboardProbe.new
probe.frame([[0x26, true, probe.state(0x26)]], held: [0x26])
probe.input
probe.frame([[0x26, false], [0x26, true, probe.state(0x26)]], held: [0x26])
assert(!EltenAPI::KeyboardState.pressed?(0x26) && probe.input == ['up'],
  'Audio Ball lost a physical release/repress or changed host suppression globally')
puts 'PASS local Audio Ball recovery of physical release/repress; the host core Result stays unchanged'


[:clear_input, :focus].each do |operation|
  probe = AudioBallKeyboardProbe.new
  probe.frame(probe.tap(0x28), update: false)
  probe.field.public_send(operation)
  probe.field.update
  assert(probe.input.empty?, "#{operation} replayed an already released native tap")
  probe.frame(probe.tap(0x26))
  assert(probe.input == ['up'], "#{operation} disabled a later fresh tap")
end
puts 'PASS clear/refocus rejects unsampled released input as well as held keys'

probe = AudioBallKeyboardProbe.new
probe.frame([], held: [0x26])
assert(probe.input == ['up'], 'single raw-state fallback key stopped working')
probe.frame
probe.frame([], held: [0x28, 0x26])
assert(probe.input.empty?, 'raw state without event order invented chronology from key codes')
probe.frame
probe.frame([[0x11, true]] + probe.tap(0x57, 0x11) + [[0x11, false]], update: false)
EltenAPI::KeyboardState.current.remove_instance_variable(GameRoomAudioBall::Keyboard::FRAME)
probe.field.update
assert(probe.input.empty?, 'fallback ignored the host press-time modifier API')
probe.frame
probe.frame(probe.tap(0x26), held: [0x10])
assert(probe.input.empty?, 'press-time metadata bypassed the live modifier guard')

module EltenWindow
  def self.keyboard_flags_driven?; true; end
end
begin
  probe = AudioBallKeyboardProbe.new
  probe.frame(probe.tap(0x28) + probe.tap(0x26))
  assert(GameRoomAudioBall::Keyboard.frame == nil && probe.input.empty?, 'flags backend was falsely treated as chronological events')
  probe.frame
  probe.frame(probe.tap(0x25))
  assert(probe.input == ['left'], 'flags backend rejected an unambiguous key')
ensure
  EltenWindow.singleton_class.send(:remove_method, :keyboard_flags_driven?)
end
puts 'PASS unordered fallback: one control works, ambiguous chords are ignored, native press-time and live modifier guards remain'

probe = AudioBallKeyboardProbe.new
probe.frame(probe.tap(0x26, 0x10))
double = GameSurfaces::AudioBallField.new('UI double beside loaded host')
double.model_keyboard_input!
double.define_singleton_method(:key_pressed?) { |code| code == 0x26 }
double.define_singleton_method(:key_held?) { |_code| false }
double.update
assert(double.take_input == ['up'], 'UI double borrowed unrelated native modifier/order metadata')
puts 'PASS UI-double fallback stays independent even when real KeyboardState is loaded'


probe = AudioBallKeyboardProbe.new
probe.frame(probe.tap(0x28) + probe.tap(0x26), update: false)
plain = Button.new('Unrelated native control')
plain.extend(EltenAPI::UI)
assert(plain.send(:key_pressed?, 0x28) && plain.send(:key_pressed?, 0x26), 'observer consumed normal host keys')
probe.field.update
assert(probe.input == %w[down up], 'unrelated control consumed Audio Ball metadata')
assert(plain.send(:key_pressed?, 0x28) && plain.send(:key_pressed?, 0x26), 'Audio Ball consumed normal host keys')
frame = GameRoomAudioBall::Keyboard.frame
assert(frame.frozen? && frame.all?(&:frozen?), 'native frame metadata is mutable')
probe.frame(probe.tap(0x70) + probe.tap(0x42))
assert(GameRoomAudioBall::Keyboard.frame.empty?, 'observer retained unrelated function/text key input')
probe.frame
probe.frame((mapping.keys * 12).flat_map { |code| probe.tap(code) })
assert(GameRoomAudioBall::Keyboard.frame.length == 32 && probe.input.length == 32,
  'native metadata/pending input exceeded the existing bound')
assert(GameRoomAudioBall::Keyboard.frame.changes.length == 64 && GameRoomAudioBall::Keyboard.frame.reset,
  'ordered defence changes exceeded their bound or retained pre-overflow held state')
assert(probe.field.take_defense_input[:changes].length == 64, 'field defence queue exceeded its bound')
probe = AudioBallKeyboardProbe.new
probe.frame(Array.new(64) { [0x53, false] }, held: [0x44])
assert(GameRoomAudioBall::Keyboard.frame.changes.length == 64 && GameRoomAudioBall::Keyboard.frame.reset,
  'raw fallback appended an unbounded change after ordered releases')
assert(GameRoomAudioBall::Keyboard.frame.all? { |code, modified| mapping.key?(code) && [true, false, nil].include?(modified) },
  'observer retained raw keyboard snapshots instead of just controls/modifier flags')
ancestors = EltenAPI::KeyboardState.singleton_class.ancestors
10.times { GameRoomAudioBall::Keyboard.install }
assert(EltenAPI::KeyboardState.singleton_class.ancestors == ancestors, 'observer installation stacked bridges')
puts 'PASS isolation, immutable current-frame metadata, bounded relevant input and idempotent lazy installation'

probe = AudioBallKeyboardProbe.new
sequence = [
  {raw_state: probe.state, events: probe.tap(0x28) + probe.tap(0x26), now: 1.0},
  {raw_state: probe.state(0x42), events: [[0x42, true, probe.state(0x42)]], now: 1.016},
  {raw_state: probe.state(0x42), events: [[0x42, :repeat, probe.state(0x42)]], now: 1.6},
  {raw_state: probe.state, events: [[0x42, false]], synthetic_keys: [0x70], now: 1.7},
  {raw_state: probe.state, now: 1.8},
  {raw_state: probe.state, events: [[0x11, true]] + probe.tap(0x57, 0x11) + [[0x11, false]], now: 1.9},
  {raw_state: probe.state(0x26), events: [[0x26, true]], active: false, now: 2.0},
  {raw_state: probe.state, events: [[0x10, true], [0x53, true], [0x53, false], [0x10, false]], pressed_implies_held: false, now: 2.1},
  {raw_state: probe.state, events: [[0x11, true], [0x57, true], [0x57, false], [0x11, false]], pressed_implies_held: false, now: 2.2},
  {raw_state: probe.state(0x10), events: [[0x10, true]], now: 2.3},
  {raw_state: probe.state, events: [[0x53, true], [0x53, false], [0x10, false]], pressed_implies_held: false, now: 2.4},
  {raw_state: probe.state(0x11), events: [[0x11, true]], now: 2.5},
  {raw_state: probe.state, events: [[0x11, false], [0x57, true], [0x57, false]], pressed_implies_held: false, now: 2.6}
]
EltenAPI::KeyboardState.reset
baseline = sequence.map { |options| original_update.call(**options) }
EltenAPI::KeyboardState.reset
sequence.each_with_index do |options, index|
  result = EltenAPI::KeyboardState.update(**options)
  assert(result.class == EltenAPI::KeyboardState::Result && result == baseline[index] && result.to_h == baseline[index].to_h,
    "observer changed host Result at frame #{index}")
  assert(result.equal?(EltenAPI::KeyboardState.current), 'observer replaced the exact host Result') unless options[:active] == false
end
puts 'PASS host parity: exact Result identity, all Struct fields, normal keys, repeats, synthetic input, inactive update'

module Log
  def self.error(_message); end
end
begin
  options = {raw_state: probe.state, events: [[Object.new, true]]}
  expected = original_update.call(**options)
  actual = EltenAPI::KeyboardState.update(**options)
  assert(actual == expected, 'observer changed the native reset result after a malformed event')
ensure
  Log.singleton_class.send(:remove_method, :error)
end
puts 'PASS observer preserves native malformed-event recovery instead of raising after the host recovered'


module EltenWindow
  class << self
    attr_accessor :test_snapshot, :snapshot_reads
    def keyboard_active?; true; end
    def activation_input_blocked?; false; end
    def keyboard_flags_driven?; false; end
    def keyboard_event_driven?; true; end
    def keyboard_pressed_implies_held?; false; end
    def keyboard_native_repeat_events?; true; end
    def consume_keyboard_snapshot
      self.snapshot_reads = snapshot_reads.to_i + 1
      result, self.test_snapshot = test_snapshot, ["\0" * 256, []]
      result
    end
  end
end
begin
  probe = AudioBallKeyboardProbe.new
  EltenWindow.snapshot_reads = 0
  EltenWindow.test_snapshot = [probe.state, probe.tap(0x28) + probe.tap(0x26)]
  $input_frame_serial = $input_frame_serial.to_i + 1
  probe.field.update
  assert(probe.input == %w[down up] && EltenWindow.snapshot_reads == 1, 'real UI.key_update lost order or consumed the native queue twice')
  $input_frame_serial += 1
  probe.field.update
  assert(probe.input.empty? && EltenWindow.snapshot_reads == 2, 'real UI idle clear replayed stale native input')
ensure
  [:test_snapshot, :test_snapshot=, :snapshot_reads, :snapshot_reads=, :keyboard_active?, :activation_input_blocked?,
    :keyboard_flags_driven?, :keyboard_event_driven?, :keyboard_pressed_implies_held?, :keyboard_native_repeat_events?,
    :consume_keyboard_snapshot].each { |name| EltenWindow.singleton_class.send(:remove_method, name) }
end
puts 'PASS actual UI.key_update: ordered native snapshot consumed exactly once; next idle frame clears metadata'
