require "json"
require "digest"
require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "../lib/biblios_strategy"

module GameRoomGames
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

    def id
      "biblios"
    end

    def name
      _("Biblios")
    end

    def rule_sections
      [
        rule_section(:goal, _("The goal"),
          _("You play the part of an abbot at the head of a monastery, seeking to amass the most illustrious library. The goal is to earn the most Victory Points by having a higher score in a category than anyone else."),
          _("There are five categories: Pigments, Monks, Forbidden Tomes, Holy Books and Manuscripts. The Scriptorium indicates how many Victory Points each category is worth. All dice start at 3, but these values may change during the game."),
          _("The game is split into two phases. During the Gift phase players receive free cards. During the Auction phase players purchase cards in an auction.")),
        rule_section(:gift, _("The Gift phase"),
          _("The active player allocates 5 cards in a four player game, 4 with three players and 3 with two players. To allocate a card means to draw it, look at it, and then place it in front of yourself face down, into the public space face up, or into the Auction pile face down."),
          _("The cards are allocated one at a time, so you must decide where each card goes before the next is drawn. You must allocate precisely 1 card to the space in front of yourself and precisely 1 card to the Auction pile. The remaining cards go to the public space, which therefore always holds one card fewer than the number of players."),
          _("Then, starting with the next player, each player draws a card from the public space and adds it to his or her hand. The next player then becomes the active player. The phase continues until the draw pile has been exhausted."),
          _("Players may look at the cards in their own hands at any time, but not at the hands of others. Only the cards taken from the public space and won at auction are seen by everyone.")),
        rule_section(:auction, _("The Auction phase"),
          _("The Auction pile is shuffled to make up a new draw pile, and its cards are auctioned one at a time. The active player turns the top card face up. The player after the active one must either bid at least 1 or pass, and then, in turn order, every other player either bids or passes."),
          _("You must bid higher than all prior bids. Once you have passed you cannot bid again until a new card is being auctioned. Bidding continues until only one player remains as the highest bidder. If all the players pass, the card is discarded."),
          _("For a card that is not a Gold card, players bid by announcing how much Gold they are willing to pay, and the winner pays with any combination of Gold cards from her hand. A player may be forced to pay more than the bid, as there is no change. When a Gold card is auctioned, players bid the number of cards they wish to pay instead, and pay with any cards they wish."),
          _("A player who cannot pay the bid, or chooses not to, is penalised, and the card is auctioned again without her. Under the medieval bluff she discards one card at random; under the full penalty the other players each take a card at random from her hand.")),
        rule_section(:church, _("Church cards"),
          _("As soon as a player acquires a Church card, the game is put on hold while the card is played and then discarded. A Church card is acquired when the active player keeps it for himself, when another player takes it from the public space, or when it is won at auction. A Church card placed in the Auction pile is not played at that point."),
          _("A Church card lets its owner adjust one or two dice on the Scriptorium by one point each. A card with two dice must be used on two separate categories or not at all, so you may not modify one category by two points. A player may decide not to use the card, in which case it is discarded.")),
        rule_section(:scoring, _("Winning the game"),
          _("Once all the cards have been purchased or discarded, the players group their cards by category and add up the values. The player with the highest total value in a category takes the corresponding die from the Scriptorium without changing its face. If two players are tied, the player with the card in that category closest to the letter A wins the category."),
          _("The players then add the numbers on their dice, and the player with the most Victory Points wins. The numbers on the cards are not Victory Points; they only determine who wins each category."),
          _("If two or more players are tied, the player with the most Gold wins. If there is still a tie, the higher total in the Monk category decides, then the tie-breaking letter, then the next category on the Scriptorium.")),
        rule_section(:controls, _("Selecting, bidding and paying"),
          _("Every decision is one list: use the Arrow keys and press Enter. In the Gift phase the list offers the places where the drawn card may go, and then the cards waiting in the public space. A Church card offers every legal adjustment of the dice and an option to decline."),
          _("In an auction the list offers Pass and a range of bids; a bid you cannot cover is marked, because you may bid more than you hold and accept the penalty. R bids any other amount. To pay, use Shift+Enter to add each card to the packet and Enter to send it, or choose Do not pay from the same list."),
          _("T reads the turn, L your library, Ctrl+L browses it by category, C the Scriptorium, Shift+C the standing counted from the cards taken openly, G your Gold, P the public space and B the auction. S reads the scores once the game is over."))
      ]
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

      events.each do |event|
        break if state[:phase] == :finished

        actor = repository.actor_of(event, session)
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
        return [:invalid_bid, nil] if !legal_bids(state, actor).include?(amount.to_i)

        [:ok, event_plan("bid", amount.to_i.to_s)]
      when "pay"
        return [:invalid, nil] if state[:phase] != :pay
        cards = parse_cards(selection["cards"])
        return [:ok, event_plan("pay", "")] if cards.empty? || cards.include?(DECLINE)
        return [:invalid_payment, nil] if !valid_payment?(state, player_key(state, actor), cards)

        [:ok, event_plan("pay", cards.join(","))]
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
      when :scores then replay.finished? ? { message: scores_text(state) } : nil
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
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id.to_i }
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
        "card" => state[:card],
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
        cards.empty? ? -50.0 : 100.0 - cards.sum { |card| card_worth(state, player, card) }
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
      return false if seed.empty?

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
          key: "bid:#{event_id}", text: _("%{player} passes.") % { player: participant_name(actor) },
          event_id: event_id, actor: actor, kind: :bid
        )
      else
        amount = value.to_i
        return false if !legal_bids(state, actor).include?(amount)

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
      if cards.empty?
        penalise(state, player, event_id, history)
        return true
      end
      return false if !valid_payment?(state, player, cards)

      cards.each { |card| state[:hands][player].delete_at(state[:hands][player].index(card)) }
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
      if state[:options]["penalty"] == "full"
        state[:players].each do |other|
          next if same_user?(other, player) || hand.empty?

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

        return [cards.sort_by { |card| discard_cost(card) }.first(state[:high])]
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

    def discard_cost(card)
      gold?(card) ? gold_value(card) * 2 : card_value(card)
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
      return JSON.parse(text).map(&:to_s) if text.start_with?("[")

      text.split(",").map(&:strip).reject(&:empty?)
    rescue JSON::ParserError
      []
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

    def scores_text(state)
      values = state[:players].map do |player|
        _("%{player}: %{score}") % { player: participant_name(player), score: victory_points(state, player) }
      end
      _("Victory Points: %{values}.") % { values: values.join("; ") }
    end

    def card_worth(state, player, card)
      return gold_value(card).to_f if gold?(card)
      return 2.0 if church?(card)

      category = card_category(card)
      total = category_total(state, player, category)
      best = state[:players].reject { |other| same_user?(other, player) }
        .map { |other| category_total(state, other, category) }.max.to_i
      gain = total + card_value(card) > best && total <= best ? state[:dice][category] : 0
      card_value(card) + gain
    end

    def allocation_score(state, player, place)
      card = state[:deck][state[:pointer]]
      worth = card_worth(state, player, card)
      case place
      when "self" then worth * 10.0
      when "auction" then worth * 2.0
      else -worth
      end
    end

    def plan_score(state, player, plan)
      return 0.0 if plan == "skip"

      plan.split(",").sum do |part|
        direction, category = part.split(":")
        leader = category_winner(state, category)
        mine = same_user?(leader, player)
        step = direction == "up" ? 1 : -1
        mine ? step * 10.0 : step * -6.0
      end
    end

    def bid_score(state, player, amount)
      return -1.0 if amount.to_s == "pass"

      value = amount.to_i
      worth = card_worth(state, player, state[:card])
      overshoot = value - payment_capacity(state, player)
      return worth * 10.0 - value * 8.0 if overshoot <= 0

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
