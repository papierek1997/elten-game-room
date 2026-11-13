require_relative "yahtzee"
require_relative "kosciane_support/five_dice_match"

module GameRoomGames
  using GameRoomLocalization::Translations

  class Kosciane < Yahtzee
    GameRoomServerRandom.register("kosciane", ["roll"])
    LABEL_KEYS = {triple: "three_kind", four: "four_kind", poker: "yahtzee"}.freeze

    def id; "kosciane"; end
    def name; "Ko\u015bciany Genera\u0142"; end
    def short_description; GameRoomLocalization.primary_language == "pl" ? "Uk\u0142adaj kombinacje z pi\u0119ciu ko\u015bci i zdobywaj premie za pe\u0142ne wiersze i kolumny." : _("Fill your score sheet by rolling five dice."); end
    def supports_bots?; true; end
    def tournament_capabilities(options: {}); super.merge(player_counts: [].freeze).freeze; end
    def shortcut_features; []; end

    def rule_sections; generated_rule_sections; end

    def option_definitions
      [
        OptionDefinition.new(key: "columns", label: _("Score columns"), kind: :integer, default: 3),
        OptionDefinition.new(key: "parity", label: _("Even and odd"), kind: :boolean, default: false),
        OptionDefinition.new(key: "fixed", label: _("Fixed scores for combinations"), kind: :boolean, default: false),
        OptionDefinition.new(key: "double_first", label: _("Double the first roll score"), kind: :boolean, default: false),
        OptionDefinition.new(key: "strict_school", label: _("School crosses prevent future bonuses"), kind: :boolean, default: false)
      ]
    end

    def options_error(options, player_count: nil)
      columns = normalize_options(options)["columns"]
      _("Choose from 1 to 6 score columns.") unless columns.is_a?(Integer) && columns.between?(1, 6)
    end

    def options_summary(options)
      _("%{columns} score columns") % {columns: normalize_options(options)["columns"]}
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      match = FiveDiceMatch.new(players, **options.slice(*%w[columns parity fixed double_first strict_school]).transform_keys(&:to_sym))
      state = {players: players, match_model: match, options: options}
      history, accepted, seen = [starting_history(players)], [], {}
      events.each do |event|
        player = match.current_player
        break unless player
        key = repository.event_id(event)
        next if seen[key] || !same_user?(repository.actor_of(event, session), player)
        if event["action"] == "roll"
          roll_state = {turn_rolls: match.rolls, dice: match.dice}
          next unless apply_roll(roll_state, event, player, repository, history)
          match.roll(player, (0...5).to_a, roll_state[:dice])
        elsif event["action"] == "score"
          category, cross = decode_choice(match, event["value"])
          next unless category && match.record(player, category, cross: cross)
          history << HistoryEntry.new(key: "score:#{key}", event_id: key, actor: player, kind: :score,
            text: "#{participant_name(player)}: #{category_label(category)}, #{cell_label(match.sheet(player)[category].last)}.")
        else
          next
        end
        seen[key] = true
        accepted << event
      end
      winners = match.winners
      state.merge!(current_player: match.current_player, turn_rolls: match.rolls, dice: match.dice)
      Replay.new(players: players, current_player: match.current_player, winner: winners&.one? ? winners.first : nil,
        draw: winners && winners.length > 1, accepted_events: accepted, history: history, state: state)
    end

    def bot_observation(replay, actor)
      match = replay.state[:match_model]
      {"dice" => match.dice, "rolls" => match.rolls, "own_sheet" => match.sheet(actor)}
    end

    def bot_action_score(replay, actor, action, context: nil)
      match = replay.state[:match_model]
      if action["action"] == "score"
        category, cross = decode_choice(match, action["category"])
        return category.is_a?(Integer) ? -100.0 : -30.0 if cross
        points, reserve_delta = match.preview(category)
        return points + reserve_delta * 3 + (category == :chance ? -12 : 0)
      end
      return 100.0 if match.rolls.zero?

      indices = parse_die_ids(action["die_ids"])
      kept = match.dice.each_with_index.filter_map { |face, index| face unless indices.include?(index) }
      counts = kept.tally
      open = match.sheet(actor).select { |_category, row| row.size < replay.state[:options]["columns"] }.keys
      targets = open.filter_map do |category|
        if category.is_a?(Integer)
          count = counts.fetch(category, 0)
          next if count.zero?
          need = [3 - match.reserve(actor, category) - count, 0].max
          next if need > indices.size
          category * (count + 1.0) - 6 * need - 2 * (kept.size - count)
        elsif %i[pair triple four poker].include?(category)
          size = {pair: 2, triple: 3, four: 4, poker: 5}.fetch(category)
          counts.map do |face, count|
            need = [size - count, 0].max
            next if need > indices.size
            face * size - 7 * need - 2 * (kept.size - count)
          end.compact.max
        end
      end
      (targets.max || 2.0) + indices.size * 0.05 - (match.rolls == 2 ? 2 : 0)
    end


    def available_scoring_categories(state, actor)
      match = state[:match_model]
      return [] unless match.rolls.positive? && same_user?(actor, match.current_player)
      open_rows = match.sheet(match.current_player)
      match.categories.flat_map do |category|
        next [] if open_rows[category].size >= state[:options]["columns"]
        choices = []
        choices << category.to_s if match.preview(category)
        choices << "cross:#{category}" if match.rolls == 3
        choices
      end
    end

    def surface_spec(replay, viewer)
      match = replay.state[:match_model]
      return super unless same_user?(replay.current_player, viewer) && !replay.finished?
      return score_grid(replay.state, match.current_player, writable: true) if match.rolls == 3
      GameSurfaces::RollAndScoreSpec.new(id: id, header: name, categories: [],
        dice: match.dice.each_with_index.map { |face, index| GameSurfaces::Die.new(id: "d#{index}", value: face, sides: 6, held: true, enabled: true) },
        can_roll: match.rolls < 3, force_categories: match.rolls == 3,
        empty_label: _("Roll the dice first"), roll_number: match.rolls, score_grid: true)
    end

    def surface_action_shortcut(selection, replay, viewer)
      if selection["kind"] == "dice" && selection["action"] == "open_score_grid"
        return custom_game_shortcuts(replay, viewer).find { |shortcut| shortcut.key == "b" }
      end
      super
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      state = replay.state
      owner = player_key(state, viewer)
      if owner
        missing = score_sheet_choices(state, owner, incomplete_only: true)
        shortcuts << if missing.empty?
          announcement_shortcut(key: "f", label: "Sprawdź wolne pola", message: "Tabela jest pełna.")
        else
          browse_shortcut(key: "f", label: "Pokaż wiersze z wolnymi polami",
            prompt: "Wiersze z wolnymi polami", choices: missing)
        end
        writable = !replay.finished? && same_user?(owner, replay.current_player) && state[:turn_rolls].positive?
        shortcuts << GameShortcut.new(key: "b", kind: :grid_preview, label: "Otwórz tabelę wyników",
          default_value: score_grid(state, owner, writable: writable))
      end
      if state[:turn_rolls] == 3
        shortcuts.reject! { |shortcut| shortcut.key == "space" }
        shortcuts << announcement_shortcut(key: "space", label: "Odczytaj kości", message: dice_text(state))
      end
      shortcuts << announcement_shortcut(key: "d", label: "Odczytaj wyrzucone kości", message: dice_text(state))
      entries = replay.players.map do |player|
        match = state[:match_model]
        "#{participant_name(player)}: #{match.total(player) - match.bonuses(player).values.sum}"
      end
      shortcuts << GameShortcut.new(key: "s", modifiers: [:shift], kind: :announcement,
        label: "Odczytaj sumę wpisów bez premii", message: entries.join(". "))
    end

    def score_grid(state, player, writable:)
      match = state[:match_model]
      columns = state[:options]["columns"]
      choices = writable ? available_scoring_categories(state, player) : match.categories
      rows = choices.map do |choice|
        category, cross = writable ? decode_choice(match, choice) : [choice, false]
        entries = match.sheet(player).fetch(category)
        label = category_label(category)
        if writable
          label = cross ? _("Cross out %{category}") % {category: label} : "#{label}, do zapisu #{match.preview(category).first}"
        end
        total = entries.grep(Integer).sum
        reserve = category.is_a?(Integer) ? (_("Reserve: %{count}") % {count: match.reserve(player, category)}) : ""
        [label, *Array.new(columns) { |index| cell_label(entries[index]) }, "Suma #{total}", reserve]
      end
      rows << ["Suma punktów #{match.total(player)}", *Array.new(columns, ""),
        _("Bonuses: %{points}") % {points: match.bonuses(player).values.sum}, ""]
      GameSurfaces::GridSpec.new(width: columns + 3, height: rows.size, header: score_sheet_title(state, player),
        cells: rows, row_origin: :top, hide_coordinates: true, score_categories: writable ? choices : nil)
    end

    def result_text(replay)
      winners = replay.state[:match_model].winners
      return super unless winners && winners.length.between?(2, replay.players.length - 1)
      _("Winners: %{players}") % {players: winners.map { |player| participant_name(player) }.join(", ")}
    end

    def score_sheet_title(_state, player)
      _("Score sheet: %{player}") % {player: participant_name(player)}
    end

    def score_sheet_choices(state, player, incomplete_only: false)
      match = state[:match_model]
      rows = match.sheet(player).filter_map do |category, entries|
        next if incomplete_only && entries.size >= state[:options]["columns"]

        cells = Array.new(state[:options]["columns"]) { |index| cell_label(entries[index]) }
        line = "#{category_label(category)}: #{cells.join(', ')}"
        line += "; " + (_("Reserve: %{count}") % {count: match.reserve(player, category)}) if category.is_a?(Integer)
        line
      end
      unless incomplete_only
        rows << (_("Bonuses: %{points}") % {points: match.bonuses(player).values.sum})
        rows << (_("Total: %{points}") % {points: match.total(player)})
      end
      rows.map { |line| ShortcutChoice.new(label: line, value: nil) }
    end

    def total_score(state, player)
      state[:match_model].total(player)
    end

    private

    def decode_choice(match, value)
      raw = value.to_s
      [match.categories.find { |category| category.to_s == raw.delete_prefix("cross:") }, raw.start_with?("cross:")]
    end

    def category_label(category)
      return _("Even") if category == :even
      return _("Odd") if category == :odd
      return "Genera\u0142" if category == :poker && GameRoomLocalization.primary_language == "pl"
      return _("Five of a kind") if category == :poker
      key = category.is_a?(Integer) ? STANDARD_CATEGORIES.fetch(category - 1) : LABEL_KEYS.fetch(category, category.to_s)
      CATEGORY_LABELS.fetch(key)
    end

    def cell_label(value)
      return _("not filled") if value.nil?
      value == :cross ? _("crossed out") : value.to_s
    end
  end
end

require_relative 'generated/rulebooks/kosciane'
