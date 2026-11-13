require_relative "specifications"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations



  # One-field dice surface used by score-sheet games. Enter rolls the selected
  # dice or, when none are selected, opens the local category list. Selecting
  # a category is the only server action created by that local list.
  class RollAndScoreSurface
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      @dice = spec.dice.to_a
      @categories = spec.categories.to_a
      validate!
      @signature = dice_signature
      restored_signature = state_value(state, "dice_signature", "").to_s
      @selected_ids = if restored_signature == @signature
        state_value(state, "selected_ids", []).to_a.map(&:to_s)
      else
        []
      end
      @selected_ids.select! { |id| @dice.any? { |die| die.id.to_s == id } }
      remembered_mode = state_value(state, "mode", "dice").to_s
      @mode = spec.force_categories == true && !spec.score_grid ? :categories : remembered_mode.to_sym
      @mode = :dice if @mode != :categories || @categories.empty?
      @index = state_value(state, "index", 0).to_i
      @control = RefreshAwareListBox.new(
        labels,
        header: current_header,
        index: bounded_index(@index),
        quiet: true,
        empty_label: (spec.empty_label || _("No choices are available")).to_s
      )
      @control.on(:select) { activate }
    end

    def fields
      [@control]
    end

    def state
      {
        "mode" => @mode.to_s,
        "index" => @control.index.to_i,
        "selected_ids" => @selected_ids.dup,
        "dice_signature" => @signature
      }
    end

    def suppress_next_focus!(_field_index = 0)
      @control.suppress_next_focus!
    end

    def cancel_pending_action?
      @mode == :categories
    end

    def cancel_pending_action!
      return false if @mode != :categories

      switch_mode(:dice, speak: true)
      true
    end

    def handle_command(command, payload = {})
      case command.to_s
      when "select_die"
        change_die_selection(payload, select: true)
      when "unselect_die"
        change_die_selection(payload, select: false)
      when "announce_dice"
        speak(dice_status_text)
        true
      when "show_categories"
        return false if @categories.empty?

        switch_mode(:categories, speak: true)
        true
      else
        false
      end
    end

    private

    def activate
      if @mode == :categories
        category = @categories[@control.index.to_i]
        return if category == nil

        emit_action("dice", "score", { "category" => category.value.to_s }, source: @spec.id)
        return
      end

      if @dice.empty? || @dice.any? { |die| die.value == nil }
        emit_roll(@dice.map { |die| die.id.to_s })
      elsif @spec.force_categories == true || @spec.can_roll == false
        switch_mode(:categories, speak: true)
      elsif !@selected_ids.empty?
        emit_roll(@selected_ids)
      elsif @spec.score_grid || !@categories.empty?
        switch_mode(:categories, speak: true)
      end
    end

    def emit_roll(ids)
      emit_action(
        "dice", "roll",
        { "die_ids" => ids.join(",") },
        source: @spec.id
      )
    end

    def change_die_selection(payload, select:)
      return false if @mode != :dice || @dice.any? { |die| die.value == nil }
      return false if @spec.can_roll == false || @spec.force_categories == true

      value = (payload["value"] || payload[:value]).to_i
      matching = @dice.select { |die| die.value.to_i == value }
      die = if select
        matching.find { |candidate| !@selected_ids.include?(candidate.id.to_s) }
      else
        matching.reverse.find { |candidate| @selected_ids.include?(candidate.id.to_s) }
      end
      if die == nil
        message = select ? _("%{value}, no die available to select.") : _("%{value}, no selected die.")
        speak(message % { value: value })
        return true
      end

      if select
        @selected_ids << die.id.to_s
      else
        @selected_ids.delete(die.id.to_s)
      end
      @control.options = labels if @spec.score_grid
      speak(dice_status_text)
      true
    end

    def switch_mode(mode, speak:)
      if mode == :categories && @spec.score_grid
        emit_action("dice", "open_score_grid", {}, source: @spec.id)
        return
      end

      @mode = mode
      @control.options = labels
      @control.header = current_header
      @control.index = 0
      @control.focus(0) if speak
    end

    def labels
      return @categories.map { |category| category.label.to_s } if @mode == :categories

      return ["Zapisz w tabeli"] if @spec.score_grid && @dice.none? { |die| die.value.nil? } && @selected_ids.empty?

      [_('Roll the dice')]
    end

    def current_header
      @mode == :categories ? _("Choose a scoring category") : @spec.header.to_s
    end

    def bounded_index(index)
      count = labels.length
      return 0 if count <= 0

      [[index.to_i, 0].max, count - 1].min
    end

    def dice_signature
      [@spec.roll_number.to_i, *@dice.map { |die| "#{die.id}:#{die.value}" }].join("|")
    end

    def dice_status_text
      return _("The dice have not been rolled.") if @dice.any? { |die| die.value == nil }

      kept, rerolled = @dice.partition { |die| !@selected_ids.include?(die.id.to_s) }
      _("You keep %{kept} and reroll %{rerolled}.") % {
        kept: kept.empty? ? _("no dice") : kept.map(&:value).sort.join(" "),
        rerolled: rerolled.empty? ? _("no dice") : rerolled.map(&:value).sort.join(" ")
      }
    end

    def validate!
      raise ArgumentError, "a roll and score surface requires an id" if @spec.id.to_s.empty?
      ids = @dice.map { |die| die.id.to_s }
      raise ArgumentError, "dice require unique ids" if ids.any?(&:empty?) || ids.uniq.length != ids.length
      category_ids = @categories.map { |category| category.id.to_s }
      if category_ids.any?(&:empty?) || category_ids.uniq.length != category_ids.length
        raise ArgumentError, "scoring categories require unique ids"
      end
    end


  end
end
