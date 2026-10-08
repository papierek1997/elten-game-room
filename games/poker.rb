require "digest"
require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "../lib/game_turn_clock"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Poker < CardGame
    VARIANTS = [
      OptionChoice.new(value: "holdem", label: _("Texas Hold'em")),
      OptionChoice.new(value: "draw", label: _("Five-card draw"))
    ].freeze
    STRUCTURES = [
      OptionChoice.new(value: "no_limit", label: _("No limit")),
      OptionChoice.new(value: "pot_limit", label: _("Pot limit")),
      OptionChoice.new(value: "half_pot", label: _("Half-pot limit")),
      OptionChoice.new(value: "fixed", label: _("Fixed limit"))
    ].freeze
    BLIND_INTERVALS = [
      OptionChoice.new(value: "never", label: _("Never")),
      OptionChoice.new(value: "hands", label: _("After a number of hands")),
      OptionChoice.new(value: "minutes", label: _("After a number of minutes"))
    ].freeze
    DRAW_VARIANT = ->(options) { options["variant"].to_s == "draw" }
    USES_BLINDS = lambda do |options|
      options["variant"].to_s == "holdem" || options["draw_uses_blinds"] == true
    end
    INCREASES_BLINDS = lambda do |options|
      USES_BLINDS.call(options) && options["blind_interval"].to_s != "never"
    end
    SUIT_NAMES = { "C" => _("clubs"), "D" => _("diamonds"), "H" => _("hearts"), "S" => _("spades") }.freeze
    RANK_NAMES = { "T" => "10", "J" => _("jack"), "Q" => _("queen"), "K" => _("king"), "A" => _("ace") }.freeze

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      return "shuffle" if action == "deal"
      return "draw" if action == "exchange" && !GameRoomTurnClock.payload(after_replay.state, event).empty?
      return "play" if action == "bet" && event["value"].to_s !~ /\A(?:check|fold)\|/
    end

    def notification_option_keys(_options); %w[variant]; end

    def id
      "poker"
    end

    def eliminated_from_game?(replay, viewer)
      player = player_key(replay.state, viewer)
      return false unless player && replay.state.fetch(:stacks, {}).key?(player)
      replay.state[:stacks][player] <= 0 &&
        ([:hand_complete, :finished].include?(replay.state[:phase]) || hand_for(replay.state, player).empty?)
    end

    def name
      _("Poker")
    end

    def short_description
      _("Win chips with stronger cards or bluff your opponents into folding.")
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
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def rule_sections
      generated_rule_sections
    end

    def option_definitions
      [
        OptionDefinition.new(key: "variant", label: _("Poker variant"), kind: :choice, default: "holdem", choices: VARIANTS),
        OptionDefinition.new(key: "starting_chips", label: _("Starting chips"), kind: :integer, default: 1_000),
        OptionDefinition.new(key: "small_blind", label: _("Small blind"), kind: :integer, default: 5, visible_if: USES_BLINDS),
        OptionDefinition.new(key: "big_blind", label: _("Big blind"), kind: :integer, default: 10, visible_if: USES_BLINDS),
        OptionDefinition.new(key: "ante", label: _("Ante in five-card draw"), kind: :integer, default: 5,
          visible_if: ->(options) { DRAW_VARIANT.call(options) && !options["draw_uses_blinds"] }),
        OptionDefinition.new(key: "draw_uses_blinds", label: _("Use blinds in five-card draw"), kind: :boolean, default: false,
          visible_if: DRAW_VARIANT),
        OptionDefinition.new(key: "betting", label: _("Betting structure"), kind: :choice, default: "no_limit", choices: STRUCTURES),
        OptionDefinition.new(key: "raise_cap_enabled", label: _("Limit raises per betting round"), kind: :boolean, default: false),
        OptionDefinition.new(key: "raise_cap", label: _("Maximum raises per betting round"), kind: :integer, default: 3,
          visible_if: { "raise_cap_enabled" => true }),
        OptionDefinition.new(key: "blind_interval", label: _("Increase blinds"), kind: :choice, default: "hands", choices: BLIND_INTERVALS,
          visible_if: USES_BLINDS),
        OptionDefinition.new(key: "blind_interval_value", label: _("Hands or minutes between blind increases"), kind: :integer, default: 5,
          visible_if: INCREASES_BLINDS),
        OptionDefinition.new(key: "blind_multiplier", label: _("Blind multiplier"), kind: :integer, default: 2,
          visible_if: INCREASES_BLINDS),
        OptionDefinition.new(key: "draw_five", label: _("Allow exchanging all five cards"), kind: :boolean, default: false,
          visible_if: DRAW_VARIANT),
        OptionDefinition.new(key: "jacks_or_better", label: _("Jacks or better is required to open draw poker"), kind: :boolean, default: false,
          visible_if: DRAW_VARIANT)
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("Starting chips must be from 100 to 100000.") if !values["starting_chips"].to_i.between?(100, 100_000)
      if USES_BLINDS.call(values) && (values["small_blind"].to_i < 1 || values["big_blind"].to_i < values["small_blind"].to_i)
        return _("Blinds must be positive and the big blind must not be smaller than the small blind.")
      end
      if DRAW_VARIANT.call(values) && !values["draw_uses_blinds"] && !values["ante"].to_i.between?(1, values["starting_chips"].to_i)
        return _("The ante must be positive and cannot exceed the starting stack.")
      end
      if values["raise_cap_enabled"] && !values["raise_cap"].to_i.between?(1, 10)
        return _("The raise cap must be from 1 to 10.")
      end
      if INCREASES_BLINDS.call(values) && !values["blind_interval_value"].to_i.between?(1, 100)
        return _("The blind interval must be from 1 to 100.")
      end
      if INCREASES_BLINDS.call(values) && !values["blind_multiplier"].to_i.between?(2, 10)
        return _("The blind multiplier must be from 2 to 10.")
      end
      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      variant = VARIANTS.find { |choice| choice.value == values["variant"] }&.label
      structure = STRUCTURES.find { |choice| choice.value == values["betting"] }&.label
      stakes = if USES_BLINDS.call(values)
        _("blinds %{small}/%{big}") % { small: values["small_blind"], big: values["big_blind"] }
      else
        _("ante %{ante}") % { ante: values["ante"] }
      end
      _("%{variant}; %{chips} chips; %{stakes}; %{structure}") % {
        variant: variant, chips: values["starting_chips"], stakes: stakes, structure: structure
      }
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
        next if %w[bet exchange].include?(event["action"]) && poker_deadline_reached?(state, time)
        # Timed deals reuse the envelope's time instead of sending it twice.
        if event["action"] == "deal" && time != nil
          event = event.merge("value" => "#{event['value']}|#{time}")
        end
        actor = repository.actor_of(event, session)
        previous_recycle = state[:recycle]
        applied = case event["action"].to_s
        when "deal" then apply_deal(state, event, actor, repository, history)
        when "bet" then apply_bet(state, event, actor, repository, history)
        when "exchange" then apply_exchange(state, event, actor, repository, history)
        when "turn_timeout" then apply_timeout(state, event, actor, repository, history, time)
        else false
        end
        if applied
          record_deck_reshuffle(history, previous_recycle, state[:recycle], event_id)
          GameRoomTurnClock.advance(state, time, running: [:betting, :exchange].include?(state[:phase]))
          accepted << original_event
          seen[event_id] = true
        end
      end
      GameRoomTurnClock.attach_session(state, session)
      Replay.new(board: nil, players: players, current_player: state[:current_player], winner: state[:winner],
        draw: false, accepted_events: accepted, history: history, state: state)
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      return { "kind" => "command", "action" => "turn_timeout" } if poker_deadline_reached?(replay.state, context&.now)
      return nil if ![:awaiting_deal, :hand_complete].include?(replay.state[:phase])
      { "kind" => "command", "action" => "deal" }
    end

    def automatic_action_due?(replay, actor, context: nil)
      !replay.finished? && same_user?(actor, replay.players.first) && poker_deadline_reached?(replay.state, context&.now)
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if replay.finished? || !same_user?(state[:current_player], actor)
      return [] if poker_deadline_reached?(state, context&.now)
      if state[:phase] == :exchange
        maximum = state[:options]["draw_five"] ? 5 : 3
        hand = hand_for(state, actor)
        actions = [{ "kind" => "card_packet", "action" => "exchange", "cards" => "[]" }]
        1.upto(maximum) do |count|
          hand.combination(count) { |cards| actions << { "kind" => "card_packet", "action" => "exchange", "cards" => JSON.generate(cards) } }
        end
        return actions
      end
      return [] if state[:phase] != :betting
      player = player_key(state, actor)
      return [] if player == nil || state[:all_in][player] || state[:folded][player]
      call_amount = [[state[:current_bet] - state[:street_bets][player], 0].max, state[:stacks][player]].min
      actions = [{ "kind" => "command", "action" => call_amount.zero? ? "check" : "call", "amount" => call_amount }]
      actions << { "kind" => "command", "action" => "fold" }
      if state[:stacks][player] > call_amount && can_open_draw_betting?(state, player)
        raise_amounts(state, player).each do |amount|
          actions << { "kind" => "command", "action" => "raise", "amount" => amount }
        end
        if raise_amounts(state, player).include?(state[:stacks][player])
          actions << { "kind" => "command", "action" => "all_in", "amount" => state[:stacks][player] }
        end
      end
      actions << { "kind" => "command", "action" => "all_in", "amount" => state[:stacks][player] } if state[:stacks][player] > 0 && state[:stacks][player] <= call_amount
      actions
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?
      if selection["kind"].to_s == "command" && selection["action"].to_s == "deal"
        return [:not_your_turn, nil] if !same_user?(actor, replay.players.first)
        return [:invalid, nil] if ![:awaiting_deal, :hand_complete].include?(state[:phase]) || context&.random_source == nil
        seed = card_seed(context.random_source)
        dealer = state[:dealer_index] == nil ? seed.to_i(16) % replay.players.length : next_seated_index(state, state[:dealer_index])
        value = "#{state[:hand_number] + 1}|#{dealer}|#{seed}"
        value += "|#{GameRoomTurnClock.logical_now(state, context)}" unless GameRoomTurnClock.enabled?(state)
        return [:ok, timed_poker_plan("deal", value, state, context)]
      end
      if selection["action"].to_s == "turn_timeout"
        return [:not_your_turn, nil] unless same_user?(actor, replay.players.first)
        return [:invalid, nil] unless poker_deadline_reached?(state, context&.now)
        return [:ok, timed_poker_plan("turn_timeout", state[:turn_deadline].to_s(36), state, context)]
      end
      return [:invalid, nil] if poker_deadline_reached?(state, context&.now)
      legal = legal_actions(replay, actor, context: context)
      if selection["action"].to_s == "exchange"
        cards = JSON.parse(selection["cards"].to_s).map(&:to_s)
        candidate = legal.find { |item| item["action"] == "exchange" && JSON.parse(item["cards"]).sort == cards.sort }
        return [:invalid_exchange, nil] if candidate == nil
        return [:ok, timed_poker_plan("exchange", cards.join(","), state, context)]
      end
      action = selection["action"].to_s
      if action == "raise" && selection.key?("raise_by")
        player = player_key(state, actor)
        return [:invalid_bet, nil] if player == nil
        call = [state[:current_bet] - state[:street_bets][player], 0].max
        return [:invalid_bet, nil] if selection["quoted_call"].to_i != call
        increment = Integer(selection["raise_by"].to_s, 10) rescue nil
        return [:invalid_bet, nil] if increment == nil
        amount = call + increment
      else
        amount = Integer(selection["amount"].to_s, 10) rescue 0
      end
      candidate = bet_candidate(state, actor, action, amount)
      return [:invalid_bet, nil] if candidate == nil
      amount = candidate["amount"].to_i
      [:ok, timed_poker_plan("bet", "#{action}|#{amount}", state, context)]
    rescue JSON::ParserError
      [:invalid_exchange, nil]
    end

    def hand_sorting_available?(replay, viewer)
      replay.state[:phase] == :exchange && same_user?(replay.current_player, viewer)
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if state[:phase] == :exchange && same_user?(state[:current_player], viewer)
        cards = hand_for(state, viewer).sort_by { |card| playing_sort_key(card) }.map do |card|
          GameSurfaces::Card.new(id: card, label: poker_card_label(card), value: card,
            sort_keys: standard_hand_sort_keys(rank: card[0], suit: card[1], position: hand_for(state, viewer).index(card)))
        end
        packet = GameSurfaces::PacketCardSpec.new(id: "poker_exchange", header: _("Choose cards to exchange"),
          packet_tip: _("Press Shift+Enter to select or unselect the current card for exchange."),
          activation_tip: _("Press Enter to exchange the current card or the selected cards."),
          cards: cards, action_name: "exchange", allow_packet: true, empty_label: _("No cards"),
          hand_order: hand_for(state, viewer).dup, hand_epoch: [viewer, state[:hand_number]].join(":"))
        stand_pat = GameSurfaces::CommandPanelSpec.new(commands: [
          GameSurfaces::Command.new(id: "exchange", label: _("Keep all cards"), enabled: true, payload: { "cards" => "[]" })
        ])
        return GameSurfaces::CompositeSpec.new(parts: [
          GameSurfaces::SurfacePart.new(id: "stand_pat", surface: stand_pat),
          GameSurfaces::SurfacePart.new(id: "exchange", surface: packet)
        ])
      end
      items = legal_actions(replay, viewer).map.with_index do |action, index|
        label = betting_action_label(action, state, viewer)
        GameSurfaces::PawnTrackItem.new(id: "poker_action_#{index}", label: label,
          action: GameSurfaces::Action.new(kind: action["kind"], name: action["action"], payload: action.reject { |key, _| %w[kind action].include?(key) }, source: "poker_actions"))
      end
      if items.empty?
        label = replay.finished? ? result_text(replay) : _("Waiting for %{player}") % { player: participant_name(state[:current_player]) }
        items << GameSurfaces::PawnTrackItem.new(id: "status", label: label)
      end
      GameSurfaces::PawnTrackSpec.new(id: "poker_actions", header: _("Poker actions"), items: items, empty_label: _("No action is available"))
    end

    def participant_scores(replay)
      replay.state[:stacks].dup
    end

    def participant_status(replay, participant, connected: true)
      player = player_key(replay.state, participant)
      return _("all in") if player != nil && replay.state[:all_in][player] && [:betting, :exchange].include?(replay.state[:phase])
      return _("out") if player != nil && replay.state[:stacks][player].to_i <= 0
      super
    end

    def custom_game_shortcuts(replay, viewer)
      state = replay.state
      actions = legal_actions(replay, viewer)
      shortcuts = []
      check_call = actions.find { |action| %w[check call].include?(action["action"]) }
      shortcuts << GameShortcut.new(key: "c", label: _("check or call"), kind: :action, action_kind: "command", action_name: check_call["action"], payload: { "amount" => check_call["amount"] }) if check_call
      %w[fold all_in].each do |action_name|
        action = actions.find { |candidate| candidate["action"] == action_name }
        next if action == nil

        key = action_name == "fold" ? "f" : "a"
        shortcuts << GameShortcut.new(key: key, label: action_name == "fold" ? _("fold") : _("go all in"), kind: :action, action_kind: "command", action_name: action_name, payload: { "amount" => action&.fetch("amount", 0) })
      end
      raises = actions.select { |action| action["action"] == "raise" }
      if !raises.empty?
        player = player_key(state, viewer)
        call = [state[:current_bet] - state[:street_bets][player], 0].max
        limits = raise_limits(state, player)
        minimum, maximum = limits.begin - call, limits.end - call
        prompt = _("Raise by:")
        shortcuts << GameShortcut.new(key: "r", label: _("raise"), kind: :number_input, prompt: prompt,
          action_kind: "command", action_name: "raise", value_key: "raise_by", allowed_values: minimum..maximum,
          default_value: minimum, payload: { "quoted_call" => call })
      end
      shortcuts + information_shortcuts(state, viewer)
    end

    def bot_observation(replay, actor)
      state = replay.state
      { "variant" => state[:options]["variant"], "phase" => state[:phase], "current_player" => state[:current_player],
        "own_cards" => hand_for(state, actor), "community" => state[:community], "pot" => state[:contributions].values.sum,
        "stacks" => state[:stacks], "folded" => state[:folded], "current_bet" => state[:current_bet] }
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return poker_exchange_value(state, actor, JSON.parse(action["cards"]), exchanges: poker_public_exchanges(replay)) if action["action"] == "exchange"
      return -0.001 if action["action"] == "fold"
      ranges = poker_public_ranges(replay)
      pot = state[:contributions].sum { |_, chips| [chips, state[:contributions][actor] + state[:stacks][actor]].min }.to_f
      call = [[state[:current_bet] - state[:street_bets][actor], 0].max, state[:stacks][actor]].min
      paid = action["amount"].to_i
      contributions = state[:contributions].merge(actor => state[:contributions][actor] + paid)
      expectation = poker_pot_expectation(state, actor, contributions, ranges) - paid
      case action["action"]
      # Checking keeps our share of the existing pot. Comparing a raise with
      # zero incorrectly rewarded virtually any positive-equity hand for betting.
      when "check", "call" then expectation
      when "raise", "all_in"
        return expectation if paid <= call
        raise_by = paid - call
        opponents = contenders(state) - [actor]
        fold_chance = opponents.reduce(1.0) do |chance, player|
          next 0.0 if state[:all_in][player]
          pressure = raise_by.to_f / [pot + raise_by, 1].max
          # A token bet into a large pot should not inherit a large baseline
          # chance of making EVERY rival fold. Public aggression reduces it.
          chance * [[pressure * 0.8 / (1 + ranges.fetch(player, 0) * 0.5), 0.005].max, 0.65].min
        end
        opponents.each do |player|
          extra = [state[:street_bets][actor] + paid - state[:street_bets][player], state[:stacks][player]].min
          contributions[player] += [extra, 0].max
        end
        called = poker_pot_expectation(state, actor, contributions, ranges) - paid
        risk = 0.12 * raise_by * raise_by / [pot + current_big_blind(state), 1].max
        fold_chance * pot + (1 - fold_chance) * called - risk
      else 0
      end
    end

    def move_error(status)
      case status
      when :invalid_bet then _("That betting action is not available now.")
      when :invalid_exchange then _("You cannot exchange that set of cards.")
      else super
      end
    end

    def move_error_for(status, selection: nil, replay: nil, actor: nil)
      return super if replay == nil || selection == nil || ![:invalid_bet, :invalid_exchange].include?(status)
      state = replay.state
      return move_error(:not_your_turn) if !same_user?(state[:current_player], actor)
      player = player_key(state, actor)
      return super if player == nil
      if status == :invalid_exchange
        return _("It is not the card-exchange stage.") if state[:phase] != :exchange
        cards = JSON.parse(selection["cards"].to_s) rescue []
        maximum = state[:options]["draw_five"] ? 5 : 3
        return _("You may exchange at most %{count} cards.") % { count: maximum } if cards.length > maximum
        return _("Select each card only once, from your own hand.")
      end
      return _("You have no chips left to bet.") if state[:stacks][player].to_i <= 0
      call = [state[:current_bet] - state[:street_bets][player], 0].max
      if selection.key?("raise_by") && selection["quoted_call"].to_i != call
        return _("The call amount has changed to %{amount}. Choose your raise again.") % { amount: call }
      end
      if %w[raise all_in].include?(selection["action"].to_s)
        if state[:options]["raise_cap_enabled"] && state[:raises] >= state[:options]["raise_cap"].to_i
          return _("The raise limit for this betting round has been reached.")
        end
        return _("You do not have enough chips to raise after calling.") if state[:stacks][player] <= call
        return _("Opening the betting requires a pair of jacks or better.") if !can_open_draw_betting?(state, player)
        limits = raise_limits(state, player)
        return _("Betting has not reopened for you; you cannot raise again yet.") if limits == nil
        return _("Raise by %{minimum} to %{maximum} above the call.") % { minimum: limits.begin - call, maximum: limits.end - call }
      end
      super
    end

    def describe_event(event, repository, replay, viewer)
      id = repository.event_id(event).to_i
      values = replay.history.filter_map { |entry| entry.text if entry.event_id.to_i == id }
      values.empty? ? nil : values
    end

    private

    def timed_poker_plan(action, value, state, context)
      event_plan(action, GameRoomTurnClock.encode(state, value, context))
    end

    def poker_deadline_reached?(state, now)
      [:betting, :exchange].include?(state[:phase]) && GameRoomTurnClock.expired?(state, now)
    end

    def apply_timeout(state, event, actor, repository, history, time)
      return false unless same_user?(actor, state[:players].first) && poker_deadline_reached?(state, time)
      return false unless /\A[0-9a-z]+\z/.match?(event["value"].to_s) && event["value"].to_i(36) == state[:turn_deadline]
      player = state[:current_player]
      if state[:phase] == :betting
        return apply_bet(state, event.merge("value" => "fold|0"), player, repository, history)
      end
      # All-in still has the right to a showdown: a missed exchange means
      # standing pat, never forfeiting the committed chips or playing cards.
      if state[:all_in][player]
        return apply_exchange(state, event.merge("value" => ""), player, repository, history)
      end
      # Unlike a betting fold, this happens after betting has already closed.
      # Any unmatched excess belongs to its bettor, not to a forfeited pot.
      matched = state[:contributions].reject { |other, _| other == player }.values.max.to_i
      excess = [state[:contributions][player] - matched, 0].max
      state[:contributions][player] -= excess
      state[:stacks][player] += excess
      state[:street_bets][player] = [state[:street_bets][player] - excess, 0].max
      state[:folded][player] = true
      id = repository.event_id(event)
      history << HistoryEntry.new(key: "bet:#{id}", text: betting_history(player, "fold", 0, state, state[:current_bet]),
        event_id: id, actor: player, kind: :game)
      if contenders(state).one?
        award_uncontested(state, contenders(state).first, id, history)
      else
        advance_exchange(state, player, id, history)
      end
      true
    end

    def initial_state(players, options)
      chips = options["starting_chips"].to_i
      { players: players, options: options, stacks: players.to_h { |player| [player, chips] },
        phase: :awaiting_deal, hand_number: 0, dealer_index: nil, current_player: nil,
        hands: players.to_h { |player| [player, []] }, deck: [], community: [], seed: nil,
        folded: {}, all_in: {}, acted: {}, acted_at_bet: {}, exchanged: {}, draw_discards: [], recycle: 0, street: 0, current_bet: 0, min_raise: options["big_blind"].to_i,
        street_bets: players.to_h { |player| [player, 0] }, contributions: players.to_h { |player| [player, 0] },
        raises: 0, hand_started_at: 0, tournament_started_at: 0, winner: nil }
    end

    def apply_deal(state, event, actor, repository, history)
      return false if !same_user?(actor, state[:players].first) || ![:awaiting_deal, :hand_complete].include?(state[:phase])
      hand_text, dealer_text, seed, timestamp_text = event["value"].to_s.split("|", 4)
      hand_number, dealer, timestamp = Integer(hand_text, 10), Integer(dealer_text, 10), Integer(timestamp_text, 10)
      return false if hand_number != state[:hand_number] + 1 || seed !~ /\A[0-9a-f]{32}\z/ || timestamp < 0
      seated = seated_players(state)
      return false if seated.length < 2 || !seated.include?(state[:players][dealer])
      previous_blinds = [current_small_blind(state), current_big_blind(state)]
      deck = shuffled_cards(standard_deck, seed)
      count = state[:options]["variant"] == "holdem" ? 2 : 5
      hands = state[:players].to_h { |player| [player, []] }
      cursor = dealer
      (seated.length * count).times do
        cursor = next_seated_index(state, cursor)
        hands[state[:players][cursor]] << deck.shift
      end
      state.update(hand_number: hand_number, dealer_index: dealer, hands: hands, deck: deck, community: [], seed: seed,
        folded: {}, all_in: {}, acted: {}, acted_at_bet: {}, exchanged: {}, draw_discards: [], recycle: 0, street: 0, current_bet: 0,
        min_raise: current_big_blind(state), street_bets: state[:players].to_h { |player| [player, 0] },
        contributions: state[:players].to_h { |player| [player, 0] }, raises: 0, hand_started_at: timestamp,
        tournament_started_at: state[:tournament_started_at].to_i.zero? ? timestamp : state[:tournament_started_at])
      state[:min_raise] = current_big_blind(state)
      payments = []
      if state[:options]["variant"] == "draw" && !state[:options]["draw_uses_blinds"]
        seated.each do |player|
          paid = commit_chips(state, player, [state[:options]["ante"].to_i, state[:stacks][player]].min, street: false)
          payments << _("%{player} pays ante: %{amount}.") % { player: participant_name(player), amount: paid } if paid > 0
        end
        state[:phase] = :betting
        state[:current_player] = first_actionable_after_dealer(state)
      else
        if seated.length == 2
          small_index = dealer
          big_index = next_seated_index(state, dealer)
        else
          small_index = next_seated_index(state, dealer)
          big_index = next_seated_index(state, small_index)
        end
        small_paid = commit_chips(state, state[:players][small_index], [current_small_blind(state), state[:stacks][state[:players][small_index]]].min)
        big_paid = commit_chips(state, state[:players][big_index], [current_big_blind(state), state[:stacks][state[:players][big_index]]].min)
        payments << _("%{player} pays the small blind: %{amount}.") % { player: participant_name(state[:players][small_index]), amount: small_paid }
        payments << _("%{player} pays the big blind: %{amount}.") % { player: participant_name(state[:players][big_index]), amount: big_paid }
        state[:current_bet] = state[:street_bets].values.max
        state[:phase] = :betting
        state[:current_player] = state[:players][next_actionable_index(state, big_index)]
      end
      id = repository.event_id(event)
      history << HistoryEntry.new(key: "deal:#{hand_number}", text: _("Poker hand %{hand} was dealt. Dealer: %{dealer}.") % { hand: hand_number, dealer: participant_name(state[:players][dealer]) }, event_id: id, actor: actor, kind: :deal)
      if (state[:options]["variant"] != "draw" || state[:options]["draw_uses_blinds"]) && previous_blinds != [current_small_blind(state), current_big_blind(state)]
        payments.unshift(_("Blinds increase to %{small} and %{big}.") % { small: current_small_blind(state), big: current_big_blind(state) })
      end
      history << HistoryEntry.new(key: "forced_bets:#{id}", text: payments.join(" "), event_id: id, actor: "", kind: :game) if !payments.empty?
      stage_history(state, id, history, state[:options]["variant"] == "draw" ? _("First betting round.") : _("Preflop. First betting round."))
      progress_after_action(state, state[:players][dealer], id, history) if betting_complete?(state)
      true
    rescue ArgumentError
      false
    end

    def apply_bet(state, event, actor, repository, history)
      return false if state[:phase] != :betting || !same_user?(state[:current_player], actor)
      action, amount_text = event["value"].to_s.split("|", 2)
      amount = Integer(amount_text.to_s, 10) rescue nil
      return false if amount == nil
      player = player_key(state, actor)
      candidate = bet_candidate(state, actor, action, amount)
      return false if candidate == nil
      paid = 0
      previous_bet = state[:current_bet]
      case action
      when "fold"
        state[:folded][player] = true
      when "check"
      when "call"
        paid = commit_chips(state, player, candidate["amount"].to_i)
      when "raise", "all_in"
        paid = commit_chips(state, player, candidate["amount"].to_i)
        if state[:street_bets][player] > state[:current_bet]
          increase = state[:street_bets][player] - state[:current_bet]
          state[:current_bet] = state[:street_bets][player]
          if increase >= state[:min_raise]
            state[:min_raise] = increase
            state[:raises] += 1
            state[:acted] = {}
          end
        end
      end
      state[:all_in][player] = true if state[:stacks][player].zero?
      state[:acted][player] = true
      (state[:acted_at_bet] ||= {})[player] = state[:current_bet]
      id = repository.event_id(event)
      history << HistoryEntry.new(key: "bet:#{id}", text: betting_history(player, action, paid, state, previous_bet), event_id: id, actor: actor, kind: :game)
      progress_after_action(state, player, id, history)
      true
    end

    def apply_exchange(state, event, actor, repository, history)
      return false if state[:phase] != :exchange || !same_user?(state[:current_player], actor)
      player = player_key(state, actor)
      cards = event["value"].to_s.split(",").reject(&:empty?)
      maximum = state[:options]["draw_five"] ? 5 : 3
      return false if cards.length > maximum || cards.uniq.length != cards.length || cards.any? { |card| !state[:hands][player].include?(card) }
      # Previously discarded cards may be shuffled when the deck runs out.
      # Keep this player's own discards aside until their replacement is complete.
      state[:draw_discards] ||= []
      if state[:deck].length < cards.length
        state[:recycle] = state[:recycle].to_i + 1
        state[:deck].concat(shuffled_cards(state[:draw_discards], "#{state[:seed]}:draw:#{state[:recycle]}"))
        state[:draw_discards] = []
      end
      return false if state[:deck].length < cards.length
      replacements = state[:deck].shift(cards.length)
      cards.each { |card| state[:hands][player].delete_at(state[:hands][player].index(card)) }
      state[:hands][player].concat(replacements)
      state[:draw_discards].concat(cards)
      state[:exchanged][player] = true
      id = repository.event_id(event)
      text = cards.empty? ? _("%{player} keeps all cards.") % { player: participant_name(player) } : n_("%{player} exchanged %{count} card.", "%{player} exchanged %{count} cards.", cards.length) % { player: participant_name(player), count: cards.length }
      history << HistoryEntry.new(key: "exchange:#{id}", text: text, event_id: id, actor: actor, kind: :game)
      advance_exchange(state, player, id, history)
      true
    end

    def advance_exchange(state, player, id, history)
      next_player = next_pending_exchange(state, player)
      if next_player == nil
        start_betting_street(state, 1)
        stage_history(state, id, history, _("Second betting round."))
        showdown(state, id, history) if betting_complete?(state)
      else
        state[:current_player] = next_player
      end
    end

    def progress_after_action(state, actor, event_id, history)
      live = contenders(state)
      if live.length == 1
        award_uncontested(state, live.first, event_id, history)
        return
      end
      if betting_complete?(state)
        if state[:options]["variant"] == "draw"
          if state[:street].zero?
            state[:phase] = :exchange
            state[:exchanged] = {}
            state[:current_player] = next_pending_exchange(state, state[:players][state[:dealer_index]])
            stage_history(state, event_id, history, _("Card exchange."))
          else
            showdown(state, event_id, history)
          end
        elsif state[:street] < 3
          reveal_community(state, event_id, history)
          start_betting_street(state, state[:street] + 1)
          run_out_if_needed(state, event_id, history)
        else
          showdown(state, event_id, history)
        end
      else
        state[:current_player] = state[:players][next_actionable_index(state, player_index(state[:players], actor))]
      end
    end

    def start_betting_street(state, street)
      state[:phase] = :betting
      state[:street] = street
      state[:current_bet] = 0
      state[:street_bets] = state[:players].to_h { |player| [player, 0] }
      state[:acted] = {}
      state[:acted_at_bet] = {}
      state[:raises] = 0
      state[:min_raise] = current_big_blind(state)
      state[:current_player] = first_actionable_after_dealer(state)
    end

    def stage_history(state, event_id, history, text)
      history << HistoryEntry.new(key: "stage:#{event_id}:#{state[:phase]}:#{state[:street]}",
        text: text, event_id: event_id, actor: "", kind: :game)
    end

    def reveal_community(state, event_id, history)
      state[:deck].shift
      count = state[:street].zero? ? 3 : 1
      cards = state[:deck].shift(count)
      state[:community].concat(cards)
      label = [_("Flop"), _("Turn"), p_("poker", "River")].fetch(state[:street])
      history << HistoryEntry.new(key: "stage:#{event_id}:community:#{state[:street] + 1}",
        text: _("%{stage}: %{cards}.") % { stage: label, cards: cards.map { |card| poker_card_label(card) }.join(", ") },
        event_id: event_id, actor: "", kind: :game)
    end

    def run_out_if_needed(state, event_id, history)
      return if actionable_players(state).length > 1
      while state[:street] < 3
        reveal_community(state, event_id, history)
        state[:street] += 1
      end
      showdown(state, event_id, history)
    end

    def betting_complete?(state)
      actionable = actionable_players(state)
      return true if actionable.empty?
      return true if actionable.one? && state[:street_bets][actionable.first] >= state[:current_bet]
      actionable.all? { |player| state[:acted][player] && state[:street_bets][player] == state[:current_bet] }
    end

    def showdown(state, event_id, history)
      eligible = contenders(state)
      ranks = eligible.to_h { |player| [player, hand_rank(hand_for(state, player) + state[:community])] }
      pots = side_pots(state, eligible)
      payouts = Hash.new(0)
      messages = []
      pots.each_with_index do |pot, index|
        winners = pot[:eligible].select { |player| ranks.key?(player) }
        best = winners.map { |player| ranks[player] }.max
        winners.select! { |player| ranks[player] == best }
        share, remainder = pot[:amount].divmod(winners.length)
        winners.each { |player| payouts[player] += share }
        extra_chip = winners.sort_by do |player|
          (player_index(state[:players], player) - state[:dealer_index].to_i - 1) % state[:players].length
        end.take(remainder)
        extra_chip.each { |player| payouts[player] += 1 }
        pot_name = index.zero? ? _("main pot") : _("side pot %{number}") % { number: index }
        messages << _("%{pot} is split between %{players}.") % { pot: pot_name, players: winners.map { |player| participant_name(player) }.join(", ") } if winners.length > 1
        winners.each do |player|
          peers = pot[:eligible].reject { |other| other == player }.map { |other| ranks[other] }
          messages << _("%{player} receives %{amount} from the %{pot}: %{hand}.") % {
            player: participant_name(player), amount: share + (extra_chip.include?(player) ? 1 : 0),
            pot: pot_name, hand: showdown_hand_text(ranks[player], peers)
          }
        end
      end
      payouts.each { |player, amount| state[:stacks][player] += amount }
      history << HistoryEntry.new(key: "showdown:#{event_id}", text: _("Showdown: %{summary}.") % { summary: messages.join(" ").sub(/\.\z/, "") }, event_id: event_id, actor: "", kind: :round_result)
      complete_hand(state, event_id, history)
    end

    def award_uncontested(state, player, event_id, history)
      amount = state[:contributions].values.sum
      state[:stacks][player] += amount
      history << HistoryEntry.new(key: "pot:#{event_id}", text: _("%{player} receives %{amount} from the pot; all other players folded.") % { player: participant_name(player), amount: amount }, event_id: event_id, actor: player, kind: :round_result)
      complete_hand(state, event_id, history)
    end

    def complete_hand(state, event_id, history)
      remaining = seated_players(state)
      if remaining.length <= 1
        state[:winner] = remaining.first
        state[:phase] = :finished
        state[:current_player] = nil
        history << result_history(event_id: event_id, winner: state[:winner])
      else
        state[:phase] = :hand_complete
        state[:current_player] = nil
      end
    end

    def commit_chips(state, player, amount, street: true)
      paid = [[amount.to_i, 0].max, state[:stacks][player]].min
      state[:stacks][player] -= paid
      state[:street_bets][player] += paid if street
      state[:contributions][player] += paid
      state[:all_in][player] = true if state[:stacks][player].zero?
      paid
    end

    def bet_candidate(state, actor, action, amount)
      player = player_key(state, actor)
      return nil if player == nil || state[:phase] != :betting || !same_user?(state[:current_player], actor) || state[:folded][player] || state[:all_in][player]
      if action == "raise"
        limits = raise_limits(state, player)
        return nil if limits == nil || !limits.cover?(amount) || !can_open_draw_betting?(state, player)
        return { "action" => action, "amount" => amount }
      end
      legal_actions(Replay.new(state: state, current_player: state[:current_player], winner: state[:winner], draw: false), actor).find do |item|
        item["action"] == action && item.fetch("amount", 0).to_i == amount
      end
    end

    # Inclusive bounds, not a list of sample bot bets. Humans may use any
    # integer in this interval, with exactly the same validation on replay.
    def raise_limits(state, player)
      return nil if state[:options]["raise_cap_enabled"] && state[:raises] >= state[:options]["raise_cap"].to_i
      last_bet = (state[:acted_at_bet] || {})[player] || state[:street_bets][player]
      return nil if state[:acted][player] && state[:current_bet] - last_bet < state[:min_raise]
      call_amount = [state[:current_bet] - state[:street_bets][player], 0].max
      available = state[:stacks][player] - call_amount
      return nil if available <= 0
      minimum = [state[:min_raise], available].min
      pot = state[:contributions].values.sum + call_amount
      maximum = case state[:options]["betting"]
      when "fixed" then [current_big_blind(state), available].min
      when "half_pot" then [[pot / 2, minimum].max, available].min
      when "pot_limit" then [[pot, minimum].max, available].min
      else available
      end
      minimum = maximum if state[:options]["betting"] == "fixed"
      return nil if maximum < minimum
      (call_amount + minimum)..(call_amount + maximum)
    end

    def raise_amounts(state, player)
      limits = raise_limits(state, player)
      return [] if limits == nil
      call = [state[:current_bet] - state[:street_bets][player], 0].max
      pot = state[:contributions].values.sum + call
      [limits.begin, call + pot / 2, call + pot, limits.end].map { |amount| [[amount, limits.begin].max, limits.end].min }.uniq.sort
    end

    def side_pots(state, eligible)
      levels = state[:contributions].values.select { |value| value > 0 }.uniq.sort
      previous = 0
      levels.each_with_object([]) do |level, pots|
        contributors = state[:players].select { |player| state[:contributions][player] >= level }
        amount = (level - previous) * contributors.length
        previous = level
        candidates = contributors & eligible
        next if amount.zero?
        if candidates.empty? && !pots.empty?
          # All contenders of a side pot can time out during the exchange.
          # Their matched chips are dead money, not chips to erase.
          pots.last[:amount] += amount
        elsif !candidates.empty?
          pots << { amount: amount, eligible: candidates }
        end
      end
    end

    def hand_rank(cards)
      cards.combination(5).map { |five| five_card_rank(five) }.max || [0]
    end

    def five_card_rank(cards)
      ranks = cards.map { |card| rank_index(card) }
      counts = ranks.tally
      groups = counts.map { |rank, count| [count, rank] }.sort.reverse
      flush = cards.map { |card| card[1] }.uniq.length == 1
      unique = ranks.uniq.sort
      straight = unique == [0, 1, 2, 3, 12] || (unique.length == 5 && unique.each_cons(2).all? { |left, right| right == left + 1 })
      high_straight = straight ? (unique == [0, 1, 2, 3, 12] ? 3 : unique.max) : nil
      return [8, high_straight] if straight && flush
      return [7, groups[0][1], groups[1][1]] if groups[0][0] == 4
      return [6, groups[0][1], groups[1][1]] if groups.map(&:first).take(2) == [3, 2]
      return [5, *ranks.sort.reverse] if flush
      return [4, high_straight] if straight
      return [3, groups[0][1], *groups.drop(1).map(&:last).sort.reverse] if groups[0][0] == 3
      return [2, *groups.select { |count, _| count == 2 }.map(&:last).sort.reverse, groups.find { |count, _| count == 1 }[1]] if groups.count { |count, _| count == 2 } == 2
      return [1, groups[0][1], *groups.drop(1).map(&:last).sort.reverse] if groups[0][0] == 2
      [0, *ranks.sort.reverse]
    end

    def hand_name(rank)
      [_('high card'), _('one pair'), _('two pairs'), _('three of a kind'), _('straight'), _('flush'), _('full house'), _('four of a kind'), _('straight flush')][rank.to_a[0].to_i]
    end

    def best_combination_text(cards)
      ranks = cards.to_a.map { |card| rank_index(card) }
      return _("You have no cards.") if ranks.empty?

      rank = if cards.length >= 5
        hand_rank(cards)
      else
        groups = ranks.tally.map { |value, count| [count, value] }.sort.reverse
        pairs = groups.count { |count, _value| count >= 2 }
        category = if groups[0][0] >= 4
          7
        elsif groups[0][0] >= 3
          3
        elsif pairs >= 2
          2
        elsif pairs == 1
          1
        else
          0
        end
        [category, groups[0][1]]
      end
      return _("You have no combination.") if rank[0].to_i.zero?
      important = combination_values(rank)
      return hand_name(rank) if important.empty?

      _("%{hand}: %{values}.") % {
        hand: hand_name(rank),
        values: important.map { |value| rank_label(value) }.join(", ")
      }
    end

    def showdown_hand_text(rank, peers)
      values = combination_values(rank)
      values = rank[1, 1] if rank[0] == 5
      text = values.empty? ? hand_name(rank) : _("%{hand}: %{values}") % { hand: hand_name(rank), values: values.map { |value| rank_label(value) }.join(", ") }
      # A kicker matters only when the main combination is the same. Compare
      # against the strongest competing hand, without exposing folded cards.
      runner_up = peers.compact.max
      if runner_up && rank[0] == runner_up[0] && (rank <=> runner_up) == 1
        difference = (1...[rank.length, runner_up.length].min).find { |i| rank[i] != runner_up[i] }
        if difference && difference > values.length
          text += _("; deciding card: %{card}") % { card: rank_label(rank[difference]) }
        end
      end
      text
    end

    def combination_values(rank)
      case rank.to_a[0].to_i
      when 8, 7, 4, 3, 1, 0 then rank.to_a[1, 1].to_a
      when 6, 2 then rank.to_a[1, 2].to_a
      else []
      end
    end

    def rank_label(index)
      rank = %w[2 3 4 5 6 7 8 9 T J Q K A][index.to_i]
      RANK_NAMES.fetch(rank, rank)
    end

    def rank_index(card)
      %w[2 3 4 5 6 7 8 9 T J Q K A].index(card.to_s[0]) || 0
    end

    def poker_public_ranges(replay)
      events = GameRoomParticipantDecisionEvents.for(replay).to_a
      start = events.rindex { |event| event["action"] == "deal" }
      events = events[(start + 1)..] if start
      ranges = Hash.new(0)
      events.each do |event|
        next unless event["action"] == "bet"
        name = event["value"].to_s.split("|", 2).first
        ranges[event["actor"]] += 1 if %w[raise all_in].include?(name)
      end
      ranges[:exchanges] = poker_public_exchanges(replay) if replay.state[:options]["variant"] == "draw"
      ranges
    end

    def poker_public_exchanges(replay)
      events = GameRoomParticipantDecisionEvents.for(replay).to_a
      start = events.rindex { |event| event["action"] == "deal" }
      events = events[(start + 1)..] if start
      # Only the announced NUMBER of exchanged cards is usable by opponents.
      # A timeout's forced stand-pat is not a voluntary hint of hand strength.
      events.each_with_object({}) do |event, result|
        if event["action"] == "exchange"
          result[event["actor"]] = GameRoomTurnClock.payload(replay.state, event).split(",").reject(&:empty?).length
        end
      end
    end

    def poker_pot_expectation(state, actor, contributions, ranges)
      cap = contributions[actor]
      previous = 0
      contributions.values.uniq.sort.sum do |level|
        next 0.0 if level > cap
        amount = (level - previous) * contributions.count { |_, chips| chips >= level }
        previous = level
        eligible = contenders(state).select { |player| contributions[player] >= level }
        amount * poker_equity(state, actor, opponents: eligible - [actor], ranges: ranges)
      end
    end

    def poker_equity(state, actor, opponents: nil, ranges: {})
      own = hand_for(state, actor)
      board = state[:community]
      all_opponents = contenders(state) - [actor]
      opponents ||= all_opponents
      return 1.0 if opponents.empty?
      key = [actor, own, board, all_opponents, state[:options]["variant"], ranges].inspect
      if @poker_equity_key == key
        return poker_sample_equity(opponents)
      end
      random = Random.new(Digest::SHA256.hexdigest(key).to_i(16))
      unknown = standard_deck - own - board
      @poker_samples = Array.new(64) do
        sample = unknown.dup
        # Partial Fisher-Yates, independent of the actual deal seed and hands.
        needed = state[:options]["variant"] == "holdem" ? 5 - board.length + all_opponents.length * 2 : all_opponents.length * 5
        needed.times do |index|
          other = index + random.rand(sample.length - index)
          sample[index], sample[other] = sample[other], sample[index]
        end
        simulated_board = state[:options]["variant"] == "holdem" ? board + sample.shift(5 - board.length) : []
        own_rank = hand_rank(own + simulated_board)
        rivals = all_opponents.to_h do |player|
          cards = sample.shift(state[:options]["variant"] == "holdem" ? 2 : 5)
          rank = hand_rank(cards + simulated_board)
          strength = if state[:options]["variant"] == "holdem"
            values = cards.map { |card| rank_index(card) }
            [values.sum / 24.0 + (values.uniq.length == 1 ? 0.45 : 0), 1.0].min
          else
            [rank[0] / 3.0, 1.0].min
          end
          # Importance weights condition the SAME worlds on public aggression;
          # no actual opposing hand or private discard is read.
          weight = 1.0 + [ranges.fetch(player, 0), 3].min * (strength - 0.5) * 0.5
          if state[:options]["variant"] == "draw"
            exchanged = ranges.fetch(:exchanges, {})[player]
            weight *= poker_exchange_evidence_weight(rank, exchanged) unless exchanged == nil
          end
          [player, [rank, weight]]
        end
        [own_rank, rivals]
      end
      @poker_equity_key = key
      poker_sample_equity(opponents)
    end

    def poker_sample_equity(opponents)
      weighted_wins = 0.0
      weights = 0.0
      @poker_samples.each do |own, rivals|
        entries = opponents.map { |player| rivals.fetch(player) }
        weight = entries.reduce(1.0) { |product, entry| product * entry[1] }
        comparison = entries.map { |entry| own <=> entry[0] }
        weighted_wins += weight / (1 + comparison.count(0)) unless comparison.include?(-1)
        weights += weight
      end
      weighted_wins / weights
    end

    def poker_exchange_value(state, actor, discards, exchanges: {})
      own = hand_for(state, actor)
      opponents = contenders(state).reject { |player| same_user?(player, actor) }
      key = [actor, own, opponents, state[:options]["draw_five"], exchanges].inspect
      if @exchange_plan_key != key
        @exchange_plan_key = key
        random = Random.new(Digest::SHA256.hexdigest(key).to_i(16))
        unknown = standard_deck - own
        @exchange_samples = Array.new(96) do
          sample = unknown.dup
          sample.length.times do |index|
            other = index + random.rand(sample.length - index)
            sample[index], sample[other] = sample[other], sample[index]
          end
          draw = sample.shift(5)
          hands = Array.new(opponents.length) { sample.shift(5) }
          weight = 1.0
          ranks = hands.each_with_index.map do |hand, index|
            maximum = state[:options]["draw_five"] ? 5 : 3
            discard = poker_model_discards(hand, maximum)
            observed = exchanges[opponents[index]]
            if observed
              # Weight worlds consistent with the public decision more highly;
              # retain bluff/deceptive exchanges instead of declaring impossible.
              weight *= observed == discard.length ? 3.0 : 0.5
              discard = poker_model_exchange_count(hand, observed, discard)
            end
            # Recycle previously discarded cards only if the pool runs out,
            # never the cards this opponent is currently exchanging.
            count = [discard.length, sample.length].min
            final = (hand - discard.first(count)) + sample.shift(count)
            sample.concat(discard.first(count))
            five_card_rank(final)
          end
          [draw, ranks, weight]
        end
        @exchange_scores = {}
        @exchange_outcomes = {}
        maximum = state[:options]["draw_five"] ? 5 : 3
        @exchange_reference = poker_model_discards(own, maximum).sort
      end
      @exchange_scores[discards.sort] ||= begin
        outcomes = poker_exchange_outcomes(own, discards)
        reference = poker_exchange_outcomes(own, @exchange_reference)
        total = @exchange_samples.sum { |sample| sample[2] }
        mean = outcomes.each_with_index.sum { |value, i| value * @exchange_samples[i][2] } / total
        difference = outcomes.zip(reference).map { |value, prior| value - prior }
        delta = difference.each_with_index.sum { |value, i| value * @exchange_samples[i][2] } / total
        # Paired uncertainty on the SAME worlds: an improvement smaller than
        # its sampling noise should not break a sensible standard exchange.
        # This is a conservative heuristic, not a confidence guarantee and
        # not additional samples. A clear improvement still beats the prior.
        variance = difference.each_with_index.sum do |value, i|
          @exchange_samples[i][2]**2 * (value - delta)**2
        end / total**2
        mean - Math.sqrt(variance) + (discards.sort == @exchange_reference ? 0.0001 : 0.0) - discards.length * 0.00001
      end
    end

    def poker_exchange_outcomes(own, discards)
      @exchange_outcomes[discards.sort] ||= @exchange_samples.map do |draw, opponents, _weight|
        rank = five_card_rank((own - discards) + draw.first(discards.length))
        comparisons = opponents.map { |opponent| rank <=> opponent }
        comparisons.include?(-1) ? 0.0 : 1.0 / (1 + comparisons.count(0))
      end
    end

    def poker_model_exchange_count(hand, count, preferred)
      # Keep paired/high cards longest if an observed count differs from the
      # simple model's preferred count. Does not inspect private discards.
      groups = hand.group_by { |card| rank_index(card) }
      rest = (hand - preferred).sort_by { |card| [groups[rank_index(card)].length, rank_index(card)] }
      (preferred + rest).first(count)
    end

    def poker_exchange_evidence_weight(rank, count)
      # Approximate public evidence after a draw; keeping all five usually
      # signals a made hand but can still be a bluff. Never a hard constraint.
      case count
      when 0 then rank[0] >= 4 ? 3.0 : 0.5
      when 1 then rank[0] >= 2 ? 2.0 : 1.0
      when 2 then rank[0] >= 3 ? 2.0 : 1.0
      when 3 then rank[0] >= 1 ? 1.5 : 1.0
      else 1.0
      end
    end

    def poker_model_discards(hand, maximum)
      rank = five_card_rank(hand)
      return [] if rank[0] >= 4
      groups = hand.group_by { |card| rank_index(card) }
      if groups.values.any? { |cards| cards.length >= 2 }
        return groups.values.select { |cards| cards.length == 1 }.flatten.first(maximum)
      end
      flush = hand.group_by { |card| card[-1] }.values.find { |cards| cards.length == 4 }
      return hand - flush if flush
      values = groups.keys
      (-1..8).each do |low|
        straight = (low..(low + 4)).map { |value| value == -1 ? 12 : value }
        keep = hand.select { |card| straight.include?(rank_index(card)) }
        return hand - keep if keep.length == 4
      end
      hand.sort_by { |card| rank_index(card) }.first([maximum, 3].min)
    end

    def can_open_draw_betting?(state, player)
      return true if state[:options]["variant"] != "draw" || !state[:options]["jacks_or_better"]
      return true if state[:street].to_i > 0 || state[:current_bet].to_i > 0

      rank = hand_rank(hand_for(state, player))
      rank[0].to_i > 1 || (rank[0].to_i == 1 && rank[1].to_i >= rank_index("JC"))
    end

    def information_shortcuts(state, viewer)
      player = player_key(state, viewer)
      cards = hand_for(state, viewer)
      board = state[:community]
      result = [
        announcement_shortcut(key: "s", label: _("read your stack"), message: _("Your stack: %{chips}.") % { chips: state[:stacks][player].to_i }),
        GameShortcut.new(key: "s", modifiers: [:shift], label: _("read other stacks"), kind: :announcement, message: stack_text(state, viewer)),
        announcement_shortcut(key: "v", label: _("read the call amount"), message: _("To call: %{amount}.") % { amount: player == nil ? 0 : [state[:current_bet] - state[:street_bets][player], 0].max }),
        announcement_shortcut(key: "d", label: _("read your cards"), message: cards.empty? ? _("You have no cards.") : cards.map { |card| poker_card_label(card) }.join(", ")),
        announcement_shortcut(key: "e", label: _("read visible table cards"), message: board.empty? ? _("No community cards are visible.") : board.map { |card| poker_card_label(card) }.join(", ")),
        announcement_shortcut(key: "p", label: _("read the pot"), message: _("Pot: %{amount}.") % { amount: state[:contributions].values.sum }),
        announcement_shortcut(key: "i", label: _("read your total investment"), message: _("You have invested %{amount} in this hand.") % { amount: state[:contributions][player].to_i }),
        announcement_shortcut(key: "h", label: _("read active and folded players"), message: active_text(state)),
        announcement_shortcut(key: "g", label: _("read your best combination"), message: cards.empty? ? _("You have no cards.") : best_combination_text(cards + board)),
        announcement_shortcut(key: "l", label: _("read the blinds"), message: _("Blinds: %{small} and %{big}.") % { small: current_small_blind(state), big: current_big_blind(state) })
      ]
      1.upto(state[:options]["variant"] == "draw" ? 5 : 7) do |number|
        card = state[:options]["variant"] == "draw" || number <= 2 ? cards[number - 1] : board[number - 3]
        result << announcement_shortcut(key: number.to_s, label: _("read card %{number}") % { number: number }, message: card == nil ? _("No card in position %{number}.") % { number: number } : poker_card_label(card))
      end
      result
    end

    def betting_action_label(action, state, viewer)
      case action["action"]
      when "check" then _("Check")
      when "call" then _("Call %{amount}") % { amount: action["amount"] }
      when "fold" then _("Fold")
      when "raise"
        player = player_key(state, viewer)
        call = [state[:current_bet] - state[:street_bets][player], 0].max
        _("Raise by %{raise}; total payment %{amount}") % { raise: action["amount"] - call, amount: action["amount"] }
      when "all_in" then _("All in; %{amount}") % { amount: action["amount"] }
      else action["action"]
      end
    end

    def betting_history(player, action, amount, state, previous_bet = nil)
      case action
      when "fold" then _("%{player} folds.") % { player: participant_name(player) }
      when "check" then _("%{player} checks.") % { player: participant_name(player) }
      when "call" then _("%{player} calls %{amount}.") % { player: participant_name(player), amount: amount }
      when "raise" then _("%{player} raises by %{increase}, to %{amount}.") % { player: participant_name(player), increase: state[:street_bets][player] - (previous_bet || state[:current_bet]), amount: state[:street_bets][player] }
      when "all_in" then _("%{player} is all in for %{amount}.") % { player: participant_name(player), amount: amount }
      end
    end

    def blind_level(state)
      return 0 if state[:options]["blind_interval"] == "never"
      return [state[:hand_number].to_i - 1, 0].max / state[:options]["blind_interval_value"].to_i if state[:options]["blind_interval"] == "hands"
      elapsed = [state[:hand_started_at].to_i - state[:tournament_started_at].to_i, 0].max
      elapsed / (state[:options]["blind_interval_value"].to_i * 60)
    end

    def current_small_blind(state)
      state[:options]["small_blind"].to_i * (state[:options]["blind_multiplier"].to_i**blind_level(state))
    end

    def current_big_blind(state)
      state[:options]["big_blind"].to_i * (state[:options]["blind_multiplier"].to_i**blind_level(state))
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def hand_for(state, actor)
      player = player_key(state, actor)
      player == nil ? [] : state[:hands][player]
    end

    def seated_players(state)
      state[:players].select { |player| state[:stacks][player].to_i > 0 }
    end

    def contenders(state)
      state[:players].select do |player|
        !state[:hands][player].to_a.empty? && !state[:folded][player]
      end
    end

    def actionable_players(state)
      contenders(state).reject { |player| state[:all_in][player] }
    end

    def next_seated_index(state, index)
      cursor = index.to_i
      state[:players].length.times do
        cursor = (cursor + 1) % state[:players].length
        return cursor if state[:stacks][state[:players][cursor]].to_i > 0
      end
      cursor
    end

    def next_actionable_index(state, index)
      cursor = index.to_i
      state[:players].length.times do
        cursor = (cursor + 1) % state[:players].length
        return cursor if actionable_players(state).include?(state[:players][cursor])
      end
      cursor
    end

    def first_actionable_after_dealer(state)
      state[:players][next_actionable_index(state, state[:dealer_index])]
    end

    def next_pending_exchange(state, actor)
      index = player_index(state[:players], actor)
      state[:players].length.times do
        index = (index + 1) % state[:players].length
        player = state[:players][index]
        return player if contenders(state).include?(player) && !state[:exchanged][player]
      end
      nil
    end

    def playing_sort_key(card)
      [PLAYROOM_SUIT_ORDER.index(card[1]) || 9, PLAYROOM_RANK_ORDER.index(card[0]) || 99]
    end

    def poker_card_label(card)
      _("%{rank} of %{suit}") % { rank: RANK_NAMES.fetch(card.to_s[0], card.to_s[0]), suit: SUIT_NAMES.fetch(card.to_s[1], card.to_s[1]) }
    end

    def stack_text(state, viewer)
      replay = Replay.new(state: state)
      out = state[:players].to_h { |p| [p, eliminated_from_game?(replay, p)] }
      score_announcement_order(state[:players], state[:stacks], eliminated: out).reject { |player| same_user?(player, viewer) }.map { |player| _("%{player}: %{chips}") % { player: participant_name(player), chips: state[:stacks][player] } }.join("; ")
    end

    def active_text(state)
      _("In: %{active}; folded: %{folded}.") % { active: contenders(state).length, folded: state[:folded].count { |_player, folded| folded } }
    end
  end
end

require_relative 'generated/rulebooks/poker'
