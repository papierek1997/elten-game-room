# encoding: UTF-8
require "json"
require "digest"
require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "../lib/biblios_strategy"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Biblios < CardGame
    CATEGORIES = %w[p m f h s].freeze
    TIE_ORDER = %w[m p f h s].freeze
    LETTERS = %w[A B C D E F G H I].freeze
    RICH_CATEGORIES = %w[p m].freeze
    RICH_VALUES = [2, 2, 2, 2, 3, 3, 3, 4, 4].freeze
    PLAIN_VALUES = [1, 1, 1, 1, 1, 1, 1, 2, 2].freeze
    GOLD_VALUES = [1, 2, 3].freeze
    GOLD_PER_VALUE = 6
    CHURCH_KINDS = (["up1"] * 6 + ["down1"] * 6 + ["up2"] * 4 + ["down2"] * 4 + ["any1"] * 4).freeze
    SETUP = { 2 => [2, 21], 3 => [1, 12], 4 => [0, 7] }.freeze
    DIE_FACES = (1..6).freeze
    START_FACE = 3
    DECLINE = "decline".freeze
    BLUFF_WINDOW = 5
    BLUFF_REACH = 2

    PENALTIES = [
      OptionChoice.new(value: "bluff", label: _("Medieval bluff: one random card")),
      OptionChoice.new(value: "full", label: _("Full: every other player takes a card"))
    ].freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      kinds = history.map(&:kind)
      return "shuffle" if kinds.include?(:deal)
      return "draw" if kinds.include?(:take)
      return "play" if (kinds & [:allocate, :pay, :church, :scriptorium]).any?
    end

    def id
      "biblios"
    end

    def name
      _("Biblios")
    end

    def short_description
      _("Collect cards for your library and bid on those that will put you ahead of your rivals in the categories you choose.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      2
    end

    def maximum_players
      4
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= BibliosPlanning::Strategy.new
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "penalty",
          label: _("Penalty for an unpaid bid"),
          kind: :choice,
          default: "bluff",
          choices: PENALTIES
        )
      ]
    end

    def options_summary(options)
      values = normalize_options(options)
      choice = PENALTIES.find { |penalty| penalty.value == values["penalty"] }
      choice == nil ? "" : choice.label
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      state = initial_state(players, options_from_json(session["options"]))
      accepted = []
      history = [starting_history(players)]
      seen = {}

      events.each do |event|
        break if state[:phase] == :finished

        event_id = repository.event_id(event).to_s
        next if seen[event_id]
        seen[event_id] = true

        actor = repository.actor_of(event, session)
        next unless players.any? { |player| same_user?(player, actor) }
        next if event["action"].to_s == "start" && !same_user?(actor, players.first)
        applied = case event["action"].to_s
        when "start" then apply_start(state, event, repository, history)
        when "allocate" then apply_allocate(state, event, actor, repository, history)
        when "take" then apply_take(state, event, actor, repository, history)
        when "church" then apply_church(state, event, actor, repository, history)
        when "bid" then apply_bid(state, event, actor, repository, history)
        when "pay" then apply_pay(state, event, actor, repository, history)
        else false
        end
        accepted << event if applied
      end

      Replay.new(
        board: nil,
        players: players,
        current_player: state[:current_player],
        winner: state[:winner],
        draw: state[:tie],
        accepted_events: accepted,
        history: history,
        state: state
      )
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || replay.state[:phase] != :setup
      return nil if !same_user?(actor, replay.players.first)

      { "kind" => "command", "action" => "start" }
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:phase] == :finished
      return [] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :allocate
        allocation_places(state).map { |place| { "kind" => "command", "action" => "allocate", "place" => place } }
      when :take
        state[:public].map { |card| { "kind" => "command", "action" => "take", "card" => card } }
      when :church
        church_plans(state).map { |plan| { "kind" => "command", "action" => "church", "plan" => plan } }
      when :auction
        actions = [{ "kind" => "command", "action" => "bid", "amount" => "pass" }]
        legal_bids(state, actor).each { |amount| actions << { "kind" => "command", "action" => "bid", "amount" => amount } }
        actions
      when :pay
        actions = [{ "kind" => "command", "action" => "pay", "cards" => "[]" }]
        payments(state, player_key(state, actor)).each do |cards|
          actions << { "kind" => "card_packet", "action" => "pay", "cards" => JSON.generate(cards) }
        end
        actions
      else
        []
      end
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?

      action = selection["action"].to_s
      if selection["kind"].to_s == "card" && action == "select"
        return zone_action(selection, replay, actor)
      end
      if action == "start"
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] if state[:phase] != :setup || context == nil || context.random_source == nil

        return [:ok, event_plan("start", card_seed(context.random_source))]
      end
      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)

      case action
      when "allocate"
        place = selection["place"].to_s
        return [:invalid, nil] if state[:phase] != :allocate || !allocation_places(state).include?(place)

        [:ok, event_plan("allocate", place)]
      when "take"
        card = selection["card"].to_s
        return [:invalid, nil] if state[:phase] != :take || !state[:public].include?(card)

        [:ok, event_plan("take", card)]
      when "church"
        plan = selection["plan"].to_s
        return [:invalid, nil] if state[:phase] != :church || !church_plans(state).include?(plan)

        [:ok, event_plan("church", plan)]
      when "bid"
        return [:invalid, nil] if state[:phase] != :auction
        amount = selection["amount"].to_s
        return [:ok, event_plan("bid", "pass")] if amount == "pass"
        return [:invalid_bid, nil] if !amount.match?(/\A\d+\z/) || !legal_bids(state, actor).include?(amount.to_i)

        [:ok, event_plan("bid", amount.to_i.to_s)]
      when "pay"
        return [:invalid, nil] if state[:phase] != :pay
        cards = parse_cards(selection["cards"])
        return [:invalid_payment, nil] if cards == nil
        return [:ok, event_plan("pay", "")] if cards.empty? || cards == [DECLINE]
        return [:invalid_payment, nil] if !valid_payment?(state, player_key(state, actor), cards)

        [:ok, event_plan("pay", encode_payment(cards))]
      else
        [:invalid, nil]
      end
    end

    def surface_spec(replay, viewer)
      state = replay.state
      return waiting_surface(current_turn_shortcut_text(replay, viewer)) if replay.finished?
      return waiting_surface(current_turn_shortcut_text(replay, viewer)) if !same_user?(state[:current_player], viewer)

      case state[:phase]
      when :allocate then allocation_surface(state)
      when :take then take_surface(state)
      when :church then church_surface(state)
      when :auction then auction_surface(state, viewer)
      when :pay then payment_surface(state, viewer)
      else waiting_surface(_("Waiting for the cards to be dealt"))
      end
    end

    def playable_card_navigation(replay, viewer)
      state = replay.state
      return nil unless state[:phase] == :pay && same_user?(state[:current_player], viewer)

      cards = payable_cards(state, player_key(state, viewer))
      actions = {}
      cards.each do |card|
        other = cards - [card]
        packet = if gold?(state[:card])
          [card] + other.first(state[:high] - 1) if cards.length >= state[:high]
        else
          # Find a minimal legal packet containing this physical card, without
          # enumerating all packets or selecting one on behalf of the player.
          sums = { 0 => [] }
          other.each do |candidate|
            sums.to_a.each do |sum, selected|
              value = sum + gold_value(candidate)
              sums[value] ||= selected + [candidate] if value < state[:high]
            end
          end
          total = sums.keys.sort.find { |sum| sum + gold_value(card) >= state[:high] }
          [card] + sums[total] if total
        end
        if packet && valid_payment?(state, player_key(state, viewer), packet)
          actions[card] = [{ "kind" => "card_packet", "action" => "pay", "cards" => JSON.generate(packet) }]
        end
      end
      card_navigation_spec(hand_id: "biblios_payment", card_actions: actions)
    end

    def participant_scores(replay)
      return nil if !replay.finished?

      state = replay.state
      state[:players].to_h { |player| [player, victory_points(state, player)] }
    end

    def shortcut_features
      [:turn, :scores, :bidding]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :scores then replay.finished? ? { message: scores_text(state, sorted: true) } : nil
      when :bidding then { message: auction_text(state) }
      else super
      end
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      shortcuts = [
        announcement_shortcut(key: "l", label: _("read your library"), message: library_text(state, viewer)),
        browse_shortcut(key: "l", modifiers: [:control], label: _("browse your library"),
          prompt: _("Your library"), choices: library_choices(state, viewer)),
        announcement_shortcut(key: "c", label: _("read the Scriptorium"), message: scriptorium_text(state)),
        GameShortcut.new(key: "c", modifiers: [:shift], label: _("read who leads each category"),
          kind: :announcement, message: leaders_text(state)),
        announcement_shortcut(key: "g", label: _("read your Gold"), message: gold_text(state, viewer)),
        announcement_shortcut(key: "p", label: _("read the public space"), message: public_text(state))
      ]
      if state[:phase] == :auction && same_user?(state[:current_player], viewer)
        shortcuts << number_input_shortcut(
          key: "r",
          label: _("bid an amount"),
          prompt: _("Bid"),
          action_kind: "command",
          action_name: "bid",
          value_key: "amount",
          allowed_values: legal_bids(state, viewer),
          default_value: state[:high] + 1,
          invalid_message: _("The bid must be higher than the current one and within your reach.")
        )
      end
      shortcuts
    end

    def move_error(status)
      case status
      when :invalid_bid
        _("The bid must be higher than the current one.")
      when :invalid_payment
        _("Those cards do not pay the bid, or one of them is not needed.")
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id.to_i && ![:start, :turn, :result].include?(entry.kind) }
      messages = entries.map(&:text)
      if same_user?(repository.actor_of(event), viewer)
        taken = entries.find { |entry| entry.kind == :allocate && entry.field == "self" }
        messages << _("You pick up %{card}.") % { card: card_label(taken.value) } if taken != nil
      end
      drawn = drawn_card_message(replay.state, viewer)
      messages << drawn if drawn != nil
      messages.empty? ? nil : messages
    end

    def bot_observation(replay, actor)
      state = replay.state
      {
        "players" => state[:players],
        "phase" => state[:phase].to_s,
        "current_player" => state[:current_player],
        "dice" => state[:dice],
        "hand" => state[:hands].fetch(player_key(state, actor), []),
        "public" => state[:public],
        "card" => state[:phase] == :allocate && same_user?(state[:current_player], actor) ? state[:deck][state[:pointer]] : state[:card],
        "known_cards" => state[:revealed].transform_values(&:dup),
        "high" => state[:high],
        "viewer" => actor.to_s
      }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      player = player_key(state, actor)
      case action["action"].to_s
      when "allocate"
        allocation_score(state, player, action["place"].to_s)
      when "take"
        card_worth(state, player, action["card"].to_s) * 10.0
      when "church"
        plan_score(state, player, action["plan"].to_s)
      when "bid"
        bid_score(state, player, action["amount"])
      when "pay"
        cards = parse_cards(action["cards"])
        cards.to_a.empty? ? -100_000.0 : 100.0 - payment_cost(state, player, cards)
      else
        0.0
      end
    end

    def card_category(card)
      return nil if gold?(card) || church?(card)

      card[0]
    end

    def card_value(card)
      category = card_category(card)
      return 0 if category == nil

      values = RICH_CATEGORIES.include?(category) ? RICH_VALUES : PLAIN_VALUES
      values[LETTERS.index(card[1]).to_i].to_i
    end

    def gold?(card)
      card.to_s.start_with?("o")
    end

    def church?(card)
      card.to_s.start_with?("k")
    end

    def gold_value(card)
      ((card[1..].to_i - 1) / GOLD_PER_VALUE) + 1
    end

    def church_kind(card)
      CHURCH_KINDS[card[1..].to_i - 1]
    end

    private

    def master_deck
      cards = CATEGORIES.flat_map { |category| LETTERS.map { |letter| "#{category}#{letter}" } }
      cards += (1..(GOLD_VALUES.length * GOLD_PER_VALUE)).map { |index| "o#{index}" }
      cards + (1..CHURCH_KINDS.length).map { |index| "k#{index}" }
    end

    def prepared_deck(players, seed)
      gold_removed, random_removed = SETUP.fetch(players.length, [0, 7])
      deck = master_deck
      GOLD_VALUES.each do |value|
        matching = deck.select { |card| gold?(card) && gold_value(card) == value }
        deck -= matching.last(gold_removed)
      end
      shuffled_cards(deck, seed).drop(random_removed)
    end

    def initial_state(players, options)
      {
        players: players,
        options: options,
        seed: nil,
        deck: [],
        pointer: 0,
        hands: players.each_with_object({}) { |player, result| result[player] = [] },
        revealed: players.each_with_object({}) { |player, result| result[player] = [] },
        public: [],
        auction: [],
        dice: CATEGORIES.each_with_object({}) { |category, result| result[category] = START_FACE },
        phase: :setup,
        current_player: players.first,
        leader: players.first,
        placed: { "self" => 0, "auction" => 0, "public" => 0 },
        takers: [],
        church: nil,
        card: nil,
        passed: [],
        barred: [],
        high: 0,
        bidder: nil,
        winner: nil,
        tie: false
      }
    end

    def apply_start(state, event, repository, history)
      return false if state[:phase] != :setup

      seed = event["value"].to_s
      return false unless seed.match?(/\A[0-9a-f]{32}\z/i)

      state[:seed] = seed
      state[:deck] = prepared_deck(state[:players], seed)
      state[:pointer] = 0
      state[:phase] = :allocate
      history << HistoryEntry.new(
        key: "deal", text: _("The cards are dealt and the Gift phase begins."),
        event_id: repository.event_id(event), actor: "", kind: :deal
      )
      true
    end

    def apply_allocate(state, event, actor, repository, history)
      return false if state[:phase] != :allocate
      return false if !same_user?(state[:current_player], actor)

      place = event["value"].to_s
      return false if !allocation_places(state).include?(place)

      card = state[:deck][state[:pointer]]
      return false if card == nil

      event_id = repository.event_id(event)
      state[:pointer] += 1
      state[:placed][place] += 1
      history << HistoryEntry.new(
        key: "allocate:#{event_id}", text: allocate_text(actor, place, card),
        event_id: event_id, actor: actor, kind: :allocate, field: place, value: card
      )
      case place
      when "public" then state[:public] << card
      when "auction" then state[:auction] << card
      else acquire(state, player_key(state, actor), card, "allocate", event_id, history)
      end
      advance_gift(state, event_id, history)
      true
    end

    def apply_take(state, event, actor, repository, history)
      return false if state[:phase] != :take
      return false if !same_user?(state[:current_player], actor)

      card = event["value"].to_s
      index = state[:public].index(card)
      return false if index == nil

      event_id = repository.event_id(event)
      state[:public].delete_at(index)
      state[:takers].shift
      history << HistoryEntry.new(
        key: "take:#{event_id}",
        text: _("%{player} takes %{card} from the public space.") % {
          player: participant_name(actor), card: card_label(card)
        },
        event_id: event_id, actor: actor, kind: :take
      )
      acquire(state, player_key(state, actor), card, "take", event_id, history, revealed: true)
      advance_take(state, event_id, history)
      true
    end

    def apply_church(state, event, actor, repository, history)
      return false if state[:phase] != :church
      return false if !same_user?(state[:current_player], actor)

      plan = event["value"].to_s
      return false if !church_plans(state).include?(plan)

      event_id = repository.event_id(event)
      resume = state[:church]["resume"]
      apply_adjustments(state, plan)
      history << HistoryEntry.new(
        key: "scriptorium:#{event_id}", text: church_text(actor, plan),
        event_id: event_id, actor: actor, kind: :scriptorium
      )
      state[:church] = nil
      case resume
      when "allocate"
        state[:phase] = :allocate
        state[:current_player] = state[:leader]
        advance_gift(state, event_id, history)
      when "take"
        state[:phase] = :take
        advance_take(state, event_id, history)
      else
        state[:phase] = :auction
        advance_auction(state, event_id, history)
      end
      true
    end

    def apply_bid(state, event, actor, repository, history)
      return false if state[:phase] != :auction
      return false if !same_user?(state[:current_player], actor)

      value = event["value"].to_s
      event_id = repository.event_id(event)
      player = player_key(state, actor)
      if value == "pass"
        state[:passed] << player
        history << HistoryEntry.new(
          key: "bid:#{event_id}", text: _("%{player} passes on this auction.") % { player: participant_name(actor) },
          event_id: event_id, actor: actor, kind: :bid
        )
      else
        amount = value.to_i
        return false if !value.match?(/\A\d+\z/) || !legal_bids(state, actor).include?(amount)

        state[:high] = amount
        state[:bidder] = player
        history << HistoryEntry.new(
          key: "bid:#{event_id}",
          text: _("%{player} bids %{amount}.") % { player: participant_name(actor), amount: amount },
          event_id: event_id, actor: actor, kind: :bid
        )
      end
      settle_auction(state, event_id, history)
      true
    end

    def apply_pay(state, event, actor, repository, history)
      return false if state[:phase] != :pay
      return false if !same_user?(state[:current_player], actor)

      event_id = repository.event_id(event)
      player = player_key(state, actor)
      cards = parse_cards(event["value"])
      return false if cards == nil
      if cards.empty?
        penalise(state, player, event_id, history)
        return true
      end
      return false if !valid_payment?(state, player, cards)

      cards.each { |card| state[:hands][player].delete_at(state[:hands][player].index(card)) }
      # Paying for Gold is face down: do not reveal which formerly public
      # category cards were discarded by updating an exact hidden ledger.
      if gold?(state[:card])
        state[:revealed][player].clear
      else
        state[:revealed][player] -= cards
      end
      history << HistoryEntry.new(
        key: "pay:#{event_id}", text: payment_text(state, actor, cards),
        event_id: event_id, actor: actor, kind: :pay
      )
      acquire(state, player, state[:card], "auction", event_id, history, revealed: true)
      advance_auction(state, event_id, history) if state[:phase] != :church
      true
    end

    def acquire(state, player, card, resume, event_id, history, revealed: false)
      if church?(card)
        state[:church] = { "player" => player, "card" => card, "resume" => resume }
        state[:phase] = :church
        state[:current_player] = player
        history << HistoryEntry.new(
          key: "acquire:#{event_id}:#{card}",
          text: _("%{player} acquires %{card} and plays it at once.") % {
            player: participant_name(player), card: card_label(card)
          },
          event_id: event_id, actor: player, kind: :church
        )
      else
        state[:hands][player] << card
        state[:revealed][player] << card if revealed
      end
    end

    def allocation_size(state)
      state[:players].length + 1
    end

    def public_capacity(state)
      state[:players].length - 1
    end

    def allocated_total(state)
      state[:placed].values.sum
    end

    def allocation_places(state)
      places = []
      places << "self" if state[:placed]["self"].zero?
      places << "auction" if state[:placed]["auction"].zero?
      places << "public" if state[:placed]["public"] < public_capacity(state)
      places
    end

    def advance_gift(state, event_id, history)
      return if state[:phase] != :allocate
      return if allocated_total(state) < allocation_size(state)

      state[:takers] = others_in_order(state[:players], state[:leader])
      state[:phase] = :take
      advance_take(state, event_id, history)
    end

    def advance_take(state, event_id, history)
      return if state[:phase] != :take

      if state[:takers].empty?
        finish_gift_turn(state, event_id, history)
      else
        state[:current_player] = state[:takers].first
      end
    end

    def finish_gift_turn(state, event_id, history)
      state[:placed] = { "self" => 0, "auction" => 0, "public" => 0 }
      if state[:pointer] >= state[:deck].length
        begin_auction_phase(state, event_id, history)
      else
        state[:leader] = next_player(state[:players], state[:leader])
        state[:current_player] = state[:leader]
        state[:phase] = :allocate
      end
    end

    def begin_auction_phase(state, event_id, history)
      state[:deck] = shuffled_cards(state[:auction], "#{state[:seed]}:auction")
      state[:auction] = []
      state[:pointer] = 0
      state[:leader] = state[:players].first
      history << HistoryEntry.new(
        key: "phase:auction", text: _("The Gift phase is over and the Auction phase begins."),
        event_id: event_id, actor: "", kind: :phase
      )
      start_auction(state, event_id, history)
    end

    def start_auction(state, event_id, history)
      if state[:pointer] >= state[:deck].length
        conclude_game(state, event_id, history)
        return
      end

      state[:card] = state[:deck][state[:pointer]]
      state[:pointer] += 1
      state[:passed] = []
      state[:barred] = []
      state[:high] = 0
      state[:bidder] = nil
      state[:phase] = :auction
      state[:current_player] = next_bidder(state, state[:leader])
      history << HistoryEntry.new(
        key: "flip:#{state[:pointer]}",
        text: _("%{player} turns up %{card}.") % {
          player: participant_name(state[:leader]), card: card_label(state[:card])
        },
        event_id: event_id, actor: state[:leader], kind: :flip
      )
    end

    def advance_auction(state, event_id, history)
      state[:leader] = next_player(state[:players], state[:leader])
      start_auction(state, event_id, history)
    end

    def settle_auction(state, event_id, history)
      remaining = state[:players].reject { |player| passed?(state, player) || barred?(state, player) }
      if state[:bidder] == nil
        if remaining.empty?
          discard_auction_card(state, event_id, history)
        else
          state[:current_player] = next_bidder(state, state[:current_player])
        end
        return
      end
      if remaining.length <= 1
        state[:phase] = :pay
        state[:current_player] = state[:bidder]
      else
        state[:current_player] = next_bidder(state, state[:current_player])
      end
    end

    def discard_auction_card(state, event_id, history)
      history << HistoryEntry.new(
        key: "discard:#{state[:pointer]}",
        text: _("Nobody bids and %{card} is discarded.") % { card: card_label(state[:card]) },
        event_id: event_id, actor: "", kind: :discard
      )
      advance_auction(state, event_id, history)
    end

    def penalise(state, player, event_id, history)
      hand = state[:hands][player]
      state[:revealed][player].clear
      if state[:options]["penalty"] == "full"
        others_in_order(state[:players], player).each do |other|
          break if hand.empty?

          state[:hands][other] << hand.delete_at(random_index(state, event_id, hand.length, other))
        end
      elsif !hand.empty?
        hand.delete_at(random_index(state, event_id, hand.length, player))
      end
      state[:barred] << player
      state[:passed] = []
      state[:high] = 0
      state[:bidder] = nil
      history << HistoryEntry.new(
        key: "penalty:#{event_id}",
        text: _("%{player} does not pay and is penalised.") % { player: participant_name(player) },
        event_id: event_id, actor: player, kind: :penalty
      )
      if state[:players].all? { |candidate| barred?(state, candidate) }
        discard_auction_card(state, event_id, history)
      else
        state[:phase] = :auction
        state[:current_player] = next_bidder(state, state[:leader])
      end
    end

    def random_index(state, event_id, size, salt)
      return 0 if size <= 1

      Digest::SHA256.hexdigest("#{state[:seed]}:#{event_id}:#{salt}").to_i(16) % size
    end

    def passed?(state, player)
      state[:passed].any? { |candidate| same_user?(candidate, player) }
    end

    def barred?(state, player)
      state[:barred].any? { |candidate| same_user?(candidate, player) }
    end

    def next_bidder(state, after)
      players = state[:players]
      index = players.index { |player| same_user?(player, after) }
      return nil if index == nil

      players.length.times do |offset|
        candidate = players[(index + 1 + offset) % players.length]
        return candidate if !passed?(state, candidate) && !barred?(state, candidate)
      end
      nil
    end

    def others_in_order(players, leader)
      index = players.index { |player| same_user?(player, leader) }
      return [] if index == nil

      players.rotate(index + 1).first(players.length - 1)
    end

    def next_player(players, actor)
      index = players.index { |player| same_user?(player, actor) }
      index == nil ? nil : players[(index + 1) % players.length]
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def bid_ceiling(state, player)
      return 0 if player == nil || state[:card] == nil

      hand = state[:hands].fetch(player, [])
      gold?(state[:card]) ? hand.length : hand.length * GOLD_VALUES.max
    end

    def legal_bids(state, actor)
      ceiling = bid_ceiling(state, player_key(state, actor))
      return [] if ceiling <= state[:high]

      ((state[:high] + 1)..ceiling).to_a
    end

    def offered_bids(state, actor)
      player = player_key(state, actor)
      return [] if player == nil

      window = [payment_capacity(state, player), state[:high] + BLUFF_WINDOW].max
      ceiling = [window, bid_ceiling(state, player)].min
      return [] if ceiling <= state[:high]

      ((state[:high] + 1)..ceiling).to_a
    end

    def payment_capacity(state, player)
      hand = state[:hands].fetch(player, [])
      return hand.length if gold?(state[:card])

      hand.select { |card| gold?(card) }.sum { |card| gold_value(card) }
    end

    def payable_cards(state, player)
      hand = state[:hands].fetch(player, [])
      gold?(state[:card]) ? hand : hand.select { |card| gold?(card) }
    end

    def valid_payment?(state, player, cards)
      hand = state[:hands].fetch(player, []).dup
      return false if cards.any? { |card| hand.delete(card) == nil }
      return cards.length == state[:high] if gold?(state[:card])
      return false if cards.any? { |card| !gold?(card) }

      total = cards.sum { |card| gold_value(card) }
      return false if total < state[:high]

      cards.none? { |card| total - gold_value(card) >= state[:high] }
    end

    def payments(state, player)
      cards = payable_cards(state, player)
      return [] if player == nil || cards.empty?

      if gold?(state[:card])
        return [] if cards.length < state[:high]

        # Greedy removal recalculates category value after every card, so a
        # large payment does not silently spend a formerly secure category.
        selected = []
        state[:high].times do
          remaining = state[:hands][player] - selected
          selected << (cards - selected).min_by { |card| marginal_card_cost(state, player, card, remaining) }
        end
        return [selected]
      end
      pools = GOLD_VALUES.to_h { |value| [value, cards.select { |card| gold_value(card) == value }] }
      results = []
      (0..pools[1].length).each do |ones|
        (0..pools[2].length).each do |twos|
          (0..pools[3].length).each do |threes|
            packet = pools[1].first(ones) + pools[2].first(twos) + pools[3].first(threes)
            results << packet if valid_payment?(state, player, packet)
          end
        end
      end
      results
    end

    def church_plans(state)
      kind = church_kind(state[:church]["card"])
      plans = case kind
      when "up1" then single_plans(state, "up")
      when "down1" then single_plans(state, "down")
      when "any1" then single_plans(state, "up") + single_plans(state, "down")
      when "up2" then pair_plans(state, "up")
      else pair_plans(state, "down")
      end
      plans + ["skip"]
    end

    def single_plans(state, direction)
      CATEGORIES.select { |category| movable?(state, category, direction) }.map { |category| "#{direction}:#{category}" }
    end

    def pair_plans(state, direction)
      CATEGORIES.combination(2).filter_map do |first, second|
        next if !movable?(state, first, direction) || !movable?(state, second, direction)

        "#{direction}:#{first},#{direction}:#{second}"
      end
    end

    def movable?(state, category, direction)
      DIE_FACES.include?(state[:dice][category] + (direction == "up" ? 1 : -1))
    end

    def apply_adjustments(state, plan)
      return if plan == "skip"

      plan.split(",").each do |part|
        direction, category = part.split(":")
        state[:dice][category] += direction == "up" ? 1 : -1
      end
    end

    def conclude_game(state, event_id, history)
      best = state[:players].map { |player| final_key(state, player) }.max
      winners = state[:players].select { |player| final_key(state, player) == best }
      state[:winner] = winners.one? ? winners.first : nil
      state[:tie] = winners.length > 1
      state[:phase] = :finished
      state[:current_player] = nil
      history << HistoryEntry.new(
        key: "summary:#{event_id}", text: scores_text(state),
        event_id: event_id, actor: "", kind: :score
      )
      history << result_history(event_id: event_id, winner: state[:winner], draw: state[:tie])
    end

    def final_key(state, player)
      key = [victory_points(state, player), gold_total(state, player)]
      TIE_ORDER.each do |category|
        key << category_total(state, player, category)
        key << -letter_rank(state, player, category)
      end
      key
    end

    def total_of(cards, category)
      cards.select { |card| card_category(card) == category }.sum { |card| card_value(card) }
    end

    def letter_rank_of(cards, category)
      letters = cards.select { |card| card_category(card) == category }.map { |card| LETTERS.index(card[1]) }
      letters.empty? ? LETTERS.length : letters.min
    end

    def category_total(state, player, category)
      total_of(state[:hands].fetch(player, []), category)
    end

    def letter_rank(state, player, category)
      letter_rank_of(state[:hands].fetch(player, []), category)
    end

    def gold_total(state, player)
      state[:hands].fetch(player, []).select { |card| gold?(card) }.sum { |card| gold_value(card) }
    end

    def leader_for(state, category, &source)
      keys = state[:players].to_h do |player|
        cards = source.call(player)
        [player, [total_of(cards, category), -letter_rank_of(cards, category)]]
      end
      best = keys.values.max
      return nil if best[0] <= 0

      leaders = state[:players].select { |player| keys[player] == best }
      leaders.one? ? leaders.first : nil
    end

    def category_winner(state, category)
      leader_for(state, category) { |player| state[:hands].fetch(player, []) }
    end

    def victory_points(state, player)
      CATEGORIES.sum do |category|
        same_user?(category_winner(state, category), player) ? state[:dice][category] : 0
      end
    end

    def parse_cards(value)
      text = value.to_s
      return [] if text.empty?
      if text.start_with?("~")
        return nil unless text.match?(/\A~[0-9a-f]{1,22}\z/)
        mask = text[1..].to_i(16)
        deck = master_deck
        return nil if mask.bit_length > deck.length
        return deck.each_with_index.filter_map { |card, index| card if mask[index] == 1 }
      end
      if text.start_with?("[")
        values = JSON.parse(text)
        return nil unless values.is_a?(Array) && values.all? { |card| card.is_a?(String) }
        return values
      end

      text.split(",").map(&:strip).reject(&:empty?)
    rescue JSON::ParserError
      nil
    end

    def encode_payment(cards)
      deck = master_deck
      "~" + cards.reduce(0) { |mask, card| mask | (1 << deck.index(card)) }.to_s(16)
    end

    def zone_action(selection, replay, actor)
      value = selection["card"].to_s
      forwarded = case selection["zone"].to_s
      when "places" then { "action" => "allocate", "place" => value }
      when "public" then { "action" => "take", "card" => value }
      when "church" then { "action" => "church", "plan" => value }
      when "bids" then { "action" => "bid", "amount" => value }
      end
      return [:invalid, nil] if forwarded == nil

      action_for(forwarded, replay, actor)
    end

    def waiting_surface(label)
      text = label.to_s.empty? ? _("Waiting for the other players") : label.to_s
      GameSurfaces::CardTableSpec.new(
        zones: [GameSurfaces::CardZoneSpec.new(id: "actions", header: text, cards: [], empty_label: text)]
      )
    end

    def zone_surface(id, header, entries, empty)
      GameSurfaces::CardTableSpec.new(
        zones: [
          GameSurfaces::CardZoneSpec.new(
            id: id, header: header, empty_label: empty,
            cards: entries.map { |value, label| GameSurfaces::Card.new(id: value, label: label, value: value) }
          )
        ]
      )
    end

    def allocation_surface(state)
      card = state[:deck][state[:pointer]]
      labels = {
        "self" => _("Keep for yourself"),
        "auction" => _("Into the Auction pile"),
        "public" => _("Into the public space")
      }
      header = _("Card %{index} of %{total}: %{card}") % {
        index: allocated_total(state) + 1, total: allocation_size(state), card: card_label(card)
      }
      zone_surface("places", header, allocation_places(state).map { |place| [place, labels[place]] }, _("No places are available"))
    end

    def take_surface(state)
      entries = state[:public].map { |card| [card, card_label(card)] }
      zone_surface("public", _("Take one card from the public space"), entries, _("The public space is empty"))
    end

    def church_surface(state)
      entries = church_plans(state).map { |plan| [plan, plan_label(plan)] }
      header = _("%{card}. Choose how to change the Scriptorium") % { card: card_label(state[:church]["card"]) }
      zone_surface("church", header, entries, _("No adjustment is possible"))
    end

    def auction_surface(state, viewer)
      entries = [["pass", _("Pass")]]
      offered_bids(state, viewer).each { |amount| entries << [amount.to_s, bid_label(state, viewer, amount)] }
      header = _("%{card}. %{bid}") % { card: card_label(state[:card]), bid: bid_state_text(state) }
      zone_surface("bids", header, entries, _("You cannot bid"))
    end

    def payment_surface(state, viewer)
      available = payable_cards(state, player_key(state, viewer))
      cards = available.map { |card| GameSurfaces::Card.new(id: card, label: card_label(card), value: card) }
      cards << GameSurfaces::Card.new(id: DECLINE, label: _("Do not pay"), value: DECLINE)
      GameSurfaces::PacketCardSpec.new(
        id: "biblios_payment", header: payment_header(state), cards: cards,
        action_name: "pay", allow_packet: true, empty_label: _("You have nothing to pay with"),
        hand_order: available + [DECLINE], hand_epoch: "#{viewer}:#{state[:pointer]}"
      )
    end

    def payment_header(state)
      if gold?(state[:card])
        _("Pay %{count} cards for %{card}") % { count: state[:high], card: card_label(state[:card]) }
      else
        _("Pay %{amount} Gold for %{card}") % { amount: state[:high], card: card_label(state[:card]) }
      end
    end

    def bid_label(state, actor, amount)
      text = if gold?(state[:card])
        _("Bid %{amount} cards") % { amount: amount }
      else
        _("Bid %{amount} Gold") % { amount: amount }
      end
      return text if amount <= payment_capacity(state, player_key(state, actor))

      text + " " + _("(more than you can pay)")
    end

    def bid_state_text(state)
      return _("No bids yet.") if state[:bidder] == nil

      _("%{player} bids %{amount}.") % { player: participant_name(state[:bidder]), amount: state[:high] }
    end

    def drawn_card_message(state, viewer)
      return nil if state[:phase] != :allocate || !same_user?(state[:current_player], viewer)

      card = state[:deck][state[:pointer]]
      return nil if card == nil

      _("You draw %{card}.") % { card: card_label(card) }
    end

    def allocate_text(actor, place, card)
      case place
      when "public"
        _("%{player} places %{card} in the public space.") % { player: participant_name(actor), card: card_label(card) }
      when "auction"
        _("%{player} places a card in the Auction pile.") % { player: participant_name(actor) }
      else
        _("%{player} keeps a card.") % { player: participant_name(actor) }
      end
    end

    def payment_text(state, actor, cards)
      if gold?(state[:card])
        _("%{player} pays %{count} cards and takes %{card}.") % {
          player: participant_name(actor), count: cards.length, card: card_label(state[:card])
        }
      else
        _("%{player} pays %{amount} Gold and takes %{card}.") % {
          player: participant_name(actor),
          amount: cards.sum { |card| gold_value(card) },
          card: card_label(state[:card])
        }
      end
    end

    def church_text(actor, plan)
      return _("%{player} does not use the Church card.") % { player: participant_name(actor) } if plan == "skip"

      _("%{player} changes the Scriptorium: %{change}.") % { player: participant_name(actor), change: plan_label(plan) }
    end

    def plan_label(plan)
      return _("Do not use the card") if plan == "skip"

      plan.split(",").map do |part|
        direction, category = part.split(":")
        if direction == "up"
          _("%{category} up") % { category: category_name(category) }
        else
          _("%{category} down") % { category: category_name(category) }
        end
      end.join(", ")
    end

    def category_name(category)
      {
        "p" => _("Pigments"), "m" => _("Monks"), "f" => _("Forbidden Tomes"),
        "h" => _("Holy Books"), "s" => _("Manuscripts")
      }.fetch(category, category)
    end

    def card_label(card)
      return _("a card") if card == nil
      return _("Gold %{value}") % { value: gold_value(card) } if gold?(card)
      return church_label(card) if church?(card)

      _("%{category} %{value}, letter %{letter}") % {
        category: category_name(card_category(card)), value: card_value(card), letter: card[1]
      }
    end

    def church_label(card)
      {
        "up1" => _("a Church card raising one die"),
        "down1" => _("a Church card lowering one die"),
        "up2" => _("a Church card raising two dice"),
        "down2" => _("a Church card lowering two dice"),
        "any1" => _("a Church card moving one die either way")
      }.fetch(church_kind(card))
    end

    def scriptorium_text(state)
      values = CATEGORIES.map do |category|
        _("%{category}: %{value}") % { category: category_name(category), value: state[:dice][category] }
      end
      _("Scriptorium: %{values}.") % { values: values.join("; ") }
    end

    def leaders_text(state)
      values = CATEGORIES.map do |category|
        leader = leader_for(state, category) { |player| state[:revealed].fetch(player, []) }
        if leader == nil
          _("%{category}: nobody") % { category: category_name(category) }
        else
          _("%{category}: %{player} with %{total}") % {
            category: category_name(category), player: participant_name(leader),
            total: total_of(state[:revealed].fetch(leader, []), category)
          }
        end
      end
      _("Counting only the cards taken openly: %{values}.") % { values: values.join("; ") }
    end

    def library_text(state, viewer)
      player = player_key(state, viewer)
      return _("You have no cards.") if player == nil || state[:hands].fetch(player, []).empty?

      values = CATEGORIES.filter_map do |category|
        total = category_total(state, player, category)
        next if total.zero?

        _("%{category}: %{total}") % { category: category_name(category), total: total }
      end
      return _("Your library holds no category cards.") if values.empty?

      _("Your library: %{values}.") % { values: values.join("; ") }
    end

    def library_choices(state, viewer)
      player = player_key(state, viewer)
      cards = player == nil ? [] : state[:hands].fetch(player, []).reject { |card| gold?(card) }
      return [ShortcutChoice.new(value: nil, label: _("Your library is empty"))] if cards.empty?

      cards.sort_by { |card| [CATEGORIES.index(card_category(card)).to_i, card[1]] }.map do |card|
        ShortcutChoice.new(value: card, label: card_label(card))
      end
    end

    def gold_text(state, viewer)
      player = player_key(state, viewer)
      cards = player == nil ? [] : state[:hands].fetch(player, []).select { |card| gold?(card) }
      return _("You have no Gold.") if cards.empty?

      _("Gold: %{total} in %{count} cards.") % { total: gold_total(state, player), count: cards.length }
    end

    def public_text(state)
      return _("The public space is empty.") if state[:public].empty?

      _("Public space: %{cards}.") % { cards: state[:public].map { |card| card_label(card) }.join("; ") }
    end

    def auction_text(state)
      return _("The Auction pile holds %{count} cards.") % { count: state[:auction].length } if state[:card] == nil

      passed = state[:passed].map { |player| participant_name(player) }
      text = _("Auctioned: %{card}. %{bid}") % { card: card_label(state[:card]), bid: bid_state_text(state) }
      return text if passed.empty?

      text + " " + _("Passed: %{players}.") % { players: passed.join(", ") }
    end

    def scores_text(state, sorted: false)
      players = sorted ? score_announcement_order(state[:players], state[:players].to_h { |p| [p, victory_points(state, p)] }) : state[:players]
      values = players.map do |player|
        _("%{player}: %{score}") % { player: participant_name(player), score: victory_points(state, player) }
      end
      _("Victory Points: %{values}.") % { values: values.join("; ") }
    end

    def card_worth(state, player, card)
      return gold_value(card).to_f if gold?(card)
      if church?(card)
        evaluation = state.merge(church: { "card" => card })
        return [church_plans(evaluation).map { |plan| plan_score(evaluation, player, plan) }.max.to_f / 5, 0].max
      end

      category = card_category(card)
      before = state[:hands].fetch(player, [])
      category_strength(state, player, category, before + [card]) - category_strength(state, player, category, before)
    end

    # Own cards and public information only; never inspect hidden rival hands.
    def category_strength(state, player, category, own_cards)
      mine = [total_of(own_cards, category), -letter_rank_of(own_cards, category)]
      rivals = state[:players].reject { |other| same_user?(other, player) }
      best = rivals.map do |other|
        known = state[:revealed].fetch(other, [])
        [total_of(known, category), -letter_rank_of(known, category)]
      end.max || [0, -LETTERS.length]
      total = mine[0]
      return 0.0 if total == 0
      lead = (mine <=> best) > 0
      supply = (RICH_CATEGORIES.include?(category) ? RICH_VALUES : PLAIN_VALUES).sum
      secured = total > supply / 2.0
      state[:dice][category] * ((lead ? 1.0 : 0.0) + (secured ? 1.0 : 0.0)) +
        [total, best[0] + 4].min * 0.5
    end

    def marginal_card_cost(state, player, card, own_cards)
      return gold_value(card).to_f * 1.5 if gold?(card)
      category = card_category(card)
      category_strength(state, player, category, own_cards) -
        category_strength(state, player, category, own_cards - [card]) + card_value(card) * 0.1
    end

    def payment_cost(state, player, cards)
      return cards.sum { |card| gold_value(card) } unless gold?(state[:card])
      remaining = state[:hands].fetch(player, []).dup
      cards.sum do |card|
        cost = marginal_card_cost(state, player, card, remaining)
        remaining.delete(card)
        cost
      end
    end

    def allocation_score(state, player, place)
      card = state[:deck][state[:pointer]]
      worth = card_worth(state, player, card)
      case place
      when "self"
        # Compare with a modest fixed expectation, not unseen future cards.
        slots = allocation_size(state) - allocated_total(state)
        (worth - (slots > 1 ? 2.5 : 0.0)) * 10.0
      when "auction" then worth * 0.2
      else -worth * 0.1
      end
    end

    def plan_score(state, player, plan)
      return 0.0 if plan == "skip"

      plan.split(",").sum do |part|
        direction, category = part.split(":")
        leader = leader_for(state, category) do |candidate|
          same_user?(candidate, player) ? state[:hands].fetch(player, []) : state[:revealed].fetch(candidate, [])
        end
        mine = same_user?(leader, player)
        step = direction == "up" ? 1 : -1
        leader == nil ? 0.0 : mine ? step * 10.0 : step * -6.0
      end
    end

    def bid_score(state, player, amount)
      return -1.0 if amount.to_s == "pass"

      value = amount.to_i
      worth = card_worth(state, player, state[:card])
      overshoot = value - payment_capacity(state, player)
      if overshoot <= 0
        if gold?(state[:card])
          evaluation = state.merge(high: value)
          cheapest = payments(evaluation, player).map { |packet| payment_cost(evaluation, player, packet) }.min
        else
          # At most 18 small Gold cards: a bitset avoids enumerating packets
          # again for every possible bid, including unavoidable overpayment.
          sums = payable_cards(state, player).reduce(1) { |mask, card| mask | (mask << gold_value(card)) }
          cheapest = (value..value + 2).find { |total| sums[total] == 1 }
        end
        return -1_000.0 unless cheapest
        return worth * 10.0 - cheapest * 8.0
      end

      bluff_score(state, player, worth, overshoot)
    end

    def bluff_score(state, player, worth, overshoot)
      return -1_000.0 if overshoot > BLUFF_REACH

      rivals = rival_bidders(state, player)
      return -1_000.0 if rivals.zero?

      lost = state[:options]["penalty"] == "full" ? state[:players].length - 1 : 1
      worth * rivals - overshoot * 4.0 - lost * 12.0
    end

    def rival_bidders(state, player)
      state[:players].count do |candidate|
        !same_user?(candidate, player) && !passed?(state, candidate) && !barred?(state, candidate)
      end
    end
  end
end

require_relative 'generated/rulebooks/biblios'
