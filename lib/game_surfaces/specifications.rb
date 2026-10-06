# Pure presentation values: safe to load without native ELTEN controls.
module GameSurfaces
  MovementCommandResult = Struct.new(:action, :message, keyword_init: true)

  Action = Struct.new(:kind, :name, :payload, :source, keyword_init: true) do
    def self.from_h(value, source: nil)
      raise ArgumentError, "surface action must be a hash" if !value.respond_to?(:to_h)

      normalized = {}
      value.to_h.each { |key, item| normalized[key.to_s] = item }
      kind = normalized.delete("kind")
      name = normalized.delete("action") || normalized.delete("name")
      inherited_source = normalized.delete("source")
      raise ArgumentError, "surface action requires a kind and action" if kind.to_s.empty? || name.to_s.empty?

      new(kind: kind, name: name, payload: normalized, source: source || inherited_source)
    end

    def initialize(kind:, name:, payload: {}, source: nil)
      raise ArgumentError, "surface action payload must be a hash" if !payload.respond_to?(:to_h)

      normalized = {}
      payload.to_h.each { |key, value| normalized[key.to_s] = value }
      super(
        kind: kind.to_s,
        name: name.to_s,
        payload: normalized,
        source: source == nil ? nil : source.to_s
      )
    end

    def [](key)
      normalized = key.to_s
      return kind if normalized == "kind"
      return name if normalized == "action" || normalized == "name"
      return source if normalized == "source"

      payload[normalized]
    end

    def key?(key)
      normalized = key.to_s
      ["kind", "action", "name", "source"].include?(normalized) || payload.key?(normalized)
    end

    def to_h
      payload.merge(
        "kind" => kind,
        "action" => name,
        "source" => source
      ).reject { |_key, value| value == nil }
    end

    def with_source(value)
      self.class.new(kind: kind, name: name, payload: payload, source: value)
    end
  end

  GridSpec = Struct.new(
    :width,
    :height,
    :header,
    :cells,
    :row_origin,
    keyword_init: true
  )

  FleetGridSpec = Struct.new(
    :width,
    :height,
    :header,
    :cells,
    :row_origin,
    :epoch,
    :setup_header,
    :random_label,
    :manual_label,
    :place,
    :complete,
    :action_name,
    :status,
    :bow_check,
    :confirm_message,
    :placed_message,
    :ship_label,
    :bow_label,
    :bow_message,
    :cancel_message,
    :removed_message,
    :empty_message,
    keyword_init: true
  )

  CardChoice = Struct.new(:id, :label, :value, keyword_init: true)

  Card = Struct.new(:id, :label, :value, :choices, :shift_choice, :choice_header, :sort_keys, :confirmation, keyword_init: true)

  CardZoneSpec = Struct.new(:id, :header, :cards, :empty_label, :hand_order, :hand_epoch, keyword_init: true)

  CardTableSpec = Struct.new(:zones, keyword_init: true)

  AnswerField = Struct.new(
    :id,
    :label,
    :value,
    :required,
    :max_length,
    :multiline,
    keyword_init: true
  )

  AnswerSheetSpec = Struct.new(
    :id,
    :title,
    :fields,
    :submit_label,
    :read_only,
    keyword_init: true
  )

  AudioBallSpec = Struct.new(:game_id, :header, :players, :viewer, :scores, :sets, :set_number, :finished, keyword_init: true)

  Command = Struct.new(:id, :label, :enabled, :payload, keyword_init: true)

  CommandPanelSpec = Struct.new(:commands, keyword_init: true)

  SurfacePart = Struct.new(:id, :surface, keyword_init: true)

  CompositeSpec = Struct.new(:parts, keyword_init: true)

  Die = Struct.new(:id, :value, :sides, :held, :label, :enabled, keyword_init: true)

  DiceTraySpec = Struct.new(
    :id,
    :header,
    :dice,
    :commands,
    :empty_label,
    keyword_init: true
  )

  MeldHandSpec = Struct.new(:zones, :turn, :editable, :can_discard, :minimum,
    :validator, :table, :discard_choices, :discard_error, :action_error, keyword_init: true)

  PacketCardSpec = Struct.new(
    :id, :header, :cards, :action_name, :allow_packet, :empty_label, :hand_order, :hand_epoch, :packet_tip, :activation_tip,
    keyword_init: true
  )

  PawnTrackItem = Struct.new(:id, :label, :action, keyword_init: true)

  PawnTrackSpec = Struct.new(:id, :header, :items, :empty_label, :activation_action, :menus, :player_labels, keyword_init: true)

  Piece = Struct.new(:id, :label, :owner, :kind, :value, keyword_init: true)

  PieceBoardSpec = Struct.new(
    :id,
    :width,
    :height,
    :header,
    :pieces,
    :row_origin,
    :selectable,
    :targets,
    :empty_label,
    :cell_labels,
    :activation_action,
    :navigable,
    :navigable_by_coordinate_label_set,
    :silent_positions_by_coordinate_label_set,
    :silent_sound,
    :coordinate_label_sets,
    :coordinate_label_names,
    :default_coordinate_label_set,
    :default_orientation,
    :orientation_labels,
    :square_details,
    :origin_error,
    :destination_error,
    keyword_init: true
  )

  PongSpec = Struct.new(:game_id, :header, :players, :viewer, :scores, :finished, :score_labels, keyword_init: true)

  QuestionOption = Struct.new(:id, :label, :value, keyword_init: true)

  QuestionSpec = Struct.new(
    :id,
    :prompt,
    :mode,
    :options,
    :value,
    :submit_label,
    :show_submit_button,
    :required,
    :read_only,
    :max_length,
    :submit_on_select,
    :prompt_in_choices,
    :clear_on_submit,
    :extra_commands,
    keyword_init: true
  )

  ReviewItem = Struct.new(
    :id,
    :author,
    :category,
    :answer,
    :status,
    :decision,
    :decision_ids,
    keyword_init: true
  )

  ReviewDecision = Struct.new(:id, :label, keyword_init: true)

  ReviewSpec = Struct.new(
    :id,
    :header,
    :items,
    :decisions,
    :empty_label,
    :submit_label,
    :read_only,
    keyword_init: true
  )

  ScoreChoice = Struct.new(:id, :label, :value, keyword_init: true)

  RollAndScoreSpec = Struct.new(
    :id, :header, :dice, :categories, :can_roll, :force_categories,
    :empty_label, :roll_number, keyword_init: true
  )

  TabooSpec = Struct.new(:token, :phase, :lines, :status, :action, :master, :review, :results, :opponent, keyword_init: true)

  Tile = Struct.new(:id, :label, :value, :choices, :choice_header, keyword_init: true)

  TileChoice = Struct.new(:id, :label, :value, keyword_init: true)

  TileZoneSpec = Struct.new(:id, :header, :cards, :empty_label, :hand_order, :hand_epoch, keyword_init: true)

  TileHandSpec = Struct.new(:zones, :table_header, :table, :table_epoch, :default_target, :selection_error, keyword_init: true)

  WordBoardSpec = Struct.new(:board, :rack, :tiles, :alphabet, :epoch, :editable, :exchange,
    :deadline, :clock_offset, :frozen_at, :clock_epoch_offset, :preview, :error_message, keyword_init: true)
end
