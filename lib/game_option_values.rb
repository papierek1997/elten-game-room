require_relative 'game_content'
require_relative 'game_teams'
require_relative 'game_room_localization'

# Definitions describe effective settings; normalized storage may omit defaults.
# These readers never expand or mutate stored options, which are also hashed
# into tournament plans and match bindings.
module GameRoomOptionValues
  using GameRoomLocalization::Translations
  module_function

  # Wire/discovery/archive readers do not have a game definition yet. Reject
  # malformed shared collections before permissive game normalizers can turn
  # an unusable team assignment into an unrelated automatic one.
  def normalizable_options?(options)
    return false unless options.is_a?(Hash)

    [GameRoomTeams::OPTION_KEY, GameRoomTeams::OPTION_KEY.to_sym].all? do |key|
      seats = options[key]
      !options.key?(key) || seats == nil ||
        (seats.is_a?(Array) && seats.all? { |value| integer_coercible?(value) })
    end
  end

  # Ordinary historical settings allow to_i coercion, unlike strict published
  # tournament options. Preserve it for supported scalars without calling to_i
  # on a JSON object/boolean or a nonfinite Float.
  def integer_value(value)
    integer_coercible?(value) ? value.to_i : 0
  end

  def integer_coercible?(value)
    value == nil || value.is_a?(Integer) || value.is_a?(String) || (value.is_a?(Float) && value.finite?)
  end
  private_class_method :integer_coercible?

  def read(definition, options)
    key = definition.key.to_s
    return options[key] if options.key?(key)
    return options[key.to_sym] if options.key?(key.to_sym)

    definition.default
  end

  def normalize_mask(choices, value)
    width = choices.length
    mask = if value.is_a?(Array)
      requested = value.map(&:to_s)
      choices.each_with_index.reduce(0) do |selected, (choice, index)|
        requested.include?(choice.value.to_s) ? selected | (1 << index) : selected
      end
    else
      integer_value(value) & ((1 << width) - 1)
    end
    # Tournament documents accept only 63-bit integers. Wide checklists
    # stay compact by storing the same mask as a decimal string.
    width > 63 ? mask.to_s : mask
  end

  # Check declared types before permissive game normalizers can coerce them.
  def valid?(definition, value)
    case definition.kind.to_sym
    when :boolean
      value == true || value == false
    when :integer
      value.is_a?(Integer)
    when :choice
      definition.choices.to_a.any? { |choice| choice.value.eql?(value) }
    when :multiple_choice
      width = definition.choices.to_a.length
      if width > 63
        return false unless value.is_a?(String) && value.bytesize <= ((1 << width) - 1).to_s.length &&
          /\A(?:0|[1-9][0-9]*)\z/.match?(value)
        return (value.to_i >> width) == 0
      end
      value.is_a?(Integer) && value >= 0 && (value >> width) == 0
    when :multiple_values
      values = definition.choices.to_a.map(&:value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) && values.include?(item) }
    else
      raise ArgumentError, "Unsupported game option type: #{definition.kind}"
    end
  end

  def selected_choices(definition, value)
    definition.choices.to_a.each_with_index.filter_map do |choice, index|
      selected = if definition.kind.to_sym == :multiple_values
        value.is_a?(Array) && value.include?(choice.value)
      else
        (integer_value(value) & (1 << index)) != 0
      end
      choice if selected
    end
  end

  def format(definition, value)
    result = case definition.kind.to_sym
    when :boolean
      value == true ? _("Yes") : _("No")
    when :choice
      choice = definition.choices.to_a.find { |item| item.value.eql?(value) }
      choice ? choice.label : value
    when :multiple_choice, :multiple_values
      selected = selected_choices(definition, value).map { |choice| text(choice.label) }
      selected.empty? ? _("None") : selected.join(', ')
    when :integer
      definition.summary_unit == :seconds ? (text(n_("%{seconds} second", "%{seconds} seconds", value)) % {seconds: value}) : value
    else
      raise ArgumentError, "Unsupported game option type: #{definition.kind}"
    end
    text(result)
  end

  # Full settings documents include disabled options and zero values, unlike
  # the shorter rulebook/table announcement. Visibility still belongs to games.
  def lines(game, options)
    game.effective_option_definitions(options).filter_map do |definition|
      next unless game.option_visible?(definition, options, normalize: false)

      text(definition.summary_label || definition.label) + ': ' + format(definition, read(definition, options))
    end
  end

  def text(value)
    GameRoomContent.utf8(value)
  end
  private_class_method :text
end
