module GameRoomGames
  using GameRoomLocalization::Translations

  class MilleBornes
    DEFAULT_DECK_COUNTS = DECK_COUNTS.merge(
      "counterflow" => DECK_COUNTS.fetch("speed_limit"),
      "end_counterflow" => DECK_COUNTS.fetch("end_limit"),
      "instant_repair" => 2
    ).freeze
    CUSTOM_CARD_COUNT_RANGE = (0..100).freeze

    def deck_counts_for(options)
      values = normalize_options(options)
      error = deck_options_error(values)
      raise ArgumentError, error if error

      effective_deck_counts(values)
    end

    def option_editor_changes(_previous, current)
      return {} if current["custom_deck"]

      DEFAULT_DECK_COUNTS.to_h { |type, count| ["#{type}_cards", count] }
    end

    def rules_option_visible?(definition, options)
      return options["counterflow"] == true if %w[counterflow_cards end_counterflow_cards].include?(definition.key)
      return options["include_instant_repairs"] == true if definition.key == "instant_repair_cards"

      super
    end

    private

    def deck_option_definitions
      counts = DEFAULT_DECK_COUNTS.map do |type, count|
        condition = { "custom_deck" => true }
        condition["include_safeties"] = [nil, true] if SAFETIES.include?(type)
        condition["counterflow"] = true if %w[counterflow end_counterflow].include?(type)
        condition["include_instant_repairs"] = true if type == "instant_repair"
        label = GameRoomContent.utf8(_("Card count (0 to 100): %{card}")) % { card: card_label(type) }
        OptionDefinition.new(key: "#{type}_cards", label: label, kind: :integer, default: count, visible_if: condition)
      end
      legacy_counts, custom_counts = counts.partition { |definition| %w[counterflow_cards end_counterflow_cards].include?(definition.key) }
      [OptionDefinition.new(key: "counterflow", label: _("Add counterflow cards"), kind: :boolean, default: false)] + legacy_counts + [
        OptionDefinition.new(key: "include_safeties", label: _("Add safety cards"), kind: :boolean, default: true),
        OptionDefinition.new(key: "custom_deck", label: _("Custom deck"), kind: :boolean, default: false),
        OptionDefinition.new(key: "include_instant_repairs", label: _("Add instant repair cards"), kind: :boolean, default: false)
      ] + custom_counts
    end

    def normalize_deck_options(source, result)
      result.delete("include_safeties") if result["include_safeties"]
      result.delete("include_instant_repairs") unless result["include_instant_repairs"]
      result.delete("counterflow")
      result["counterflow"] = counterflow_requested?(source)
      custom = result["custom_deck"] == true
      explicit_normal = !custom && (source.key?("custom_deck") || source.key?(:custom_deck))
      result.delete("custom_deck") unless custom
      DEFAULT_DECK_COUNTS.each do |type, default|
        key = "#{type}_cards"
        legacy = result["counterflow"] && %w[counterflow end_counterflow].include?(type)
        unless custom || legacy
          result.delete(key)
          next
        end
        raw = if explicit_normal
          default
        elsif source.key?(key)
          source[key]
        elsif source.key?(key.to_sym)
          source[key.to_sym]
        else
          default
        end
        result[key] = normalize_deck_count(raw)
      end
    end

    def normalize_deck_count(value)
      Integer(value.to_s, 10)
    rescue ArgumentError
      -1
    end

    def effective_deck_counts(values)
      DEFAULT_DECK_COUNTS.to_h do |type, default|
        enabled = if SAFETIES.include?(type)
          values["include_safeties"] != false
        elsif %w[counterflow end_counterflow].include?(type)
          values["counterflow"] == true
        elsif type == "instant_repair"
          values["include_instant_repairs"] == true
        else
          true
        end
        count = values.fetch("#{type}_cards", default)
        [type, enabled ? count : 0]
      end
    end

    def deck_options_error(values, player_count: nil)
      unless values["custom_deck"]
        return nil unless values["counterflow"]
        unless values["counterflow_cards"].between?(1, 20)
          return _("Enter the number of counterflow cards (an integer from 1 to 20) to enable counterflow.")
        end
        unless values["end_counterflow_cards"].between?(1, 20)
          return _("Enter the number of end of counterflow cards (an integer from 1 to 20) to enable counterflow.")
        end
        return nil
      end
      CARD_ORDER.each do |type|
        unless CUSTOM_CARD_COUNT_RANGE.cover?(values["#{type}_cards"])
          return GameRoomContent.utf8(_("The number of %{card} cards must be an integer from 0 to 100.")) % { card: card_label(type) }
        end
      end
      counts = effective_deck_counts(values)
      required = 6 * (player_count || minimum_players)
      if counts.values.sum < required
        return _("The deck must contain at least %{count} cards to deal six cards to each player.") % { count: required }
      end
      safety = SAFETIES.any? { |type| counts.fetch(type).positive? }
      mileage = DISTANCES.any? { |type| counts.fetch(type).positive? }
      start = %w[go right_of_way instant_repair].any? { |type| counts.fetch(type).positive? }
      unless safety || (mileage && start)
        return _("The deck must allow players to score points: include a safety card, or mileage cards and a Green light, Right of way or Instant repair card.")
      end
      nil
    end
  end
end
