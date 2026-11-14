require_relative "yahtzee"
require_relative "kosciane_support/five_dice_match"
require_relative "score_sheet_results"

module GameRoomGames
  using GameRoomLocalization::Translations

  class Kosciane < Yahtzee
    include ScoreSheetResults
    GameRoomServerRandom.register("kosciane", ["roll"])
    LABEL_KEYS = {triple: "three_kind", four: "four_kind", poker: "yahtzee"}.freeze

    def id; "kosciane"; end
    def name; _("Dice General"); end
    def short_description; _("Roll five dice and fill rows and columns to earn bonuses."); end
    def supports_bots?; true; end
    def event_sound_cues(event:, **arguments)
      event['action'] == 'score' ? 'cht-bank' : super
    end
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
      columns = normalize_options(options)["columns"]
      n_("%{count} score column", "%{count} score columns", columns) % {count: columns}
    end

    def notification_option_keys(_options); ['columns']; end
    def notification_variant(options)
      columns = options['columns']
      return '' unless columns.is_a?(Integer) && columns.between?(1,6)
      options_summary(options)
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
          before_bonuses = match.bonuses(player)
          next unless category && match.record(player, category, cross: cross)
          history.concat(recorded_score_history(match, player, category, cross, key, before_bonuses))
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
        return cross_value(match, actor, category) if cross
        return category_value(match, category, match.dice, match.rolls)
      end
      return 100.0 if match.rolls.zero?

      indices = parse_die_ids(action["die_ids"])
      kept = match.dice.each_with_index.filter_map { |face, index| face unless indices.include?(index) }
      key = match.planning_key
      if key != @score_plan_key
        @score_plan_key = key
        model = Marshal.load(Marshal.dump(match))
        open = model.sheet(actor).select { |_category, row| row.size < replay.state[:options]["columns"] }.keys
        @score_planner = GameRoomFiveDicePlanner.new do |dice, rolls|
          open.filter_map do |category|
            category_value(model, category, dice, rolls) || (cross_value(model, actor, category) if rolls == 3)
          end.max
        end
      end
      @score_planner.roll_value(kept.sort, 3 - match.rolls) - 0.0001
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
          announcement_shortcut(key: "f", label: _("View unfilled categories"), message: _("The score sheet is full."))
        else
          browse_shortcut(key: "f", label: _("View unfilled categories"),
            prompt: _("Unfilled categories"), choices: missing)
        end
        writable = !replay.finished? && same_user?(owner, replay.current_player) && state[:turn_rolls].positive?
        shortcuts << GameShortcut.new(key: "b", kind: :grid_preview, label: _("Open the score sheet"),
          default_value: score_grid(state, owner, writable: writable))
      end
      if state[:turn_rolls] == 3
        shortcuts.reject! { |shortcut| shortcut.key == "space" }
        shortcuts << announcement_shortcut(key: "space", label: _("read the dice"), message: dice_text(state))
      end
      shortcuts << announcement_shortcut(key: "d", label: _("read the dice"), message: dice_text(state))
      entries = replay.players.map do |player|
        match = state[:match_model]
        "#{participant_name(player)}: #{match.total(player) - match.bonuses(player).values.sum}"
      end
      shortcuts << GameShortcut.new(key: "s", modifiers: [:shift], kind: :announcement,
        label: _("read the sum of recorded scores"), message: entries.join("\n"))
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
          label = cross ? _("Cross out %{category}") % {category: label} :
            _("%{category}: record %{points}") % {category: label, points: match.preview(category).first}
        end
        total = entries.grep(Integer).sum
        reserve = category.is_a?(Integer) ? (_("Reserve: %{count}") % {count: match.reserve(player, category)}) : ""
        [label, *Array.new(columns) { |index| cell_label(entries[index]) }, _("Total: %{points}") % {points: total}, reserve]
      end
      rows << [_("Total: %{points}") % {points: match.total(player)}, *Array.new(columns, ""),
        _("Bonuses: %{points}") % {points: match.bonuses(player).values.sum}, ""]
      GameSurfaces::GridSpec.new(width: columns + 3, height: rows.size, header: score_sheet_title(state, player),
        cells: rows, row_origin: :top, hide_coordinates: true,
        row_actions: writable ? choices.map { |choice| GameSurfaces::Action.new(kind: 'dice', name: 'score', payload: {'category' => choice}) } : [],
        shortcuts: [announcement_shortcut(key: 'space', label: _("read the dice"), message: dice_text(state))])
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

    def recorded_score_history(match, player, category, cross, event_id, before_bonuses)
      row = match.sheet(player).fetch(category)
      values = {player: participant_name(player), category: category_label(category), column: row.size}
      text = if cross
        _("%{player} crosses out %{category}, column %{column}.") % values
      else
        _("%{player} records %{points} in %{category}, column %{column}.") % values.merge(points: row.last)
      end
      entries = [HistoryEntry.new(key: "score:#{event_id}", event_id: event_id, actor: player, kind: :score, text: text)]
      bonuses = match.bonuses(player)
      bonuses.each do |(kind, completed), points|
        next if before_bonuses.key?([kind, completed]) || points.zero?
        message = if kind == :row
          _("%{player} earns %{points} bonus points for completing %{category}.") % {
            player: participant_name(player), points: points, category: category_label(completed)}
        else
          _("%{player} earns %{points} bonus points for completing column %{column}.") % {
            player: participant_name(player), points: points, column: completed + 1}
        end
        entries << HistoryEntry.new(key: "bonus:#{event_id}:#{kind}", event_id: event_id, actor: player, kind: :bonus, text: message)
      end
      lost = before_bonuses.values.sum - bonuses.values.sum
      if lost.positive?
        entries << HistoryEntry.new(key: "bonus:#{event_id}:lost", event_id: event_id, actor: player, kind: :bonus,
          text: _("%{player} loses %{points} bonus points.") % {player: participant_name(player), points: lost})
      end
      entries
    end

    def category_value(match, category, dice, rolls)
      result = match.preview(category, dice: dice, rolls: rolls)
      return unless result
      points, reserve_delta = result
      target = category.is_a?(Integer) ? category * 3 :
        {pair: 6, two_pairs: 12, triple: 9, four: 10, small_straight: 6,
         large_straight: 10, full_house: 10, poker: 12, chance: 23, even: 20, odd: 15}.fetch(category)
      points + reserve_delta * (category.is_a?(Integer) ? category : 0) + match.preview_bonus(category, points) - target
    end

    def cross_value(match, actor, category)
      category.is_a?(Integer) ? -100.0 - match.bonuses(actor).values.sum : -30.0
    end

    def decode_choice(match, value)
      raw = value.to_s
      [match.categories.find { |category| category.to_s == raw.delete_prefix("cross:") }, raw.start_with?("cross:")]
    end

    def category_label(category)
      return _("Even") if category == :even
      return _("Odd") if category == :odd
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
