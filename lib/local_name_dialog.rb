require_relative 'local_name_presentation'
require_relative 'game_background_policy'

module GameRoomUI
  using GameRoomLocalization::Translations

  module ReceiverInput
    CODES = [0x10, 0x11, 0x12, 0x53, 0x46, 0x48].freeze

    def handle_receiver_input
      service = game_room_program&.local_name_presentation if game_room_program&.respond_to?(:local_name_presentation)
      return false unless service
      state = EltenAPI::KeyboardState.current
      @receiver_input_latched = false if CODES.none? { |code| state.held[code] }
      return false if @receiver_input_latched || CODES.none? { |code| state.first_pressed[code] }
      complete = CODES.any? do |code|
        snapshot = EltenAPI::KeyboardState.state_when_pressed(code) if state.first_pressed[code]
        snapshot && CODES.all? { |member| snapshot[member] == true }
      end
      return false unless complete
      @receiver_input_latched = true
      return false unless game_room_hotkeys_active? && !game_room_background_help? && !game_room_pending_operation
      return false unless GameRoomBackgroundPolicy.window_foreground?
      active = $activecontrols.to_a.reverse.find { |control| control.is_a?(GameRoomUI::HostForm) } ||
        $lastactivecontrols.to_a.reverse.find { |control| control.is_a?(GameRoomUI::HostForm) }
      return false unless active.equal?(self)
      field = fields[index.to_i]
      return false if field.is_a?(EditBox) && (field.flags.to_i & EditBox::Flags::ReadOnly) == 0
      ReceiverInput.edit(self, service)
      true
    end

    def self.edit(parent, service)
      EltenAPI::KeyboardState.clear_current_frame
      field = EditBox.new('', text: service.value.to_s, quiet: true)
      accept, cancel, reset = Button.new(_('Select')), Button.new(_('Cancel')), Button.new(_('Reset'))
      form = GameRoomUI::Form.new([field, reset, accept, cancel], program: parent.game_room_program, quiet: true)
      form.accept_button, form.cancel_button = accept, cancel
      form.hide(accept)
      form.hide(cancel)
      form.hide(reset) unless service.value
      changed = false
      save = lambda do |resetting|
        next form.resume unless parent.game_room_program.local_name_presentation.equal?(service)
        begin
          changed = resetting ? service.reset : service.save(field.text)
          form.resume
        rescue ArgumentError
          speak(_('Invalid value.'))
        rescue IOError, SystemCallError
          speak(_('Could not save this value.'))
        end
      end
      accept.on(:press) { save.call(false) }
      reset.on(:press) { save.call(true) }
      cancel.on(:press) { form.resume }
      form.wait
      parent.trigger(:local_presentation_changed) if changed
      changed
    ensure
      EltenAPI::KeyboardState.clear_current_frame
      parent.focus
    end
  end
end
