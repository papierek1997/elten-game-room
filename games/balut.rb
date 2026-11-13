require_relative "yahtzee"
require_relative "balut_support/balut_scoring"
require_relative "balut_support/balut_score_grid"

module GameRoomGames
  using GameRoomLocalization::Translations

  class Balut < Yahtzee
    include BalutScoreGrid
    GameRoomServerRandom.register("balut", ["roll"])

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      dice = after_replay&.state&.fetch(:dice, [])
      return ["roll", "win1"] if event["action"] == "roll" && dice&.size == 5 && dice.none?(&:nil?) && dice.uniq.one?

      super
    end

    def id; "balut"; end
    def name; "Balut"; end
    def short_description; "Wype\u0142nij siedem wierszy po cztery pola."; end
    def option_definitions; []; end
    def options_error(options, player_count: nil); nil; end
    def options_summary(options); "28 tur"; end
    def tournament_capabilities(options: {}); super.merge(player_counts: [].freeze).freeze; end

    def rule_sections; generated_rule_sections; end

    def replay(session, events, repository)
      players = repository.players_for(session)
      sheets = players.to_h { |p| [p, BalutScoring::CATEGORIES.to_h { |c| [c, []] }] }
      state = {players: players, current_player: players.first, turn_rolls: 0, dice: Array.new(5), sheets: sheets}
      history, accepted, seen = [starting_history(players)], [], {}
      events.each do |event|
        player = state[:current_player]
        break unless player
        key = repository.event_id(event)
        next if seen[key] || !same_user?(player, repository.actor_of(event, session))
        case event["action"]
        when "roll"
          next unless apply_roll(state, event, player, repository, history)
        when "score"
          category = BalutScoring::CATEGORIES.find { |c| c.to_s == event["value"] }
          next unless state[:turn_rolls].positive? && category && BalutScoring.record(sheets[player], category, state[:dice])
          history << HistoryEntry.new(key: "score:#{key}", event_id: key, actor: player, kind: :score,
            text: "#{participant_name(player)}: #{category_label(category)}, #{sheets[player][category].last}.")
          state[:current_player] = players.rotate(players.index(player) + 1).find { |p| !BalutScoring.result(sheets[p]) }
          state[:turn_rolls] = 0
          state[:dice] = Array.new(5)
        else
          next
        end
        seen[key] = true
        accepted << event
      end
      leaders = unless state[:current_player]
        totals = players.to_h { |p| [p, total_score(state, p)] }
        totals.keys.select { |p| totals[p] == totals.values.max }
      end
      Replay.new(players: players, current_player: state[:current_player], state: state, accepted_events: accepted,
        history: history, winner: leaders&.one? ? leaders.first : nil, draw: leaders && leaders.size > 1)
    end

    def available_scoring_categories(state, actor)
      sheet = state[:sheets][player_key(state, actor)]
      sheet ? sheet.select { |_, row| row.size < 4 }.keys.map(&:to_s) : []
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return super if replay.finished? || !same_user?(replay.current_player, viewer)
      return score_grid(state, player_key(state, viewer), writable: true) if state[:turn_rolls] == 3
      categories = state[:turn_rolls].positive? ? available_scoring_categories(state, viewer).map do |category|
        points = BalutScoring.score(category.to_sym, state[:dice])
        GameSurfaces::ScoreChoice.new(id: category, value: category, label: "#{category_label(category.to_sym)}: #{points}")
      end : []
      dice = state[:dice].each_with_index.map { |value, i| GameSurfaces::Die.new(id: "d#{i}", value: value, sides: 6, held: true, enabled: true) }
      GameSurfaces::RollAndScoreSpec.new(id: id, header: name, categories: categories, dice: dice,
        can_roll: state[:turn_rolls] < 3, force_categories: state[:turn_rolls] == 3,
        empty_label: _("Roll the dice first"), roll_number: state[:turn_rolls], score_grid: true)
    end

    def score_sheet_title(_state, player); "Tabela: #{participant_name(player)}"; end
    def score_sheet_choices(state, player, incomplete_only: false)
      sheet = state[:sheets].fetch(player)
      rows = sheet.filter_map do |category, values|
        next if incomplete_only && values.size >= SLOT_COUNT
        cells = Array.new(4) { |index| values.fetch(index, "puste") }
        points = BalutScoring.row_points(category, values)
        "#{category_label(category)}: #{cells.join(', ')}. Suma: #{values.sum}. Punkty za wiersz: #{points}."
      end
      rows << balut_totals_text(state, player) unless incomplete_only
      rows.map { |label| ShortcutChoice.new(label: label, value: nil) }
    end

    def surface_action_shortcut(selection, replay, viewer)
      if selection["kind"] == "dice" && selection["action"] == "open_score_grid"
        return custom_game_shortcuts(replay, viewer).find { |shortcut| shortcut.key == "b" }
      end

      super
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super.reject { |shortcut| shortcut.key == "s" }
      state = replay.state
      players = state.fetch(:players).sort_by { |player| -total_score(state, player) }
      points = players.map { |player| "#{participant_name(player)}: #{total_score(state, player)}" }
      entries = players.map do |player|
        "#{participant_name(player)}: #{state.fetch(:sheets).fetch(player).values.sum(&:sum)}"
      end
      owner = player_key(state, viewer)
      if owner
        missing = score_sheet_choices(state, owner, incomplete_only: true)
        shortcuts << if missing.empty?
          announcement_shortcut(key: "f", label: "Sprawdź wolne pola", message: "Tabela jest pełna.")
        else
          browse_shortcut(key: "f", label: "Pokaż wiersze z wolnymi polami",
            prompt: "Wiersze z wolnymi polami", choices: missing)
        end
        writable = same_user?(owner, replay.current_player) && state[:turn_rolls].to_i.positive?
        shortcuts << GameShortcut.new(key: "b", kind: :grid_preview,
          label: "Otw\u00f3rz tabel\u0119 wynik\u00f3w", default_value: score_grid(state, owner, writable: writable))
      end
      shortcuts = shortcuts.reject { |shortcut| shortcut.key == "space" } if state[:turn_rolls] == 3
      shortcuts << announcement_shortcut(key: "space", label: "Odczytaj ko\u015bci", message: dice_text(state)) if state[:turn_rolls] == 3
      shortcuts + [
        announcement_shortcut(key: "s", label: "Odczytaj wynik gry", message: points.join(". ")),
        GameShortcut.new(key: "s", modifiers: [:shift], kind: :announcement,
          label: "Odczytaj sum\u0119 punkt\u00f3w", message: entries.join(". "))
      ]
    end
    def scores_text(state, sorted: false)
      players = state.fetch(:players)
      players = players.sort_by { |player| -total_score(state, player) } if sorted
      players.map { |player| "#{participant_name(player)}. #{balut_totals_text(state, player)}" }.join("\n")
    end

    def total_score(state, player)
      BalutScoring.current_result(state[:sheets].fetch(player)).fetch(:points)
    end

    def bot_observation(replay, actor)
      { "dice" => replay.state[:dice].dup, "own_sheet" => replay.state[:sheets].fetch(actor).transform_values(&:dup) }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      if action["action"] == "score"
        category = action["category"].to_sym
        points = BalutScoring.score(category, state[:dice])
        return points + (points.positive? && [:straight, :full_house].include?(category) ? 12 : 0)
      end
      return 100 if state[:turn_rolls].zero?
      indices = parse_die_ids(action["die_ids"])
      kept = state[:dice].each_with_index.filter_map { |face, i| face unless indices.include?(i) }
      count = kept.tally.values.max || 0
      8 + count * 5 - (kept.size - count) * 5
    end

    private

    def category_label(category)
      {fours: "Czw\u00f3rki", fives: "Pi\u0105tki", sixes: "Sz\u00f3stki", choice: "Szansa",
       straight: "Strit", full_house: "Full", balut: "Balut"}.fetch(category)
    end
  end
end

require_relative 'generated/rulebooks/balut'
