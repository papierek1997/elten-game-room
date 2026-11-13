require_relative "../lib/game_content"
require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  EventCommand = Struct.new(:action, :value, keyword_init: true)

  # Untranslated text from a packaged app can retain ASCII-8BIT even when
  # its bytes are UTF-8. Host controls append their own translated labels.
  OptionChoice = Struct.new(:value, :label, :description, keyword_init: true) do
    def initialize(**attributes)
      super(**attributes.merge(
        label: GameRoomContent.utf8(attributes[:label]),
        description: attributes[:description] == nil ? nil : GameRoomContent.utf8(attributes[:description])
      ))
    end
  end
  ShortcutChoice = Struct.new(:value, :label, keyword_init: true)
  OptionDefinition = Struct.new(
    :key,
    :label,
    :kind,
    :default,
    :choices,
    :visible_if,
    :summary_label,
    :summary_unit,
    :omit_zero,
    keyword_init: true
  ) do
    def initialize(**attributes)
      super(**attributes.merge(label: GameRoomContent.utf8(attributes[:label])))
    end
  end

  ActionPlan = Struct.new(:events, keyword_init: true) do
    def self.single(action:, value:)
      new(events: [EventCommand.new(action: action.to_s, value: value.to_s)])
    end
  end

  ActionContext = Struct.new(
    :session_id,
    :table_id,
    :hidden_submissions,
    :random_source,
    :server_random,
    :now,
    :options,
    :table_owner,
    :local_data,
    keyword_init: true
  )

  GameShortcut = Struct.new(
    :key,
    :modifiers,
    :label,
    :kind,
    :message,
    :prompt,
    :action_kind,
    :action_name,
    :value_key,
    :allowed_values,
    :default_value,
    :invalid_message,
    :payload,
    :choices,
    :fields,
    :submit_label,
    keyword_init: true
  ) do
    KINDS = [:announcement, :browse, :grid_preview, :number_input, :choice, :staged_form, :form, :action, :surface].freeze
    NAMED_KEYS = ["space", "enter", "delete", "backspace", "semicolon"].freeze

    def initialize(
      key:,
      modifiers: nil,
      label:,
      kind:,
      message: nil,
      prompt: nil,
      action_kind: nil,
      action_name: nil,
      value_key: nil,
      allowed_values: nil,
      default_value: nil,
      invalid_message: nil,
      payload: nil,
      choices: nil,
      fields: nil,
      submit_label: nil
    )
      normalized_key = key.to_s.downcase
      normalized_modifiers = normalize_shortcut_modifiers(modifiers)
      normalized_kind = kind.to_sym
      if !/\A[a-z0-9]\z/.match?(normalized_key) && !NAMED_KEYS.include?(normalized_key)
        raise ArgumentError, "a game shortcut requires one letter, digit or supported named key"
      end
      raise ArgumentError, "unsupported game shortcut kind" if !KINDS.include?(normalized_kind)
      raise ArgumentError, "a game shortcut requires a label" if label.to_s.empty?
      if normalized_kind == :announcement
        raise ArgumentError, "an announcement shortcut requires a message" if message.to_s.empty?
      elsif normalized_kind == :grid_preview
        raise ArgumentError, "a grid preview requires a grid" unless default_value.is_a?(GameSurfaces::GridSpec)
      elsif normalized_kind == :form
        raise ArgumentError, "a form shortcut requires fields and an action" if fields.to_a.empty? || action_kind.to_s.empty? || action_name.to_s.empty?
        raise ArgumentError, "invalid form field" if fields.any? { |field| !field.is_a?(OptionDefinition) || ![:integer, :choice, :multiple_choice, :boolean].include?(field.kind.to_sym) }
      elsif normalized_kind == :number_input
        raise ArgumentError, "a number shortcut requires a prompt" if prompt.to_s.empty?
        raise ArgumentError, "a number shortcut requires an action" if action_kind.to_s.empty? || action_name.to_s.empty?
        raise ArgumentError, "a number shortcut requires a payload key" if value_key.to_s.empty?
        if allowed_values.is_a?(Range)
          first, last = allowed_values.begin, allowed_values.end
          raise ArgumentError, "invalid numeric range" if !first.is_a?(Integer) || !last.is_a?(Integer) || allowed_values.exclude_end? || first > last
        else
          values = allowed_values.to_a.map(&:to_i).uniq.sort
          raise ArgumentError, "a number shortcut requires allowed values" if values.empty?
          allowed_values = values
        end
      elsif [:browse, :choice, :staged_form].include?(normalized_kind)
        raise ArgumentError, "a choice shortcut requires a prompt" if prompt.to_s.empty?
        if [:choice, :staged_form].include?(normalized_kind)
          raise ArgumentError, "a choice shortcut requires an action" if action_kind.to_s.empty? || action_name.to_s.empty?
          raise ArgumentError, "a choice shortcut requires a payload key" if value_key.to_s.empty?
        end
        choices = choices.to_a.map do |choice|
          if choice.respond_to?(:value) && choice.respond_to?(:label)
            ShortcutChoice.new(value: choice.value, label: choice.label.to_s)
          elsif choice.respond_to?(:key?)
            value = choice.key?(:value) ? choice[:value] : choice["value"]
            label = choice.key?(:label) ? choice[:label] : choice["label"]
            ShortcutChoice.new(value: value, label: label.to_s)
          else
            values = choice.to_a
            ShortcutChoice.new(value: values[0], label: values[1].to_s)
          end
        end
        if choices.empty? || choices.any? { |choice| choice.label.empty? }
          raise ArgumentError, "a choice shortcut requires labelled choices"
        end
      else
        raise ArgumentError, "an action shortcut requires an action" if action_kind.to_s.empty? || action_name.to_s.empty?
        raise ArgumentError, "an action shortcut payload must be a hash" if payload != nil && !payload.respond_to?(:to_h)
      end

      super(
        key: normalized_key,
        modifiers: normalized_modifiers,
        label: label.to_s,
        kind: normalized_kind,
        message: message == nil ? nil : message.to_s,
        prompt: prompt == nil ? nil : prompt.to_s,
        action_kind: action_kind == nil ? nil : action_kind.to_s,
        action_name: action_name == nil ? nil : action_name.to_s,
        value_key: value_key == nil ? nil : value_key.to_s,
        allowed_values: allowed_values,
        default_value: default_value,
        invalid_message: invalid_message == nil ? nil : invalid_message.to_s,
        payload: payload == nil ? {} : payload.to_h,
        choices: choices,
        fields: fields,
        submit_label: submit_label && GameRoomContent.utf8(submit_label)
      )
    end

    def allowed_value?(value)
      return false if kind != :number_input

      allowed_values.include?(Integer(value.to_s, 10))
    rescue ArgumentError
      false
    end

    private

    def normalize_shortcut_modifiers(modifiers)
      normalized = modifiers.to_a.map(&:to_sym).uniq.sort
      if normalized.any? { |modifier| ![:alt, :control, :shift].include?(modifier) }
        raise ArgumentError, "a game shortcut contains an unsupported modifier"
      end
      normalized
    end
  end

  HistoryEntry = Struct.new(
    :key,
    :text,
    :event_id,
    :actor,
    :kind,
    :field,
    :value,
    keyword_init: true
  )

  Replay = Struct.new(
    :board,
    :players,
    :current_player,
    :winner,
    :draw,
    :accepted_events,
    :history,
    :state,
    keyword_init: true
  ) do
    def finished?
      winner != nil || draw == true
    end
  end

end
