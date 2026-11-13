require_relative 'background_help_native'
require_relative 'native_tasks'
require_relative '../../lib/game_surfaces'
require_relative 'billiards'

class BilliardsNativeDriver
  attr_accessor :dialog
  def initialize
    @now, @previous, @ticks = 0.0, [], 0
    $native_tutorial_driver = self
    EltenAPI::KeyboardState.reset
  end
  def tick(form)
    @ticks += 1
    raise 'Billiards native dialog did not return' if @ticks > 5000
    snapshot
    if @dialog && form.is_a?(Form) && form.instance_variable_get(:@wait)
      action, @dialog = @dialog, nil
      action.call(form)
    end
    Thread.pass
  end
  def snapshot(keys = [], repeat: nil, events: nil)
    state = "\0" * 256
    keys.each { |code| state.setbyte(code, 0x80) }
    events ||= (@previous - keys).map { |code| [code, false] } +
      (keys - @previous).map { |code| [code, true, state] }
    events << [repeat, :repeat, state] if repeat
    @now += 0.25
    EltenAPI::KeyboardState.update(raw_state: state, events: events, now: @now,
      pressed_implies_held: false, synthesize_repeats: false)
    @previous = keys
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
  end
  def frame(control, keys = [], **options)
    snapshot(keys, **options)
    control.update
  end
end
