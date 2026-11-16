require_relative "game_room_localization"

module GameRoomShortcuts
  using GameRoomLocalization::Translations
  Definition = Struct.new(:id, :key, :label, :modifiers, keyword_init: true)

  DEFINITIONS = {
    turn: ["t", _("read whose turn it is")],
    scores: ["s", _("read the scores")],
    material: ["s", _("read the remaining pieces of each player")],
    hand: ["h", _("read your hand")],
    table_cards: ["c", _("read the cards on the table")],
    table_cards_list: ["c", _("browse the cards on the table"), [:control]],
    led_suit: ["f", _("read the led suit")],
    bidding: ["b", _("read the bids")],
    draw_card: ["space", _("draw a card")],
    current_total: ["c", _("read the current total")],
    last_roll: ["d", _("read the last roll")],
    round_summary: ["v", _("read the round information")],
    round_information: ["i", _("read the round information")],
    remaining_time: ["t", _("read the remaining time"), [:control]],
    statistics: ["s", _("read the remaining statistics"), [:shift]]
  }.freeze

  def self.build(game, feature_ids, replay, viewer)
    ids = feature_ids.to_a.map(&:to_sym)
    if ids.uniq.length != ids.length
      raise ArgumentError, "shortcut features must be unique"
    end

    shortcuts = ids.map do |feature_id|
      definition = definition_for(feature_id)
      data = game.shortcut_feature_data(feature_id, replay, viewer)
      data == nil ? nil : build_shortcut(definition, data)
    end.compact
    keys = shortcuts.map { |shortcut| [shortcut.key, shortcut.modifiers.to_a] }
    if keys.uniq.length != keys.length
      raise ArgumentError, "shortcut features must use unique keys"
    end

    shortcuts
  end

  def self.definition_for(feature_id)
    values = DEFINITIONS[feature_id.to_sym]
    raise ArgumentError, "unknown shortcut feature: #{feature_id}" if values == nil

    Definition.new(
      id: feature_id.to_sym,
      key: values[0],
      label: values[1],
      modifiers: values[2].to_a
    )
  end

  def self.build_shortcut(definition, data)
    if !data.respond_to?(:key?)
      raise ArgumentError, "shortcut feature data must be a hash"
    end

    kind = value(data, :kind, :announcement).to_sym
    label = value(data, :label, definition.label).to_s
    common = {
      key: value(data, :key, definition.key),
      modifiers: value(data, :modifiers, definition.modifiers),
      label: label,
      kind: kind
    }
    case kind
    when :announcement
      hand_id = value(data, :hand_id, definition.id == :hand ? 'hand' : nil)
      GameRoomGames::GameShortcut.new(
        **common,
        message: value(data, :message),
        payload: hand_id.to_s.empty? ? {} : {'hand_id'=>hand_id.to_s}
      )
    when :browse
      GameRoomGames::GameShortcut.new(
        **common,
        prompt: value(data, :prompt),
        choices: value(data, :choices),
        default_value: value(data, :default_value)
      )
    when :number_input
      GameRoomGames::GameShortcut.new(
        **common,
        prompt: value(data, :prompt),
        action_kind: value(data, :action_kind),
        action_name: value(data, :action_name),
        value_key: value(data, :value_key),
        allowed_values: value(data, :allowed_values),
        default_value: value(data, :default_value),
        invalid_message: value(data, :invalid_message)
      )
    when :choice
      GameRoomGames::GameShortcut.new(
        **common,
        prompt: value(data, :prompt),
        action_kind: value(data, :action_kind),
        action_name: value(data, :action_name),
        value_key: value(data, :value_key),
        choices: value(data, :choices)
      )
    when :action
      GameRoomGames::GameShortcut.new(
        **common,
        action_kind: value(data, :action_kind),
        action_name: value(data, :action_name),
        payload: value(data, :payload, {})
      )
    else
      raise ArgumentError, "unsupported shortcut feature kind: #{kind}"
    end
  end

  def self.value(data, key, default = nil)
    return data[key] if data.key?(key)
    string_key = key.to_s
    return data[string_key] if data.key?(string_key)

    default
  end

  private_class_method :build_shortcut, :value
end
