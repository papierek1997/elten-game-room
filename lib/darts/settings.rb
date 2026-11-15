# encoding: UTF-8
require_relative 'preferences'
require_relative '../game_room_ui'

require_relative '../game_room_localization'

module GameRoomDarts
  using GameRoomLocalization::Translations

  class Settings
    def _(text); GameRoomContent.utf8(super(text)); end

    def initialize(values, program:, tick: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @values, @program = Preferences.normalize(values), program
      @tick, @clock = tick, clock
    end

    def wait
      require_relative '../realtime/timer' if @tick
      choices = Preferences::LOCATOR_ASSETS.keys
      labels = [_('Rounded'), _('Clear'), _('Bright')]
      locator = ListBox.new(labels, header: _('Aiming sound (only for you)'),
        index: choices.index(@values['locator_sound']) || 0, quiet: true)
      preview = Button.new(_('Play selected sound'))
      save, cancel = Button.new(_('Save')), Button.new(_('Cancel'))
      form = GameRoomUI::Form.new([locator, preview, save, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = save, cancel
      accepted = false
      preview.on(:press) { play_preview(Preferences::LOCATOR_ASSETS.fetch(choices.fetch(locator.index.to_i))) }
      save.on(:press) { accepted = true; form.resume }
      cancel.on(:press) { form.resume }
      timer = GameRoomRealtime::Timer.new(clock: @clock, &@tick) if @tick
      form.add_timer(timer) if timer
      form.wait
      accepted ? Preferences.normalize('locator_sound' => choices.fetch(locator.index.to_i)) : nil
    ensure
      close_preview
      timer&.stop
      form.delete_timer(timer) if form && timer
    end

    private

    def play_preview(asset)
      close_preview
      @preview = @program.create_sound_from_asset(asset, loop: false, sample: false)
      unless @preview
        alert(_('Sound preview is unavailable.'))
        return
      end
      @program.manage(@preview) if @program.respond_to?(:manage)
      @preview.volume = 1.0 if @preview.respond_to?(:volume=)
      @preview.play
    end

    def close_preview
      return unless @preview

      @preview.pause if @preview.respond_to?(:pause)
      @program.release(@preview) if @program.respond_to?(:release)
      @preview.close
      @preview = nil
    end
  end
end
