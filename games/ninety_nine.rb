require_relative "../lib/game_card_wire"
require "digest"
require_relative "base"
require_relative "../lib/card_deck_history"
require_relative "../lib/game_bots"
require_relative "../lib/game_tree_search"
require_relative "../lib/ninety_nine_strategy"
require_relative "../lib/game_turn_clock"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class NinetyNine < Base
    include GameRoomCardDeckHistory
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    SUITS = %w[C D H S].freeze
    SUIT_NAMES = {
      "C" => _("clubs"),
      "D" => _("diamonds"),
      "H" => _("hearts"),
      "S" => _("spades")
    }.freeze
    RANK_NAMES = {
      "2" => "2",
      "3" => "3",
      "4" => "4",
      "5" => "5",
      "6" => "6",
      "7" => "7",
      "8" => "8",
      "9" => "9",
      "T" => "10",
      "J" => _("jack"),
      "Q" => _("queen"),
      "K" => _("king"),
      "A" => _("ace")
    }.freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      return "shuffle" if action == "deal"
      return "draw" if action == "draw"
      return nil if !["play", "play_draw"].include?(action)

      previous_total = before_replay&.state.to_h.fetch(:total, 0).to_i
      current_total = after_replay&.state.to_h.fetch(:total, previous_total).to_i
      viewer_played = GameRoomParticipants.same?(event["actor"], viewer)
      cues = ["play"]
      card, _mode = event["value"].to_s.split("|", 2)
      rank = card.to_s[1]
      cues << "reverse" if rank == "J"
      if rank == "4" && before_replay&.state.to_h.fetch(:eliminated, {}).count { |_player, eliminated| !eliminated } >= 3
        cues << "reverse3"
      end
      cues << "draw2" if [33, 66].any? { |limit| previous_total < limit && current_total > limit }
      cues << "ninety3366" if [33, 66].include?(current_total) && current_total > previous_total
      cues << (viewer_played ? "win1" : "lose1") if current_total == 99
      cues << (viewer_played ? "lose1" : "win1") if current_total > 99
      cues << "draw" if action == "play_draw"
      cues
    end

    def id
      "ninety_nine"
    end

    def notification_option_keys(_options); %w[starting_tokens]; end
    def notification_variant(options)
      value = options["starting_tokens"]
      value.is_a?(Integer) && value.positive? ? (_("Starting tokens: %{count}") % {count: value}) : ""
    end

    def eliminated_from_game?(replay, viewer)
      replay.state.fetch(:eliminated, {}).any? { |player, out| out && same_user?(player, viewer) }
    end

    def name
      "99"
    end

    def short_description
      _("Play cards that change a shared total and try to hold on to your tokens longer than your opponents.")
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

    def thinking_time_range; 1..600; end

    def bot_strategy
      @bot_strategy ||= NinetyNinePlanning::Strategy.new
    end

    def perfect_information?
      false
    end

    def bot_observation(replay, actor)
      state = replay.state
      player = player_key(state, actor)
      {
        "players" => state[:players],
        "tokens" => state[:tokens],
        "eliminated" => state[:eliminated],
        "round" => state[:round],
        "direction" => state[:direction],
        "phase" => state[:phase],
        "current_player" => state[:current_player],
        "total" => state[:total],
        "hand" => player == nil ? [] : state[:hands].fetch(player, []),
        "opponent_card_counts" => state[:players].each_with_object({}) do |candidate, result|
          result[candidate] = state[:hands].fetch(candidate, []).length if !same_user?(candidate, actor)
        end,
        "discard_top" => state[:discard].last,
        "draw_count" => state[:draw_pile].length,
        "winner" => state[:winner]
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      case action["action"].to_s
      when "draw"
        1_000.0
      when "skip_draw"
        -1_000.0
      when "no_cards"
        -10_000.0
      when "select"
        card, mode = parse_play_choice(action["card"])
        total = total_after_card(state[:total].to_i, card, mode)
        return 20_000.0 if total == 99
        return -20_000.0 if total > 99
        return 5_000.0 if exact_danger_reached?(state[:total].to_i, total, card)

        crossed = [33, 66].count { |limit| state[:total].to_i < limit && total > limit }
        total.to_f - crossed * 2_500.0
      else
        -10_000.0
      end
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "starting_tokens",
          label: _("Starting tokens"),
          kind: :integer,
          default: 9
        ),
        OptionDefinition.new(
          key: "omniscient_bots",
          label: _("Omniscient bots (they can see every hand)"),
          kind: :boolean,
          default: false
        )
      ]
    end

    def options_error(options, player_count: nil)
      return _("The number of starting tokens must be greater than zero.") if normalize_options(options)["starting_tokens"].to_i <= 0

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      summary = _("%{count} starting tokens") % { count: values["starting_tokens"] }
      summary += "; " + _("omniscient bots") if values["omniscient_bots"]
      summary
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      seen = {}
      history = [starting_history(players)]

      events.each do |event|
        break if state[:winner] != nil
        original_event = event
        event_id = repository.event_id(event)
        next if seen[event_id]
        decoded = GameRoomTurnClock.decode(state, event)
        next unless decoded
        event, time = decoded
        next if %w[play play_draw draw skip_draw no_cards].include?(event["action"]) && ninety_deadline_reached?(state, time)
        actor = repository.actor_of(event, session)
        previous_recycle = state[:recycle_count]
        applied = case event["action"].to_s
        when "deal"
          apply_deal(state, event, actor, repository, history)
        when "play"
          apply_play(state, event, actor, repository, history)
        when "play_draw"
          apply_play_draw(state, event, actor, repository, history)
        when "draw"
          apply_draw(state, event, actor, repository, history)
        when "skip_draw"
          apply_skip_draw(state, event, actor, repository, history)
        when "no_cards"
          apply_no_cards(state, event, actor, repository, history)
        when "turn_timeout"
          apply_timeout(state, event, actor, repository, history, time)
        else
          false
        end
        if applied
          record_deck_reshuffle(history, previous_recycle, state[:recycle_count], event_id)
          # A standalone legacy play still owes a draw, with the same clock.
          GameRoomTurnClock.advance(state, time, running: state[:phase] == :playing) unless state[:phase] == :awaiting_draw
          accepted << original_event
          seen[event_id] = true
        end
      end
      GameRoomTurnClock.attach_session(state, session)
      Replay.new(
        board: nil,
        players: players,
        current_player: state[:current_player],
        winner: state[:winner],
        draw: false,
        accepted_events: accepted,
        history: compact_penalties(history),
        state: state
      )
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if state == nil || state[:winner] != nil
      return nil if !same_user?(actor, replay.players.first)
      return { "kind" => "command", "action" => "turn_timeout" } if ninety_deadline_reached?(state, context&.now)
      return nil if ![:awaiting_deal, :round_complete].include?(state[:phase])

      { "kind" => "command", "action" => "deal" }
    end

    def automatic_action_due?(replay, actor, context: nil)
      !replay.finished? && same_user?(actor, replay.players.first) && ninety_deadline_reached?(replay.state, context&.now)
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:winner] != nil
      return [] if !same_user?(state[:current_player], actor)
      return [] if ninety_deadline_reached?(state, context&.now)

      case state[:phase]
      when :playing
        hand = hand_for(state, actor).to_a
        return [{ "kind" => "command", "action" => "no_cards" }] if hand.empty?

        hand.flat_map { |card| card_play_actions(card, state[:total]) }
      when :awaiting_draw
        [{ "kind" => "command", "action" => "draw" }]
      else
        []
      end
    end

    def playable_card_navigation(replay, viewer)
      state = replay.state
      return nil if state == nil || state[:phase] != :playing
      return nil if !same_user?(state[:current_player], viewer)

      actions = legal_actions(replay, viewer).select do |action|
        action["kind"] == "card" && action["action"] == "select"
      end
      grouped = actions.group_by { |action| action["card"].to_s.split("|", 2).first }
      card_navigation_spec(
        hand_id: "hand",
        card_actions: grouped,
        automatic_card_ids: grouped.keys
      )
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?

      if selection["kind"].to_s == "command" && selection["action"].to_s == "deal"
        return [:not_your_turn, nil] if !same_user?(actor, replay.players.first)
        return [:invalid, nil] if ![:awaiting_deal, :round_complete].include?(state[:phase])
        return [:invalid, nil] if context == nil || context.random_source == nil

        round = state[:round].to_i + 1
        seed = random_seed(context.random_source)
        dealer = next_dealer_index(state, seed)
        return [:ok, timed_ninety_plan("deal", [round, dealer, seed].join("|"), state, context)]
      end

      if selection["action"].to_s == "turn_timeout"
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] unless ninety_deadline_reached?(state, context&.now)
        return [:ok, timed_ninety_plan("turn_timeout", state[:turn_deadline].to_s(36), state, context)]
      end
      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)
      return [:invalid, nil] if ninety_deadline_reached?(state, context&.now)

      action = selection["action"].to_s
      case state[:phase]
      when :playing
        if action == "no_cards"
          return [:invalid, nil] if !hand_for(state, actor).to_a.empty?
          return [:ok, timed_ninety_plan("no_cards", "", state, context)]
        end
        return [:invalid, nil] if selection["kind"].to_s != "card" || action != "select"

        card, mode = parse_play_choice(selection["card"])
        return [:card_not_in_hand, nil] if !hand_for(state, actor).to_a.include?(card)
        return [:invalid_card_choice, nil] if !valid_mode?(card, mode, state[:total])

        action = draw_expected_after_play?(state, actor, card, mode) ? "play_draw" : "play"
        [:ok, timed_ninety_plan(action, [card, mode].join("|"), state, context)]
      when :awaiting_draw
        return [:invalid, nil] if selection["kind"].to_s != "command"
        return [:ok, timed_ninety_plan("draw", "", state, context)] if action == "draw"
        [:invalid, nil]
      else
        [:invalid, nil]
      end
    rescue ArgumentError
      [:invalid_card_choice, nil]
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).to_a.empty?
    end

    def surface_spec(replay, viewer)
      state = replay.state
      cards = hand_for(state, viewer).to_a.sort_by { |card| card_sort_key(card) }.map do |card|
        item = card_surface_card(card, state[:total])
        item.sort_keys = standard_hand_sort_keys(rank: card_rank(card), suit: card_suit(card), position: hand_for(state, viewer).index(card))
        item
      end
      hand = GameSurfaces::CardTableSpec.new(
        zones: [
          GameSurfaces::CardZoneSpec.new(
            id: "hand",
            header: _("Your hand"),
            cards: cards,
            hand_order: hand_for(state, viewer).to_a.dup, hand_epoch: [viewer, state[:round]].join(":"),
            empty_label: _("Your hand is empty")
          )
        ]
      )
      commands = command_surface(state, viewer)
      return hand if commands == nil

      GameSurfaces::CompositeSpec.new(
        parts: [
          GameSurfaces::SurfacePart.new(id: "hand", surface: hand),
          GameSurfaces::SurfacePart.new(id: "actions", surface: commands)
        ]
      )
    end

    def shortcut_features
      super + [:hand, :current_total, :scores]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :hand
        { message: hand_text(state, viewer) }
      when :current_total
        { message: _("Pile: %{total}.") % { total: state[:total] } }
      when :scores
        { message: tokens_text(state, sorted: true) }
      else
        super
      end
    end

    def move_error(status)
      case status
      when :card_not_in_hand
        _("This card is not in your hand.")
      when :invalid_card_choice
        _("Choose one of the available values for this card.")
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = history_entries_for_display(replay, viewer).select { |entry| entry.event_id.to_i == event_id.to_i }
      entries.empty? ? nil : entries.map(&:text)
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      replay.history.map do |entry|
        if entry.kind == :timeout_penalty && same_user?(entry.actor, viewer)
          HistoryEntry.new(**entry.to_h.merge(text: _("You lose 1 token for running out of time.")))
        else
          entry
        end
      end
    end

    private

    def timed_ninety_plan(action, value, state, context)
      event_plan(action, GameRoomTurnClock.encode(state, value, context))
    end

    def ninety_deadline_reached?(state, now)
      [:playing, :awaiting_draw].include?(state[:phase]) && GameRoomTurnClock.expired?(state, now)
    end

    def apply_timeout(state, event, actor, repository, history, time)
      return false unless same_user?(actor, state[:players].first) && ninety_deadline_reached?(state, time)
      return false unless /\A[0-9a-z]+\z/.match?(event["value"].to_s) && event["value"].to_i(36) == state[:turn_deadline]
      player = state[:current_player]
      event_id = repository.event_id(event)
      charges = []
      charge_player(state, player, 1, event_id, charges, "")
      history << HistoryEntry.new(key: "timeout:#{event_id}",
        text: _("%{player} loses 1 token for running out of time.") % { player: participant_name(player) },
        event_id: event_id, actor: player, kind: :timeout_penalty, value: 1)
      history.concat(charges.reject { |entry| entry.kind == :penalty })
      if active_players(state).length <= 1
        finish_game(state, event_id, history)
      else
        next_player = state[:phase] == :awaiting_draw ? state[:pending_player] : next_active_player(state, player, 1)
        next_player = next_active_player(state, player, 1) if next_player == nil || state[:eliminated][next_player]
        # Old split play/draw events may owe a replacement card. Complete that
        # obligation, but never draw an extra card or choose a card to play.
        apply_draw(state, event, player, repository, history) if state[:phase] == :awaiting_draw && !state[:eliminated][player]
        state[:phase] = :playing
        state[:current_player] = next_player
        state[:pending_player] = nil
      end
      true
    end

    def initial_state(players, options)
      tokens = options["starting_tokens"].to_i
      {
        players: players,
        options: options,
        tokens: players.each_with_object({}) { |player, result| result[player] = tokens },
        eliminated: players.each_with_object({}) { |player, result| result[player] = false },
        round: 0,
        dealer_index: nil,
        direction: 1,
        phase: :awaiting_deal,
        current_player: nil,
        pending_player: nil,
        total: 0,
        seed: nil,
        recycle_count: 0,
        hands: players.each_with_object({}) { |player, result| result[player] = [] },
        draw_pile: [],
        discard: [],
        winner: nil
      }
    end

    def apply_deal(state, event, actor, repository, history)
      return false if !same_user?(actor, state[:players].first)
      return false if ![:awaiting_deal, :round_complete].include?(state[:phase])

      round, dealer, seed = parse_deal(event["value"])
      return false if round != state[:round] + 1
      return false if !dealer.between?(0, state[:players].length - 1)
      return false if state[:eliminated][state[:players][dealer]]
      if state[:dealer_index] != nil
        return false if dealer != next_active_index(state, state[:dealer_index], -1)
      end

      active = active_players(state)
      return false if active.length < 2
      deck = shuffled_deck(state[:players].length, seed)
      hands = state[:players].each_with_object({}) { |player, result| result[player] = [] }
      cursor = dealer
      (active.length * 3).times do
        cursor = next_active_index(state, cursor, 1)
        hands[state[:players][cursor]] << deck.shift
      end

      state[:round] = round
      state[:dealer_index] = dealer
      state[:direction] = 1
      state[:phase] = :playing
      state[:current_player] = state[:players][next_active_index(state, dealer, 1)]
      state[:pending_player] = nil
      state[:total] = 0
      state[:seed] = seed
      state[:recycle_count] = 0
      state[:hands] = hands
      state[:draw_pile] = deck
      state[:discard] = []
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "deal:#{round}",
        text: _("Round %{round} was dealt by %{dealer}. Pile: zero.") % {
          round: round,
          dealer: participant_name(state[:players][dealer])
        },
        event_id: event_id,
        actor: actor,
        kind: :deal
      )
      true
    rescue ArgumentError
      false
    end

    def apply_play(state, event, actor, repository, history)
      return false if state[:phase] != :playing
      return false if !same_user?(state[:current_player], actor)

      card, mode = parse_play_choice(event["value"])
      player = player_key(state, actor)
      hand = state[:hands][player]
      return false if !hand.include?(card) || !valid_mode?(card, mode, state[:total])

      old_total = state[:total]
      new_total = total_after_card(old_total, card, mode)
      hand.delete_at(hand.index(card))
      state[:discard] << card
      state[:total] = new_total
      state[:direction] *= -1 if card_rank(card) == "4" && active_players(state).length > 2
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "play:#{event_id}",
        text: _("%{player} played %{card}. Pile: %{total}.") % {
          player: participant_name(player),
          card: played_card_label(card, mode),
          total: new_total
        },
        event_id: event_id,
        actor: actor,
        kind: :play,
        value: new_total
      )

      crossed = [33, 66].select { |limit| old_total < limit && new_total > limit }
      crossed.each do |limit|
        charge_player(state, player, 1, event_id, history, _("crossing %{limit}") % { limit: limit })
      end

      if exact_danger_reached?(old_total, new_total, card)
        active_players(state).reject { |other| same_user?(other, player) }.each do |other|
          charge_player(state, other, 1, event_id, history, _("the pile reaching %{limit}") % { limit: new_total })
        end
      end

      if new_total == 99
        active_players(state).reject { |other| same_user?(other, player) }.each do |other|
          charge_player(state, other, 2, event_id, history, _("the pile reaching 99"))
        end
        history << HistoryEntry.new(
          key: "round_win:#{event_id}",
          text: _("%{player} won the round by reaching 99 exactly.") % { player: participant_name(player) },
          event_id: event_id,
          actor: player,
          kind: :round_result
        )
        finish_round(state, event_id, history)
      elsif new_total > 99
        charge_player(state, player, 2, event_id, history, _("exceeding 99"))
        history << HistoryEntry.new(
          key: "round_loss:#{event_id}",
          text: _("%{player} lost the round by exceeding 99.") % { player: participant_name(player) },
          event_id: event_id,
          actor: player,
          kind: :round_result
        )
        finish_round(state, event_id, history)
      elsif active_players(state).length <= 1
        finish_game(state, event_id, history)
      elsif state[:eliminated][player]
        state[:phase] = :playing
        state[:current_player] = next_active_player(state, player, 1)
        state[:pending_player] = nil
      else
        steps = card_rank(card) == "J" ? 2 : 1
        state[:pending_player] = next_active_player(state, player, steps)
        state[:phase] = :awaiting_draw
        state[:current_player] = player
      end
      true
    rescue ArgumentError
      false
    end

    def apply_draw(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_draw
      return false if !same_user?(state[:current_player], actor)

      player = player_key(state, actor)
      recycle_draw_pile(state) if state[:draw_pile].empty?
      return false if state[:draw_pile].empty?

      state[:hands][player] << state[:draw_pile].shift
      advance_after_draw(state)
      true
    end

    # A normal Ninety-Nine turn is persisted as one row, so playing a card and
    # drawing its replacement can never be split by a failed second request.
    # Apply the compound event to a private state first and commit it only when
    # both parts are valid.
    def apply_play_draw(state, event, actor, repository, history)
      next_state = Marshal.load(Marshal.dump(state))
      next_history = []
      return false if !apply_play(next_state, event, actor, repository, next_history)
      return false if !apply_draw(next_state, event, actor, repository, next_history)

      state.replace(next_state)
      history.concat(next_history)
      true
    rescue TypeError
      false
    end

    def apply_skip_draw(state, event, actor, repository, history)
      return false if state[:phase] != :awaiting_draw
      return false if !same_user?(state[:current_player], actor)

      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "skip_draw:#{event_id}",
        text: _("%{player} continued without drawing and now has %{count} cards.") % {
          player: participant_name(actor),
          count: hand_for(state, actor).length
        },
        event_id: event_id,
        actor: actor,
        kind: :skip_draw
      )
      advance_after_draw(state)
      true
    end

    def apply_no_cards(state, event, actor, repository, history)
      return false if state[:phase] != :playing
      return false if !same_user?(state[:current_player], actor)
      return false if !hand_for(state, actor).empty?

      player = player_key(state, actor)
      event_id = repository.event_id(event)
      charge_player(state, player, 3, event_id, history, _("starting a turn without cards"))
      history << HistoryEntry.new(
        key: "no_cards:#{event_id}",
        text: _("%{player} had no cards and lost the round.") % { player: participant_name(player) },
        event_id: event_id,
        actor: player,
        kind: :round_result
      )
      finish_round(state, event_id, history)
      true
    end

    def finish_round(state, event_id, history)
      if active_players(state).length <= 1
        finish_game(state, event_id, history)
      else
        state[:phase] = :round_complete
        state[:current_player] = nil
        state[:pending_player] = nil
      end
    end

    def finish_game(state, event_id, history)
      state[:winner] = active_players(state).first
      state[:phase] = :finished
      state[:current_player] = nil
      state[:pending_player] = nil
      history << result_history(event_id: event_id, winner: state[:winner]) if state[:winner] != nil
    end

    def charge_player(state, player, amount, event_id, history, reason)
      return if player == nil || state[:eliminated][player]

      available = state[:tokens][player].to_i
      if available >= amount.to_i
        state[:tokens][player] = available - amount.to_i
        history << HistoryEntry.new(
          key: "charge:#{event_id}:#{history.length}",
          text: penalty_text([player], amount),
          event_id: event_id,
          actor: player,
          kind: :penalty,
          value: amount
        )
      else
        state[:tokens][player] = 0
        state[:eliminated][player] = true
        history << HistoryEntry.new(
          key: "eliminate:#{event_id}:#{player}",
          text: _("%{player} was eliminated.") % { player: participant_name(player) },
          event_id: event_id,
          actor: player,
          kind: :elimination
        )
      end
    end

    # Preserve chronological event positions while announcing equal losses
    # together. Several thresholds in one play are one total loss per player.
    def compact_penalties(history)
      totals = {}
      history.each do |entry|
        next if entry.kind != :penalty

        key = [entry.event_id, entry.actor]
        totals[key] = totals.fetch(key, 0) + entry.value.to_i
      end
      groups = totals.group_by { |(event_id, _actor), amount| [event_id, amount] }
      emitted = {}
      history.filter_map do |entry|
        next entry if entry.kind != :penalty

        amount = totals.fetch([entry.event_id, entry.actor])
        key = [entry.event_id, amount]
        next if emitted[key]
        emitted[key] = true
        actors = groups.fetch(key).map { |(event_actor, _amount)| event_actor[1] }
        text = penalty_text(actors, amount)
        HistoryEntry.new(
          key: "charge:#{entry.event_id}:#{amount}", text: text,
          event_id: entry.event_id, actor: actors.length == 1 ? actors.first : "",
          kind: :penalty, value: amount
        )
      end
    end

    def advance_after_draw(state)
      state[:phase] = :playing
      state[:current_player] = state[:pending_player]
      state[:pending_player] = nil
    end

    def total_after_card(total, card, mode)
      case card_rank(card)
      when "2"
        total.even? && total > 49 ? total / 2 : total * 2
      when "9"
        total
      when "T"
        mode == "minus" ? [total - 10, 0].max : total + 10
      when "J", "Q", "K"
        total + 10
      when "A"
        total + (mode == "eleven" ? 11 : 1)
      else
        total + Integer(card_rank(card), 10)
      end
    end

    def exact_danger_reached?(old_total, new_total, _card)
      [33, 66].include?(new_total) && new_total > old_total
    end

    def draw_expected_after_play?(state, actor, card, mode)
      player = player_key(state, actor)
      return false if player == nil

      old_total = state[:total].to_i
      new_total = total_after_card(old_total, card, mode)
      tokens = state[:tokens].dup
      eliminated = state[:eliminated].dup
      charge = lambda do |target, amount|
        next if target == nil || eliminated[target]

        if tokens[target].to_i >= amount.to_i
          tokens[target] = tokens[target].to_i - amount.to_i
        else
          tokens[target] = 0
          eliminated[target] = true
        end
      end

      [33, 66].each do |limit|
        charge.call(player, 1) if old_total < limit && new_total > limit
      end
      if exact_danger_reached?(old_total, new_total, card)
        state[:players].each do |other|
          charge.call(other, 1) if !same_user?(other, player) && !eliminated[other]
        end
      end
      return false if new_total >= 99

      active = state[:players].reject { |candidate| eliminated[candidate] }
      active.length > 1 && !eliminated[player]
    end

    def card_play_actions(card, total)
      modes_for(card, total).map do |mode|
        choice = [card, mode].join("|")
        {
          "kind" => "card",
          "action" => "select",
          "zone" => "hand",
          "card" => choice,
          "card_id" => choice
        }
      end
    end

    def card_surface_card(card, total)
      modes = modes_for(card, total)
      choices = modes.map do |mode|
        choice = [card, mode].join("|")
        GameSurfaces::CardChoice.new(
          id: mode,
          label: mode_label(mode),
          value: choice
        )
      end
      GameSurfaces::Card.new(
        id: card,
        label: card_label(card),
        value: [card, modes.first].join("|"),
        choices: choices.length > 1 ? choices : nil
      )
    end

    def modes_for(card, total = nil)
      case card_rank(card)
      when "T"
        modes = ["plus"]
        modes << "minus" if total == nil || total.to_i >= 10
        modes
      when "A" then %w[one eleven]
      else ["normal"]
      end
    end

    def valid_mode?(card, mode, total = nil)
      modes_for(card, total).include?(mode.to_s)
    end

    def parse_play_choice(value)
      fields = value.to_s.split("|", -1)
      raise ArgumentError, "invalid card choice" if fields.length != 2
      raise ArgumentError, "invalid card" if !valid_card_id?(fields[0])

      fields
    end

    def command_surface(state, viewer)
      return nil if !same_user?(state[:current_player], viewer)

      commands = if state[:phase] == :awaiting_draw
        [GameSurfaces::Command.new(id: "draw", label: _("Draw a replacement card"), enabled: true)]
      elsif state[:phase] == :playing && hand_for(state, viewer).empty?
        [GameSurfaces::Command.new(id: "no_cards", label: _("End the round: no cards"), enabled: true)]
      else
        []
      end
      commands.empty? ? nil : GameSurfaces::CommandPanelSpec.new(commands: commands)
    end

    def hand_text(state, viewer)
      cards = hand_for(state, viewer).to_a.sort_by { |card| card_sort_key(card) }
      return _("Your hand is empty.") if cards.empty?

      _("Your hand: %{cards}.") % { cards: cards.map { |card| card_label(card) }.join("; ") }
    end

    def tokens_text(state, sorted: false)
      players = sorted ? score_announcement_order(state[:players], state[:tokens], eliminated: state[:eliminated]) : state[:players]
      values = players.map do |player|
        if state[:eliminated][player]
          _("%{player} eliminated") % { player: participant_name(player) }
        else
          _("%{player} %{count}") % { player: participant_name(player), count: state[:tokens][player] }
        end
      end
      values.join(", ") + "."
    end

    def penalty_text(actors, amount)
      names = actors.to_a.map { |actor| participant_name(actor) }
      players = if names.length <= 1
        names.first.to_s
      elsif names.length == 2
        _("%{first} and %{second}") % { first: names[0], second: names[1] }
      else
        _("%{others}, and %{last}") % { others: names[0...-1].join(", "), last: names[-1] }
      end
      singular, plural = if names.length == 1
        ["%{players} loses %{count} token.", "%{players} loses %{count} tokens."]
      else
        ["%{players} lose %{count} token.", "%{players} lose %{count} tokens."]
      end
      template = if respond_to?(:n_, true)
        n_(singular, plural, amount.to_i)
      else
        amount.to_i == 1 ? singular : plural
      end
      template % { players: players, count: amount.to_i }
    end

    def current_turn_shortcut_text(replay, viewer)
      state = replay.state
      return result_text(replay) || _("The game is finished.") if replay.finished?
      return _("Waiting for the next deal.") if [:awaiting_deal, :round_complete].include?(state[:phase])
      if state[:phase] == :awaiting_draw
        return same_user?(state[:current_player], viewer) ?
          _("Drawing a replacement card.") :
          _("%{player} must draw a replacement card.") % { player: participant_name(state[:current_player]) }
      end

      super
    end

    def next_dealer_index(state, seed)
      return seed.to_i(16) % state[:players].length if state[:dealer_index] == nil

      next_active_index(state, state[:dealer_index], -1)
    end

    def active_players(state)
      state[:players].reject { |player| state[:eliminated][player] }
    end

    def next_active_player(state, actor, steps)
      index = state[:players].index { |player| same_user?(player, actor) }
      return nil if index == nil

      steps.to_i.times { index = next_active_index(state, index, state[:direction]) }
      state[:players][index]
    end

    def next_active_index(state, index, direction)
      cursor = index.to_i
      state[:players].length.times do
        cursor = (cursor + direction.to_i) % state[:players].length
        return cursor if !state[:eliminated][state[:players][cursor]]
      end
      cursor
    end

    def hand_for(state, actor)
      player = player_key(state, actor)
      player == nil ? [] : state[:hands].fetch(player, [])
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def deck_for(player_count)
      copies = player_count.to_i >= 7 ? 2 : 1
      Array.new(copies) do |copy|
        SUITS.product(RANKS).map { |suit, rank| "#{copy}#{rank}#{suit}" }
      end.flatten
    end

    def shuffled_deck(player_count, seed)
      deck_for(player_count).sort_by { |card| Digest::SHA256.hexdigest("#{seed}\0#{card}") }
    end

    def recycle_draw_pile(state)
      return if state[:discard].length <= 1

      top = state[:discard].pop
      state[:recycle_count] += 1
      seed = "#{state[:seed]}:#{state[:recycle_count]}"
      state[:draw_pile] = state[:discard].sort_by do |card|
        Digest::SHA256.hexdigest("#{seed}\0#{card}")
      end
      state[:discard] = [top]
    end

    def parse_deal(value)
      GameRoomCardWire.parse_deal(value)
    end

    def random_seed(source)
      source.roll(count: 16, sides: 256).values.map do |value|
        (value.to_i - 1).to_s(16).rjust(2, "0")
      end.join
    end

    def valid_card_id?(card)
      card.to_s.match?(/\A[01][23456789TJQKA][CDHS]\z/)
    end

    def card_rank(card)
      card.to_s[1]
    end

    def card_suit(card)
      card.to_s[2]
    end

    def card_label(card)
      _("%{rank} of %{suit}") % {
        rank: RANK_NAMES.fetch(card_rank(card), card_rank(card)),
        suit: SUIT_NAMES.fetch(card_suit(card), card_suit(card))
      }
    end

    def played_card_label(card, mode)
      base = card_label(card)
      case mode.to_s
      when "plus" then _("%{card}, add 10") % { card: base }
      when "minus" then _("%{card}, subtract 10") % { card: base }
      when "one" then _("%{card}, add 1") % { card: base }
      when "eleven" then _("%{card}, add 11") % { card: base }
      else base
      end
    end

    def mode_label(mode)
      case mode.to_s
      when "plus" then _("Add 10")
      when "minus" then _("Subtract 10")
      when "one" then _("Add 1")
      when "eleven" then _("Add 11")
      else _("Play card")
      end
    end

    def card_sort_key(card)
      playroom_hand_sort_key(
        card,
        tie_breaker: card.to_s[0].to_i
      )
    end
  end
end

require_relative 'generated/rulebooks/ninety_nine'
