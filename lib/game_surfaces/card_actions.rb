module GameSurfaces
  module CardActions
    using GameRoomLocalization::Translations

    attr_accessor :program

    private

    def submit_card_selection(zone, card, index)
      return unless confirm_card_action(card_confirmation(card))

      emit_action("card", "select", {
        "zone" => zone.id.to_s, "index" => index,
        "card_id" => card_id(card), "card" => card_value(card)
      })
    end

    def selected_card_action(payload)
      zone_id = state_value(payload, "hand_id", "").to_s
      zone_index = @zones.index { |zone| zone.id.to_s == zone_id && zone.hand_order != nil }
      return false if zone_index == nil
      return true unless action_allowed?
      if @pending_choices.key?(zone_id)
        speak(_("Finish or cancel the current card choice first."))
        return true
      end

      card = @cards.fetch(zone_id)[@controls[zone_index].index.to_i]
      return true if card == nil

      selection = state_value(payload, "actions", {}).fetch(card_id(card), nil)
      return true if selection == nil

      message = GameRoomContent.utf8(state_value(payload, "confirmation", ""))
      message = message % { card: GameRoomContent.utf8(card_label(card)) } unless message.empty?
      return true unless confirm_card_action(message) && action_allowed?

      Action.from_h(selection, source: "shortcut:#{state_value(payload, 'shortcut', '')}")
    end

    def card_confirmation(card)
      card.respond_to?(:confirmation) ? card.confirmation : state_value(card, "confirmation", nil)
    end

    def confirm_card_action(message)
      return true if message.to_s.empty?
      return false unless action_allowed?

      choice = RefreshAwareListBox.new([_("No"), _("Yes")].map { |label| GameRoomContent.utf8(label) },
        header: GameRoomContent.utf8(message), index: 0, flags: ListBox::Flags::AnyDir, quiet: true)
      accept = Button.new(GameRoomContent.utf8(_("Confirm")))
      cancel = Button.new(GameRoomContent.utf8(_("Cancel")))
      form = GameRoomUI::Form.new([choice, accept, cancel], program: @program, quiet: true)
      form.accept_button, form.cancel_button = accept, cancel
      form.hide(accept)
      form.hide(cancel)
      accepted = false
      accept.on(:press) { accepted = choice.index == 1; form.resume }
      cancel.on(:press) { form.resume }
      form.wait
      accepted && action_allowed?
    ensure
      EltenAPI::KeyboardState.clear_current_frame if form != nil && defined?(EltenAPI::KeyboardState)
    end
  end
end
