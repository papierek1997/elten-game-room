require_relative "base"
require_relative "../lib/game_bots"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Yahtzee < Base
    STANDARD_CATEGORIES = %w[
      ones twos threes fours fives sixes three_kind four_kind full_house
      small_straight large_straight yahtzee chance
    ].freeze
    EXTRA_CATEGORIES = %w[pair two_pairs misery].freeze
    CATEGORY_LABELS = {
      "ones" => _("Ones"), "twos" => _("Twos"), "threes" => _("Threes"),
      "fours" => _("Fours"), "fives" => _("Fives"), "sixes" => _("Sixes"),
      "three_kind" => _("Three of a kind"), "four_kind" => _("Four of a kind"),
      "full_house" => _("Full house"), "small_straight" => _("Small straight"),
      "large_straight" => _("Large straight"), "yahtzee" => _("Yahtzee"),
      "chance" => _("Chance"), "pair" => _("One pair"),
      "two_pairs" => _("Two pairs"), "misery" => _("Misery")
    }.freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      return "roll" if action == "roll"
      return "play" if action == "score"
    end

    def id
      "yahtzee"
    end

    def name
      _("Yahtzee")
    end

    def short_description
      _("Roll five dice and choose how to score them, remembering that each category can only be used once.")
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

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def rule_sections
      generated_rule_sections
    end

    def option_definitions
      [
        OptionDefinition.new(key: "matches", label: _("Number of matches"), kind: :integer, default: 1),
        OptionDefinition.new(key: "extra_categories", label: _("Pair, two pairs and misery"), kind: :boolean, default: true),
        OptionDefinition.new(key: "upper_bonus", label: _("35-point bonus for Ones through Sixes"), kind: :boolean, default: true),
        OptionDefinition.new(key: "yahtzee_bonus", label: _("Bonus for additional Yahtzees"), kind: :boolean, default: true),
        OptionDefinition.new(key: "joker_rule", label: _("Yahtzee Joker rule"), kind: :boolean, default: true)
      ]
    end

    def options_error(options, player_count: nil)
      matches = normalize_options(options)["matches"].to_i
      return _("The number of matches must be from 1 to 10.") if !matches.between?(1, 10)

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      _("%{matches} matches; extra categories: %{extra}; Yahtzee bonus: %{bonus}; Joker: %{joker}") % {
        matches: values["matches"], extra: yes_no(values["extra_categories"]),
        bonus: yes_no(values["yahtzee_bonus"]), joker: yes_no(values["joker_rule"])
      }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]
      events.each do |event|
        break if state[:winner] != nil || state[:draw]
        actor = repository.actor_of(event, session)
        next if !same_user?(actor, state[:current_player])

        applied = case event["action"].to_s
        when "roll" then apply_roll(state, event, actor, repository, history)
        when "score" then apply_score(state, event, actor, repository, history)
        else false
        end
        accepted << event if applied
      end
      Replay.new(
        board: nil, players: players, current_player: state[:current_player], winner: state[:winner],
        draw: state[:draw], accepted_events: accepted, history: history, state: state
      )
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if replay.finished? || !same_user?(state[:current_player], actor)
      if state[:turn_rolls].to_i == 0
        return [{ "kind" => "dice", "action" => "roll", "die_ids" => "d0,d1,d2,d3,d4" }]
      end

      actions = available_scoring_categories(state, actor).map do |category|
        { "kind" => "dice", "action" => "score", "category" => category }
      end
      if state[:turn_rolls].to_i < 3
        1.upto(31) do |mask|
          ids = 5.times.select { |index| (mask & (1 << index)) != 0 }.map { |index| "d#{index}" }
          actions << { "kind" => "dice", "action" => "roll", "die_ids" => ids.join(",") }
        end
      end
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)

      action = selection["action"].to_s
      case action
      when "roll"
        return [:roll_limit, nil] if state[:turn_rolls].to_i >= 3
        return [:invalid, nil] if context == nil || context.random_source == nil
        indices = if state[:turn_rolls].to_i == 0
          (0...5).to_a
        else
          parse_die_ids(selection["die_ids"])
        end
        return [:choose_dice, nil] if indices.empty?
        dice = state[:dice].dup
        values = context.random_source.roll(count: indices.length, sides: 6).values
        return [:invalid, nil] if values.length != indices.length
        indices.each_with_index { |die_index, value_index| dice[die_index] = values[value_index].to_i }
        dice.sort!
        [:ok, event_plan("roll", dice.join(","))]
      when "score"
        return [:roll_first, nil] if state[:turn_rolls].to_i == 0
        category = selection["category"].to_s
        return [:category_used, nil] if !available_scoring_categories(state, actor).include?(category)
        [:ok, event_plan("score", category)]
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if replay.finished? || !same_user?(state[:current_player], viewer)
        label = replay.finished? ? result_text(replay) : current_turn_shortcut_text(replay, viewer)
        return GameSurfaces::PawnTrackSpec.new(
          id: "yahtzee_status", header: name,
          items: [GameSurfaces::PawnTrackItem.new(id: "status", label: label)],
          empty_label: label
        )
      end

      categories = state[:turn_rolls].to_i > 0 ? available_scoring_categories(state, viewer).map do |category|
        points = score_category(category, state[:dice], state, viewer)
        GameSurfaces::ScoreChoice.new(
          id: category,
          label: _("%{category}: %{points} points") % { category: CATEGORY_LABELS.fetch(category), points: points },
          value: category
        )
      end : []
      dice = state[:dice].each_with_index.map do |value, index|
        GameSurfaces::Die.new(id: "d#{index}", value: value, sides: 6, held: true, enabled: true)
      end
      GameSurfaces::RollAndScoreSpec.new(
        id: "yahtzee_dice",
        header: name,
        dice: dice,
        categories: categories,
        can_roll: state[:turn_rolls].to_i < 3,
        force_categories: state[:turn_rolls].to_i >= 3,
        empty_label: _("No categories remain"),
        roll_number: state[:turn_rolls].to_i
      )
    end

    def participant_scores(replay)
      state = replay.state
      state[:players].to_h { |player| [player, total_score(state, player)] }
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = []
      1.upto(6) do |value|
        shortcuts << surface_shortcut(
          key: value.to_s, label: _("select another die showing %{value}") % { value: value },
          command: "select_die", payload: { "value" => value }
        )
        shortcuts << surface_shortcut(
          key: value.to_s, modifiers: [:shift], label: _("keep another die showing %{value}") % { value: value },
          command: "unselect_die", payload: { "value" => value }
        )
      end
      owner = player_key(replay.state, viewer)
      if owner
        shortcuts << browse_shortcut(key: "v", label: _("view your score sheet"), prompt: score_sheet_title(replay.state,owner), choices: score_sheet_choices(replay.state,owner))
      end
      others = replay.players.reject { |player| same_user?(player,viewer) }
      unless others.empty?
        choices = others.length == 1 ? score_sheet_choices(replay.state,others.first) : others.map do |player|
          ShortcutChoice.new(label: participant_name(player), value: score_sheet_choices(replay.state,player))
        end
        shortcuts << browse_shortcut(key: "v", modifiers: [:shift], label: _("view another player's score sheet"),
          prompt: others.length == 1 ? score_sheet_title(replay.state,others.first) : _("Choose a player's score sheet"), choices: choices)
      end
      shortcuts + [
        surface_shortcut(key: "space", label: _("read the dice and their selection state"), command: "announce_dice"),
        announcement_shortcut(key: "s", label: _("read the scores"), message: scores_text(replay.state, sorted: true))
      ]
    end

    def shortcut_features; super + [:last_roll]; end
    def shortcut_feature_data(feature, replay, viewer)
      return super unless feature == :last_roll
      { message: dice_text(replay.state) }
    end

    def score_sheet_title(state,player)
      _("%{player}'s score sheet, match %{match}") % { player: participant_name(player), match: state[:match] }
    end
    def score_sheet_choices(state,player)
      sheet = state[:sheets].fetch(player)
      labels = [score_sheet_title(state,player)] + categories(state).map do |category|
        value = sheet.key?(category) ? sheet[category].to_s : _("not filled")
        "#{CATEGORY_LABELS.fetch(category)}: #{value}"
      end
      upper = %w[ones twos threes fours fives sixes].sum { |c| sheet[c].to_i }
      labels << (_("Ones through Sixes: %{points} of 63.") % { points: upper })
      labels << (_("Bonus for Ones through Sixes: %{points}.") % { points: upper >= 63 ? 35 : 0 }) if state[:options]["upper_bonus"]
      labels << (_("Additional Yahtzee bonuses: %{points}.") % { points: state[:yahtzee_bonuses][player].to_i }) if state[:options]["yahtzee_bonus"]
      labels << (_("This sheet: %{points}.") % { points: sheet_total(state,player) })
      labels << (_("Total across matches: %{points}.") % { points: total_score(state,player) })
      labels.map { |label| ShortcutChoice.new(label: label,value: nil) }
    end

    def bot_observation(replay, actor)
      state = replay.state
      {
        "players" => state[:players], "current_player" => state[:current_player],
        "dice" => state[:dice], "turn_rolls" => state[:turn_rolls],
        "own_sheet" => state[:sheets][player_key(state, actor)],
        "totals" => state[:totals], "match" => state[:match], "winner" => state[:winner]
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      if action["action"] == "score"
        return 1_000_000.0 if bot_wins_by_scoring?(state, actor, action["category"])
        return bot_category_value(action["category"], state[:dice], state, actor)
      end
      return 10_000.0 if state[:turn_rolls].zero?

      rerolled = parse_die_ids(action["die_ids"])
      kept = state[:dice].each_with_index.filter_map { |value, index| value if !rerolled.include?(index) }
      # All 6^n outcomes are represented by a small memoized tree of sorted
      # multisets. This evaluates the remaining rolls without sampling or
      # inspecting any other player's future dice.
      key = [state[:sheets][actor], state[:options], state[:yahtzee_bonuses][actor], state[:turn_rolls]].inspect
      if @dice_plan_key != key
        @dice_plan_key = key
        @dice_expectations = {}
        @dice_decisions = {}
      end
      bot_roll_value(kept.sort, 3 - state[:turn_rolls], state, actor) - 0.0001
    end

    def move_error(status)
      case status
      when :roll_limit then _("You have already used all three rolls.")
      when :choose_dice then _("Select at least one die to reroll, or open the scoring categories.")
      when :roll_first then _("Roll the dice before choosing a category.")
      when :category_used then _("That scoring category has already been used.")
      else super
      end
    end

    def describe_event(event, repository, replay, viewer)
      id = repository.event_id(event).to_i
      messages = replay.history.filter_map { |entry| entry.text if entry.event_id.to_i == id }
      messages.empty? ? nil : messages
    end

    private

    def initial_state(players, options)
      {
        players: players, options: options, match: 1, current_player: players.first,
        dice: Array.new(5), turn_rolls: 0,
        sheets: new_sheets(players), totals: players.to_h { |player| [player, 0] },
        yahtzee_bonuses: players.to_h { |player| [player, 0] }, winner: nil, draw: false
      }
    end

    def apply_roll(state, event, actor, repository, history)
      return false if state[:turn_rolls].to_i >= 3
      dice = event["value"].to_s.split(",").map { |value| Integer(value, 10) }
      return false if dice.length != 5 || dice.any? { |value| !value.between?(1, 6) } || dice != dice.sort

      state[:dice] = dice
      state[:turn_rolls] += 1
      id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "roll:#{id}", text: _("%{player} rolled %{dice}.") % {
          player: participant_name(actor), dice: dice.join(" ")
        }, event_id: id, actor: actor, kind: :roll
      )
      true
    rescue ArgumentError
      false
    end

    def apply_score(state, event, actor, repository, history)
      category = event["value"].to_s
      player = player_key(state, actor)
      return false if state[:turn_rolls].zero? || !available_scoring_categories(state, player).include?(category)
      bonus_yahtzee = additional_yahtzee?(state, player)
      upper_before = %w[ones twos threes fours fives sixes].sum { |key| state[:sheets][player][key].to_i }
      points = score_category(category, state[:dice], state, player)
      state[:sheets][player][category] = points
      if bonus_yahtzee
        state[:yahtzee_bonuses][player] += 100
      end
      id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "score:#{id}", text: _("%{player} scored %{points} in %{category}.") % {
          player: participant_name(player), points: points, category: CATEGORY_LABELS.fetch(category)
        }, event_id: id, actor: player, kind: :score, value: points
      )
      if bonus_yahtzee
        history << HistoryEntry.new(key: "yahtzee_bonus:#{id}", text: _("%{player} receives 100 bonus points for another Yahtzee.") % { player: participant_name(player) }, event_id: id, actor: player, kind: :game)
      end
      upper_after = %w[ones twos threes fours fives sixes].sum { |key| state[:sheets][player][key].to_i }
      if state[:options]["upper_bonus"] && upper_before < 63 && upper_after >= 63
        history << HistoryEntry.new(key: "upper_bonus:#{id}", text: _("%{player} receives 35 bonus points for Ones through Sixes.") % { player: participant_name(player) }, event_id: id, actor: player, kind: :game)
      end
      state[:dice] = Array.new(5)
      state[:turn_rolls] = 0
      finish_or_advance(state, id, history)
      true
    end

    def finish_or_advance(state, event_id, history)
      current = player_index(state[:players], state[:current_player])
      next_index = (current + 1) % state[:players].length
      state[:current_player] = state[:players][next_index]
      return if state[:sheets].values.any? { |sheet| sheet.length < categories(state).length }

      state[:players].each do |player|
        state[:totals][player] += sheet_total(state, player)
      end
      state[:sheet_counted] = true
      history << HistoryEntry.new(
        key: "match:#{event_id}", text: match_summary(state), event_id: event_id,
        actor: "", kind: :round_result
      )
      if state[:match].to_i >= state[:options]["matches"].to_i
        maximum = state[:totals].values.max
        winners = state[:players].select { |player| state[:totals][player] == maximum }
        state[:winner] = winners.one? ? winners.first : nil
        state[:draw] = winners.length > 1
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
      else
        state[:match] += 1
        state[:sheets] = new_sheets(state[:players])
        state[:sheet_counted] = false
        state[:yahtzee_bonuses] = state[:players].to_h { |player| [player, 0] }
        state[:current_player] = state[:players][(state[:match] - 1) % state[:players].length]
      end
    end

    def categories(state)
      state[:options]["extra_categories"] ? STANDARD_CATEGORIES + EXTRA_CATEGORIES : STANDARD_CATEGORIES
    end

    def unused_categories(state, actor)
      player = player_key(state, actor)
      return [] if player == nil
      categories(state) - state[:sheets][player].keys
    end

    def available_scoring_categories(state, actor)
      unused = unused_categories(state, actor)
      return unused if !joker_active?(state, actor, state[:dice])

      matching_upper = %w[ones twos threes fours fives sixes][state[:dice].first.to_i - 1]
      return [matching_upper] if unused.include?(matching_upper)

      lower = unused - %w[ones twos threes fours fives sixes]
      lower.empty? ? unused : lower
    end

    def score_category(category, dice, state, actor)
      values = dice.to_a.map(&:to_i)
      counts = values.tally
      face = %w[ones twos threes fours fives sixes].index(category.to_s)
      return values.count(face + 1) * (face + 1) if face != nil
      joker = joker_active?(state, actor, values)
      case category.to_s
      when "three_kind" then counts.values.max.to_i >= 3 ? values.sum : 0
      when "four_kind" then counts.values.max.to_i >= 4 ? values.sum : 0
      when "full_house" then (counts.values.sort == [2, 3] || joker) ? [25, values.sum].max : 0
      when "small_straight" then straight_length(values) >= 4 || joker ? 30 : 0
      when "large_straight" then straight_length(values) >= 5 || joker ? 40 : 0
      when "yahtzee" then counts.values.max.to_i == 5 ? 50 : 0
      when "chance" then values.sum
      when "pair" then counts.values.any? { |count| count >= 2 } ? values.sum : 0
      when "two_pairs"
        pairs = counts.select { |_value, count| count >= 2 }.keys.max(2)
        pairs.length == 2 ? values.sum : 0
      when "misery" then 36 - values.sum
      else 0
      end
    end

    def straight_length(values)
      best = current = 1
      values.uniq.sort.each_cons(2) do |left, right|
        current = right == left + 1 ? current + 1 : 1
        best = [best, current].max
      end
      best
    end

    def joker_active?(state, actor, dice)
      player = player_key(state, actor)
      state[:options]["joker_rule"] && dice.uniq.length == 1 &&
        state[:sheets][player]["yahtzee"].to_i == 50
    end

    def additional_yahtzee?(state, actor)
      state[:options]["yahtzee_bonus"] && state[:dice].uniq.length == 1 &&
        state[:sheets][actor]["yahtzee"].to_i == 50
    end

    def sheet_total(state, player)
      sheet = state[:sheets][player]
      upper = %w[ones twos threes fours fives sixes].sum { |category| sheet[category].to_i }
      bonus = state[:options]["upper_bonus"] && upper >= 63 ? 35 : 0
      sheet.values.sum + bonus + state[:yahtzee_bonuses][player].to_i
    end

    def new_sheets(players)
      players.to_h { |player| [player, {}] }
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def parse_die_ids(value)
      value.to_s.split(",").filter_map do |id|
        match = /\Ad([0-4])\z/.match(id)
        match == nil ? nil : match[1].to_i
      end.uniq
    end

    def dice_text(state)
      return _("The dice have not been rolled.") if state[:dice].any?(&:nil?)
      state[:dice].join(", ") + "."
    end

    def scores_text(state, sorted: false)
      players = sorted ? score_announcement_order(state[:players], state[:players].to_h { |p| [p, total_score(state, p)] }) : state[:players]
      players.map do |player|
        _("%{player}: %{score}") % { player: participant_name(player), score: total_score(state, player) }
      end.join("; ")
    end

    def total_score(state, player)
      state[:totals][player].to_i + (state[:sheet_counted] ? 0 : sheet_total(state, player))
    end

    def bot_category_value(category, dice, state, actor)
      points = score_category(category, dice, state, actor).to_f
      # Reserve flexible/high-value boxes instead of cashing every mediocre
      # roll immediately. Upper-section progress also has value before 63.
      upper = %w[ones twos threes fours fives sixes]
      face = upper.index(category)
      targets = { "three_kind" => 20, "four_kind" => 14, "full_house" => 20,
        "small_straight" => 25, "large_straight" => 23, "yahtzee" => 12,
        "chance" => 22, "pair" => 22, "two_pairs" => 20, "misery" => 24 }
      reserve = face ? (face + 1) * 3 : targets.fetch(category, 0)
      reserve = 0 if unused_categories(state, actor).length == 1
      value = points - reserve
      if face && state[:options]["upper_bonus"]
        previous = upper.sum { |name| state[:sheets][actor][name].to_i }
        remaining = upper.each_index.select { |index| !state[:sheets][actor].key?(upper[index]) }
        before = bot_upper_bonus_probability(remaining, 63 - previous)
        after = bot_upper_bonus_probability(remaining - [face], 63 - previous - points.to_i)
        value += 35.0 * (after - before)
      end
      if state[:options]["yahtzee_bonus"] && dice.uniq.length == 1 && state[:sheets][actor]["yahtzee"] == 50
        value += 100
      end
      value
    end

    def bot_upper_bonus_probability(faces, needed)
      return 1.0 if needed <= 0
      return 0.0 if faces.sum { |face| (face + 1) * 5 } < needed
      @upper_probabilities ||= {}
      probability_key = [faces, needed]
      return @upper_probabilities[probability_key] if @upper_probabilities.key?(probability_key)
      # Model each future upper box as five dice kept for that face through
      # three rolls. This is an explicit approximation, not knowledge of rolls.
      @upper_distributions ||= { [] => { 0 => 1.0 } }
      unless @upper_distributions.key?(faces)
        p = 1.0 - (5.0 / 6)**3
        count_weights = [1, 5, 10, 10, 5, 1].each_with_index.map { |n, k| n * p**k * (1 - p)**(5 - k) }
        distribution = { 0 => 1.0 }
        faces.each do |face|
          next_distribution = Hash.new(0.0)
          distribution.each do |points, chance|
            count_weights.each_with_index { |weight, k| next_distribution[points + k * (face + 1)] += chance * weight }
          end
          distribution = next_distribution
        end
        @upper_distributions[faces.dup] = distribution
      end
      @upper_probabilities[[faces.dup, needed]] = @upper_distributions[faces].sum { |points, probability| points >= needed ? probability : 0.0 }
    end

    def bot_wins_by_scoring?(state, actor, category)
      player = player_key(state, actor)
      return false if state[:match].to_i < state[:options]["matches"].to_i
      return false unless unused_categories(state, player) == [category]
      others = state[:players] - [player]
      return false unless others.all? { |other| unused_categories(state, other).empty? }

      sheet = state[:sheets][player].merge(category => score_category(category, state[:dice], state, player))
      bonuses = state[:yahtzee_bonuses].dup
      bonuses[player] += 100 if additional_yahtzee?(state, player)
      after = state.merge(sheets: state[:sheets].merge(player => sheet), yahtzee_bonuses: bonuses)
      others.all? { |other| total_score(after, player) > total_score(state, other) }
    end

    def bot_roll_value(kept, rolls, state, actor)
      key = [rolls, kept]
      return @dice_expectations[key] if @dice_expectations.key?(key)
      value = if kept.length == 5
        bot_best_value(kept, rolls - 1, state, actor)
      else
        (1..6).sum { |face| bot_roll_value((kept + [face]).sort, rolls, state, actor) } / 6.0
      end
      @dice_expectations[key] = value
    end

    def bot_best_value(dice, rolls, state, actor)
      key = [rolls, dice]
      return @dice_decisions[key] if @dice_decisions.key?(key)
      simulated = state.merge(dice: dice)
      best = available_scoring_categories(simulated, actor).map { |category| bot_category_value(category, dice, simulated, actor) }.max
      if rolls > 0
        subsets = [[]]
        dice.tally.each do |face, count|
          subsets = subsets.flat_map { |subset| (0..count).map { |number| subset + Array.new(number, face) } }
        end
        subsets.each do |kept|
          next if kept.length == 5
          best = [best, bot_roll_value(kept, rolls, state, actor)].max
        end
      end
      @dice_decisions[key] = best
    end

    def match_summary(state)
      _("Match %{match} finished. %{scores}.") % { match: state[:match], scores: scores_text(state) }
    end

    def yes_no(value)
      value ? _("yes") : _("no")
    end
  end
end

require_relative 'generated/rulebooks/yahtzee'
