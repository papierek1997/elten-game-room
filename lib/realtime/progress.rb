require_relative 'timer'
require_relative '../game_background_policy'
require_relative '../game_background_presentation'
require_relative '../recordings/capture'

module GameRoomRealtime
  # The form and the active-UI bridge share ONE clock-gated timer. Detaching a
  # view does not stop transport/physics; closing the client stops both paths.
  # No worker touches a form, keyboard, audio device or realtime engine.
  class Progress
    attr_reader :timer

    def initialize(program:, clock:, key:, &advance)
      @program, @ui_thread, @advance = program, Thread.current, advance
      @timer = Timer.new(clock: clock) { @advance.call(@background == true) }
      @presentation = GameRoomBackgroundPresentation.attach(self, program: program, runner: self,
        key: [program.class, :realtime, key])
    end

    def attach(form)
      # A match may start on the covering scene's UI before it has a view.
      # Its eventual form belongs to the returning game's UI, not that scene.
      # Otherwise the bridge wins every clock tick with neutral background
      # input even while this form is visibly processing the player's keys.
      @ui_thread = Thread.current
      return if @form.equal?(form)
      detach
      @form = form
      @form.add_timer(@timer)
      @form.retain_binding_timer(@timer) if @form.respond_to?(:retain_binding_timer)
    end

    def detach
      @form.delete_timer(@timer) if @form
      @form = nil
    end

    def update(background: false)
      return if @closed
      @background = background
      @timer.update
    ensure
      @background = false
    end

    def covered?
      !@form || GameRoomBackgroundPolicy.covered?(@ui_thread, program: @program, form: @form)
    end

    def closed?; @closed == true; end
    def presentation_snapshot; nil; end
    def present_background_session(_runner); update(background: true); end

    def close
      return if @closed
      @closed = true
      @timer.stop
      detach
      @presentation.close
      @advance = @program = nil
    end
  end

  module ProgressClient
    include GameRoomRecordings::CaptureClient
    def background_progress?; true; end

    def start_progress
      attach_recording
      @audio.background_provider = -> { @progress&.covered? } if @audio.respond_to?(:background_provider=)
      @progress = Progress.new(program: @program, clock: @clock, key: @base_match) do |background|
        @background_input = background
        @replay&.finished? ? tick : frame
      ensure
        @background_input = false
      end
    end

    def progress_frame(background: true)
      @progress ? @progress.update(background: background) : frame
    end

    def announce_progress(text, interrupt: true)
      covered = @progress&.covered?
      return unless GameRoomBackgroundPolicy.speech?(@program, covered: covered)
      covered || !interrupt ? speak(text, stop: false, break_sequence: false) : speak(text)
    end
  end
end
