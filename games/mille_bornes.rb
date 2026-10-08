require_relative "base"
require_relative "../lib/game_random"
require_relative "../lib/game_bots"

module GameRoomGames
  using GameRoomLocalization::Translations

  class MilleBornes < Base
    DECK_COUNTS = {
      "25" => 10, "50" => 10, "75" => 10, "100" => 12, "200" => 4,
      "stop" => 5, "speed_limit" => 4, "out_of_gas" => 3,
      "flat_tire" => 3, "accident" => 3, "go" => 14,
      "end_limit" => 6, "fuel" => 6, "spare_tire" => 6, "repairs" => 6,
      "right_of_way" => 1, "extra_tank" => 1, "puncture_proof" => 1, "driving_ace" => 1
    }.freeze
    DISTANCES = %w[25 50 75 100 200].freeze
    HAZARDS = %w[stop out_of_gas flat_tire accident speed_limit counterflow].freeze
    REMEDIES = {
      "fuel" => "out_of_gas", "spare_tire" => "flat_tire", "repairs" => "accident",
      "end_limit" => "speed_limit", "end_counterflow" => "counterflow"
    }.freeze
    PROTECTION = {
      "stop" => "right_of_way", "speed_limit" => "right_of_way",
      "out_of_gas" => "extra_tank", "flat_tire" => "puncture_proof",
      "accident" => "driving_ace", "counterflow" => "driving_ace"
    }.freeze
    CARD_ORDER = (DECK_COUNTS.keys + %w[counterflow end_counterflow instant_repair]).freeze
    SAFETIES = %w[right_of_way extra_tank puncture_proof driving_ace].freeze
    TEAM_COUNTS = { 4 => [2], 6 => [2, 3], 8 => [2, 4] }.freeze

    def id
      "mille_bornes"
    end

    def name
      _("1000 miles")
    end

    def short_description
      _("Race with cards, cover mile after mile and slow down your opponents.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      2
    end

    def maximum_players
      8
    end

    def supports_bots?
      true
    end

    def default_bot_move_delay
      1
    end

    def perfect_information?
      false
    end

    def actions_during_bot_turn?
      true
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def option_definitions
      [
        OptionDefinition.new(key: "target_score", label: _("Target score"), kind: :integer, default: 5000),
        OptionDefinition.new(key: "team_count", label: _("Teams"), kind: :choice, default: 0, choices: [
          OptionChoice.new(value: 0, label: _("Every player for themselves")),
          OptionChoice.new(value: 2, label: _("Two teams")),
          OptionChoice.new(value: 3, label: _("Three teams")),
          OptionChoice.new(value: 4, label: _("Four teams"))
        ]),
        OptionDefinition.new(key: "accumulate_hazards", label: _("Accumulate problems"), kind: :boolean, default: false),
        OptionDefinition.new(key: "recycle_discard", label: _("Use discarded cards as a new deck when the current deck runs out"), kind: :boolean, default: false)
      ] + deck_option_definitions
    end

    def normalize_options(values)
      result = super
      source = values.is_a?(Hash) ? values : {}
      normalize_deck_options(source, result)
      roster = source[GameRoomTeams::PLAYERS_KEY] || source[GameRoomTeams::PLAYERS_KEY.to_sym]
      if roster.is_a?(Array) && roster.length <= maximum_players &&
          roster.all? { |player| player.is_a?(String) && !player.empty? && player.length <= 64 }
        result[GameRoomTeams::PLAYERS_KEY] = roster.dup
      end
      result
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      error = deck_options_error(values, player_count: player_count)
      return error if error
      return _("The target score must be between 100 and 100000.") unless values["target_score"].between?(100, 100_000)
      return nil if player_count == nil
      return _("1000 miles requires between 2 and 8 players.") unless player_count.between?(minimum_players, maximum_players)
      count = values["team_count"]
      if count != 0 && !TEAM_COUNTS.fetch(player_count, []).include?(count)
        return _("Choose equal teams: 4 players in 2 teams; 6 in 2 or 3; 8 in 2 or 4.")
      end
      nil
    end

    def team_size(options, player_count:)
      count = normalize_options(options)["team_count"]
      TEAM_COUNTS.fetch(player_count, []).include?(count) ? player_count / count : 0
    end

    def notification_option_keys(options)
      keys = %w[target_score team_count accumulate_hazards recycle_discard counterflow counterflow_cards end_counterflow_cards include_safeties custom_deck include_instant_repairs]
      keys += CARD_ORDER.map { |type| "#{type}_cards" } if normalize_options(options)["custom_deck"]
      keys.uniq
    end

    def rules_options_text(options)
      values = { "include_safeties" => true }.merge(normalize_options(options))
      if values["include_instant_repairs"] && !values["custom_deck"]
        values["instant_repair_cards"] = DEFAULT_DECK_COUNTS.fetch("instant_repair")
      end
      super(values)
    end

    def options_summary(options)
      values = normalize_options(options)
      parts = [_("Target score: %{score}") % { score: values["target_score"] }]
      parts << (values["team_count"] == 0 ? _("Individual play") : _("Teams: %{count}") % { count: values["team_count"] })
      parts << _("Accumulate problems") if values["accumulate_hazards"]
      parts << _("Use discarded cards as a new deck when the current deck runs out") if values["recycle_discard"]
      parts << "#{_("Add safety cards")}: #{_("No")}" if values["include_safeties"] == false
      parts << _("Custom deck") if values["custom_deck"]
      parts << _("Add instant repair cards") if values["include_instant_repairs"]
      if values["counterflow"]
        parts << _("Counterflow: %{attacks} attack cards and %{remedies} remedy cards") % {
          attacks: values["counterflow_cards"], remedies: values["end_counterflow_cards"]
        }
      end
      parts.join("; ")
    end

    private

    def counterflow_requested?(options)
      return false unless options.is_a?(Hash)
      ["counterflow", :counterflow].any? do |key|
        next false unless options.key?(key)
        value = options[key]
        next false if value == nil || value == false || value == 0
        next false if value.is_a?(String) && ["0", "false"].include?(value.downcase)
        true
      end
    end
  end
end

require_relative "mille_bornes/deck_options"
require_relative "mille_bornes/model"
require_relative "mille_bornes/presentation"
require_relative "mille_bornes/bots"
require_relative "generated/rulebooks/mille_bornes"
