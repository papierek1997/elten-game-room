require_relative "base"
require_relative "../lib/game_bots"
require_relative "../lib/game_tree_search"
require_relative "../lib/mancala_strategy"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Mancala < Base
    PITS = 6
    SIDE = PITS + 1
    TOTAL = SIDE * 2
    STONE_CHOICES = (2..8).to_a.freeze
    IDLE_LIMIT = 120
    RELAY_LIMIT = 200
    LEVELS = {
      "calm" => { depth: 2, nodes: 3_000 },
      "steady" => { depth: 4, nodes: 12_000 },
      "sharp" => { depth: 8, nodes: 60_000 }
    }.freeze

    SKILLS = [
      OptionChoice.new(value: "calm", label: _("Calm (short search)")),
      OptionChoice.new(value: "steady", label: _("Steady (looks a few moves ahead)")),
      OptionChoice.new(value: "sharp", label: _("Sharp (searches deeply and answers more slowly)"))
    ].freeze

    VARIANTS = [
      OptionChoice.new(value: "oware", label: _("Oware (capture two or three seeds in the other row)")),
      OptionChoice.new(value: "ayoayo", label: _("Ayoayo (keep sowing on from every pit that was not empty)")),
      OptionChoice.new(value: "kalah", label: _("Kalah (sow into your own store and sow again from it)"))
    ].freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      kinds = history.map(&:kind)
      { sow: "domino_move_tile", capture: "hit1" }.select { |kind, _| kinds.include?(kind) }.values
    end

    def id
      "mancala"
    end

    def notification_option_keys(_options); %w[variant]; end
    def notification_variant(options)
      {"oware" => _("Oware"), "ayoayo" => _("Ayoayo"), "kalah" => _("Kalah")}.fetch(options["variant"], "")
    end

    def name
      _("Mancala")
    end

    def short_description
      _("Move stones between pits on the board, planning your moves to collect more than your opponent.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      2
    end

    def maximum_players
      2
    end

    def supports_bots?
      true
    end

    def shareable_simulation_snapshot?
      true
    end

    def bot_strategy
      @bot_strategy ||= MancalaPlanning::Strategy.new
    end

    def strategy_for(level)
      @strategies ||= {}
      size = LEVELS.fetch(level.to_s, LEVELS["steady"])
      @strategies[level.to_s] ||= GameRoomBots::AlphaBetaStrategy.new(
        max_depth: size[:depth], node_limit: size[:nodes], optimize_transpositions: true
      )
    end

    def skill(state)
      state[:options]["skill"].to_s
    end

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: _("Game"), kind: :choice, default: "oware", choices: VARIANTS),
        OptionDefinition.new(key: "stones", label: _("Seeds in each pit"), kind: :integer, default: 4),
        OptionDefinition.new(key: "skill", label: _("How hard the computer plays"), kind: :choice,
          default: "steady", choices: SKILLS),
        OptionDefinition.new(key: "capture", label: _("Capture from an empty pit"), kind: :boolean, default: true,
          visible_if: ->(values) { values["variant"] == "kalah" })
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      if !STONE_CHOICES.include?(values["stones"].to_i)
        return _("Each pit must start with %{from} to %{to} seeds.") % { from: STONE_CHOICES.first, to: STONE_CHOICES.last }
      end

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      variant = VARIANTS.find { |choice| choice.value == values["variant"] }
      text = _("%{variant}; %{seeds} seeds in each pit") % { variant: variant&.label, seeds: values["stones"] }
      values["variant"] == "kalah" && !values["capture"] ? text + "; " + _("no capturing") : text
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]

      events.each do |event|
        break if state[:phase] == :finished

        actor = repository.actor_of(event, session)
        accepted << event if event["action"].to_s == "sow" && apply_sow(state, event, actor, repository, history)
      end

      wrap(players, state, accepted, history)
    end

    def incremental_replay(replay, session, events, repository)
      return nil if replay == nil

      state = replay.state.merge(pits: replay.state[:pits].dup, players: replay.players)
      accepted = replay.accepted_events.dup
      history = replay.history.dup
      events.each do |event|
        break if state[:phase] == :finished

        actor = repository.actor_of(event, session)
        accepted << event if event["action"].to_s == "sow" && apply_sow(state, event, actor, repository, history)
      end
      wrap(replay.players, state, accepted, history)
    end

    def wrap(players, state, accepted, history)
      Replay.new(
        board: nil, players: players, current_player: state[:current_player],
        winner: state[:winner], draw: state[:tie], accepted_events: accepted,
        history: history, state: state
      )
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:phase] == :finished
      return [] if !same_user?(state[:current_player], actor)

      sowable(state, side_of(state, actor)).map do |pit|
        { "kind" => "grid", "action" => "select", "x" => pit, "y" => 0 }
      end
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] if selection["action"].to_s != "select"
      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)
      return [:other_side, nil] if selection["y"].to_i != 0

      side = side_of(state, actor)
      pit = selection["x"].to_i
      return [:invalid, nil] if !pit.between?(0, PITS - 1)
      return [:empty_pit, nil] if state[:pits][side * SIDE + pit].zero?
      return [:must_feed, nil] if !sowable(state, side).include?(pit)

      [:ok, event_plan("sow", pit.to_s)]
    end

    def surface_spec(replay, viewer)
      state = replay.state
      side = side_of(state, viewer) || 0
      mine = (0...PITS).map { |column| pit_label(state, side, column, column, 0) }
      theirs = (0...PITS).map { |column| pit_label(state, 1 - side, PITS - 1 - column, column, 1) }
      GameSurfaces::GridSpec.new(
        width: PITS, height: 2, header: board_header(replay, viewer),
        cells: [mine, theirs], row_origin: :bottom
      )
    end

    def participant_scores(replay)
      state = replay.state
      state[:players].each_with_index.to_h { |player, index| [player, store_of(state, index)] }
    end

    def shortcut_features
      [:turn, :scores]
    end

    def shortcut_feature_data(feature, replay, viewer)
      return { message: stores_text(replay.state) } if feature.to_sym == :scores

      super
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      side = side_of(state, viewer) || 0
      [
        announcement_shortcut(key: "p", label: _("read your pits"), message: row_text(state, side, true)),
        GameShortcut.new(key: "p", modifiers: [:shift], label: _("read the other row"),
          kind: :announcement, message: row_text(state, 1 - side, false))
      ]
    end

    def move_error(status)
      case status
      when :empty_pit then _("That pit is empty.")
      when :other_side then _("You may only sow your own pits.")
      when :must_feed then _("You must put seeds into the other row.")
      else super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = history_entries_for_display(replay, viewer).select { |entry| entry.event_id.to_i == event_id.to_i }
      entries.empty? ? nil : entries.map(&:text)
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      view_side = side_of(replay.state, viewer) || 0
      replay.history.map do |item|
        next item unless item.kind == :sow && item.value.is_a?(Hash)
        own = side_of(replay.state, item.actor) == view_side
        pit = item.value.fetch("pit")
        field = own ? field_label(pit, 0) : field_label(PITS - 1 - pit, 1)
        displayed = item.dup
        displayed.field = field
        displayed.text = _("%{player} sows %{seeds} from %{pit}.") % {
          player: participant_name(item.actor), seeds: seed_count(item.value.fetch("seeds")), pit: field
        }
        displayed
      end
    end

    def bot_search_key(replay, actor)
      state = replay.state
      [variant(state), state[:options]["capture"], state[:idle], state[:phase],
        side_of(state, actor), side_of(state, state[:current_player]), state[:pits]].inspect
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      side = side_of(state, actor)
      pit = selection_value(action, "x")
      preview = state[:pits].dup
      landing = scatter(preview, state, side, pit)
      taken = harvest(preview, state, side, landing)
      return taken * 20.0 + 10.0 if taken.positive?
      return 100.0 if repeats?(state, side, landing)

      state[:pits][side * SIDE + pit].to_f
    end

    def bot_position_value(replay, actor)
      return bot_reward(replay, actor) * 1_000_000.0 if replay.finished?

      state = replay.state
      side = side_of(state, actor)
      other = 1 - side
      gathered = store_of(state, side) - store_of(state, other)
      held = side_stones(state, side) - side_stones(state, other)
      gathered * 12.0 + held * 1.0
    end

    private

    def initial_state(players, options)
      seeds = options["stones"].to_i
      pits = Array.new(TOTAL) { |index| (index % SIDE) == PITS ? 0 : seeds }
      {
        players: players, options: options, pits: pits, idle: 0,
        phase: :playing, current_player: players.first, winner: nil, tie: false
      }
    end

    def apply_sow(state, event, actor, repository, history)
      return false if state[:phase] != :playing || !same_user?(state[:current_player], actor)

      side = side_of(state, actor)
      pit = Integer(event["value"].to_s, 10)
      return false if side == nil || !sowable(state, side).include?(pit)

      seeds = state[:pits][side * SIDE + pit]
      landing = scatter(state[:pits], state, side, pit)
      event_id = repository.event_id(event)
      history << entry("sow:#{event_id}", _("%{player} sows %{seeds} from %{pit}.") % {
        player: participant_name(actor), seeds: seed_count(seeds), pit: field_label(pit, 0)
      }, event_id, actor, :sow)
      history.last.value = { "pit" => pit, "seeds" => seeds }
      taken = harvest(state[:pits], state, side, landing)
      if taken.positive?
        state[:pits][store_index(side)] += taken
        state[:idle] = 0
        history << entry("take:#{event_id}", _("%{player} captures %{seeds}.") % {
          player: participant_name(actor), seeds: seed_count(taken)
        }, event_id, actor, :capture)
      else
        state[:idle] += 1
      end
      again = repeats?(state, side, landing)
      state[:current_player] = state[:players][1 - side] unless again
      settle(state, event_id, history)
      if again && state[:phase] == :playing
        history << entry("again:#{event_id}", _("%{player} sows again.") % { player: participant_name(actor) },
          event_id, actor, :again)
      end
      true
    rescue ArgumentError
      false
    end

    def scatter(pits, state, side, pit)
      cursor = side * SIDE + pit
      laps = 0
      loop do
        cursor = sow_once(pits, state, side, cursor)
        laps += 1
        break if !relay?(state) || pits[cursor] < 2 || laps > RELAY_LIMIT
      end
      cursor
    end

    def sow_once(pits, state, side, origin)
      cursor = origin
      seeds = pits[cursor]
      pits[cursor] = 0
      while seeds.positive?
        cursor = (cursor + 1) % TOTAL
        next if skipped?(state, side, cursor, origin)

        pits[cursor] += 1
        seeds -= 1
      end
      cursor
    end

    def skipped?(state, side, cursor, origin)
      return true if cursor == store_index(1 - side)
      return false if kalah?(state)

      cursor == store_index(side) || cursor == origin
    end

    def harvest(pits, state, side, landing)
      return oware_harvest(pits, side, landing) if oware?(state)
      return 0 if kalah?(state) && !state[:options]["capture"]
      return 0 if !own_pits(side).include?(landing) || pits[landing] != 1

      facing_pit = facing(landing)
      return 0 if pits[facing_pit].zero?

      taken = pits[facing_pit] + 1
      pits[facing_pit] = 0
      pits[landing] = 0
      taken
    end

    def oware_harvest(pits, side, landing)
      other = 1 - side
      cursor = landing
      picked = []
      while own_pits(other).include?(cursor) && [2, 3].include?(pits[cursor])
        picked << cursor
        cursor = (cursor - 1) % TOTAL
      end
      return 0 if picked.empty?
      return 0 if picked.sum { |pit| pits[pit] } == own_pits(other).sum { |pit| pits[pit] }

      taken = picked.sum { |pit| pits[pit] }
      picked.each { |pit| pits[pit] = 0 }
      taken
    end

    def repeats?(state, side, landing)
      kalah?(state) && landing == store_index(side)
    end

    def settle(state, event_id, history)
      total = state[:pits].sum
      scores = [store_of(state, 0), store_of(state, 1)]
      return conclude(state, event_id, history) if scores.sum == total

      side = side_of(state, state[:current_player])
      if oware?(state)
        return conclude(state, event_id, history) if scores.any? { |score| score * 2 > total }
        return gather_each(state, event_id, history) if state[:idle] >= IDLE_LIMIT
        return gather_each(state, event_id, history) if sowable(state, side).empty?

        return false
      end
      if relay?(state)
        return false if sowable(state, side).any?

        return gather_to(state, 1 - side, event_id, history)
      end

      empty = [0, 1].find { |index| side_stones(state, index).zero? }
      return false if empty == nil

      gather_to(state, 1 - empty, event_id, history, own_only: true)
    end

    def gather_each(state, event_id, history)
      [0, 1].each { |index| move_to_store(state, index, index, event_id, history) }
      conclude(state, event_id, history)
    end

    def gather_to(state, index, event_id, history, own_only: false)
      sources = own_only ? [index] : [0, 1]
      sources.each { |source| move_to_store(state, source, index, event_id, history) }
      conclude(state, event_id, history)
    end

    def move_to_store(state, source, index, event_id, history)
      left = side_stones(state, source)
      return if left.zero?

      own_pits(source).each { |pit| state[:pits][pit] = 0 }
      state[:pits][store_index(index)] += left
      history << entry("sweep:#{event_id}:#{source}", _("%{player} takes the last %{seeds}.") % {
        player: participant_name(state[:players][index]), seeds: seed_count(left)
      }, event_id, state[:players][index], :sweep)
    end

    def conclude(state, event_id, history)
      state[:phase] = :finished
      state[:current_player] = nil
      first = store_of(state, 0)
      second = store_of(state, 1)
      state[:winner] = first == second ? nil : state[:players][first > second ? 0 : 1]
      state[:tie] = first == second
      history << entry("scores:#{event_id}", stores_text(state), event_id, "", :score)
      history << result_history(event_id: event_id, winner: state[:winner], draw: state[:tie])
      true
    end

    def sowable(state, side)
      return [] if side == nil

      moves = (0...PITS).select { |pit| state[:pits][side * SIDE + pit].positive? }
      return moves if kalah?(state) || side_stones(state, 1 - side).positive?

      moves.select { |pit| feeds?(state, side, pit) }
    end

    def feeds?(state, side, pit)
      preview = state[:pits].dup
      scatter(preview, state, side, pit)
      own_pits(1 - side).any? { |place| preview[place].positive? }
    end

    def oware?(state)
      variant(state) == "oware"
    end

    def relay?(state)
      variant(state) == "ayoayo"
    end

    def kalah?(state)
      variant(state) == "kalah"
    end

    def variant(state)
      state[:options]["variant"].to_s
    end

    def own_pits(side)
      ((side * SIDE)..(side * SIDE + PITS - 1)).to_a
    end

    def store_index(side)
      side * SIDE + PITS
    end

    def store_of(state, side)
      state[:pits][store_index(side)].to_i
    end

    def side_stones(state, side)
      own_pits(side).sum { |pit| state[:pits][pit] }
    end

    def facing(pit)
      TOTAL - 2 - pit
    end

    def side_of(state, actor)
      state[:players].index { |player| same_user?(player, actor) }
    end

    def seed_count(number)
      n_("%{count} seed", "%{count} seeds", number) % { count: number }
    end

    def pit_label(state, side, pit, column, row)
      _("%{field}, %{seeds}") % {
        field: field_label(column, row), seeds: seed_count(state[:pits][side * SIDE + pit])
      }
    end

    def board_header(replay, viewer)
      state = replay.state
      return _("%{result} %{stores}") % { result: result_text(replay), stores: stores_text(state) } if replay.finished?

      _("%{turn} %{stores}") % { turn: current_turn_shortcut_text(replay, viewer), stores: stores_text(state) }
    end

    def stores_text(state)
      scores = state[:players].each_with_index.to_h { |player, index| [player, store_of(state, index)] }
      values = score_announcement_order(state[:players], scores).map do |player|
        _("%{player}: %{seeds}") % { player: participant_name(player), seeds: scores.fetch(player) }
      end
      _("Stores: %{values}.") % { values: values.join("; ") }
    end

    def row_text(state, side, own)
      return _("No pits.") if side == nil

      values = (0...PITS).map { |pit| state[:pits][side * SIDE + pit] }
      header = own ? _("Your pits: %{values}.") : _("The other row: %{values}.")
      header % { values: values.join(", ") }
    end

    def entry(key, text, event_id, actor, kind)
      HistoryEntry.new(key: key, text: text, event_id: event_id, actor: actor, kind: kind)
    end
  end
end

require_relative 'generated/rulebooks/mancala'
