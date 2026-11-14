require_relative "../dealt_card_game"
require_relative "cribbage_cards"
require_relative "cribbage_round"

GameRoomServerRandom.register("cribbage", %w[deal])
GameRoomPrivateCards.register("cribbage", host: %w[private_deal], claim: %w[private_ready crib_discard crib_go crib_count],
  take: %w[initial_hand private_draw], reveal: %w[play private_show], random: %w[deal], ordered: true, retain_unrevealed_draws: true)

module GameRoomGames
  class CribbageTable < DealtCardGame
    def id; "cribbage"; end
    def name; "Cribbage"; end
    def minimum_players; 2; end
    def maximum_players; 2; end
    def short_description; "Zdobywaj punkty za zagrania i uk\u0142ady kart. Wygrywa gracz, kt\u00f3ry pierwszy zdob\u0119dzie 121 punkt\u00f3w."; end
    def private_table_required?(_options); true; end

    def rule_sections; generated_rule_sections; end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def describe_event(event, repository, replay, viewer)
      played = replay.history.find do |entry|
        entry.kind == :play && entry.event_id.to_i == repository.event_id(event).to_i
      end
      return super unless played

      announcement = "#{GameRoomContent.utf8(participant_name(played.actor))} zagrywa #{playing_card_label(played.value)}."
      [announcement, *replay.history.filter_map { |entry| entry.text if entry.kind == :count && entry.event_id.to_i == played.event_id.to_i }]
    end

    def bot_action_score(replay, actor, action, context: nil)
      return 0 unless action["kind"] == "card"

      state = replay.state
      preferred = if state[:phase] == :discard
        hand = hand_for(state, actor).filter_map { |card| CribbageCards::DECODED[card] }
        discarded = state.fetch(:crib).fetch(state[:current_player]).filter_map { |card| CribbageCards::DECODED[card] }
        initial_hand = hand.dup
        slot = state[:discard_slots].fetch(state[:current_player], []).first
        initial_hand.insert(slot, discarded.first) if slot && discarded.one?
        CribbageBot.discard(initial_hand, dealer: !same_user?(actor, first_player(state)))
          &.find { |card| hand.include?(card) }
      else
        cards = legal_cards(state, actor).map { |card| CribbageCards.decode(card) }
        CribbageBot.play(cards, state[:sequence])
      end
      preferred && action["card"] == CribbageCards.encode(preferred) ? 1 : 0
    end

    def shortcut_features
      super - [:round_summary]
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      state = replay.state
      starter = state[:starter]
      shortcuts << GameShortcut.new(key: "d", kind: :announcement, label: "Odczytaj kart\u0119 startow\u0105",
        message: starter ? "Karta startowa: #{playing_card_label(starter)}." : "Brak karty startowej.")
      if state[:dealer]
        shortcuts << GameShortcut.new(key: "v", kind: :announcement, label: "Sprawd\u017a, kto liczy crib",
          message: crib_dealer_text(state))
      end
      return shortcuts unless state[:phase] == :manual_count && same_user?(state[:current_player], viewer)

      shortcuts << GameShortcut.new(key: "enter", label: "Podaj wynik", kind: :number_input,
        prompt: "Ile punkt\u00f3w daj\u0105 te karty?", action_kind: "command", action_name: "crib_count",
        value_key: "points", allowed_values: 0..29, payload: {"stage" => state[:count_index]})
    end

    def surface_spec(replay, viewer)
      state = replay.state
      if state[:phase] == :manual_count
        hand = count_cards(state) + [state.fetch(:starter)]
        cards = hand.map do |card|
          label = playing_card_label(card)
          label = "Karta startowa. #{label}" if card == state[:starter]
          GameSurfaces::Card.new(id: card, value: card, label: label)
        end
        label = state[:count_index] == 2 ? "Crib" : "Karty do podliczenia"
        return GameSurfaces::CardTableSpec.new(zones: [
          GameSurfaces::CardZoneSpec.new(id: "hand", header: label, cards: cards,
            hand_order: hand, hand_epoch: [state[:round], state[:count_index]].join(":"))
        ])
      end

      if legal_actions(replay, viewer).any? { |action| action["action"] == "crib_go" }
        action = GameSurfaces::Action.new(kind: "command", name: "crib_go", payload: {}, source: "cribbage_go")
        item = GameSurfaces::PawnTrackItem.new(id: "crib_go", label: "Pas", action: action)
        return GameSurfaces::PawnTrackSpec.new(id: "cribbage_go",
          header: "\u017badna karta nie mie\u015bci si\u0119 w limicie 31", items: [item])
      end
      super
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      if state[:phase] == :manual_count
        return [] unless same_user?(actor, state[:current_player])

        return [{"kind" => "command", "action" => "crib_count",
          "stage" => state[:count_index], "points" => count_points(state)}]
      end
      if state[:phase] == :playing && same_user?(actor, state[:current_player]) && legal_cards(state, actor).empty?
        return [{"kind" => "command", "action" => "crib_go"}]
      end
      return super unless state[:phase] == :discard
      return [] unless same_user?(actor, state[:current_player])

      hand_for(state, actor).filter_map do |card|
        next unless CribbageCards::DECODED.key?(card)

        {"kind" => "card", "action" => "select", "zone" => "hand", "card" => card, "card_id" => card}
      end
    end

    def move_error(status)
      return "Ta karta podnios\u0142aby sum\u0119 powy\u017cej 31. Wybierz kart\u0119, kt\u00f3ra mie\u015bci si\u0119 w limicie." if status == :must_follow_suit

      super
    end

    def action_for(selection, replay, actor, context: nil)
      if selection["action"] == "crib_count"
        state = replay.state
        return [:invalid, nil] unless state[:phase] == :manual_count && same_user?(state[:current_player], actor)
        return [:invalid, nil] unless selection["stage"].to_s == state[:count_index].to_s
        points = selection["points"].to_s
        return [:invalid, nil] unless points.match?(/\A(?:0|[1-9][0-9]?)\z/) && points.to_i <= 29

        plan = event_plan("crib_count", "#{state[:count_index]},#{selection["points"]}")
        return private_secure_plan(plan, state, actor) if state[:private_cards]

        return [:ok, plan]
      end
      if selection["action"] == "crib_go"
        return [:invalid, nil] unless legal_actions(replay, actor).any? { |action| action.all? { |key, value| selection[key] == value } }

        plan = event_plan("crib_go", "")
        return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

        return [:ok, plan]
      end
      return super unless replay.state[:phase] == :discard
      return [:invalid, nil] unless legal_actions(replay, actor).any? do |action|
        %w[kind action zone card].all? { |key| selection[key] == action[key] }
      end

      slot = hand_for(replay.state, actor).index(selection["card"])
      plan = event_plan("crib_discard", slot.to_s)
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

      [:ok, plan]
    end

    protected

    def table_cards(state)
      cards = state[:phase] == :manual_count ? count_cards(state) : state.fetch(:sequence_cards, [])
      cards
    end

    def table_information_text(state)
      cards = table_cards(state)
      cards.empty? ? "Brak kart na stole." : cards_text(cards)
    end

    def count_announcement(state)
      name = GameRoomContent.utf8(participant_name(state[:current_player]))
      label = state[:count_index] == 2 ? "Crib" : "R\u0119ka"
      "#{name}. #{label} do podliczenia. Enter, aby poda\u0107 wynik."
    end

    def crib_dealer_text(state)
      dealer = next_player(state, first_player(state))
      "#{GameRoomContent.utf8(participant_name(dealer))} liczy crib."
    end

    def deal_round(state, seed, event, repository, history)
      add_history(history, event, repository, :crib_dealer, crib_dealer_text(state))
      seats = state.fetch(:seats)
      deck = state[:private_cards] ? Array.new(13) : shuffled_cards(CribbageCards::DECK, seed)
      state[:hands] = seats.to_h { |seat| [seat, []] }
      leader = first_player(state)
      order = [leader, next_player(state, leader)]
      12.times { |index| state[:hands].fetch(order[index % 2]) << deck[index] }
      state[:starter] = deck[12]
      state[:crib] = seats.to_h { |seat| [seat, []] }
      state[:played] = seats.to_h { |seat| [seat, []] }
      state[:discard_slots] = {}
      state[:sequence] = []
      state[:sequence_cards] = []
      state[:go] = []
      state[:play_count] = 0
      state[:phase], state[:current_player] = :discard, leader
    end

    def private_deal_spec(state)
      {hands: state.fetch(:hands), deck: CribbageCards::DECK}
    end

    def apply_extra_card_event(state, event, session, repository, history)
      return apply_count(state, event, session, repository, history) if event["action"] == "crib_count"
      return apply_go(state, event, session, repository, history) if event["action"] == "crib_go"
      return super unless event["action"] == "crib_discard"
      return false unless state[:phase] == :discard && event["value"].to_s.match?(/\A[0-5]\z/)

      actor = state[:current_player]
      return false unless same_user?(actor, repository.actor_of(event, session))

      hand = hand_for(state, actor)
      index = event["value"].to_i
      return false unless index < hand.size

      state[:crib].fetch(actor) << hand.delete_at(index)
      slots = (state[:discard_slots][actor] ||= [])
      slots << index
      return true unless slots.size == 2

      if state[:crib].values.sum(&:size) == 4
        state[:phase], state[:current_player] = :playing, first_player(state)
        if state[:private_cards]
          private_request_draw(state, actor: state[:current_player], count: 1, purpose: "cribbage_starter")
        end
      else
        state[:current_player] = next_player(state, actor)
      end
      true
    end

    def legal_cards(state, actor)
      return [] unless state[:phase] == :playing && same_user?(actor, state[:current_player])

      hand_for(state, actor).select do |card|
        decoded = CribbageCards::DECODED[card]
        decoded && CribbageScoring.pegging(state[:sequence] + [decoded.first])
      end
    end

    def play_card(state, actor, card, event, repository, history)
      seat = state[:current_player]
      state[:played].fetch(seat) << card
      state[:sequence_cards] << card
      state[:sequence] << CribbageCards.decode(card).first
      return if award_points(state, seat, CribbageScoring.pegging(state[:sequence]), event, repository, history)
      state[:last_play] = seat
      if state[:sequence].sum { |rank| [rank, 10].min } == 31
        reset_sequence(state, seat)
      elsif state[:hands].values.all?(&:empty?)
        return if award_points(state, seat, 1, event, repository, history)
        reset_sequence(state, seat)
      else
        other = next_player(state, actor)
        state[:current_player] = state[:go].include?(other) || hand_for(state, other).empty? ? seat : other
      end
    end

    def apply_go(state, event, session, repository, history)
      return false unless state[:phase] == :playing && event["value"] == ""

      seat = state[:current_player]
      return false unless same_user?(seat, repository.actor_of(event, session))
      return false unless state[:private_cards] || legal_cards(state, seat).empty?

      other = next_player(state, seat)
      if state[:go].include?(other) || hand_for(state, other).empty?
        last = state.fetch(:last_play)
        return true if award_points(state, last, 1, event, repository, history)
        reset_sequence(state, last)
      else
        state[:go] << seat
        state[:current_player] = other
      end
      true
    end

    def reset_sequence(state, last)
      state[:sequence].clear
      state[:sequence_cards].clear
      state[:go].clear
      state.delete(:last_play)
      if state[:hands].values.all?(&:empty?)
        state[:phase], state[:current_player] = :counting, nil
      else
        other = next_player(state, last)
        state[:current_player] = hand_for(state, other).empty? ? last : other
      end
    end

    def apply_replay_event(state, event, session, repository, history)
      accepted = super
      count_round(state, event, repository, history) if accepted && !state[:private_cards] && state[:phase] == :counting
      accepted
    end

    def private_after_event(state, event, _session, repository, history)
      count_round(state, event, repository, history) if state[:phase] == :counting
    end

    def private_disclosure_completed(state, purpose, event, _session, repository, history)
      count_round(state, event, repository, history) if purpose == "cribbage_count"
    end

    def count_round(state, event, repository, history)
      if state[:private_cards] && GameRoomPrivateCardDisclosure.prepare(state, state[:seats],
          purpose: "cribbage_count", zone: :crib)
        return
      end

      state[:count_index] = 0
      state[:phase], state[:current_player] = :manual_count, first_player(state)
      add_history(history, event, repository, :count, count_announcement(state))
    end

    def count_cards(state)
      state[:count_index] == 2 ? state[:crib].values.flatten : state[:played].fetch(state[:current_player])
    end

    def count_points(state)
      starter = CribbageCards.decode(state.fetch(:starter))
      cards = count_cards(state).map { |card| CribbageCards.decode(card) }
      CribbageScoring.hand(cards, starter, crib: state[:count_index] == 2)
    end

    def apply_count(state, event, session, repository, history)
      return false unless state[:phase] == :manual_count

      actor = state[:current_player]
      return false unless same_user?(actor, repository.actor_of(event, session))

      actual = count_points(state)
      _stage, claim = event["value"].to_s.split(",", -1)
      return false unless claim && event["value"] == "#{state[:count_index]},#{claim}"
      return false unless claim.match?(/\A(?:0|[1-9][0-9]?)\z/)

      submitted = claim.to_i
      return false if submitted > 29
      points = [submitted, actual].min

      add_history(history, event, repository, :count, "#{GameRoomContent.utf8(participant_name(actor))}: #{points} pkt.")
      return true if award_points(state, actor, points, event, repository, history)

      missed = (actual - submitted).abs
      if missed.positive?
        opponent = next_player(state, actor)
        name = GameRoomContent.utf8(participant_name(opponent))
        add_history(history, event, repository, :count, "Zg\u0142oszono #{submitted} pkt, prawid\u0142owy wynik to #{actual}. #{name} dostaje #{missed} pkt r\u00f3\u017cnicy.")
        return true if award_points(state, opponent, missed, event, repository, history)
      end

      state[:count_index] += 1
      if state[:count_index] == 3
        state[:phase] = :round_complete
      else
        state[:current_player] = next_player(state, first_player(state))
        add_history(history, event, repository, :count, count_announcement(state))
      end
      true
    end

    def award_points(state, seat, points, event, repository, history)
      state[:scores][seat] += points
      return false if state[:scores][seat] < 121

      finish_game(state, event, repository, history)
      true
    end

    def private_received_cards(state, purpose, cards, event, repository, history)
      return super unless purpose == "cribbage_starter"

      state[:starter] = cards.fetch(0)
      dealer = next_player(state, first_player(state))
      award_points(state, dealer, 2, event, repository, history) if CribbageCards.decode(state[:starter]).first == 11
    end
  end
end

require_relative '../generated/rulebooks/cribbage'
