require_relative "../lib/game_card_wire"
require_relative "card_game"
require_relative "../lib/game_bots"
require_relative "bridge/rules"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # Contract bridge for four players in two fixed partnerships. A table plays
  # either one rubber or a single-table duplicate series compared with a
  # reference score. Seats are kept as indices 0..3 (North, East, South,
  # West); side 0 (team:0) is North-South and side 1 (team:1) East-West.
  class Bridge < CardGame
    R = BridgeRules
    BOARD_COUNTS = [4, 8, 12, 16, 24].freeze

    def id
      "bridge"
    end

    def name
      _("Bridge")
    end

    def short_description
      _("Bid with your partner for a contract, then take the tricks you promised while declarer plays both hands.")
    end

    def rule_sections
      generated_rule_sections
    end

    def minimum_players
      4
    end

    def maximum_players
      4
    end

    def team_size(_options, player_count:)
      2
    end

    def supports_bots?
      true
    end

    def bot_strategy
      @bot_strategy ||= BridgeStrategy.new
    end

    def perfect_information?
      false
    end

    def bot_allied?(replay, first, second)
      state = replay.state
      first_seat = seat_of(state, first)
      second_seat = seat_of(state, second)
      return super if first_seat == nil || second_seat == nil

      R.side_of(first_seat) == R.side_of(second_seat)
    end

    def bot_reward(replay, actor)
      return 0.0 if !replay.finished? || replay.draw

      seat = seat_of(replay.state, actor)
      return 0.0 if seat == nil

      replay.winner.to_s == "team:#{R.side_of(seat)}" ? 1.0 : -1.0
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      case event["action"].to_s
      when "deal" then "shuffle"
      when "play" then "play"
      end
    end

    def notification_option_keys(_options); %w[variant boards scoring]; end

    def notification_variant(options)
      values = normalize_options(options)
      return _("Rubber") if values["variant"] != "duplicate"

      _("Duplicate, %{boards} boards, %{scoring}") % {
        boards: values["boards"],
        scoring: values["scoring"] == "mp" ? _("matchpoints") : _("IMPs")
      }
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "variant",
          label: _("Bridge variant"),
          kind: :choice,
          default: "rubber",
          choices: [
            OptionChoice.new(value: "rubber", label: _("Rubber bridge (social)")),
            OptionChoice.new(value: "duplicate", label: _("Duplicate bridge (sport)"))
          ]
        ),
        OptionDefinition.new(
          key: "honors",
          label: _("Score honours"),
          kind: :boolean,
          default: true,
          visible_if: { "variant" => "rubber" }
        ),
        OptionDefinition.new(
          key: "boards",
          label: _("Number of boards"),
          kind: :choice,
          default: 8,
          choices: BOARD_COUNTS.map { |count| OptionChoice.new(value: count, label: count.to_s) },
          visible_if: { "variant" => "duplicate" }
        ),
        OptionDefinition.new(
          key: "scoring",
          label: _("Duplicate scoring"),
          kind: :choice,
          default: "imp",
          choices: [
            OptionChoice.new(value: "imp", label: _("IMPs")),
            OptionChoice.new(value: "mp", label: _("Matchpoints"))
          ],
          visible_if: { "variant" => "duplicate" }
        )
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _("Choose rubber or duplicate bridge.") if !%w[rubber duplicate].include?(values["variant"])
      return _("Choose a supported number of boards.") if !BOARD_COUNTS.include?(values["boards"].to_i)
      return _("Choose IMP or matchpoint scoring.") if !%w[imp mp].include?(values["scoring"])
      return _("Bridge requires exactly four players.") if player_count != nil && player_count.to_i != 4

      nil
    end

    def options_summary(options)
      values = normalize_options(options)
      if values["variant"] == "duplicate"
        return _("duplicate, %{boards} boards, %{scoring}") % {
          boards: values["boards"],
          scoring: values["scoring"] == "mp" ? _("matchpoints") : _("IMPs")
        }
      end

      values["honors"] ? _("rubber, honours scored") : _("rubber, without honours")
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = initial_state(players, options)
      accepted = []
      history = [starting_history_for(state)]

      events.each do |event|
        break if state[:winner] != nil || state[:draw]

        accepted << event if apply_replay_event(state, event, session, repository, history)
      end

      build_replay(state, players, accepted, history)
    end

    def incremental_replay(replay, session, events, repository)
      return nil if replay == nil || replay.state == nil

      state = replay.state
      events.each do |event|
        break if state[:winner] != nil || state[:draw]

        if apply_replay_event(state, event, session, repository, replay.history)
          decision_events = GameRoomParticipantDecisionEvents.for(replay)
          unless decision_events.equal?(replay.accepted_events)
            actor = repository.actor_of(event, session)
            decision_events << event.merge("__replay_actor" => actor, "actor" => actor)
          end
          replay.accepted_events << event
        end
      end
      replay.current_player = state[:current_player]
      replay.winner = state[:winner]
      replay.draw = state[:draw]
      replay
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if state == nil || finished_state?(state)
      return nil if !same_user?(actor, replay.players.first)
      return nil if ![:awaiting_deal, :round_complete].include?(state[:phase])

      { "kind" => "command", "action" => "deal" }
    end

    def active_actors(replay)
      replay.current_player == nil ? [] : [replay.current_player]
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if state == nil || finished_state?(state)
      return [] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :bidding
        legal_calls(state).map { |call| call_action(call) }
      when :playing
        zone = playing_zone(state, actor)
        legal_cards(state).map do |card|
          { "kind" => "card", "action" => "select", "zone" => zone, "card" => card, "card_id" => card }
        end
      else
        []
      end
    end

    def playable_card_navigation(replay, viewer)
      state = replay.state
      return nil if state == nil || state[:phase] != :playing
      return nil if !same_user?(state[:current_player], viewer)

      grouped = legal_actions(replay, viewer).group_by { |action| action["card_id"].to_s }
      card_navigation_spec(hand_id: playing_zone(state, viewer), card_actions: grouped, automatic_card_ids: grouped.keys)
    end

    def action_for(selection, replay, actor, context: nil)
      state = replay.state
      return [:finished, nil] if replay.finished?

      if selection["kind"].to_s == "command" && selection["action"].to_s == "deal"
        return [:not_your_turn, nil] if !same_user?(actor, replay.players.first)
        return [:invalid, nil] if ![:awaiting_deal, :round_complete].include?(state[:phase])
        return [:invalid, nil] if context == nil || context.random_source == nil

        round = state[:round] + 1
        seed = card_seed(context.random_source)
        dealer = next_dealer(state, round) || card_seed_dealer(seed)
        return [:ok, event_plan("deal", [round, dealer, seed].join("|"))]
      end

      return [:not_your_turn, nil] if !same_user?(state[:current_player], actor)

      case state[:phase]
      when :bidding
        call = selected_call(selection)
        return [:invalid, nil] if call == nil
        return [:invalid_call, nil] if !legal_calls(state).include?(call)

        [:ok, event_plan("call", call)]
      when :playing
        return [:invalid, nil] if selection["kind"].to_s != "card" || selection["action"].to_s != "select"

        card = selection["card"].to_s
        zone = selection["zone"].to_s
        return [:wrong_hand, nil] if !zone.empty? && zone != playing_zone(state, actor)
        return [:card_not_in_hand, nil] if !state[:hands][state[:seat_to_play]].include?(card)
        return [:must_follow_suit, nil] if !legal_cards(state).include?(card)

        [:ok, event_plan("play", card)]
      else
        [:invalid, nil]
      end
    end

    def move_error(status)
      case status
      when :invalid_call
        _("This call is not allowed now. A bid must be higher than the last bid, and you may only double or redouble your opponents.")
      when :card_not_in_hand
        _("This card is not in the hand that is to play.")
      when :wrong_hand
        _("Play a card from the hand whose turn it is.")
      when :must_follow_suit
        _("You must follow the suit that was led.")
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id && ![:start, :result].include?(entry.kind) }
      return nil if entries.empty?

      entries.map(&:text)
    end

    def result_text(replay)
      replay.state == nil ? nil : final_result_text(replay.state)
    end

    # Team totals (rubber points, IMPs or matchpoints) keyed like the
    # tournament's team units.
    def tournament_scores(replay, options:)
      replay.state == nil ? nil : replay.state[:scores].dup
    end

    def participant_scores(replay)
      state = replay.state
      state[:seats].each_with_index.to_h { |player, seat| [player, state[:scores].fetch(unit_id(R.side_of(seat)), 0)] }
    end

    private

    def finished_state?(state)
      state[:winner] != nil || state[:draw]
    end

    def build_replay(state, players, accepted, history)
      Replay.new(
        board: nil,
        players: players,
        current_player: state[:current_player],
        winner: state[:winner],
        draw: state[:draw],
        accepted_events: accepted,
        history: history,
        state: state
      )
    end

    def initial_state(players, options)
      {
        players: players,
        options: options,
        seats: seat_order(players, options),
        units: [unit_id(0), unit_id(1)],
        scores: { unit_id(0) => 0, unit_id(1) => 0 },
        round: 0,
        phase: :awaiting_deal,
        dealer: nil,
        seed: nil,
        vulnerability: :none,
        hands: Array.new(R::SEATS) { [] },
        initial_hands: Array.new(R::SEATS) { [] },
        calls: [],
        contract: nil,
        dummy_visible: false,
        trick: [],
        completed_tricks: [],
        tricks_won: [0, 0],
        seat_to_play: nil,
        current_player: nil,
        rubber: R.new_rubber,
        deals: [],
        winner: nil,
        draw: false
      }
    end

    # Partners sit opposite: the first and second member of each team take
    # North/South and East/West, so the team choice made at the table decides
    # the partnerships and the roster order decides who sits where.
    def seat_order(players, options)
      assignment = team_assignment(options, players: players)
      if assignment != nil
        ns = assignment.members_for(unit_id(0))
        ew = assignment.members_for(unit_id(1))
        return [ns[0], ew[0], ns[1], ew[1]] if ns.length == 2 && ew.length == 2
      end
      players.first(R::SEATS)
    end

    def unit_id(side)
      "team:#{side}"
    end

    def side_of_unit(unit)
      unit.to_s.delete_prefix("team:").to_i
    end

    def duplicate?(state)
      state[:options]["variant"] == "duplicate"
    end

    def seat_of(state, actor)
      return nil if state == nil

      state[:seats].index { |player| same_user?(player, actor) }
    end

    def controller_of(state, seat)
      contract = state[:contract]
      if state[:phase] == :playing && contract != nil && seat == R.partner_of(contract.declarer)
        return state[:seats][contract.declarer]
      end

      state[:seats][seat]
    end

    def dummy_seat(state)
      state[:contract] == nil ? nil : R.partner_of(state[:contract].declarer)
    end

    def playing_zone(state, actor)
      seat = seat_of(state, actor)
      state[:seat_to_play] == seat ? "hand" : "dummy"
    end

    def legal_calls(state)
      return [] if state[:phase] != :bidding

      R.legal_calls(state[:calls], state[:seat_to_play])
    end

    def legal_cards(state)
      return [] if state[:phase] != :playing

      R.legal_cards(state[:hands][state[:seat_to_play]], state[:trick])
    end

    def call_action(call)
      { "kind" => "command", "action" => "call", "call" => call }
    end

    def selected_call(selection)
      call = if selection["kind"].to_s == "question" && selection["action"].to_s == "submit" && selection["question_id"].to_s == "call"
        selection["answer"]
      elsif selection["kind"].to_s == "command" && selection["action"].to_s == "call"
        selection["call"]
      end
      value = call.to_s.upcase
      R::CALLS.include?(value) ? value : nil
    end

    def next_dealer(state, round)
      return R.board_dealer(round) if duplicate?(state)
      return nil if state[:dealer] == nil

      R.next_seat(state[:dealer])
    end

    def card_seed_dealer(seed)
      seed.to_i(16) % R::SEATS
    end

    def apply_replay_event(state, event, session, repository, history)
      actor = repository.actor_of(event, session)
      case event["action"].to_s
      when "deal" then apply_deal(state, event, actor, repository, history)
      when "call" then apply_call(state, event, actor, repository, history)
      when "play" then apply_play(state, event, actor, repository, history)
      else false
      end
    end

    def apply_deal(state, event, actor, repository, history)
      return false if !same_user?(actor, state[:players].first)
      return false if ![:awaiting_deal, :round_complete].include?(state[:phase])

      round, dealer, seed = GameRoomCardWire.parse_deal(event["value"])
      return false if round != state[:round] + 1 || !dealer.between?(0, R::SEATS - 1)
      expected = next_dealer(state, round)
      return false if expected != nil && expected != dealer
      return false if expected == nil && dealer != card_seed_dealer(seed)

      hands = R.deal(seed, dealer)
      state[:round] = round
      state[:dealer] = dealer
      state[:seed] = seed
      state[:hands] = hands
      state[:initial_hands] = hands.map(&:dup)
      state[:vulnerability] = deal_vulnerability(state, round)
      state[:calls] = []
      state[:contract] = nil
      state[:dummy_visible] = false
      state[:trick] = []
      state[:completed_tricks] = []
      state[:tricks_won] = [0, 0]
      state[:phase] = :bidding
      state[:seat_to_play] = dealer
      state[:current_player] = state[:seats][dealer]
      history << HistoryEntry.new(key: "deal:#{round}", text: deal_text(state), event_id: repository.event_id(event),
        actor: actor, kind: :deal)
      true
    rescue ArgumentError
      false
    end

    def deal_vulnerability(state, round)
      return R.board_vulnerability(round) if duplicate?(state)

      rubber = state[:rubber]
      ns = R.rubber_vulnerable?(rubber, 0)
      ew = R.rubber_vulnerable?(rubber, 1)
      return :both if ns && ew
      return :ns if ns
      return :ew if ew

      :none
    end

    def apply_call(state, event, actor, repository, history)
      return false if state[:phase] != :bidding || !same_user?(actor, state[:current_player])

      call = event["value"].to_s
      seat = state[:seat_to_play]
      return false if !legal_calls(state).include?(call)

      state[:calls] << [seat, call]
      event_id = repository.event_id(event)
      history << HistoryEntry.new(key: "call:#{event_id}", text: call_history_text(state, seat, call), event_id: event_id,
        actor: actor, kind: :bid, value: call)
      if R.auction_finished?(state[:calls])
        finish_auction(state, event_id, history)
      else
        move_to(state, R.next_seat(seat))
      end
      true
    end

    def finish_auction(state, event_id, history)
      contract = R.final_contract(state[:calls])
      if contract == nil
        history << HistoryEntry.new(key: "passed:#{state[:round]}", text: _("All four players passed. The deal is thrown in."),
          event_id: event_id, actor: "", kind: :contract)
        record_deal(state, nil, 0, nil)
        complete_deal(state, event_id, history)
        return
      end

      state[:contract] = contract
      state[:phase] = :playing
      leader = R.next_seat(contract.declarer)
      history << HistoryEntry.new(key: "contract:#{state[:round]}", text: contract_announcement(state, contract, leader),
        event_id: event_id, actor: "", kind: :contract)
      move_to(state, leader)
    end

    def move_to(state, seat)
      state[:seat_to_play] = seat
      state[:current_player] = controller_of(state, seat)
    end

    def apply_play(state, event, actor, repository, history)
      return false if state[:phase] != :playing || !same_user?(actor, state[:current_player])

      card = event["value"].to_s
      seat = state[:seat_to_play]
      hand = state[:hands][seat]
      return false if !hand.include?(card) || !legal_cards(state).include?(card)

      hand.delete(card)
      state[:trick] << [seat, card]
      event_id = repository.event_id(event)
      history << HistoryEntry.new(key: "play:#{event_id}", text: play_text(state, seat, card), event_id: event_id,
        actor: actor, kind: :play, value: card)
      if !state[:dummy_visible]
        state[:dummy_visible] = true
        history << HistoryEntry.new(key: "dummy:#{state[:round]}", text: dummy_text(state), event_id: event_id,
          actor: "", kind: :dummy)
      end

      if state[:trick].length < R::SEATS
        move_to(state, R.next_seat(seat))
        return true
      end

      winner = R.trick_winner(state[:trick], state[:contract].strain)
      state[:tricks_won][R.side_of(winner)] += 1
      state[:completed_tricks] << { cards: state[:trick].dup, winner: winner }
      state[:trick] = []
      history << HistoryEntry.new(key: "trick:#{event_id}", text: trick_text(state, winner), event_id: event_id,
        actor: state[:seats][winner], kind: :trick)
      if state[:completed_tricks].length == 13
        score_contract(state, event_id, history)
        complete_deal(state, event_id, history)
      else
        move_to(state, winner)
      end
      true
    end

    def declarer_tricks(state)
      state[:tricks_won][state[:contract].side]
    end

    def score_contract(state, event_id, history)
      contract = state[:contract]
      tricks = declarer_tricks(state)
      if duplicate?(state)
        vulnerable = R.vulnerable?(state[:vulnerability], contract.side)
        score = R.duplicate_score(contract, tricks, vulnerable: vulnerable)
        ns_score = contract.side == 0 ? score : -score
        record_deal(state, contract, ns_score, tricks)
      else
        entries = R.score_rubber_deal(state[:rubber], contract, tricks, hands: state[:initial_hands],
          honors: state[:options]["honors"] != false)
        totals = R.rubber_totals(state[:rubber])
        state[:scores] = { unit_id(0) => totals[0], unit_id(1) => totals[1] }
        record_deal(state, contract, nil, tricks, entries: entries)
      end
      history << HistoryEntry.new(key: "score:#{state[:round]}", text: deal_result_text(state, state[:deals].last),
        event_id: event_id, actor: "", kind: :score)
    end

    # Duplicate boards are compared with a reference result. A thrown-in
    # board is compared too, so a strong pair that passed out loses IMPs.
    def record_deal(state, contract, ns_score, tricks, entries: nil)
      deal = { round: state[:round], dealer: state[:dealer], vulnerability: state[:vulnerability],
        contract: contract, tricks: tricks, entries: entries }
      if duplicate?(state)
        datum = R.datum(state[:initial_hands], state[:vulnerability])
        deal[:ns_score] = ns_score.to_i
        deal[:datum] = datum
        if state[:options]["scoring"] == "mp"
          ns = ns_score.to_i <=> datum
          deal[:ns_points] = ns + 1
          deal[:ew_points] = 1 - ns
        else
          imps = R.imps(ns_score.to_i - datum)
          deal[:ns_points] = [imps, 0].max
          deal[:ew_points] = [-imps, 0].max
        end
        state[:scores][unit_id(0)] += deal[:ns_points]
        state[:scores][unit_id(1)] += deal[:ew_points]
      end
      state[:deals] << deal
    end

    def complete_deal(state, event_id, history)
      state[:phase] = :round_complete
      state[:seat_to_play] = nil
      state[:current_player] = nil
      if duplicate?(state)
        return if state[:round] < state[:options]["boards"].to_i
      else
        return if !R.rubber_finished?(state[:rubber])
      end

      first, second = state[:scores].values_at(unit_id(0), unit_id(1))
      state[:phase] = :finished
      if first == second
        state[:draw] = true
      else
        state[:winner] = unit_id(first > second ? 0 : 1)
      end
      history << HistoryEntry.new(key: "result:#{event_id}", text: final_result_text(state),
        event_id: event_id, actor: state[:winner].to_s, kind: :result)
    end
  end
end

require_relative "bridge/presentation"
require_relative "bridge/bot"
require_relative "generated/rulebooks/bridge"
