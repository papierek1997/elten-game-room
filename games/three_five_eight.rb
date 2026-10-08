require_relative "../lib/game_card_wire"
# encoding: UTF-8
require "digest"
require_relative "base"
require_relative "../lib/game_bots"
require_relative "../lib/participant_decision_events"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations

  # Polish tournament 3-5-8: three players, six contracts per player and
  # eighteen deals in total. The four-card kitty and the discarded cards are
  # reconstructed from the public deal seed, while only information intended
  # by the rules is announced to other players.
  class ThreeFiveEight < Base
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    SUITS = %w[H S D C].freeze
    CONTRACTS = %w[H S D C NT MISERE].freeze
    BOT_DECK = SUITS.flat_map { |suit| RANKS.map { |rank| "#{rank}#{suit}".freeze } }.freeze

    # Build the information set once per decision, not once per candidate.
    # No simulated deal or retained replay cache is needed by this policy.
    class BotStrategy < GameRoomBots::HeuristicStrategy
      def choose(game:, replay:, actor:, context: nil, **arguments)
        super(game: game, replay: replay, actor: actor,
          context: game.bot_decision_context(replay, actor), **arguments)
      end
    end
    SUIT_NAMES = {
      "C" => _("clubs"), "D" => _("diamonds"),
      "H" => _("hearts"), "S" => _("spades")
    }.freeze
    RANK_NAMES = {
      "T" => _("10"), "J" => _("jack"), "Q" => _("queen"),
      "K" => _("king"), "A" => _("ace")
    }.freeze

    def id
      "three_five_eight"
    end

    def notification_option_keys(_options); %w[card_exchange]; end
    def notification_variant(options)
      notification_flag(options, "card_exchange", _("with card exchange"), _("without card exchange")).to_s
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      cues = []
      cues << "shuffle" if action == "deal"
      # Own-turn dings belong to the shared, preference-aware presenter.
      cues << "draw" if %w[exchange return stop_exchange discard].include?(action)
      if action == "play"
        cues << "play"
        trump = after_replay&.state.to_h[:contract].to_s
        cues << "draw2" if %w[H S D C].include?(trump) && event["value"].to_s.end_with?(trump)
      end
      round_result = history.find do |entry|
        entry.kind == :round_result && GameRoomParticipants.same?(entry.actor, viewer)
      end
      if round_result
        change = round_result.value.to_i
        cues << "win1" if change > 0
        cues << "lose1" if change < 0
      end
      cues
    end

    def restored_event_value(event, controller_mapping)
      return super if event["action"] != "exchange"

      target, card = event["value"].split("|", 2)
      "#{controller_mapping.fetch(target.downcase)}|#{card}"
    end

    def name
      _("3-5-8")
    end

    def short_description
      _("A card game for three players, each with a different target, where a good result gives you an advantage in the next deal.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      3
    end

    def maximum_players
      3
    end

    def supports_bots?
      true
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "card_exchange",
          label: _("Card exchange between players"),
          kind: :boolean,
          default: true
        )
      ]
    end

    def bot_strategy
      @bot_strategy ||= BotStrategy.new
    end

    def perfect_information?
      false
    end

    def options_summary(options)
      values = normalize_options(options)
      exchange = values["card_exchange"] ? _("card exchange enabled") : _("card exchange disabled")
      _("%{exchange}; 18 deals") % { exchange: exchange }
    end

    def bot_observation(replay, actor)
      state = replay.state
      player = player_key(state, actor)
      {
        "players" => state[:players], "phase" => state[:phase].to_s,
        "current_player" => state[:current_player], "round" => state[:round],
        "dealer" => state[:dealer_index], "contract" => state[:contract],
        "scores" => state[:scores], "round_deltas" => state[:previous_deltas],
        "tricks" => state[:tricks], "current_trick" => state[:current_trick],
        "hand" => player == nil ? [] : state[:hands].fetch(player, []),
        "used_contracts" => player == nil ? [] : state[:used_contracts].fetch(player, []),
        "winner" => state[:winner], "draw" => state[:draw]
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      information = context.is_a?(Hash) && context.key?(:unseen_cards) ? context : bot_decision_context(replay, actor)
      hand = information[:hand]
      case action["action"].to_s
      when "choose_contract"
        contract_score(hand, action["contract"].to_s)
      when "exchange"
        bot_exchange_score(state, action["card"].to_s, action["target"].to_s, information)
      when "return", "discard"
        remaining = hand - [action["card"].to_s]
        state[:contract] == "MISERE" ? -bot_misere_risk(remaining) : bot_hand_value(remaining, state[:contract])
      when "stop_exchange"
        0.0
      when "play"
        card = action["card"].to_s
        probability = bot_trick_probability(state, actor, card, information)
        remaining = hand - [card]
        if state[:contract] == "MISERE"
          -1_000.0 * probability - 20.0 * bot_misere_risk(remaining) + card_strength(card) * 0.001
        else
          # Ordinary scoring rewards every trick, including overtricks.
          1_000.0 * probability + 20.0 * bot_hand_value(remaining, state[:contract]) - card_strength(card) * 0.001
        end
      else
        0.0
      end
    end

    def bot_decision_context(replay, actor)
      state = replay.state
      hand = hand_for(state, actor).to_a
      plays = []
      own_discards = []
      # The decision projection uses current occupants, while the accepted
      # event log and its historical authors remain immutable.
      events = GameRoomParticipantDecisionEvents.for(replay).to_a
      events.reverse_each do |event|
        break if event["action"] == "deal"
        if event["action"] == "play"
          plays << {player: player_key(state, event["actor"]), card: event["value"].to_s}
        elsif event["action"] == "discard" && same_user?(event["actor"], actor)
          own_discards << event["value"].to_s
        end
      end
      plays.reverse!
      voids = state[:players].to_h { |player| [player, []] }
      plays.each_slice(3) { |trick| bot_record_voids(trick, voids) }
      bot_record_voids(state[:current_trick], voids)
      played = (plays + state[:current_trick]).map { |play| play[:card] }.uniq
      unseen = BOT_DECK - hand - played - own_discards
      pools = state[:players].reject { |player| same_user?(player, actor) }.to_h do |player|
        [player, unseen.reject { |card| voids[player].include?(card_suit(card)) }]
      end
      {hand: hand, unseen_cards: unseen, void_suits: voids, opponent_pools: pools,
        opponent_suits: pools.transform_values { |cards| cards.group_by { |card| card_suit(card) } },
        exchange_bounds: bot_exchange_bounds(state, actor, hand, events)}
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]
      events.each do |event|
        break if state[:phase] == :finished

        actor = repository.actor_of(event, session)
        applied = case event["action"].to_s
        when "deal" then apply_deal(state, event, actor, repository, history)
        when "choose_contract" then apply_choose_contract(state, event, actor, repository, history)
        when "exchange" then apply_exchange(state, event, actor, repository, history)
        when "return" then apply_exchange_return(state, event, actor, repository, history)
        when "stop_exchange" then apply_stop_exchange(state, event, actor, repository, history)
        when "discard" then apply_discard(state, event, actor, repository, history)
        when "play" then apply_play(state, event, actor, repository, history)
        else false
        end
        accepted << event if applied
      end
      Replay.new(
        board: nil, players: players, current_player: state[:current_player],
        winner: state[:winner], draw: state[:draw], accepted_events: accepted,
        history: history, state: state
      )
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if state == nil || state[:phase] == :finished
      return nil if !same_user?(actor, replay.players.first)
      return nil if ![:awaiting_deal, :round_complete].include?(state[:phase])
      return nil if context == nil || context.random_source == nil

      seed = random_seed(context.random_source)
      round = state[:round].to_i + 1
      dealer = state[:dealer_index] == nil ? seed.to_i(16) % 3 : (state[:dealer_index] + 1) % 3
      { "kind" => "command", "action" => "deal", "round" => round, "dealer" => dealer, "seed" => seed }
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:phase] == :finished
      if [:awaiting_deal, :round_complete].include?(state[:phase])
        return [] if !same_user?(actor, replay.players.first)
        return [{ "kind" => "command", "action" => "deal" }]
      end
      return [] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :choosing_contract
        available_contracts(state, actor).map do |contract|
          { "kind" => "command", "action" => "choose_contract", "contract" => contract }
        end
      when :exchanging
        actions = eligible_exchange_targets(state, actor).flat_map do |target|
          hand_for(state, actor).to_a.map do |card|
            { "kind" => "card", "action" => "exchange", "card" => card, "card_id" => card, "target" => target }
          end
        end
        actions << { "kind" => "command", "action" => "stop_exchange" }
        actions
      when :exchange_return
        exchange_return_cards(state, actor).map do |card|
          { "kind" => "card", "action" => "return", "card" => card, "card_id" => card }
        end
      when :discarding
        hand_for(state, actor).to_a.map do |card|
          { "kind" => "card", "action" => "discard", "card" => card, "card_id" => card }
        end
      when :playing
        legal_cards(state, actor).map do |card|
          { "kind" => "card", "action" => "play", "card" => card, "card_id" => card }
        end
      else
        []
      end
    end

    def playable_card_navigation(replay, viewer)
      return nil if replay.state[:phase] != :playing || !same_user?(replay.current_player, viewer)

      actions = legal_actions(replay, viewer).select { |action| action["action"] == "play" }
      grouped = actions.group_by { |action| action["card_id"].to_s }
      card_navigation_spec(hand_id: "hand", card_actions: grouped, automatic_card_ids: grouped.keys)
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?

      if selection["action"].to_s == "deal"
        return [:not_your_turn, nil] if !same_user?(actor, replay.players.first)
        return [:invalid, nil] if ![:awaiting_deal, :round_complete].include?(state[:phase])
        if selection["seed"].to_s.empty?
          return [:invalid, nil] if context == nil || context.random_source == nil
          generated = automatic_action(replay, actor, context: context)
          return action_for(generated, replay, actor, context: context)
        end
        value = [selection["round"], selection["dealer"], selection["seed"]].join("|")
        return [:ok, event_plan("deal", value)]
      end

      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)
      embedded = selection["card"] if selection["card"].respond_to?(:key?)
      action = (embedded && embedded["action"] || selection["action"]).to_s
      case state[:phase]
      when :choosing_contract
        contract = selection["contract"].to_s
        return [:invalid_contract, nil] if !action.start_with?("choose_contract") || !available_contracts(state, actor).include?(contract)
        [:ok, event_plan("choose_contract", contract)]
      when :exchanging
        return [:ok, event_plan("stop_exchange", "")] if action == "stop_exchange"
        card = selected_card(selection)
        target = (embedded && embedded["target"] || selection["target"]).to_s
        valid = legal_actions(replay, actor).any? do |candidate|
          candidate["action"] == "exchange" && candidate["card"] == card && same_user?(candidate["target"], target)
        end
        return [:invalid_exchange, nil] if !valid
        [:ok, event_plan("exchange", [target, card].join("|"))]
      when :exchange_return
        card = selected_card(selection)
        return [:invalid_exchange, nil] if action != "return" || !exchange_return_cards(state, actor).include?(card)
        [:ok, event_plan("return", card)]
      when :discarding
        card = selected_card(selection)
        return [:card_not_in_hand, nil] if action != "discard" || !hand_for(state, actor).to_a.include?(card)
        [:ok, event_plan("discard", card)]
      when :playing
        card = selected_card(selection)
        return [:card_not_in_hand, nil] if action != "play" || !hand_for(state, actor).to_a.include?(card)
        return [:must_follow_rules, nil] if !legal_cards(state, actor).include?(card)
        [:ok, event_plan("play", card)]
      else
        [:invalid, nil]
      end
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).to_a.empty?
    end

    def surface_spec(replay, viewer)
      state = replay.state
      cards = hand_for(state, viewer).to_a.sort_by { |card| card_sort_key(card) }
      actions = same_user?(state[:current_player], viewer) ? legal_actions(replay, viewer) : []
      cards = cards.map do |card|
        card_actions = actions.select { |action| action["card_id"].to_s == card }
        choices = card_actions.select { |action| action["action"] == "exchange" }.map do |action|
          label = case action["action"]
          when "exchange" then _("Exchange with %{player}") % { player: participant_name(action["target"]) }
          else nil
          end
          GameSurfaces::CardChoice.new(id: action["action"] == "exchange" ? "exchange:#{action['target']}" : action["action"], label: label, value: action) if label
        end.compact
        value = if state[:phase] == :playing
          { "action" => "play", "card" => card }
        elsif state[:phase] == :discarding
          { "action" => "discard", "card" => card }
        elsif state[:phase] == :exchange_return
          { "action" => "return", "card" => card }
        else
          card
        end
        GameSurfaces::Card.new(
          id: card, label: card_label(card), value: value,
          choices: choices.empty? ? nil : choices,
          sort_keys: standard_hand_sort_keys(rank: card_rank(card), suit: card_suit(card), position: hand_for(state, viewer).to_a.index(card))
        )
      end
      hand = GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(
        id: "hand", header: hand_header(state, viewer), cards: cards,
        empty_label: _("Your hand is empty"), hand_order: hand_for(state, viewer).to_a.dup,
        hand_epoch: [viewer, state[:round]].join(":")
      )])
      commands = command_surface(state, replay, viewer)
      return hand if commands == nil

      GameSurfaces::CompositeSpec.new(parts: [
        GameSurfaces::SurfacePart.new(id: "cards", surface: hand),
        GameSurfaces::SurfacePart.new(id: "commands", surface: commands)
      ])
    end

    def move_error(status)
      case status
      when :invalid_contract then _("This contract is not available to you.")
      when :invalid_exchange then _("This card exchange is not available.")
      when :card_not_in_hand then _("This card is not in your hand.")
      when :must_follow_rules then _("You must follow suit when you have a card of the led suit.")
      else super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event).to_i
      replay.history.select { |entry| entry.event_id.to_i == event_id }.map(&:text)
    end

    def participant_scores(replay)
      replay.state[:scores].dup
    end

    def result_text(replay)
      winners = replay.state[:winners].to_a
      return nil if winners.empty?
      if winners.length == 1
        _("%{winner} won the game.") % { winner: participant_name(winners.first) }
      else
        _("The game ended in a draw between %{players}.") % { players: winners.map { |player| participant_name(player) }.join(", ") }
      end
    end

    def shortcut_features
      [:turn, :scores, :hand, :table_cards, :table_cards_list, :round_summary]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :scores then { message: scores_text(state) }
      when :hand then { message: hand_text(state, viewer) }
      when :table_cards then { message: table_cards_text(state) }
      when :table_cards_list then table_cards_browse_data(state)
      when :round_summary then { message: round_text(state) }
      else super
      end
    end

    def custom_game_shortcuts(replay, _viewer)
      [announcement_shortcut(key: "f", label: _("read the current contract and trump suit"), message: contract_text(replay.state))]
    end

    private

    def initial_state(players, options)
      {
        players: players, options: options, round: 0, phase: :awaiting_deal,
        dealer_index: nil, chooser: nil, contract: nil, seed: nil,
        hands: players.each_with_object({}) { |player, result| result[player] = [] },
        complete_hands: {}, kitty: [], discards: [], current_trick: [],
        tricks: players.each_with_object({}) { |player, result| result[player] = 0 },
        targets: {}, scores: players.each_with_object({}) { |player, result| result[player] = 0 },
        previous_deltas: players.each_with_object({}) { |player, result| result[player] = 0 },
        used_contracts: players.each_with_object({}) { |player, result| result[player] = [] },
        exchange_queue: [], exchange_limits: {}, exchange_used: {}, exchange_targets: {},
        pending_exchange: nil, current_player: nil, winner: nil, winners: [], draw: false
      }
    end

    def apply_deal(state, event, actor, repository, history)
      return false if !same_user?(actor, state[:players].first)
      return false if ![:awaiting_deal, :round_complete].include?(state[:phase])
      round, dealer, seed = parse_deal(event["value"])
      return false if round != state[:round] + 1 || !dealer.between?(0, 2)
      return false if state[:dealer_index] != nil && dealer != (state[:dealer_index] + 1) % 3

      complete, kitty = deal_cards(state[:players], dealer, seed)
      state[:round] = round
      state[:dealer_index] = dealer
      state[:chooser] = state[:players][(dealer + 1) % 3]
      state[:seed] = seed
      state[:phase] = :choosing_contract
      state[:contract] = nil
      state[:complete_hands] = complete
      state[:hands] = complete.transform_values { |hand| hand.first(6) }
      state[:kitty] = kitty
      state[:discards] = []
      state[:current_trick] = []
      state[:tricks] = state[:players].each_with_object({}) { |player, result| result[player] = 0 }
      state[:targets] = ordinary_targets(state)
      state[:exchange_queue] = []
      state[:pending_exchange] = nil
      state[:current_player] = state[:chooser]
      history << HistoryEntry.new(
        key: "deal:#{round}",
        text: _("Deal %{round} of 18. %{dealer} deals; %{chooser} chooses the contract from the first six cards.") % {
          round: round, dealer: participant_name(state[:players][dealer]), chooser: participant_name(state[:chooser])
        },
        event_id: repository.event_id(event), actor: actor, kind: :deal
      )
      true
    rescue ArgumentError
      false
    end

    def apply_choose_contract(state, event, actor, repository, history)
      return false if state[:phase] != :choosing_contract || !same_user?(actor, state[:chooser])
      contract = event["value"].to_s
      return false if !available_contracts(state, actor).include?(contract)

      player = player_key(state, actor)
      state[:contract] = contract
      state[:used_contracts][player] << contract
      state[:hands] = state[:complete_hands].transform_values(&:dup)
      state[:complete_hands] = {}
      state[:targets] = contract == "MISERE" ? misere_targets(state) : ordinary_targets(state)
      history << HistoryEntry.new(
        key: "contract:#{state[:round]}",
        text: _("%{player} chose %{contract}.") % { player: participant_name(player), contract: contract_label(contract) },
        event_id: repository.event_id(event), actor: actor, kind: :contract, value: contract
      )
      if state[:options]["card_exchange"] && trump_contract?(contract) && state[:round] > 1
        prepare_exchange(state, repository.event_id(event), history)
      else
        begin_kitty(state, repository.event_id(event), history)
      end
      true
    end

    def apply_exchange(state, event, actor, repository, history)
      return false if state[:phase] != :exchanging || !same_user?(actor, state[:current_player])
      target, card = event["value"].to_s.split("|", 2)
      giver = player_key(state, actor)
      target = player_key(state, target)
      return false if target == nil || !eligible_exchange_targets(state, giver).include?(target)
      hand = state[:hands][giver]
      return false if !hand.include?(card)

      hand.delete_at(hand.index(card))
      state[:hands][target] << card
      if card_suit(card) == state[:contract]
        state[:pending_exchange] = { giver: giver, target: target, card: card }
        state[:phase] = :exchange_return
        state[:current_player] = target
        history << HistoryEntry.new(
          key: "exchange_offer:#{repository.event_id(event)}",
          text: _("%{giver} gave a trump card to %{target}; %{target} chooses the return card.") % {
            giver: participant_name(giver), target: participant_name(target)
          }, event_id: repository.event_id(event), actor: actor, kind: :exchange
        )
      else
        returned = highest_card_of_suit(state[:hands][target], card_suit(card))
        finish_exchange_card(state, giver, target, returned)
        history << HistoryEntry.new(
          key: "exchange:#{repository.event_id(event)}",
          text: _("%{giver} exchanged one card with %{target}.") % {
            giver: participant_name(giver), target: participant_name(target)
          }, event_id: repository.event_id(event), actor: actor, kind: :exchange
        )
        continue_or_advance_exchange(state, repository.event_id(event), history)
      end
      true
    end

    def apply_exchange_return(state, event, actor, repository, history)
      pending = state[:pending_exchange]
      return false if state[:phase] != :exchange_return || pending == nil
      return false if !same_user?(actor, pending[:target])
      card = event["value"].to_s
      return false if !exchange_return_cards(state, actor).include?(card)

      finish_exchange_card(state, pending[:giver], pending[:target], card)
      state[:pending_exchange] = nil
      state[:phase] = :exchanging
      state[:current_player] = pending[:giver]
      history << HistoryEntry.new(
        key: "exchange:#{repository.event_id(event)}",
        text: _("%{giver} completed an exchange with %{target}.") % {
          giver: participant_name(pending[:giver]), target: participant_name(pending[:target])
        }, event_id: repository.event_id(event), actor: actor, kind: :exchange
      )
      continue_or_advance_exchange(state, repository.event_id(event), history)
      true
    end

    def apply_stop_exchange(state, event, actor, repository, history)
      return false if state[:phase] != :exchanging || !same_user?(actor, state[:current_player])
      history << HistoryEntry.new(
        key: "exchange_done:#{repository.event_id(event)}", text: _("%{player} finished exchanging cards.") % { player: participant_name(actor) },
        event_id: repository.event_id(event), actor: actor, kind: :exchange
      )
      advance_exchange_actor(state, repository.event_id(event), history)
      true
    end

    def apply_discard(state, event, actor, repository, history)
      return false if state[:phase] != :discarding || !same_user?(actor, state[:chooser])
      card = event["value"].to_s
      hand = hand_for(state, actor)
      return false if hand == nil || !hand.include?(card) || state[:discards].length >= 4

      hand.delete_at(hand.index(card))
      state[:discards] << card
      history << HistoryEntry.new(
        key: "discard:#{repository.event_id(event)}",
        text: _("%{player} discarded a card to the kitty (%{count} of 4).") % {
          player: participant_name(actor), count: state[:discards].length
        }, event_id: repository.event_id(event), actor: actor, kind: :discard
      )
      if state[:discards].length == 4
        state[:phase] = :playing
        state[:current_player] = state[:chooser]
      end
      true
    end

    def apply_play(state, event, actor, repository, history)
      return false if state[:phase] != :playing || !same_user?(actor, state[:current_player])
      card = event["value"].to_s
      hand = hand_for(state, actor)
      return false if hand == nil || !hand.include?(card) || !legal_cards(state, actor).include?(card)

      hand.delete_at(hand.index(card))
      state[:current_trick] << { player: player_key(state, actor), card: card }
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "play:#{event_id}", text: _("%{player} played %{card}.") % { player: participant_name(actor), card: card_label(card) },
        event_id: event_id, actor: actor, kind: :play, value: card
      )
      if state[:current_trick].length == 3
        winner = trick_winner(state[:current_trick], trump_suit(state))
        state[:tricks][winner] += 1
        history << HistoryEntry.new(
          key: "trick:#{event_id}", text: _("%{player} won the trick.") % { player: participant_name(winner) },
          event_id: event_id, actor: winner, kind: :trick
        )
        state[:current_trick] = []
        if state[:hands].values.all?(&:empty?)
          complete_round(state, event_id, history)
        else
          state[:current_player] = winner
        end
      else
        state[:current_player] = next_player(state[:players], actor)
      end
      true
    end

    def complete_round(state, event_id, history)
      deltas = state[:players].each_with_object({}) do |player, result|
        tricks = state[:tricks][player].to_i
        target = state[:targets][player].to_i
        result[player] = round_delta(state, tricks, target)
      end
      state[:previous_deltas] = deltas
      deltas.each do |player, delta|
        state[:scores][player] += delta
        history << HistoryEntry.new(
          key: "score:#{state[:round]}:#{player}",
          text: _("%{player}: tricks won %{tricks}, target %{target}, points this deal %{points}, total score %{score}.") % {
            player: participant_name(player), tricks: state[:tricks][player], target: state[:targets][player],
            points: signed_number(delta), score: state[:scores][player]
          }, event_id: event_id, actor: player, kind: :round_result, value: delta
        )
      end
      if state[:round] >= 18
        best = state[:scores].values.max
        state[:winners] = state[:players].select { |player| state[:scores][player] == best }
        state[:winner] = state[:winners].first if state[:winners].length == 1
        state[:draw] = state[:winners].length > 1
        state[:phase] = :finished
        state[:current_player] = nil
        history << HistoryEntry.new(
          key: "result:#{event_id}", text: result_text(Replay.new(state: state, winner: state[:winner], draw: state[:draw])),
          event_id: event_id, actor: state[:winner].to_s, kind: :result
        )
      else
        state[:phase] = :round_complete
        state[:current_player] = nil
      end
    end

    def prepare_exchange(state, event_id, history)
      positives = state[:players].select { |player| state[:previous_deltas][player].to_i > 0 }
      negatives = state[:players].select { |player| state[:previous_deltas][player].to_i < 0 }
      positives.sort_by! { |player| [-state[:targets][player].to_i, state[:players].index(player)] }
      state[:exchange_queue] = positives
      state[:exchange_limits] = positives.each_with_object({}) { |player, result| result[player] = state[:previous_deltas][player].to_i }
      state[:exchange_used] = positives.each_with_object({}) { |player, result| result[player] = 0 }
      state[:exchange_targets] = negatives.each_with_object({}) { |player, result| result[player] = -state[:previous_deltas][player].to_i }
      state[:pending_exchange] = nil
      if positives.empty? || negatives.empty?
        begin_kitty(state, event_id, history)
      else
        state[:phase] = :exchanging
        state[:current_player] = positives.first
      end
    end

    def continue_or_advance_exchange(state, event_id, history)
      actor = state[:current_player]
      if state[:exchange_used][actor].to_i >= state[:exchange_limits][actor].to_i || eligible_exchange_targets(state, actor).empty?
        advance_exchange_actor(state, event_id, history)
      end
    end

    def advance_exchange_actor(state, event_id, history)
      current = state[:current_player]
      index = state[:exchange_queue].index { |player| same_user?(player, current) }
      candidate = index == nil ? nil : state[:exchange_queue][index + 1]
      candidate = nil if candidate != nil && eligible_exchange_targets(state, candidate).empty?
      if candidate == nil
        begin_kitty(state, event_id, history)
      else
        state[:phase] = :exchanging
        state[:current_player] = candidate
      end
    end

    def finish_exchange_card(state, giver, target, returned)
      target_hand = state[:hands][target]
      target_hand.delete_at(target_hand.index(returned))
      state[:hands][giver] << returned
      state[:exchange_used][giver] = state[:exchange_used][giver].to_i + 1
      state[:exchange_targets][target] = state[:exchange_targets][target].to_i - 1
    end

    def begin_kitty(state, event_id, history)
      chooser = state[:chooser]
      state[:hands][chooser].concat(state[:kitty])
      state[:phase] = :discarding
      state[:current_player] = chooser
      return if history == nil

      history << HistoryEntry.new(
        key: "kitty:#{state[:round]}",
        text: _("The kitty is %{cards}.") % { cards: state[:kitty].map { |card| card_label(card) }.join(", ") },
        event_id: event_id, actor: chooser, kind: :kitty
      )
    end

    def eligible_exchange_targets(state, actor)
      return [] if state[:exchange_used][actor].to_i >= state[:exchange_limits][actor].to_i
      state[:players].select { |player| state[:exchange_targets][player].to_i > 0 }
    end

    def exchange_return_cards(state, actor)
      pending = state[:pending_exchange]
      return [] if pending == nil || !same_user?(pending[:target], actor)
      hand = hand_for(state, actor).to_a
      trump = state[:contract]
      highest_trump = highest_card_of_suit(hand, trump)
      hand.select { |card| card_suit(card) != trump || card == highest_trump }
    end

    def highest_card_of_suit(hand, suit)
      hand.select { |card| card_suit(card) == suit }.max_by { |card| RANKS.index(card_rank(card)).to_i }
    end

    def available_contracts(state, actor)
      player = player_key(state, actor)
      return [] if player == nil
      CONTRACTS - state[:used_contracts].fetch(player, [])
    end

    def ordinary_targets(state)
      dealer = state[:dealer_index]
      {
        state[:players][dealer] => 3,
        state[:players][(dealer + 2) % 3] => 5,
        state[:players][(dealer + 1) % 3] => 8
      }
    end

    def misere_targets(state)
      dealer = state[:dealer_index]
      {
        state[:players][dealer] => 8,
        state[:players][(dealer + 2) % 3] => 5,
        state[:players][(dealer + 1) % 3] => 3
      }
    end

    def legal_cards(state, actor)
      return [] if state[:phase] != :playing || !same_user?(state[:current_player], actor)
      hand = hand_for(state, actor).to_a
      return hand if state[:current_trick].empty?

      led = card_suit(state[:current_trick].first[:card])
      following = hand.select { |card| card_suit(card) == led }
      following.empty? ? hand : following
    end

    def round_delta(state, tricks, target)
      state[:contract].to_s == "MISERE" ? target.to_i - tricks.to_i : tricks.to_i - target.to_i
    end

    def trick_winner(trick, trump)
      led = card_suit(trick.first[:card])
      candidates = trump == nil ? [] : trick.select { |play| card_suit(play[:card]) == trump }
      candidates = trick.select { |play| card_suit(play[:card]) == led } if candidates.empty?
      candidates.max_by { |play| card_strength(play[:card]) }[:player]
    end

    def projected_trick_winner(state, actor, card)
      trick_winner(state[:current_trick] + [{ player: player_key(state, actor), card: card }], trump_suit(state))
    end

    def contract_score(hand, contract)
      # All contracts use estimated trick margins, not unrelated rank sums
      # with a large MISERE offset. Only the visible first six cards count;
      # unseen cards use the same neutral one-third baseline. The one-trick
      # kitty allowance is deliberately an estimate, not a peek at the deal.
      unknown = (16 - hand.length) / 3.0
      if contract == "MISERE"
        return 3.0 - [bot_misere_risk(hand) + unknown - 1.0, 0.0].max
      end

      strength = hand.sum { |card| bot_card_value(card, contract) }
      if trump_contract?(contract)
        length = hand.count { |card| card_suit(card) == contract }
        strength += (length - hand.length / 4.0) * 0.15
      end
      strength + unknown + 1.0 - 8.0
    end

    def bot_card_value(card, contract)
      strength = (card_strength(card) / 12.0)**2
      return strength if !trump_contract?(contract)

      card_suit(card) == contract ? 0.4 + strength * 0.6 : strength * 0.8
    end

    def bot_hand_value(hand, contract)
      value = hand.sum { |card| bot_card_value(card, contract) }
      suits = hand.group_by { |card| card_suit(card) }
      if trump_contract?(contract) && suits.fetch(contract, []).any?
        # Shortening a weak side suit creates future ruffing opportunities;
        # it is not a reason to throw away a side ace or a useful trump.
        value += (SUITS - [contract]).sum do |suit|
          length = suits.fetch(suit, []).length
          length == 0 ? 0.4 : (length == 1 ? 0.05 : 0.0)
        end
      elsif contract == "NT"
        value += suits.values.sum do |cards|
          cards.any? { |card| card_strength(card) >= 9 } ? [cards.length - 3, 0].max * 0.05 : 0.0
        end
      end
      value
    end

    def bot_misere_risk(hand)
      hand.group_by { |card| card_suit(card) }.values.sum do |cards|
        cards.sum do |card|
          rank = card_strength(card)
          escapes = cards.count { |other| card_strength(other) < rank && card_strength(other) <= 3 }
          # Low cards in the same suit protect a high card. An isolated high
          # card has no such escape; voiding that suit removes its risk.
          (rank / 12.0)**2 * (cards.length == 1 ? 1.35 : 1.0) / (1.0 + escapes * 1.5)
        end
      end
    end

    def bot_exchange_bounds(state, actor, hand, events)
      bounds = {}
      return bounds unless state[:phase] == :exchanging

      changed_suits = []
      events.reverse_each do |event|
        break unless event["action"] == "exchange" && same_user?(event["actor"], actor)

        target, card = event["value"].to_s.split("|", 2)
        suit = card_suit(card)
        break if suit == state[:contract]
        next if changed_suits.include?(suit)

        if hand.include?(card)
          # During this uninterrupted run of our non-trump offers, a card
          # still in our hand was returned unchanged. The recipient has no
          # higher card of that suit. A successful later exchange makes the
          # earlier hand unknown, so stop inferring for that suit only.
          entry = (bounds[player_key(state, target)] ||= {})
          entry[suit] = [entry.fetch(suit, 12), card_strength(card)].min
        else
          changed_suits << suit
        end
      end
      bounds
    end

    def bot_exchange_score(state, card, target, information)
      # Offering a trump gives the recipient a free choice of side card.
      # A voluntary exchange should instead force a useful rank upgrade.
      return -1.0 if card_suit(card) == state[:contract]

      bound = information[:exchange_bounds].fetch(player_key(state, target), {}).fetch(card_suit(card), 12)
      candidates = information[:unseen_cards].select do |other|
        card_suit(other) == card_suit(card) && card_strength(other) > card_strength(card) && card_strength(other) <= bound
      end.sort_by { |other| -card_strength(other) }
      ownership = 16.0 / [information[:unseen_cards].length, 16].max
      remaining_probability = 1.0
      gain = candidates.sum do |other|
        probability = remaining_probability * ownership
        remaining_probability *= 1.0 - ownership
        probability * (bot_card_value(other, state[:contract]) - bot_card_value(card, state[:contract]))
      end
      gain - 0.000_001
    end

    def bot_record_voids(trick, voids)
      return if trick.empty?

      led = card_suit(trick.first[:card])
      trick.drop(1).each do |play|
        next if card_suit(play[:card]) == led || !voids.key?(play[:player])

        # Following suit is compulsory, but trumping and beating are not.
        voids[play[:player]] << led unless voids[play[:player]].include?(led)
      end
    end

    def bot_trick_probability(state, actor, card, information)
      return 0.0 unless same_user?(projected_trick_winner(state, actor, card), actor)

      led = state[:current_trick].empty? ? card_suit(card) : card_suit(state[:current_trick].first[:card])
      trump = trump_suit(state)
      index = state[:players].index { |player| same_user?(player, actor) }
      remaining = state[:players].rotate(index + 1).first(2 - state[:current_trick].length)
      remaining.reduce(1.0) do |probability, player|
        pool = information[:opponent_pools].fetch(player)
        counts = information[:opponent_suits].fetch(player)
        led_cards = counts.fetch(led, [])
        hand_size = [information[:hand].length, pool.length].min
        none = ->(number) { bot_none_probability(pool.length, number, hand_size) }
        beaten = if state[:contract] == "MISERE"
          lower = led_cards.count { |other| card_strength(other) < card_strength(card) }
          # Opponents avoid tricks too: only a forced higher follower takes
          # this trick away. Being able to beat is not enough in MISERE.
          none.call(lower) - none.call(led_cards.length)
        elsif card_suit(card) == trump
          higher = counts.fetch(trump, []).count { |other| card_strength(other) > card_strength(card) }
          led == trump ? 1.0 - none.call(higher) : none.call(led_cards.length) - none.call(led_cards.length + higher)
        else
          higher = led_cards.count { |other| card_strength(other) > card_strength(card) }
          trumps = trump == nil ? 0 : counts.fetch(trump, []).length
          1.0 - none.call(higher) + none.call(led_cards.length) - none.call(led_cards.length + trumps)
        end
        probability * (1.0 - beaten.clamp(0.0, 1.0))
      end
    end

    def bot_none_probability(total, matching, count)
      return 1.0 if matching == 0 || count == 0
      return 0.0 if total - matching < count

      count.times.reduce(1.0) { |probability, index| probability * (total - matching - index) / (total - index) }
    end

    def command_surface(state, replay, viewer)
      return nil if !same_user?(state[:current_player], viewer)
      commands = case state[:phase]
      when :choosing_contract
        available_contracts(state, viewer).map do |contract|
          GameSurfaces::Command.new(id: "choose_contract_#{contract.downcase}", label: contract_label(contract), enabled: true, payload: { "contract" => contract })
        end
      when :exchanging
        [GameSurfaces::Command.new(id: "stop_exchange", label: _("Finish exchanging"), enabled: true, payload: {})]
      else
        []
      end
      commands.empty? ? nil : GameSurfaces::CommandPanelSpec.new(commands: commands)
    end

    def hand_header(state, viewer)
      case state[:phase]
      when :choosing_contract
        same_user?(viewer, state[:chooser]) ? _("Your first six cards") : _("Your first six cards; waiting for the contract")
      when :discarding
        same_user?(viewer, state[:chooser]) ? _("Your hand; discard %{remaining} cards") % { remaining: 4 - state[:discards].length } : _("Your hand")
      when :exchange_return
        same_user?(viewer, state[:current_player]) ? _("Your hand; choose a return card") : _("Your hand")
      else
        _("Your hand")
      end
    end

    def hand_text(state, viewer)
      cards = hand_for(state, viewer).to_a.sort_by { |card| card_sort_key(card) }
      return _("Your hand is empty.") if cards.empty?
      _("Your hand: %{cards}.") % { cards: cards.map { |card| card_label(card) }.join("; ") }
    end

    def table_cards_text(state)
      return _("There are no cards on the table.") if state[:current_trick].empty?
      _("Cards on the table: %{cards}.") % { cards: state[:current_trick].map { |play| _("%{player}: %{card}") % { player: participant_name(play[:player]), card: card_label(play[:card]) } }.join("; ") }
    end

    def scores_text(state)
      score_announcement_order(state[:players], state[:scores]).map do |player|
        _("%{player}: %{score}") % { player: participant_name(player), score: state[:scores][player] }
      end.join("; ")
    end

    def round_text(state)
      details = state[:players].map do |player|
        _("%{player}: %{tricks}/%{target}") % { player: participant_name(player), tricks: state[:tricks][player], target: state[:targets][player] }
      end
      _("Deal %{round} of 18. %{details}.") % { round: state[:round], details: details.join("; ") }
    end

    def contract_text(state)
      return _("No contract has been chosen yet.") if state[:contract] == nil
      _("Contract: %{contract}.") % { contract: contract_label(state[:contract]) }
    end

    def contract_label(contract)
      case contract.to_s
      when "NT" then _("no trump")
      when "MISERE" then _("misere; take as few tricks as possible")
      else _("%{suit} as trump") % { suit: SUIT_NAMES.fetch(contract.to_s, contract.to_s) }
      end
    end

    def trump_contract?(contract)
      SUITS.include?(contract.to_s)
    end

    def trump_suit(state)
      trump_contract?(state[:contract]) ? state[:contract] : nil
    end

    def deal_cards(players, dealer, seed)
      deck = SUITS.product(RANKS).map { |suit, rank| "#{rank}#{suit}" }
      deck = deck.sort_by { |card| Digest::SHA256.hexdigest("#{seed}\0#{card}") }
      hands = players.each_with_object({}) { |player, result| result[player] = [] }
      48.times do |index|
        hands[players[(dealer + 1 + index) % 3]] << deck[index]
      end
      [hands, deck.last(4)]
    end

    def parse_deal(value)
      GameRoomCardWire.parse_deal(value)
    end

    def random_seed(source)
      source.roll(count: 16, sides: 256).values.map { |value| (value.to_i - 1).to_s(16).rjust(2, "0") }.join
    end

    def selected_card(selection)
      value = selection["card"]
      return value["card"].to_s if value.respond_to?(:key?) && value.key?("card")
      value.to_s
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def hand_for(state, actor)
      player = player_key(state, actor)
      player == nil ? nil : state[:hands][player]
    end

    def next_player(players, actor)
      index = players.index { |player| same_user?(player, actor) }
      index == nil ? nil : players[(index + 1) % players.length]
    end

    def card_rank(card)
      card.to_s[0]
    end

    def card_suit(card)
      card.to_s[1]
    end

    def card_strength(card)
      RANKS.index(card_rank(card)).to_i
    end

    def card_label(card)
      _("%{rank} of %{suit}") % { rank: RANK_NAMES.fetch(card_rank(card), card_rank(card)), suit: SUIT_NAMES.fetch(card_suit(card), card_suit(card)) }
    end

    def card_sort_key(card)
      playroom_hand_sort_key(card)
    end

    def signed_number(value)
      value.to_i > 0 ? "+#{value.to_i}" : value.to_i.to_s
    end
  end
end

require_relative 'generated/rulebooks/three_five_eight'
