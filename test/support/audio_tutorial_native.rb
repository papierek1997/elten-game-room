require_relative 'host_source'
require_relative 'host_session'
host = EltenTestHost.root
%w[
  ri/__ri eapi/structs eapi/keyboard eapi/speech eltenlink/__eltenlink
  ui/input eapi/common/input ui/form ui/controls/form_field
  ui/controls/list_box ui/controls/edit_box ui/controls/button ui/controls/grid_box
].each { |source| require File.join(host, 'src', source) }

Object.include(EltenAPI::UI)
Object.include(EltenAPI::Common)
Object.include(EltenAPI::Controls)
Object.include(EltenAPI::Speech)
Configuration = EltenAPI::Structs::Configuration
Configuration.keyboardscheme = :windows
Configuration.listtype = :linear
Configuration.controlspresentation = :voice_only
Configuration.soundthemeactivation = false
Configuration.voicepitch = 50
%w[Form ListBox EditBox Button GridBox].each do |name|
  Object.const_set(name, EltenAPI::Controls.const_get(name))
end

module EltenWindow
  def self.keyboard_key_held?(_code); false; end
  def self.keyboard_active?; true; end
  def self.character_input_supported?; true; end
  def self.take_character(_multi); ''; end
end

module Programs
  def self.emit_event(_event); end
end

module Log
  def self.error(message); raise message; end
  def self.warning(message); raise message; end
end

module SpeechOutput
  class << self
    attr_reader :queue, :calls
    def reset
      @queue, @calls = [], []
    end
    def current_output; self; end
    def pause_supported?; false; end
    def speak_text(text, method:, interrupt:, **_options)
      stop if interrupt
      @queue << text
      @calls << [text, method, interrupt]
    end
    def stop
      @queue.clear
    end
  end
end

def _(text); text; end
SpeechOutput.reset
def p_(_context, text); text; end
def play_sound(_name, **_options); end
def loop_update(*_args); $native_tutorial_driver.tick(self); end

require_relative '../../lib/game_room_ui'
require_relative '../../lib/audio_tutorial'

def assert(value, message)
  raise message unless value
end

class NativeTutorialSound
  attr_reader :close_count
  def initialize
    @close_count = 0
  end
  def close
    @close_count += 1
  end
end

class NativeTutorialProgram
  attr_reader :plays
  def initialize
    @plays = []
  end
  def play_sound_from_asset(asset, **options)
    sound = NativeTutorialSound.new
    @plays << [asset, options, sound]
    sound
  end
  private
  def game_room_sound_volume(_asset); 0.4; end
  def game_room_sound_enabled?(_asset); true; end
end

class NativeTutorialDriver
  attr_reader :form, :ticks, :checks, :repeats

  def initialize(program, entries)
    @program, @entries = program, entries
    @frames, @raw_keys, @repeats = [], [], []
    @ticks, @checks = 0, 0
    @now = 0.0
    @expected_index, @expected_assets, @expected_closes = 0, [], []
  end

  def frame(label, keys = [], repeat: nil, index: @expected_index, play: nil, stop: false, welcome: false)
    closes = @expected_closes.dup
    closes[-1] = 1 if !closes.empty? && (play || stop)
    assets = @expected_assets.dup
    if play
      assets << play
      closes << 0
    end
    @frames << [label, keys, repeat, index, assets, closes, welcome]
    @expected_index, @expected_assets, @expected_closes = index, assets, closes
  end

  def activation(label, code, asset)
    2.times do |press|
      prefix = "#{label} press #{press + 1}"
      frame(prefix, [code], play: asset)
      frame("#{prefix} held", [code])
      frame("#{prefix} native repeat", [code], repeat: code)
      frame("#{prefix} still held", [code])
      frame("#{prefix} second native repeat", [code], repeat: code)
      frame("#{prefix} release")
      frame("#{prefix} idle")
    end
  end

  def tick(form)
    verify_previous
    assert(form.is_a?(GameRoomUI::Form), 'Tutorial bypassed the native form')
    assert(@form.nil? || @form.equal?(form), 'Tutorial opened an extra form')
    @form = form
    assert(form.fields.length == 1 && form.fields.first.instance_of?(ListBox), 'Tutorial added an extra focus field')
    assert(form.fields.first.options == @entries.map(&:label), 'Native list labels differ from tutorial entries')
    frame = @frames.shift
    raise 'Tutorial did not exit before the finite input stream ended' unless frame
    assert(form.instance_variable_get(:@wait) == false, 'Escape did not resume native Form#wait') if @frames.empty?
    @ticks += 1
    label, keys, repeat = frame
    state = "\0" * 256
    keys.each { |code| state.setbyte(code, 0x80) }
    events = (@raw_keys - keys).map { |code| [code, false] } +
      (keys - @raw_keys).map { |code| [code, true] }
    events << [repeat, :repeat] if repeat
    @now += 0.1
    result = EltenAPI::KeyboardState.update(raw_state: state, events: events, now: @now,
      pressed_implies_held: false, synthesize_repeats: false)
    if repeat
      assert(result.repeated[repeat] && result.pressed[repeat] && !result.first_pressed[repeat], "#{label}: native repeat was not delivered")
      @repeats << repeat
    end
    (@raw_keys - keys).each do |code|
      assert(result.released[code] && !result.held[code] && !result.first_pressed[code], "#{label}: native release was not delivered")
    end
    @raw_keys = keys
    $input_frame_serial = $input_frame_serial.to_i + 1
    $keyboard_state_frame_serial = $input_frame_serial
    $keyboard_state_frame_thread = Thread.current
    $activecontrols = []
    @previous = frame
  end

  def finish
    verify_previous
    assert(@frames.empty?, 'Tutorial returned before processing Escape')
    assert(@form.instance_variable_get(:@wait) == false, 'Escape did not resume native Form#wait')
    assert(!@form.game_room_hotkeys_active?, 'Tutorial left its form hotkeys active')
  end

  private

  def verify_previous
    return unless @previous
    label, _keys, _repeat, index, assets, closes, welcome = @previous
    assert(@form.fields.first.index == index, "#{label}: native arrow navigation selected the wrong row")
    assert(@program.plays.map(&:first) == assets, "#{label}: playback count or selected asset changed")
    assert(@program.plays.map { |entry| entry[2].close_count } == closes, "#{label}: playback cleanup or overlap differs")
    @program.plays.each do |entry|
      assert(entry[1] == {volume: 0.4, sample: false, loop: false}, "#{label}: wrong playback options")
    end
    if welcome
      opening = "#{WELCOME} #{@entries.first.label}"
      assert(SpeechOutput.queue == [opening], "#{label}: the first item was read before the welcome, or the welcome was cut off")
      assert(SpeechOutput.calls.count { |call| call.first.include?(WELCOME) } == 1, "#{label}: welcome was repeated")
      assert(SpeechOutput.calls.last == [opening, 1, true], "#{label}: opening did not replace stale menu speech")
    end
    @previous = nil
    @checks += 1
  end
end

WELCOME = 'Welcome to the audio tutorial. Here you will learn the sounds used in this game. Use the arrow keys to browse. Press Space or Enter to play a sound.'
