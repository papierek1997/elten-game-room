require_relative 'game_room_localization'
require_relative 'game_option_values'

# Owns only the option form. Storage, table creation and its parent window
# stay with the program; callbacks make those boundaries explicit.
class GameRoomOptionEditor
  using GameRoomLocalization::Translations

  # Only lists with described choices opt in. Let the native list announce
  # its name and checked state first, then append to that same utterance.
  # Labels stay unchanged for type-ahead, Braille and saved option summaries.
  module ChoiceDescriptions
    attr_writer :choice_descriptions

    def speak_item_option(id = index, ...)
      @announced_choice_description = @choice_descriptions.to_a[id] if id && id >= 0
      super
    ensure
      @announced_choice_description = nil
    end

    def lspeak(text)
      description = @announced_choice_description.to_s
      text = speech_value_append(text, "\n" + description) unless description.empty?
      super(text)
    end
  end

  def initialize(program:, defaults:, remember:, alert:)
    @program, @defaults, @remember, @alert = program, defaults, remember, alert
  end

  # Creation returns table privacy separately from game rules; ordinary
  # editing (Ctrl+X) keeps its existing options-only result and controls.
  def edit(game, initial_options: nil, submit_label: nil, creating_table: false, initial_private_table: false, require_confirmation: false)
    return creating_table ? nil : {} if game == nil

    selected = if initial_options == nil
      @defaults.call(game, game.effective_option_definitions)
    else
      game.normalize_options(initial_options)
    end
    # Keep canonical non-control values (for example a category-pool version
    # or team seats). Content-pack identity is derived again from the visible
    # language/set controls, as before, so changing them cannot keep a stale pack.
    # Remembered hidden controls may belong to a custom profile. Normalize the
    # non-control metadata, not those raw control values: a default preset would
    # otherwise overwrite them before the user switches back to Custom.
    base_options = game.normalize_options(selected).reject do |key, _value|
      [GameRoomContent::PACK_OPTION_KEY, GameRoomContent::PACK_VERSION_KEY,
        GameRoomContent::PACK_CHECKSUM_KEY].include?(key)
    end
    definitions = game.option_editor_definitions(selected).to_a
    return selected if definitions.empty? && !creating_table && !require_confirmation
    built_language = selected[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
    private_table = initial_private_table == true

    loop do
      controls = [Static.new(_("Choose game options using Tab and the arrow keys. In lists allowing multiple selections, use Space to select or clear an item."))]
      privacy_control = nil
      if creating_table
        privacy_control = CheckBox.new(GameRoomContent.utf8(_("Private table")), checked: private_table)
        controls << privacy_control
      end
      option_controls, bindings = build_option_controls(definitions, selected)
      controls.concat(option_controls)

      extension = game.build_option_editor_extension(@program, selected)
      controls.concat(extension.fields) if extension
      action = nil
      save_button = Button.new(submit_label || _("Create table"))
      cancel_button = Button.new(_("Cancel"))
      form = GameRoomUI::Form.new(controls + [save_button, cancel_button], program: @program, index: 0, quiet: true)
      form.accept_button = save_button
      form.cancel_button = cancel_button
      previous_options = game.normalize_options(game_option_values(bindings, base_options))
      refresh_visibility = lambda do
        previous_options = refresh_option_controls(game, bindings, previous_options, form, base_options)
        extension&.refresh(previous_options, form)
      end
      bindings.each do |definition, control|
        event = definition.kind.to_s == "boolean" ? :change : :move
        control.on(event) { refresh_visibility.call } if ["boolean", "choice"].include?(definition.kind.to_s)
      end
      refresh_visibility.call
      save_button.on(:press) do
        action = :save
        form.resume
      end
      cancel_button.on(:press) do
        action = :cancel
        form.resume
      end
      language_binding = bindings.find do |definition, _control|
        definition.key.to_s == GameRoomContent::LANGUAGE_OPTION_KEY
      end
      if language_binding != nil
        language_binding[1].on(:move) do
          # Replace only the dependent choices. Recreating the form here
          # steals focus (and speech) from the language being browsed.
          options = game.normalize_options(game_option_values(bindings, base_options))
          definitions = game.option_editor_definitions(options).to_a
          set_binding = bindings.find { |definition, _control| definition.key.to_s == GameRoomContent::SET_OPTION_KEY }
          set_definition = definitions.find { |definition| definition.key.to_s == GameRoomContent::SET_OPTION_KEY }
          if set_binding && set_definition
            control = set_binding[1]
            set_binding[0] = set_definition
            control.options = set_definition.choices.map { |choice| choice.label.to_s }
            describe_choices(control, set_definition.choices)
            control.index = set_definition.choices.index { |choice| choice.value.to_s == options[GameRoomContent::SET_OPTION_KEY].to_s }.to_i
          end
          built_language = options[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
          refresh_visibility.call
        end
      end
      loop do
        action = nil
        form.wait
        return nil if action != :save

        private_table = privacy_control.checked == true if creating_table
        raw = game_option_values(bindings, base_options)
        options = game.normalize_options(raw)
        begin
          options = extension.prepare(options) if extension
        rescue ArgumentError, IOError, SystemCallError => error
          @alert.call(GameRoomContent.utf8(error.message))
          next
        end
        chosen_language = options[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
        if chosen_language != built_language
          selected = options
          built_language = chosen_language
          definitions = game.option_editor_definitions(selected).to_a
          break
        end
        error = game.validation_error(options)
        if error == nil
          @remember.call(game, definitions, options) if initial_options == nil
          return creating_table ? { game_options: options, private_table: private_table } : options
        end

        # Keep the actual controls, including unfinished/invalid input, focus,
        # dependent choices and table privacy. Validation is not cancellation.
        @alert.call(error)
      end
    end
  end

  private

  def build_option_controls(definitions, selected)
    controls = []
    bindings = []
    defaults = selected
    definitions.each do |definition|
      case definition.kind.to_s
      when "boolean"
        control = CheckBox.new(
          definition.label.to_s,
          checked: GameRoomOptionValues.read(definition, defaults) == true
        )
        controls << control
        bindings << [definition, control]
      when "choice"
        choices = definition.choices.to_a
        default_index = choices.index do |choice|
          choice.value.to_s == GameRoomOptionValues.read(definition, defaults).to_s
        end.to_i
        control = choice_control(definition, index: default_index)
        controls << control
        bindings << [definition, control]
      when "multiple_choice", "multiple_values"
        if definition.kind.to_s == "multiple_values"
          definition = multiple_values_definition(definition, GameRoomOptionValues.read(definition, defaults))
        end
        choices = definition.choices.to_a
        control = choice_control(definition, multiple: true)
        selected_indices = if definition.kind.to_s == "multiple_values"
          selected_values = GameRoomOptionValues.read(definition, defaults)
          choices.each_index.select { |index| selected_values.is_a?(Array) && selected_values.include?(choices[index].value) }
        else
          mask = GameRoomOptionValues.read(definition, defaults).to_i
          choices.each_index.select { |index| (mask & (1 << index)) != 0 }
        end
        control.select_multiselection_indices(selected_indices)
        controls << control
        bindings << [definition, control]
      when "integer"
        control = EditBox.new(
          definition.label.to_s,
          type: EditBox::Flags::Numbers,
          text: GameRoomOptionValues.read(definition, defaults).to_i.to_s,
          quiet: true
        )
        control.select_all if !control.text.to_s.empty?
        controls << control
        bindings << [definition, control]
      else
        raise ArgumentError, "Unsupported game option type: #{definition.kind}"
      end
    end

    [controls, bindings]
  end

  def choice_control(definition, index: 0, multiple: false)
    choices = definition.choices.to_a
    control = ListBox.new(choices.map { |choice| choice.label.to_s },
      header: definition.label.to_s, index: index,
      flags: multiple ? ListBox::Flags::MultiSelection : 0, quiet: true)
    describe_choices(control, choices)
    control
  end

  def describe_choices(control, choices)
    descriptions = choices.map(&:description)
    control.extend(ChoiceDescriptions) if descriptions.any? { |text| !text.to_s.empty? } && !control.is_a?(ChoiceDescriptions)
    control.choice_descriptions = descriptions if control.is_a?(ChoiceDescriptions)
  end

  def refresh_option_controls(game, bindings, previous_options, form, base_options)
    raw_values = game_option_values(bindings, base_options)
    values = game.normalize_options(raw_values)
    changes = game.option_editor_changes(previous_options, values)
    changes.each do |key, value|
      binding = bindings.find { |definition, _control| definition.key.to_s == key.to_s }
      binding[1].set_text(value.to_s) if binding && binding[0].kind.to_s == "integer"
    end
    # Only ID-based checklists opt in to changing catalogue choices. Keep
    # their native control and selected IDs; old bit-mask lists are fixed.
    if bindings.any? { |definition, _control| definition.kind.to_s == "multiple_values" }
      current_definitions = game.effective_option_definitions(values)
      bindings.each do |binding|
        definition, control = binding
        next unless definition.kind.to_s == "multiple_values"

        key = definition.key.to_s
        replacement = current_definitions.find { |entry| entry.key.to_s == key } || definition
        selected_values = changes.fetch(key, changes.fetch(key.to_sym, raw_values[key]))
        replacement = multiple_values_definition(replacement, selected_values)
        old_choices = definition.choices.to_a
        choices = replacement.choices.to_a
        selected_indices = choices.each_index.select { |index| selected_values.is_a?(Array) && selected_values.include?(choices[index].value) }
        if choices != old_choices || selected_indices != control.multiselections
          focused_value = old_choices[control.index]&.value
          control.deselect_multiselection_indices(control.multiselections)
          control.options = choices.map { |choice| choice.label.to_s }
          describe_choices(control, choices)
          control.select_multiselection_indices(selected_indices)
          control.index = choices.index { |choice| choice.value == focused_value }.to_i
        end
        binding[0] = replacement
      end
    end
    values = game.normalize_options(game_option_values(bindings, base_options))
    bindings.each do |definition, control|
      if game.option_visible?(definition, values)
        form.show(control)
      else
        form.hide(control)
      end
    end
    values
  end

  def multiple_values_definition(definition, selected)
    return definition unless selected.is_a?(Array)

    choices = definition.choices.to_a
    missing = selected.grep(String).uniq - choices.map(&:value)
    return definition if missing.empty?

    # A removed pack remains visibly selected until explicitly cleared. Do
    # not silently turn an unavailable saved selection into a different pool.
    copy = definition.dup
    copy.choices = choices + missing.map do |value|
      GameRoomGames::OptionChoice.new(value: value, label: _("Unavailable choice: %{id}") % { id: value })
    end
    copy
  end

  def game_option_values(bindings, base_options = {})
    bindings.each_with_object(base_options.dup) do |(definition, control), raw|
      key = definition.key.to_s
      raw[key] = if definition.kind.to_s == "boolean"
        control.checked == true
      elsif definition.kind.to_s == "integer"
        control.text.to_s
      elsif ["multiple_choice", "multiple_values"].include?(definition.kind.to_s)
        choices = definition.choices.to_a
        control.multiselections.filter_map { |index| choices[index]&.value }
      else
        choices = definition.choices.to_a
        selected = choices[control.index.to_i]
        selected == nil ? definition.default : selected.value
      end
    end
  end

end
