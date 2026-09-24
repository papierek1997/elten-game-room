# encoding: UTF-8
require "digest"
require_relative "base"
require_relative "../lib/game_bots"

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

    def name
      _("3-5-8")
    end

    def rule_sections
      # Generated from docs/rulebooks/three_five_eight.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:course, GameRoomRules.translate("Eighteen deals and six contracts"),
          GameRoomRules.translate("3-5-8 is an individual game for exactly three players, using all 52 cards. Each player receives 16 cards and four cards form the kitty. The player to the dealer's left chooses the contract after seeing their first six cards, then receives the rest of their hand."),
          GameRoomRules.translate("There are six contracts: hearts, spades, diamonds and clubs as trump, no trump, and misere. During the game every player must choose each contract exactly once. The dealer moves one seat after every deal, so the complete game has 18 deals."),
          GameRoomRules.translate("After any exchanges, the chooser reveals the four-card kitty, adds it to their hand and discards four cards face down. The chooser leads the first trick. The winner of every trick leads the next one.")),
        rule_section(:play, GameRoomRules.translate("Following suit"),
          GameRoomRules.translate("Cards rank from two, the lowest, to ace, the highest. You must follow the led suit when you can, but you do not have to beat the currently winning card."),
          GameRoomRules.translate("If you cannot follow, you may play any card. You do not have to play a trump or overtrump. No-trump and misere deals have no trump suit.")),
        rule_section(:exchange, GameRoomRules.translate("Exchanging cards after the first deal"),
          GameRoomRules.translate("The table owner can disable card exchange in the game options. When it is disabled, every deal goes directly from contract selection to taking the kitty."),
          GameRoomRules.translate("Card exchange is available only in a trump contract. A player who scored above zero in the previous deal may exchange up to that many cards with players who scored below zero. A player with the higher target in the current deal exchanges first. You may stop before using the whole allowance."),
          GameRoomRules.translate("For a non-trump card, the recipient automatically returns their highest card of the same suit; if the received card is their only card of that suit, it simply returns. For a trump card, the recipient may instead return any non-trump card, or their highest trump. Exchanges are completed before the chooser takes the kitty.")),
        rule_section(:scoring, GameRoomRules.translate("Targets and scoring"),
          GameRoomRules.translate("In an ordinary deal the dealer's target is 3 tricks, the player to the dealer's right needs 5, and the chooser to the dealer's left needs 8. Your score for the deal is tricks won minus your target. The three changes therefore always total zero."),
          GameRoomRules.translate("Misere reverses the targets: the dealer may take at most 8 tricks, the player to the dealer's right at most 5, and the chooser at most 3. Your score is the limit minus tricks won, so avoiding tricks earns points and exceeding the limit loses points."),
          GameRoomRules.translate("After the eighteenth deal, the player with the highest total score wins. Equal highest totals produce a shared draw.")),
        rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
          GameRoomRules.translate("Arrows: browse cards or available commands."),
          GameRoomRules.translate("Enter: choose a contract, exchange or return a card, discard to the kitty, or play the selected card."),
          GameRoomRules.translate("H: read your hand."),
          GameRoomRules.translate("C: read the trick cards."),
          GameRoomRules.translate("Ctrl+C: browse the trick cards."),
          GameRoomRules.translate("F: read the current contract and trump suit."),
          GameRoomRules.translate("V: read tricks, targets and the current deal."),
          GameRoomRules.translate("S: read scores."),
          GameRoomRules.translate("T: read whose turn it is."),
          GameRoomRules.translate("Z: next legal card; play it automatically if it is the only unambiguous option."),
          GameRoomRules.translate("Shift+Z: previous legal card; play it automatically if it is the only unambiguous option."),
          GameRoomRules.translate("Shift+C: sort by suit or colour; press again to reverse the order."),
          GameRoomRules.translate("Shift+H: sort by rank or value; press again to reverse the order."),
          GameRoomRules.translate("Shift+M: restore the order in which cards were received."))
      ]
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
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
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
      case action["action"].to_s
      when "choose_contract"
        contract = action["contract"].to_s
        hand = hand_for(state, actor).to_a
        contract_score(hand, contract)
      when "exchange"
        card = action["card"].to_s
        -card_strength(card).to_f - (card_suit(card) == state[:contract] ? 5.0 : 0.0)
      when "return", "discard"
        -card_strength(action["card"].to_s).to_f
      when "stop_exchange"
        -10_000.0
      when "play"
        card = action["card"].to_s
        wants_trick = wants_trick?(state, actor)
        winner = projected_trick_winner(state, actor, card)
        value = card_strength(card).to_f
        if state[:contract] == "MISERE"
          same_user?(winner, actor) ? -1_000.0 - value : 1_000.0 - value
        elsif wants_trick
          same_user?(winner, actor) ? 1_000.0 - value : value
        else
          same_user?(winner, actor) ? -1_000.0 - value : -value
        end
      else
        0.0
      end
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

    def wants_trick?(state, actor)
      player = player_key(state, actor)
      state[:tricks][player].to_i < state[:targets][player].to_i
    end

    def contract_score(hand, contract)
      ranks = hand.sum { |card| card_strength(card) }
      if contract == "MISERE"
        return 500.0 - ranks - hand.group_by { |card| card_suit(card) }.values.sum { |cards| cards.length * cards.length }
      end
      return ranks + 20.0 if contract == "NT"

      suited = hand.select { |card| card_suit(card) == contract }
      ranks + suited.length * 20.0 + suited.sum { |card| card_strength(card) }
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
      fields = value.to_s.split("|", -1)
      raise ArgumentError, "invalid deal" if fields.length != 3
      round = Integer(fields[0], 10)
      dealer = Integer(fields[1], 10)
      seed = fields[2].to_s.downcase
      raise ArgumentError, "invalid deal seed" if seed !~ /\A[0-9a-f]{32}\z/
      [round, dealer, seed]
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
