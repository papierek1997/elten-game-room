# encoding: UTF-8
# Real ELTEN 3.0.4 controls/keyboard/speech adapter; only device boundaries are fake.
# Neither this helper nor its dependencies load NVDA/SAPI/audio device backends.
require_relative 'background_help_native'
require_relative 'program_settings'

raise 'Native tournament test must not run inside a live NVDA process' if defined?(NVDA)
module NVDA
  class << self
    attr_reader :calls
    def reset; @calls = []; end
    def check; true; end
    def braille(text, *arguments); @calls << [text, arguments, Thread.current]; end
  end
end

class TournamentNativeDriver < BackgroundHelpNativeDriver
  attr_reader :forms, :steps, :ui_thread, :resume_counts
  attr_accessor :on_resume

  def initialize
    super
    @forms, @steps = [], []
    @resume_counts = {}.compare_by_identity
    @ui_thread = Thread.current
    SpeechOutput.reset
    NVDA.reset
    EltenAPI::KeyboardState.reset
    $focus = false
    $native_tutorial_driver = self
  end

  def step(header, keys = [], &check)
    @steps << [header, keys, check]
  end

  def press(header, key, &check)
    step(header, [key], &check)
    step(header)
  end

  # Explicit navigation to a test-only actor selector. Production tournaments
  # use the signed-in account and never ask the user to invent a participant.
  def open_test_participant
    translate = ->(value) { GameRoomContent.utf8(GameRoomLocalization.translate(value)) }
    step(translate.call('Local tournament tests'), [13]) do |form|
      advanced = form.fields.grep(Button).find { |field| field.label == translate.call('Advanced local test tools') }
      change = form.fields.grep(Button).find { |field| field.label == translate.call('Change test participant') }
      assert(advanced && change, 'Missing test participant controls')
      advanced.press if form.instance_variable_get(:@hidden)[form.fields.index(change)]
      form.index = form.fields.index(change)
    end
  end

  def tick(form)
    assert(Thread.current == @ui_thread, 'Native UI ran outside its UI thread')
    @forms << form if form.is_a?(GameRoomUI::Form) && !@forms.include?(form)
    keys = []
    if form.is_a?(GameRoomUI::Form) && form.instance_variable_get(:@wait) == true
      header, keys, check = @steps.shift || raise('Native tournament exhausted its finite keyboard queue')
      assert(header === form.fields.first.header, "Expected #{header}, got #{form.fields.first.header}")
      check&.call(form)
    elsif form.is_a?(GameRoomUI::Form) && form.instance_variable_get(:@wait) == false
      @resume_counts[form] = @resume_counts.fetch(form, 0) + 1
      assert(@resume_counts[form] == 1, 'Reentrant Back/Enter resumed the same form twice')
      @on_resume&.call(form)
    end
    # Constructor/resume ticks release keys without consuming another user action,
    # exactly like BackgroundHelpNativeDriver. Form#wait/update/focus stay native.
    @root, @keys = form, [keys]
    super
  end

  def finish
    assert(@steps.empty?, 'Native tournament returned before processing all keyboard actions')
    assert(@forms.all? { |form| form.instance_variable_get(:@wait) == false }, 'A native modal wait remained active')
    assert(@forms.none?(&:game_room_hotkeys_active?), 'A closed form retained active hotkeys')
    assert(NVDA.calls.all? { |call| call.last == @ui_thread }, 'Braille ran outside the UI thread')
  end
end
