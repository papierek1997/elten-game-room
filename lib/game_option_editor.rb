require_relative 'game_room_localization'

# Owns only the option form. Storage, table creation and its parent window
# stay with the program; callbacks make those boundaries explicit.
class GameRoomOptionEditor
  using GameRoomLocalization::Translations

  def initialize(program:, defaults:, remember:, alert:)
    @program, @defaults, @remember, @alert = program, defaults, remember, alert
  end

  # Creation returns table privacy separately from game rules; ordinary
  # editing (Ctrl+X) keeps its existing options-only result and controls.
  def edit(game, initial_options: nil, submit_label: nil, creating_table: false, initial_private_table: false)
    return creating_table ? nil : {} if game == nil

    selected = initial_options == nil ? {} : game.normalize_options(initial_options)
    definitions = game.effective_option_definitions(selected).to_a
    return game.default_options if definitions.empty? && !creating_table
    built_language = selected.fetch(GameRoomContent::LANGUAGE_OPTION_KEY, game.default_options[GameRoomContent::LANGUAGE_OPTION_KEY]).to_s
    private_table = initial_private_table == true

    loop do
      controls = [Static.new(_("Choose game options using Tab and the arrow keys. In lists allowing multiple selections, use Space to select or clear an item."))]
      privacy_control = nil
      if creating_table
        privacy_control = CheckBox.new(GameRoomContent.utf8(_("Private table")), checked: private_table)
        controls << privacy_control
      end
      bindings = []
      defaults = @defaults.call(game, definitions).merge(selected)
      definitions.each do |definition|
        key = definition.key.to_s
        case definition.kind.to_s
        when "boolean"
          control = CheckBox.new(
            definition.label.to_s,
            checked: defaults.fetch(key, definition.default) == true
          )
          controls << control
          bindings << [definition, control]
        when "choice"
          choices = definition.choices.to_a
          default_index = choices.index do |choice|
            choice.value.to_s == defaults[key].to_s
          end.to_i
          control = ListBox.new(
            choices.map { |choice| choice.label.to_s },
            header: definition.label.to_s,
            index: default_index,
            quiet: true
          )
          controls << control
          bindings << [definition, control]
        when "multiple_choice"
          choices = definition.choices.to_a
          control = ListBox.new(
            choices.map { |choice| choice.label.to_s },
            header: definition.label.to_s,
            index: 0,
            flags: ListBox::Flags::MultiSelection,
            quiet: true
          )
          mask = defaults[key].to_i
          control.select_multiselection_indices(
            choices.each_index.select { |index| (mask & (1 << index)) != 0 }
          )
          controls << control
          bindings << [definition, control]
        when "integer"
          control = EditBox.new(
            definition.label.to_s,
            type: EditBox::Flags::Numbers,
            text: defaults[key].to_i.to_s,
            quiet: true
          )
          control.select_all if !control.text.to_s.empty?
          controls << control
          bindings << [definition, control]
        else
          raise ArgumentError, "Unsupported game option type: #{definition.kind}"
        end
      end

      action = nil
      save_button = Button.new(submit_label || _("Create table"))
      cancel_button = Button.new(_("Cancel"))
      form = GameRoomUI::Form.new(controls + [save_button, cancel_button], program: @program, index: 0, quiet: true)
      form.accept_button = save_button
      form.cancel_button = cancel_button
      previous_options = game.normalize_options(game_option_values(bindings))
      refresh_visibility = lambda do
        values = game.normalize_options(game_option_values(bindings))
        game.option_editor_changes(previous_options, values).each do |key, value|
          binding = bindings.find { |definition, _control| definition.key.to_s == key.to_s }
          binding[1].set_text(value.to_s) if binding && binding[0].kind.to_s == "integer"
        end
        values = game.normalize_options(game_option_values(bindings))
        previous_options = values
        bindings.each do |definition, control|
          if game.option_visible?(definition, values)
            form.show(control)
          else
            form.hide(control)
          end
        end
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
          options = game.normalize_options(game_option_values(bindings))
          definitions = game.effective_option_definitions(options).to_a
          set_binding = bindings.find { |definition, _control| definition.key.to_s == GameRoomContent::SET_OPTION_KEY }
          set_definition = definitions.find { |definition| definition.key.to_s == GameRoomContent::SET_OPTION_KEY }
          if set_binding && set_definition
            control = set_binding[1]
            set_binding[0] = set_definition
            control.options = set_definition.choices.map { |choice| choice.label.to_s }
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
        raw = game_option_values(bindings)
        options = game.normalize_options(raw)
        chosen_language = options[GameRoomContent::LANGUAGE_OPTION_KEY].to_s
        if chosen_language != built_language
          selected = options
          built_language = chosen_language
          definitions = game.effective_option_definitions(selected).to_a
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

  def game_option_values(bindings)
    bindings.each_with_object({}) do |(definition, control), raw|
      key = definition.key.to_s
      raw[key] = if definition.kind.to_s == "boolean"
        control.checked == true
      elsif definition.kind.to_s == "integer"
        control.text.to_s
      elsif definition.kind.to_s == "multiple_choice"
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
