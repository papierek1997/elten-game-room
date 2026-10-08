require_relative "../lib/game_card_wire"
require "digest"
require_relative "base"
require_relative "../lib/game_bots"
require_relative "../lib/spades_learning"
require_relative "../lib/spades_round_planner"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Spades < Base
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    SUITS = %w[C D H S].freeze
    # Immutable deck metadata; each actual deal receives its own mutable array.
    DECKS = { 3 => 1, 4 => 0, 5 => 2, 6 => 4 }.to_h do |count, removed_twos|
      deck = SUITS.product(RANKS).map { |suit, rank| "#{rank}#{suit}".freeze }
      SUITS.first(removed_twos).each { |suit| deck.delete("2#{suit}") }
      [count, deck.freeze]
    end.freeze
    DECK_SUIT_COUNTS = DECKS.transform_values do |deck|
      SUITS.to_h { |suit| [suit, deck.count { |card| card[1] == suit }] }.freeze
    end.freeze
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
    DIFFICULT_CONTRACT_THRESHOLD = {
      3 => 10,
      4 => 7,
      5 => 6,
      6 => 5
    }.freeze
    PLANNING_FULL_CONFIDENCE_MARGIN = 8.0
    PLANNING_DOMINATED_RAW_MARGIN = 40.0
    PLANNING_DOMINATED_CHOICE_PENALTY = 24.0
    PLANNING_MATCH_LOSS_RAW_THRESHOLD = 500.0
    BID_THREAT_MAX_PENALTY = 3.5
    MATCH_CLOSING_BID_PENALTY = 24.0
    CERTAIN_TRICK_NIL_PENALTY = 1_000.0
    MATCH_DEFENSE_TRICK_PRIORITY = 72.0
    FUTURE_CONTROL_DISCARD_PENALTY = 28.0
    EXPIRING_CONTROL_PRIORITY = 30.0
    # The raw hand-strength model was originally tuned around five-player
    # deals. Fewer opponents make high cards and long trump suits substantially
    # stronger, while six-player hands convert slightly fewer nominal winners.
    # These factors calibrate the mean estimate to the fair share of available
    # tricks for each supported deck size without revealing any private hand.
    BID_STRENGTH_SCALE = {
      3 => 1.901,
      4 => 1.392,
      5 => 1.003,
      6 => 0.818
    }.freeze

    UnitResult = Struct.new(
      :unit,
      :points,
      :score,
      keyword_init: true
    )
    ScoreResult = Struct.new(:scores, :units, keyword_init: true)

    class Scoring
      def initialize(players, options)
        @players = players.to_a
        @options = options
        @assignment = build_assignment
      end

      def unit_ids
        return @players.dup if @assignment == nil

        @assignment.team_ids
      end

      def members_for(unit)
        return @players if unit == "all"
        return @assignment.members_for(unit) if @assignment != nil

        @players.select { |player| player.to_s.casecmp(unit.to_s) == 0 }
      end

      def apply(bids:, tricks:, scores:)
        updated_scores = unit_ids.each_with_object({}) do |unit, result|
          result[unit] = scores.fetch(unit, 0).to_i
        end
        units = unit_ids.map do |unit|
          points, earned = score_unit(members_for(unit), bids, tricks)
          if !quicksand?
            current_bags = updated_scores[unit] % 10
            points -= ((current_bags + earned) / 10) * 100
          end
          updated_scores[unit] += points
          UnitResult.new(
            unit: unit,
            points: points,
            score: updated_scores[unit]
          )
        end
        ScoreResult.new(scores: updated_scores, units: units)
      end

      private

      def score_unit(members, bids, tricks)
        nil_players = members.select { |player| bids.fetch(player, -1).to_i == 0 }
        regular_players = members.reject { |player| bids.fetch(player, -1).to_i == 0 }
        points = 0
        bags = 0

        nil_players.each do |player|
          won = tricks.fetch(player, 0).to_i
          points += won == 0 ? 100 : -100
          if won > 0 && !quicksand?
            points += won
            bags += won
          end
        end

        if !regular_players.empty?
          bid = regular_players.sum { |player| bids.fetch(player, 0).to_i }
          won = regular_players.sum { |player| tricks.fetch(player, 0).to_i }
          contract_points, contract_bags = score_regular_contract(bid, won)
          points += contract_points
          bags += contract_bags
        end

        [points, bags]
      end

      def score_regular_contract(bid, won)
        if won < bid
          points = quicksand? ? -10 * (bid - won) : -10 * bid
          return [points, 0]
        end

        extra = won - bid
        points = if quicksand?
          10 * bid - 10 * extra
        else
          10 * bid + extra
        end
        if !quicksand?
          points += 20 if [3, 4].include?(@players.length) && [1, 2].include?(bid) && won == bid
          threshold = DIFFICULT_CONTRACT_THRESHOLD.fetch(@players.length)
          points += 10 * (bid - threshold + 1) if bid >= threshold
        end
        [points, quicksand? ? 0 : extra]
      end

      def build_assignment
        size = team_size
        return nil if size <= 0

        GameRoomTeams::Assignment.new(
          players: @players,
          team_size: size,
          seats: @options[GameRoomTeams::OPTION_KEY]
        )
      rescue ArgumentError
        nil
      end

      def team_size
        return @options["team_size"].to_i if @options.key?("team_size")

        @options["partnership"] == true ? 2 : 0
      end

      def quicksand?
        @options["quicksand"] == true
      end
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      return "shuffle" if action == "deal"
      return nil if action != "play"

      event["value"].to_s.end_with?("S") ? ["play", "draw2"] : "play"
    end

    def id
      "spades"
    end

    def notification_option_keys(_options); %w[no_hell quicksand suicide score_limit]; end
    def notification_variant(options)
      names = {"no_hell" => _("No hell"), "quicksand" => _("Quicksand"), "suicide" => _("Suicide")}
      selected = names.filter_map { |key, label| label if options[key] == true }
      selected << _("Standard") if selected.empty? && names.keys.all? { |key| options[key] == false }
      (selected + [notification_points(options, "score_limit")]).compact.join(", ")
    end

    def name
      _("Spades")
    end

    def short_description
      _("Predict how many times you will collect the cards from the table, then play to fulfil your bid.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      3
    end

    def maximum_players
      6
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= SpadesLearning::Strategy.new
    end

    def perfect_information?
      false
    end

    def bot_allied?(replay, first, second)
      assignment = team_assignment(replay.state[:options], players: replay.players)
      return super if assignment == nil

      assignment.team_index_for(first) == assignment.team_index_for(second)
    end

    def bot_reward(replay, actor)
      return 0.0 if !replay.finished?

      assignment = team_assignment(replay.state[:options], players: replay.players)
      return super if assignment == nil

      team = assignment.team_index_for(actor)
      replay.winner.to_s == "team:#{team}" ? 1.0 : -1.0
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "score_limit",
          label: _("Score limit"),
          kind: :integer,
          default: 300
        ),
        OptionDefinition.new(
          key: "team_size",
          label: _("Team arrangement"),
          kind: :choice,
          default: 0,
          choices: [
            OptionChoice.new(value: 0, label: _("Individual play")),
            OptionChoice.new(value: 2, label: _("Teams of two")),
            OptionChoice.new(value: 3, label: _("Teams of three"))
          ]
        ),
        OptionDefinition.new(
          key: "no_hell",
          label: _("No hell"),
          kind: :boolean,
          default: false,
          visible_if: ->(options) { options["suicide"] != true || options["no_hell"] == true }
        ),
        OptionDefinition.new(
          key: "quicksand",
          label: _("Quicksand scoring"),
          kind: :boolean,
          default: false
        ),
        OptionDefinition.new(
          key: "suicide",
          label: _("Suicide"),
          kind: :boolean,
          default: false,
          visible_if: ->(options) { options["no_hell"] != true || options["suicide"] == true }
        ),
        OptionDefinition.new(
          key: "omniscient_bots",
          label: _("Omniscient bots (they can see every hand)"),
          kind: :boolean,
          default: false
        )
      ]
    end

    def normalize_options(values)
      source = values.is_a?(Hash) ? values.dup : {}
      has_team_size = source.key?("team_size") || source.key?(:team_size)
      if !has_team_size
        legacy = if source.key?("partnership")
          source["partnership"]
        elsif source.key?(:partnership)
          source[:partnership]
        end
        source["team_size"] = legacy == true ? 2 : 0 if legacy != nil
      end
      super(source)
    end

    def team_size(options, player_count:)
      normalize_options(options)["team_size"].to_i
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("The score limit must be greater than zero.") if values["score_limit"].to_i <= 0
      return _("No Hell and Suicide cannot be enabled together.") if values["no_hell"] && values["suicide"]

      team_size = values["team_size"].to_i
      if values["suicide"] && team_size != 2
        return _("Suicide requires teams of two.")
      end
      if player_count != nil
        count = player_count.to_i
        if team_size == 2 && ![4, 6].include?(count)
          return _("Teams of two require four or six players.")
        end
        if team_size == 3 && count != 6
          return _("Teams of three require exactly six players.")
        end
      end

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      arrangement = case values["team_size"].to_i
      when 2 then _("teams of two")
      when 3 then _("teams of three")
      else _("individual play")
      end
      variants = [arrangement]
      variants << _("No hell") if values["no_hell"]
      variants << _("Quicksand") if values["quicksand"]
      variants << _("Suicide") if values["suicide"]
      variants << _("omniscient bots") if values["omniscient_bots"]
      _("to %{score} points; %{variants}") % {
        score: values["score_limit"],
        variants: variants.join(", ")
      }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      scoring = Scoring.new(players, options)
      state = initial_state(players, options, scoring)
      accepted = []
      history = [starting_history(players)]

      events.each do |event|
        break if state[:winner] != nil

        applied = apply_replay_event(state, event, session, repository, history, scoring)
        accepted << event if applied
      end

      Replay.new(
        board: nil,
        players: players,
        current_player: state[:current_player],
        winner: state[:winner],
        draw: false,
        accepted_events: accepted,
        history: history,
        state: state
      )
    end

    # Training matches can contain thousands of actions. Replaying the whole
    # event stream after every card makes their running time quadratic. The
    # production replay remains the source of truth; the simulator merely uses
    # the same event applicators to extend its cached replay in place.
    def incremental_replay(replay, session, events, repository)
      return nil if replay == nil || replay.state == nil

      state = replay.state
      options = options_from_json(session["options"])
      scoring = Scoring.new(replay.players, options)
      events.each do |event|
        break if state[:winner] != nil

        if apply_replay_event(state, event, session, repository, replay.history, scoring)
          decision_events = GameRoomParticipantDecisionEvents.for(replay)
          unless decision_events.equal?(replay.accepted_events)
            actor = repository.actor_of(event, session)
            decision_events << event.merge('__replay_actor' => actor, 'actor' => actor)
          end
          replay.accepted_events << event
        end
      end
      replay.current_player = state[:current_player]
      replay.winner = state[:winner]
      replay.draw = false
      replay
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if state == nil || state[:winner] != nil
      return nil if !same_user?(actor, replay.players.first)
      return nil if ![:awaiting_deal, :round_complete].include?(state[:phase])

      { "kind" => "command", "action" => "deal" }
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || state[:winner] != nil
      return [] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :bidding
        legal_bid_values(state, actor).map do |bid|
          { "kind" => "command", "action" => "bid_#{bid}", "bid" => bid }
        end
      when :playing
        legal_cards(state, actor).map do |card|
          { "kind" => "card", "action" => "select", "zone" => "hand", "card" => card, "card_id" => card }
        end
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
      grouped = actions.group_by { |action| action["card_id"].to_s }
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
        dealer = if state[:dealer_index] == nil
          seed.to_i(16) % replay.players.length
        else
          (state[:dealer_index].to_i + 1) % replay.players.length
        end
        return [:ok, event_plan("deal", [round, dealer, seed].join("|"))]
      end

      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :bidding
        return [:invalid, nil] if selection["kind"].to_s != "command"
        bid = selection_value(selection, "bid")
        if !selection.key?("bid")
          match = /\Abid_(\d+)\z/.match(selection["action"].to_s)
          return [:invalid, nil] if match == nil
          bid = match[1].to_i
        end
        return [:invalid_bid, nil] if !legal_bid_values(state, actor).include?(bid)

        [:ok, event_plan("bid", bid.to_s)]
      when :playing
        return [:invalid, nil] if selection["kind"].to_s != "card"
        return [:invalid, nil] if selection["action"].to_s != "select"
        card = selection["card"].to_s
        hand = hand_for(state, actor)
        return [:card_not_in_hand, nil] if hand == nil || !hand.include?(card)
        return [:must_follow_suit, nil] if !legal_cards(state, actor).include?(card)

        [:ok, event_plan("play", card)]
      else
        [:invalid, nil]
      end
    end

    def hand_sorting_available?(replay, viewer)
      !hand_for(replay.state, viewer).to_a.empty?
    end

    def surface_spec(replay, viewer)
      card_table_spec(replay.state, viewer)
    end

    def move_error(status)
      case status
      when :invalid_bid
        _("This bid is not allowed with the selected Spades rules.")
      when :card_not_in_hand
        _("This card is not in your hand.")
      when :must_follow_suit
        _("You must follow the suit that was led.")
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id }
      return nil if entries.empty?

      entries.map(&:text)
    end

    def result_text(replay)
      return nil if replay.winner == nil

      _("%{winner} won the game.") % { winner: unit_label(replay.state, replay.winner) }
    end

    def participant_scores(replay)
      state = replay.state
      scoring = Scoring.new(state[:players], state[:options])
      scoring.unit_ids.each_with_object({}) do |unit, scores|
        scoring.members_for(unit).each { |player| scores[player] = state[:scores].fetch(unit, 0) }
      end
    end

    def shortcut_features
      [:bidding] + super + [
        :hand,
        :table_cards,
        :table_cards_list,
        :led_suit,
        :round_summary,
        :round_information,
        :scores
      ]
    end

    # Keep an explicit delegator so a development soft reload replaces the
    # pre-feature implementation that older builds defined on this class.
    def game_shortcuts(replay, viewer)
      super
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      return nil if state == nil

      case feature.to_sym
      when :bidding
        bids = legal_bid_values(state, viewer)
        if bids.empty?
          {
            message: bids_information_text(state)
          }
        else
          {
            kind: :number_input,
            label: _("make a bid"),
            prompt: _("Enter your bid. Allowed values: %{values}.") % { values: bids.join(", ") },
            action_kind: "command",
            action_name: "bid",
            value_key: "bid",
            allowed_values: bids,
            invalid_message: move_error(:invalid_bid)
          }
        end
      when :hand
        { message: hand_information_text(state, viewer) }
      when :table_cards
        { message: table_cards_information_text(state) }
      when :table_cards_list
        table_cards_browse_data(state)
      when :led_suit
        { message: led_suit_information_text(state) }
      when :round_summary
        { message: round_information_text(state) }
      when :round_information
        { message: personal_round_information_text(state, viewer) }
      when :scores
        { message: _("Scores: %{scores}.") % { scores: score_text(state, sorted: true) } }
      else
        super
      end
    end

    private

    def apply_replay_event(state, event, session, repository, history, scoring)
      actor = repository.actor_of(event, session)
      case event["action"].to_s
      when "deal"
        apply_deal(state, event, actor, repository, history)
      when "bid"
        apply_bid(state, event, actor, repository, history)
      when "play"
        apply_play(state, event, actor, repository, history, scoring)
      else
        false
      end
    end





    def current_turn_shortcut_text(replay, _viewer)
      turn_information_text(replay.state)
    end

    def initial_state(players, options, scoring)
      units = scoring.unit_ids
      {
        players: players,
        options: options,
        units: units,
        scores: units.each_with_object({}) { |unit, result| result[unit] = 0 },
        round: 0,
        phase: :awaiting_deal,
        dealer_index: nil,
        seed: nil,
        hands: players.each_with_object({}) { |player, result| result[player] = [] },
        bids: {},
        tricks: players.each_with_object({}) { |player, result| result[player] = 0 },
        current_trick: [],
        spades_broken: false,
        current_player: nil,
        winner: nil
      }
    end

    def apply_deal(state, event, actor, repository, history)
      return false if !same_user?(actor, state[:players].first)
      return false if ![:awaiting_deal, :round_complete].include?(state[:phase])

      round, dealer, seed = parse_deal(event["value"])
      return false if round != state[:round] + 1
      return false if !dealer.between?(0, state[:players].length - 1)
      if state[:dealer_index] != nil
        expected_dealer = (state[:dealer_index] + 1) % state[:players].length
        return false if dealer != expected_dealer
      end

      hands = deal_hands(state[:players], dealer, seed)
      return false if hands.values.map(&:length).uniq.length != 1

      state[:round] = round
      state[:phase] = :bidding
      state[:dealer_index] = dealer
      state[:seed] = seed
      state[:hands] = hands
      state[:bids] = {}
      state[:tricks] = state[:players].each_with_object({}) { |player, result| result[player] = 0 }
      state[:current_trick] = []
      state[:spades_broken] = false
      state[:current_player] = state[:players][(dealer + 1) % state[:players].length]
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "deal:#{round}",
        text: _("Round %{round} was dealt. %{dealer} is the dealer.") % {
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

    def apply_bid(state, event, actor, repository, history)
      return false if state[:phase] != :bidding
      return false if !same_user?(actor, state[:current_player])

      bid = Integer(event["value"].to_s, 10)
      return false if !legal_bid_values(state, actor).include?(bid)

      player = player_key(state, actor)
      state[:bids][player] = bid
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "bid:#{event_id}",
        text: bid == 0 ?
          _("%{player} bid nil.") % { player: participant_name(actor) } :
          _("%{player} bid %{count}.") % { player: participant_name(actor), count: bid },
        event_id: event_id,
        actor: actor,
        kind: :bid,
        value: bid
      )
      if state[:bids].length == state[:players].length
        state[:phase] = :playing
        state[:current_player] = state[:players][(state[:dealer_index] + 1) % state[:players].length]
      else
        state[:current_player] = next_player(state[:players], actor)
      end
      true
    rescue ArgumentError
      false
    end

    def apply_play(state, event, actor, repository, history, scoring)
      return false if state[:phase] != :playing
      return false if !same_user?(actor, state[:current_player])

      card = event["value"].to_s
      hand = hand_for(state, actor)
      return false if hand == nil || !hand.include?(card)
      return false if !legal_cards(state, actor).include?(card)

      hand.delete_at(hand.index(card))
      state[:spades_broken] = true if card_suit(card) == "S"
      state[:current_trick] << { player: player_key(state, actor), card: card }
      event_id = repository.event_id(event)
      history << HistoryEntry.new(
        key: "play:#{event_id}",
        text: _("%{player} played %{card}.") % {
          player: participant_name(actor),
          card: card_label(card)
        },
        event_id: event_id,
        actor: actor,
        kind: :play,
        value: card
      )

      if state[:current_trick].length == state[:players].length
        winner = trick_winner(state[:current_trick])
        state[:tricks][winner] += 1
        history << HistoryEntry.new(
          key: "trick:#{event_id}",
          text: _("%{player} won the trick.") % { player: participant_name(winner) },
          event_id: event_id,
          actor: winner,
          kind: :trick
        )
        state[:current_trick] = []
        if state[:hands].values.all?(&:empty?)
          complete_round(state, scoring, event_id, history)
        else
          state[:current_player] = winner
        end
      else
        state[:current_player] = next_player(state[:players], actor)
      end
      true
    end

    def complete_round(state, scoring, event_id, history)
      result = scoring.apply(
        bids: state[:bids],
        tricks: state[:tricks],
        scores: state[:scores]
      )
      state[:scores] = result.scores
      result.units.each do |unit|
        history << HistoryEntry.new(
          key: "score:#{state[:round]}:#{unit.unit}",
          text: _("%{unit}: %{change} points this round, %{score} total.") % {
            unit: unit_label(state, unit.unit),
            change: signed_number(unit.points),
            score: unit.score
          },
          event_id: event_id,
          actor: "",
          kind: :score,
          value: unit.points
        )
      end

      leaders = state[:scores].group_by { |_unit, score| score }.max_by { |score, _items| score }
      winning_units = leaders == nil ? [] : leaders[1].map(&:first)
      target = state[:options]["score_limit"].to_i
      if leaders != nil && leaders[0] >= target && winning_units.length == 1
        state[:winner] = winning_units.first
        state[:phase] = :finished
        state[:current_player] = nil
        history << HistoryEntry.new(
          key: "result:#{event_id}",
          text: _("%{winner} won the game.") % { winner: unit_label(state, state[:winner]) },
          event_id: event_id,
          actor: state[:winner],
          kind: :result
        )
      else
        state[:phase] = :round_complete
        state[:current_player] = nil
      end
    end

    def card_table_spec(state, viewer)
      hand = hand_for(state, viewer).to_a.sort_by { |card| card_sort_key(card) }
      hand_cards = hand.map do |card|
        GameSurfaces::Card.new(id: card, label: card_label(card), value: card,
          sort_keys: standard_hand_sort_keys(rank: card_rank(card), suit: card_suit(card), position: hand_for(state, viewer).index(card)))
      end
      GameSurfaces::CardTableSpec.new(
        zones: [
          GameSurfaces::CardZoneSpec.new(
            id: "hand",
            header: _("Your hand"),
            cards: hand_cards,
            hand_order: hand_for(state, viewer).to_a.dup, hand_epoch: [viewer, state[:round]].join(":"),
            empty_label: _("Your hand is empty")
          )
        ]
      )
    end

    def score_text(state, sorted: false)
      units = sorted ? score_announcement_order(state[:units], state[:scores]) : state[:units]
      units.map do |unit|
        _("%{unit} %{score}") % {
          unit: unit_label(state, unit),
          score: state[:scores][unit]
        }
      end.join("; ")
    end

    def unit_label(state, unit)
      if unit.to_s.start_with?("team:")
        members = Scoring.new(state[:players], state[:options]).members_for(unit)
        return _("Team %{players}") % {
          players: members.map { |player| participant_name(player) }.join(" and ")
        }
      end

      participant_name(unit)
    end

    def turn_information_text(state)
      case state[:phase]
      when :awaiting_deal, :round_complete
        _("Waiting for the next deal.")
      when :bidding
        _("%{player} is bidding.") % { player: participant_name(state[:current_player]) }
      when :playing
        _("It is %{player}'s turn.") % { player: participant_name(state[:current_player]) }
      when :finished
        _("The game is finished. %{winner} won.") % { winner: unit_label(state, state[:winner]) }
      else
        _("No active turn.")
      end
    end

    def bids_information_text(state)
      bids = state[:players].map do |player|
        bid = state[:bids][player]
        value = if bid == nil
          _("not bid yet")
        elsif bid.to_i == 0
          _("nil")
        else
          bid.to_i.to_s
        end
        _("%{player}: %{bid}") % { player: participant_name(player), bid: value }
      end
      _("Bids: %{bids}.") % { bids: bids.join("; ") }
    end

    def table_cards_information_text(state)
      if state[:current_trick].empty?
        return _("There are no cards on the table.")
      end

      cards = state[:current_trick].map do |play|
        _("%{player}: %{card}") % {
          player: participant_name(play[:player]),
          card: card_label(play[:card])
        }
      end
      _("Cards on the table: %{cards}.") % { cards: cards.join("; ") }
    end

    def hand_information_text(state, viewer)
      cards = hand_for(state, viewer).to_a.sort_by { |card| card_sort_key(card) }
      return _("Your hand is empty.") if cards.empty?

      _("Your hand: %{cards}.") % {
        cards: cards.map { |card| card_label(card) }.join("; ")
      }
    end

    def led_suit_information_text(state)
      return _("No suit has been led.") if state[:current_trick].empty?

      suit = card_suit(state[:current_trick].first[:card])
      _("The led suit is %{suit}.") % { suit: SUIT_NAMES.fetch(suit, suit) }
    end

    def round_information_text(state)
      trick_progress = state[:players].map do |player|
        player_trick_progress_text(state, player)
      end
      completed = state[:tricks].values.sum
      total = cards_per_player(state[:players].length)
      current = [completed + 1, total].min
      _("Round %{round}. Tricks: %{tricks}. Trick %{current} of %{total}.") % {
        round: state[:round],
        tricks: trick_progress.join("; "),
        current: current,
        total: total
      }
    end

    def personal_round_information_text(state, viewer)
      player = player_key(state, viewer)
      progress = if player == nil
        _("You are not playing in this round.")
      else
        player_trick_progress_text(state, player)
      end
      completed = state[:tricks].values.sum
      total = cards_per_player(state[:players].length)
      current = [completed + 1, total].min
      _("Round %{round}. %{progress}. Trick %{current} of %{total}.") % {
        round: state[:round],
        progress: progress,
        current: current,
        total: total
      }
    end

    def player_trick_progress_text(state, player)
      bid = state[:bids][player]
      bid_text = if bid == nil
        _("not bid yet")
      elsif bid.to_i == 0
        _("nil")
      else
        bid.to_i.to_s
      end
      _("%{player}: %{tricks}/%{bid}") % {
        player: participant_name(player),
        tricks: state[:tricks].fetch(player, 0).to_i,
        bid: bid_text
      }
    end

    def legal_bid_values(state, actor)
      return [] if state[:phase] != :bidding || !same_user?(state[:current_player], actor)

      maximum = cards_per_player(state[:players].length)
      bids = (0..maximum).to_a
      if state[:options]["suicide"]
        bids.select! { |bid| bid == 0 || bid >= 4 }
        partner = suicide_partner(state, actor)
        partner_bid = state[:bids][partner]
        bids.select! { |bid| bid == 0 } if partner_bid != nil && partner_bid.to_i >= 4
      end
      if state[:options]["no_hell"] && state[:bids].length == state[:players].length - 1
        announced = state[:bids].values.sum
        bids.reject! { |bid| announced + bid == maximum }
      end
      bids
    end

    def legal_cards(state, actor)
      return [] if state[:phase] != :playing || !same_user?(state[:current_player], actor)

      hand = hand_for(state, actor).to_a
      return [] if hand.empty?
      if state[:current_trick].empty?
        non_spades = hand.reject { |card| card_suit(card) == "S" }
        return non_spades if !state[:spades_broken] && !non_spades.empty?

        return hand
      end

      led_suit = card_suit(state[:current_trick].first[:card])
      legal_cards_for_led_suit(hand, led_suit)
    end

    # QC Salon Spades permits a player whose only spade is the ace of spades
    # to withhold it even when spades were led. The ace remains a legal play,
    # but the player may discard any other card from the hand instead.
    def legal_cards_for_led_suit(hand, led_suit)
      following = hand.select { |card| card_suit(card) == led_suit }
      lone_ace_of_spades = led_suit == "S" && following.length == 1 &&
        card_rank(following.first) == "A"
      return hand if lone_ace_of_spades && hand.length > 1

      following.empty? ? hand : following
    end

    def trick_winner(trick)
      led_suit = card_suit(trick.first[:card])
      candidates = trick.select { |play| card_suit(play[:card]) == "S" }
      candidates = trick.select { |play| card_suit(play[:card]) == led_suit } if candidates.empty?
      candidates.max_by { |play| RANKS.index(card_rank(play[:card])).to_i }[:player]
    end

    def deal_hands(players, dealer, seed)
      deck = deck_for(players.length).sort_by { |card| Digest::SHA256.hexdigest("#{seed}\0#{card}") }
      hands = players.each_with_object({}) { |player, result| result[player] = [] }
      deck.each_with_index do |card, index|
        player = players[(dealer + 1 + index) % players.length]
        hands[player] << card
      end
      hands
    end

    def deck_for(player_count)
      DECKS.fetch(player_count).dup
    end

    def cards_per_player(player_count)
      DECKS.fetch(player_count).length / player_count
    end

    def parse_deal(value)
      GameRoomCardWire.parse_deal(value)
    end

    def random_seed(source)
      source.roll(count: 16, sides: 256).values.map do |value|
        (value.to_i - 1).to_s(16).rjust(2, "0")
      end.join
    end

    def hand_for(state, actor)
      key = player_key(state, actor)
      key == nil ? nil : state[:hands][key]
    end

    def player_key(state, actor)
      state[:players].find { |player| same_user?(player, actor) }
    end

    def next_player(players, actor)
      index = players.index { |player| same_user?(player, actor) }
      index == nil ? nil : players[(index + 1) % players.length]
    end

    def suicide_partner(state, actor)
      players = state[:players]
      index = players.index { |player| same_user?(player, actor) }
      return nil if index == nil

      assignment = team_assignment(state[:options], players: players)
      return nil if assignment == nil || assignment.team_size != 2

      assignment.teammates_for(actor).find { |player| !same_user?(player, actor) }
    end

    def card_rank(card)
      card.to_s[0]
    end

    def card_suit(card)
      card.to_s[1]
    end

    def card_label(card)
      _("%{rank} of %{suit}") % {
        rank: RANK_NAMES.fetch(card_rank(card), card_rank(card)),
        suit: SUIT_NAMES.fetch(card_suit(card), card_suit(card))
      }
    end

    def card_sort_key(card)
      playroom_hand_sort_key(card)
    end

    def signed_number(value)
      value.to_i > 0 ? "+#{value.to_i}" : value.to_i.to_s
    end
  end
end

require_relative "spades/bid_evaluation"

require_relative "spades/play_evaluation"

require_relative "spades/decision_context"

require_relative 'generated/rulebooks/spades'
