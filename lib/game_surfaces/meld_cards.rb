require_relative "specifications"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations


  class MeldListBox < RefreshAwareListBox
    attr_accessor :meld_context
    def context(menu, submenu = false)
      super
      meld_context&.call(menu) unless submenu
    end
  end

  # Ordered groups are local UI state. The game supplies a pure validator and
  # current legal destinations; this control knows no Rummy scoring rules.
  class MeldHandSurface < CardTable
    def initialize(spec, state: {})
      @draft = false
      @groups = []
      @selection = []
      @view = nil
      super
      if state["meld_turn"] == spec.turn && spec.editable
        @draft = state["meld_draft"] == true
        @groups = state.fetch("meld_groups", []).map(&:dup)
        @selection = state.fetch("meld_selection", []).dup
        discard_missing_draft!
      end
      @controls.first.meld_context = method(:context_menu)
      refresh_labels if @draft
      if state["meld_turn"].to_a.first == spec.turn.to_a.first
        @editing_group = state["meld_editing_group"]
        restore_view(state["meld_view"].to_s, state["meld_view_item"], state["meld_view_index"].to_i)
      end
    end

    def reusable_for?(spec)
      spec.is_a?(MeldHandSpec)
    end

    def state
      view_index = @controls.first.index.to_i
      view_item = @view_items.to_a[view_index]
      with_hand_index do
        super.merge("meld_turn" => @spec.turn, "meld_draft" => @draft,
          "meld_groups" => @groups.map(&:dup), "meld_selection" => @selection.dup,
          "meld_view" => @view.to_s, "meld_view_index" => view_index,
          "meld_view_item" => view_item && view_item[:id], "meld_editing_group" => @editing_group&.dup)
      end
    end

    def update_spec(spec)
      previous_turn = @spec.turn
      previous_view = @view
      previous_index = @controls.first.index.to_i
      previous_item = @view_items&.[](previous_index)&.[](:id)
      close_view(speak: false) if @view
      super
      if previous_turn != spec.turn || !spec.editable
        clear_draft
      else
        discard_missing_draft!
      end
      refresh_labels if @draft
      # Inspection survives harmless updates; actions are rebuilt from the
      # latest spec. Never replace a picker with the hand on a mere refresh.
      if previous_turn.to_a.first == spec.turn.to_a.first
        restore_view(previous_view.to_s, previous_item, previous_index)
      end
      self
    end

    def take_cursor_announcement(field_index = nil)
      # The hand cursor is kept up to date behind the inspection, but must
      # not announce a hand card while the user is on a public meld list.
      super(@view ? nil : field_index)
    end

    def handle_command(command, payload = {})
      @command_field_index = nil
      case command.to_s
      when "meld_new"
        return unavailable(@spec.action_error) unless @spec.editable
        return unavailable unless @pending_choices.empty? && !@view
        if @draft && !@selection.empty?
          return true unless validate_groups([@selection])
          @groups << @selection.dup
          @selection = []
        end
        @draft = true
        refresh_labels
        speak(_("Select cards in meld order with Enter."))
      when "meld_submit"
        return unavailable unless @draft && @spec.editable && !@view
        groups = @groups + (@selection.empty? ? [] : [@selection])
        preview = validate_groups(groups)
        return true unless preview
        if preview[:points] < @spec.minimum.to_i
          speak(_("First meld: %{points} points; %{missing} more required.") % { points: preview[:points], missing: @spec.minimum.to_i - preview[:points] })
          return true
        end
        return Action.new(kind: "command", name: "meld", payload: { "groups" => groups.map(&:dup) })
      when "meld_read"
        read_draft
      when "meld_edit"
        edit_groups
      when "meld_table"
        open_table
      when "meld_discard_pile"
        choices = @spec.discard_choices.to_a
        return unavailable(@spec.discard_error) if choices.empty?
        return unavailable unless !@draft && @pending_choices.empty?
        if choices.one?
          close_view(speak: false) if @view
          return Action.from_h(choices.first[:action])
        end
        open_view(:discards, _("Discard pile"), choices)
      when "meld_discard"
        return unavailable(@spec.action_error) unless @spec.editable
        return unavailable unless @spec.can_discard && !@draft && !@view && @pending_choices.empty?
        card = @cards.fetch(@zones.first.id.to_s)[@controls.first.index.to_i]
        return Action.new(kind: "command", name: "discard", payload: { "card" => card_id(card) }) if card
      when "navigate_playable_card"
        return unavailable if @view
        payload = payload.merge("auto_action" => nil, "auto_card_id" => nil) if @draft
        return super(command, payload)
      when "sort_cards"
        return unavailable if @view
        result = super
        refresh_labels if @draft
        return result
      else
        return super
      end
      true
    end

    def cancel_pending_action?
      @view != nil || @draft || super
    end

    def save_game_error
      _("Cancel the prepared melds before saving the game.") if @draft
    end

    def cancel_pending_action!
      if @view
        close_view
        return true
      elsif @draft
        clear_draft
        refresh_labels
        @controls.first.announce_current_card
        return true
      end
      if !@pending_choices.empty?
        restore_card_list(@zones.first, @controls.first, speak: false)
        @controls.first.announce_current_card
        return true
      end
      false
    end

    private

    def card_list_control_class; MeldListBox; end

    def intercept_card_selection(zone_id, index)
      if @view
        entry = @view_items[index]
        return true unless entry
        if entry[:action]
          action = entry[:action]
          close_view(speak: false)
          emit_action(action["kind"], action["action"], action.reject { |k, _| %w[kind action].include?(k) })
        elsif entry[:select]
          entry[:select].call
        else
          speak(entry[:details].to_s.empty? ? entry[:label] : entry[:details])
        end
        return true
      end
      if @pending_choices[zone_id]
        choice = card_choices(@pending_choices[zone_id][:card])[index]
        if choice && choice_id(choice) == "cancel"
          restore_card_list(@zones.first, @controls.first, speak: false)
          @controls.first.announce_current_card
          return true
        end
        return false
      end
      return unavailable(@spec.action_error) unless @spec.editable
      if !@draft && card_choices(@cards.fetch(zone_id)[index]).empty?
        return unavailable(_("This card cannot be laid off. Use N to prepare a meld."))
      end
      return false unless @draft
      card = @cards.fetch(zone_id)[index]
      return true unless card
      id = card_id(card)
      if @selection.include?(id)
        @selection.delete(id)
      elsif @groups.flatten.include?(id)
        speak(_("This card already belongs to another prepared meld."))
        return true
      else
        @selection << id
      end
      refresh_labels
      @controls.first.announce_current_card
      true
    end

    def clear_draft
      @draft = false; @groups = []; @selection = []; @editing_group = nil
    end

    def discard_missing_draft!
      ids = @cards.fetch(@zones.first.id.to_s).map { |c| card_id(c) }
      clear_draft unless ((@groups.flatten + @selection) - ids).empty?
    end

    def refresh_labels
      return if @view || !@pending_choices.empty?
      selected = @groups.flatten + @selection
      @controls.first.options = @cards.fetch(@zones.first.id.to_s).map do |card|
        label = card_label(card)
        selected.include?(card_id(card)) ? _("%{card}; selected") % { card: label } : label
      end
    end

    def validate_groups(groups)
      value = @spec.validator.call(groups)
      unless value
        # Keep correct prepared melds, but let the player start an invalid
        # one again without manually unticking every card. Reading with P
        # does not use this submission path and remains non-destructive.
        @groups.select! { |group| @spec.validator.call([group]) }
        @selection = [] if !@selection.empty? && !@spec.validator.call([@selection])
        refresh_labels
        speak(_("These cards do not form valid ordered melds."))
      end
      value
    end

    def read_draft
      groups = @groups + (@selection.empty? ? [] : [@selection])
      if groups.empty?
        speak(_("No meld is being prepared."))
        return
      end
      labels = @cards.fetch(@zones.first.id.to_s).to_h { |card| [card_id(card), card_label(card)] }
      text = groups.map { |g| g.map { |id| labels[id] }.join(", ") }.join("; ")
      value = @spec.validator.call(groups)
      text += ". "
      text += if !value
        _("These cards do not form valid ordered melds.")
      elsif @spec.minimum.to_i > value[:points]
        _("First meld: %{points} points; %{missing} more required.") % { points: value[:points], missing: @spec.minimum.to_i - value[:points] }
      else
        _("Prepared melds: %{points} points.") % { points: value[:points] }
      end
      speak(text)
    end

    def edit_groups
      return unavailable unless @draft && @spec.editable && @pending_choices.empty?
      unless @selection.empty?
        @groups << @selection.dup
        @selection = []
      end
      items = group_items
      return unavailable if items.empty?
      open_view(:groups, _("Prepared melds"), items)
    end

    def open_table(speak: true)
      items = @spec.table.to_a
      return unavailable(_("There are no melds on the table.")) if items.empty? && speak
      open_view(:table, _("Melds on the table"), items, speak: speak)
    end

    def open_view(view, header, items, speak: true)
      # A view replaces a card-choice popup, never nests inside its indices.
      restore_card_list(@zones.first, @controls.first, speak: false) unless @pending_choices.empty?
      @hand_index = @controls.first.index.to_i unless @view
      @view = view
      @view_items = items
      @controls.first.options = items.map { |i| i[:label] }
      @controls.first.header = header
      @controls.first.empty_label = view == :table ? _("There are no melds on the table.") : ""
      @controls.first.index = 0
      @command_field_index = 0
      @controls.first.focus if speak
    end

    def close_view(speak: true)
      @view = nil
      @view_items = nil
      @controls.first.header = @zones.first.header
      @controls.first.empty_label = @zones.first.empty_label
      refresh_labels
      @controls.first.index = @hand_index.to_i
      @controls.first.announce_current_card if speak
    end

    def group_items
      labels = @cards.fetch(@zones.first.id.to_s).to_h { |card| [card_id(card), card_label(card)] }
      @groups.map do |group|
        { id: group.dup, label: group.map { |id| labels[id] }.join(", "), select: lambda do
          @editing_group = group.dup
          open_view(:group_actions, _("Prepared meld"), group_action_items)
        end }
      end
    end

    def group_action_items
      [
        { id: "edit", label: _("Edit this meld"), select: lambda do
          index = @groups.index(@editing_group)
          @selection = @groups.delete_at(index) if index
          close_view
        end },
        { id: "remove", label: _("Remove this meld"), select: lambda do
          index = @groups.index(@editing_group)
          @groups.delete_at(index) if index
          close_view
        end }
      ]
    end

    def restore_view(view, item_id, index)
      case view
      when "table"
        open_table(speak: false)
      when "discards"
        return if @spec.discard_choices.to_a.empty?
        open_view(:discards, _("Discard pile"), @spec.discard_choices, speak: false)
      when "groups"
        return unless @draft && @spec.editable && !@groups.empty?
        open_view(:groups, _("Prepared melds"), group_items, speak: false)
      when "group_actions"
        return unless @draft && @spec.editable && @groups.include?(@editing_group)
        open_view(:group_actions, _("Prepared meld"), group_action_items, speak: false)
      else
        return
      end
      selected = @view_items.index { |item| item[:id] == item_id } unless item_id == nil
      @controls.first.index = selected || [[index.to_i, @view_items.length - 1].min, 0].max
    end

    def with_hand_index
      return yield unless @view
      index = @controls.first.index
      @controls.first.index = @hand_index.to_i
      begin
        yield
      ensure
        @controls.first.index = index
      end
    end

    def context_menu(menu)
      return unless @view == :table
      item = @view_items[@controls.first.index.to_i]
      return unless item
      merges = item.fetch(:merges, [])
      unless merges.empty?
        menu.submenu(_("Merge")) do |submenu|
          merges.each { |entry| submenu.option(entry[:label]) { send_table_action(entry[:action]) } }
        end
      end
      item.fetch(:actions, []).each { |entry| menu.option(entry[:label]) { send_table_action(entry[:action]) } }
    end

    def send_table_action(action)
      return unless action_allowed?
      close_view(speak: false) if action["action"] == "take"
      emit_action(action["kind"], action["action"], action.reject { |k, _| %w[kind action].include?(k) })
    end

    def unavailable(message = nil)
      speak(message || _("This action is not available now."))
      true
    end
  end
end
