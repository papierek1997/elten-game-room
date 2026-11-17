# encoding: UTF-8
require_relative 'preferences'
require_relative '../game_room_ui'

require_relative '../game_room_localization'

module GameRoomDarts
  using GameRoomLocalization::Translations

  class Settings
    Outcome = Struct.new(:values, :publish_saved, keyword_init: true)

    def _(text); GameRoomContent.utf8(super(text)); end

    def initialize(values, program:, tick: nil, withdraw: nil, confirm_publish: nil, confirm_withdraw: nil, notify: nil,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @values, @program = Preferences.normalize(values), program
      @tick, @clock = tick, clock
      @withdraw = withdraw
      @confirm_publish = confirm_publish || -> {
        confirm(_('Publish your three saved personal records in each Darts ranking too?'))
      }
      @confirm_withdraw = confirm_withdraw || -> {
        confirm(_('Remove all your results from the public Darts rankings? Your private records will stay saved. If publishing remains enabled, later records can appear again.'))
      }
      @notify = notify || ->(message) { alert(message) }
    end

    def wait
      require_relative '../realtime/timer' if @tick
      choices = Preferences::LOCATOR_ASSETS.keys
      labels = [_('Rounded'), _('Clear'), _('Bright')]
      public_rankings = CheckBox.new(_('Publish new Darts records in the public rankings'),
        checked: @values['public_rankings'])
      private_history = CheckBox.new(_('Show private Darts records in the table history'),
        checked: @values['private_records_in_history'])
      locator = ListBox.new(labels, header: _('Aiming sound (only for you)'),
        index: choices.index(@values['locator_sound']) || 0, quiet: true)
      preview = Button.new(_('Play selected sound'))
      mouse_input = CheckBox.new(_('Play Darts using the mouse or touchpad'), checked: @values['mouse_input'])
      withdraw = Button.new(_('Remove my results from the public Darts rankings')) if @withdraw
      save, cancel = Button.new(_('Save')), Button.new(_('Cancel'))
      fields = [public_rankings, private_history, locator, preview, mouse_input]
      fields << withdraw if withdraw
      form = GameRoomUI::Form.new(fields + [save, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = save, cancel
      accepted = false
      preview.on(:press) { play_preview(Preferences::LOCATOR_ASSETS.fetch(choices.fetch(locator.index.to_i))) }
      withdraw&.on(:press) do
        next unless @confirm_withdraw.call
        if @withdraw.call
          @notify.call(_('Removal of your public Darts results has been queued.'))
        else
          @notify.call(_('Could not queue removal of your public Darts results.'))
        end
      end
      save.on(:press) { accepted = true; form.resume }
      cancel.on(:press) { form.resume }
      timer = GameRoomRealtime::Timer.new(clock: @clock, &@tick) if @tick
      form.add_timer(timer) if timer
      form.wait
      return unless accepted
      values = Preferences.normalize('locator_sound' => choices.fetch(locator.index.to_i),
        'public_rankings' => public_rankings.checked == true,
        'unlocked_difficulty' => @values['unlocked_difficulty'],
        'unlocked_account' => @values['unlocked_account'],
        'private_records_in_history' => private_history.checked == true,
        'mouse_input' => mouse_input.checked == true)
      publish_saved = !@values['public_rankings'] && values['public_rankings'] && @confirm_publish.call
      Outcome.new(values: values, publish_saved: publish_saved)
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
