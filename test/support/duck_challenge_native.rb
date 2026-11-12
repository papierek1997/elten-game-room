require_relative 'background_help_native'
require_relative 'native_tasks'
require EltenTestHost.file('src/ui/controls/grid_box.rb')
GridBox = EltenAPI::Controls::GridBox unless defined?(GridBox) && GridBox.equal?(EltenAPI::Controls::GridBox)
require_relative '../../lib/game_surfaces'
require_relative 'duck_challenge_ui'

# The control-only host fixture omits the logged-in account service. Layout's
# existing voice control still reads it, even when these tests have no channel.
unless defined?(Session)
  module Session
    def self.name; 'Alice'; end
  end
end

module EltenWindow
  class << self
    attr_accessor :duck_characters
    def take_character(_multi)
      value, self.duck_characters = duck_characters.to_s, ''
      value
    end
  end
end

class DuckChallengeNativeDriver
  attr_reader :now, :result
  def initialize
    @now = 0.0
    $native_tutorial_driver = self
    EltenAPI::KeyboardState.reset
  end

  def tick(_form)
    snapshot([], [])
  end

  def raw(keys)
    value = "\0" * 256
    keys.each { |key| value.setbyte(key, 0x80) }
    value
  end

  def tap(key, modifiers: [])
    modifiers.map { |modifier| [modifier, true] } +
      [[key, true, raw([key] + modifiers)], [key, false]] +
      modifiers.reverse.map { |modifier| [modifier, false] }
  end

  def snapshot(events, held, active: true)
    @now += 0.016
    @result = EltenAPI::KeyboardState.update(raw_state: raw(held), events: events, now: @now,
      pressed_implies_held: false, synthesize_repeats: false, active: active)
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
    @result
  end

  def frame(form, events = [], held: [], characters: '', active: true)
    EltenWindow.duck_characters = characters
    snapshot(events, held, active: active)
    form.update
    @result
  end

  def form(surface)
    chat = EditBox.new('Chat', text: 'Keep my draft.', quiet: true)
    form = GameRoomUI::Form.new(surface.fields + [chat], quiet: true)
    form.game_room_background_help_enabled = true
    form.focus
    form
  end
end
