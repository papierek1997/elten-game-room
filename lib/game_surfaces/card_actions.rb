module GameSurfaces
  module CardActions
    using GameRoomLocalization::Translations

    attr_accessor :program

    private

    def select_card_row(zone_id, control, raw_index)
      zone = @zones.find { |item| item.id.to_s == zone_id }
      cards, pending = @cards.fetch(zone_id), @pending_choices[zone_id]
      index = raw_index - (pending ? 0 : leading_rows(zone).length)
      return activate_leading_row(zone) if index < 0
      return if respond_to?(:intercept_card_selection, true) && intercept_card_selection(zone_id, index)
      return select_card_choice(zone, control, pending, index) if pending
      if index >= cards.length
        command = zone_commands(zone)[index - cards.length]
        emit_action('command', command.id, command.payload.nil? ? {} : command.payload.to_h) if command
        return
      end
      card = cards[index]
      return unless card
      choices = card_choices(card)
      if GameRoomUI.modifiers_when_pressed(control, :enter).include?(:shift)
        return if select_shifted_card(zone, card, choices, index)
      end
      choices.empty? ? submit_card_selection(zone, card, index) : begin_card_choice(zone, control, card, index)
    end

    def select_card_choice(zone, control, pending, index)
      choice = card_choices(pending[:card])[index]
      return unless choice
      payload = {'zone'=>zone.id.to_s, 'index'=>pending[:card_index],
        'card_id'=>card_id(pending[:card]), 'card'=>choice_value(choice), 'choice_id'=>choice_id(choice)}
      restore_card_list(zone, control, speak:false)
      emit_action('card', 'select', payload)
    end

    def select_shifted_card(zone, card, choices, index)
      choice = shifted_choice(card, choices)
      id = choice ? choice_id(choice) : shift_choice_id(card)
      return false if id.empty?
      # An unavailable declared Shift action still goes to the game validator;
      # it must not silently become an ordinary play.
      emit_action('card', 'select', {'zone'=>zone.id.to_s, 'index'=>index,
        'card_id'=>card_id(card), 'card'=>choice ? choice_value(choice) : card_value(card), 'choice_id'=>id})
      true
    end

    def submit_card_selection(zone, card, index)
      return unless confirm_card_action(card_confirmation(card))

      if (action = zone.activation_action)
        emit_action(action.kind, action.name, action.payload, source: action.source)
      else
        emit_action("card", "select", {
          "zone" => zone.id.to_s, "index" => index,
          "card_id" => card_id(card), "card" => card_value(card)
        })
      end
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

      index = card_index_for(@zones[zone_index], @controls[zone_index])
      return true if index < 0
      card = @cards.fetch(zone_id)[index]
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

      choice = GameRoomUI.choose_index(message, [_("No"), _("Yes")], program: @program,
        flags: ListBox::Flags::AnyDir)
      choice == 1 && action_allowed?
    end
  end
end
