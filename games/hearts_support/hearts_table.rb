require_relative "../dealt_card_game"
require_relative "hearts_cards"
require_relative "hearts_bot"
require_relative "hearts_match"
require_relative "../../lib/private_card_round_audit"

GameRoomServerRandom.register("hearts", ["deal"])
GameRoomPrivateCards.register("hearts", host: %w[private_deal], claim: %w[private_ready],
  take: %w[initial_hand], reveal: %w[pass_card hearts_open play], random: %w[deal])

module GameRoomGames
  class HeartsTable < DealtCardGame
    def id; "hearts"; end
    def name; "Kierki"; end
    def short_description; "Unikaj kier\u00f3w i damy pik. Wygrywa gracz z najmniejsz\u0105 liczb\u0105 punkt\u00f3w karnych."; end
    def private_table_required?(_options); true; end

    def rule_sections; generated_rule_sections; end
    def minimum_players; 4; end
    def maximum_players; 4; end

    def turn_announcement(replay, viewer)
      state = replay&.state
      if state && state[:phase] == :passing && same_user?(state[:current_player], viewer)
        direction = {1 => "w lewo", -1 => "w prawo", 2 => "naprzeciwko"}.fetch(state[:pass_offset])
        remaining = 3 - state[:passes].fetch(state[:current_player], []).size
        return "Przeka\u017c trzy karty #{direction}. Wybierz ka\u017cd\u0105 Enterem." if remaining == 3
        return "Pozosta\u0142o kart do przekazania: #{remaining}."
      end

      super
    end

    def describe_event(event, repository, replay, viewer)
      messages = Array(super)
      exchange = replay.state[:last_exchange]
      return messages unless exchange && exchange[:event_id] == repository.event_id(event)

      receipt = exchange[:received].find { |seat, _| same_user?(seat, viewer) }&.last
      return messages unless receipt

      sender, cards = receipt
      name = GameRoomContent.utf8(participant_name(sender))
      messages << "Karty od #{name}: #{GameRoomContent.utf8(cards_text(cards))}."
    end

    def bot_strategy
      @bot_strategy ||= GameRoomBots::HeuristicStrategy.new
    end

    def shortcut_features
      super + [:led_suit, :statistics]
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      cues = Array(super)
      card = HeartsCards::DECODED[event["value"]]
      cues << "duck_memory_bell" if event["action"] == "play" && card&.first == :hearts && history.any? { |entry| entry.kind == :play }
      cues << "hit1" if event["action"] == "play" && event["value"] == "QS" && history.any? { |entry| entry.kind == :play }
      cues
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      if feature == :statistics
        points = state[:round_penalties] || state.fetch(:captured, {}).transform_values do |cards|
          cards.count { |suit, _| suit == :hearts } + (cards.include?([:spades, 12]) ? 13 : 0)
        end
        names = replay.players.map { |player| "#{GameRoomContent.utf8(participant_name(player))}: #{points.fetch(player, 0)}" }
        return {label: "Punkty karne rozdania", message: names.empty? ? "Brak punkt\u00f3w." : names.join(". ")}
      end
      if feature == :led_suit
        card = table_cards(state).first
        labels = {clubs: "trefl", diamonds: "karo", hearts: "kier", spades: "pik"}
        return {message: card ? "Kolor wyj\u015bcia: #{labels.fetch(HeartsCards.decode(card).first)}." : "Lewa jest pusta."}
      end
      if feature == :round_summary && state[:phase] != :passing
        return {message: state[:hearts_broken] ? "Kiery s\u0105 ju\u017c otwarte." : "Kiery s\u0105 jeszcze zamkni\u0119te."}
      end
      return super unless feature == :round_summary && state[:phase] == :passing

      direction = {1 => "w lewo", -1 => "w prawo", 2 => "naprzeciwko"}.fetch(state[:pass_offset])
      count = state[:passes].fetch(viewer, []).size
      {message: "Przekazywanie kart #{direction}. Wybrano #{count} z 3 kart."}
    end

    def bot_action_score(replay, actor, action, context: nil)
      return 0 unless action["kind"] == "card"
      state = replay.state
      if state[:phase] == :passing
        hand = known_hand(state, actor).map { |card| HeartsCards.decode(card) }
        preferred = HeartsBot.pass(hand).map { |card| HeartsCards.encode(card) }
        return preferred.include?(action["card"]) ? 1 : 0
      end
      legal = legal_cards(state, actor).map { |card| HeartsCards.decode(card) }
      preferred = HeartsBot.play(legal, decoded_trick(state))
      preferred && action["card"] == HeartsCards.encode(preferred) ? 1 : 0
    end

    def automatic_action(replay, actor, context: nil)
      if replay.state[:phase] == :opening && hand_for(replay.state, actor).include?("2C")
        return {"kind" => "command", "action" => "hearts_open"}
      end
      super
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return super unless state[:phase] == :passing
      return [] unless same_user?(state[:current_player], actor)

      (known_hand(state, actor) - state[:passes].fetch(actor, [])).map do |card|
        {"kind" => "card", "action" => "select", "zone" => "hand", "card" => card, "card_id" => card}
      end
    end

    def action_for(selection, replay, actor, context: nil)
      if selection["action"] == "hearts_open"
        return [:invalid, nil] unless selection == automatic_action(replay, actor, context: context)

        return private_secure_plan(event_plan("hearts_open", "2C"), replay.state, actor)
      end
      return super unless replay.state[:phase] == :passing
      return [:invalid, nil] unless legal_actions(replay, actor).any? do |action|
        %w[kind action zone card].all? { |key| selection[key] == action[key] }
      end

      plan = event_plan("pass_card", selection["card"])
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

      [:ok, plan]
    end

    protected

    def deal_round(state, seed, event, repository, history)
      seats = state.fetch(:seats)
      cards = state[:private_cards] ? Array.new(52) : shuffled_cards(HeartsCards::DECK, seed)
      state[:hands] = seats.zip(cards.each_slice(13).to_a).to_h
      state[:trick] = []
      state[:captured] = seats.to_h { |seat| [seat, []] }
      state[:hearts_broken] = false
      state[:play_count] = 0
      state[:passes] = {}
      state[:last_exchange] = nil
      state[:round_penalties] = nil
      direction = HeartsMatch::DIRECTIONS.fetch((state[:round] - 1) % 4)
      state[:pass_offset] = HeartsRound::PASS.fetch(direction)
      if state[:pass_offset].zero?
        start_hearts_play(state)
      else
        state[:phase] = :passing
        state[:current_player] = first_player(state)
      end
      announce_exchange(state, event, repository, history) unless state[:private_cards]
    end

    def announce_exchange(state, event, repository, history)
      return unless state[:pass_offset].zero?

      add_history(history, event, repository, :exchange, "W tym rozdaniu zachowujesz wszystkie karty.")
    end

    def private_dealing_applied(state, event, _session, repository, history)
      announce_exchange(state, event, repository, history)
    end

    def apply_extra_card_event(state, event, session, repository, history)
      if event["action"] == "hearts_open"
        return false unless state[:phase] == :opening && event["value"] == "2C"

        actor = repository.actor_of(event, session)
        seat = state[:seats].find { |player| same_user?(player, actor) }
        return false unless seat && hand_for(state, seat).include?("2C")

        state[:phase], state[:current_player] = :playing, seat
        return true
      end
      return super unless event["action"] == "pass_card"
      actor = repository.actor_of(event, session)
      return false unless state[:phase] == :passing && same_user?(state[:current_player], actor)

      card = event["value"]
      hand = hand_for(state, actor)
      return false unless hand.include?(card)
      selected = (state[:passes][state[:current_player]] ||= [])
      return false if selected.include?(card)
      selected << card
      return true if selected.size < 3

      following = next_player(state, actor)
      if state[:passes].key?(following)
        seats = state[:seats]
        hands = seats.map { |seat| state[:hands].fetch(seat) }
        passes = seats.map { |seat| state[:passes].fetch(seat) }
        received = seats.each_with_index.to_h do |seat, index|
          sender = (index - state[:pass_offset]) % seats.size
          [seat, [seats.fetch(sender), passes.fetch(sender).dup]]
        end
        state[:last_exchange] = {event_id: repository.event_id(event), received: received}
        state[:hands] = seats.zip(HeartsRules.exchange(hands, passes, state[:pass_offset])).to_h
        state[:passes].clear
        start_hearts_play(state)
      else
        state[:current_player] = following
      end
      true
    end

    def known_hand(state, actor)
      hand_for(state, actor).select { |card| HeartsCards::DECODED.key?(card) }
    end

    def private_after_event(state, event, session, repository, history)
      return unless %w[pass_card hearts_open play].include?(event["action"])

      state.fetch(:private_round_actions) << event
      return unless state[:phase] == :private_round_end

      audit = GameRoomPrivateCardRoundAudit.initial_state(state)
      audited_history = []
      valid = audit && state.fetch(:private_round_actions).all? do |record|
        if record["action"] == "hearts_open"
          actor = repository.actor_of(record, session)
          audit[:phase] == :playing && same_user?(audit[:current_player], actor) &&
            hand_for(audit, actor).include?("2C")
        else
          apply_replay_event(audit, record, session, repository, audited_history)
        end
      end
      if valid
        state.merge!(audit)
        history.concat(audited_history.select { |entry| %i[round_result result].include?(entry.kind) })
      else
        GameRoomPrivateCardRoundAudit.reject_round(state, event, repository, history)
      end
    end

    def private_deal_spec(state)
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state.fetch(:hands), deck: HeartsCards::DECK}
    end

    def private_event_card(event, state)
      return event["value"] if %w[hearts_open pass_card].include?(event["action"])

      super
    end

    def start_hearts_play(state)
      if state[:private_cards]
        state[:phase], state[:current_player] = :opening, nil
        return
      end
      state[:phase] = :playing
      state[:current_player] = state[:seats].find { |seat| state[:hands].fetch(seat).include?("2C") }
    end

    def score_order; "lower"; end

    def table_cards(state)
      state.fetch(:trick, []).map(&:last)
    end

    def decoded_trick(state)
      table_cards(state).map { |card| HeartsCards.decode(card) }
    end

    def legal_cards(state, actor)
      return [] unless state[:phase] == :playing && same_user?(state[:current_player], actor)

      hand = known_hand(state, actor).map { |card| HeartsCards.decode(card) }
      HeartsRules.legal(hand, decoded_trick(state), first_trick: state[:play_count] < 4,
        hearts_broken: state[:hearts_broken]).map { |card| HeartsCards.encode(card) }
    end

    def play_card(state, actor, card, event, repository, history)
      trick = state.fetch(:trick)
      trick << [actor, card]
      if !state[:hearts_broken] && HeartsCards.decode(card).first == :hearts
        state[:hearts_broken] = true
        add_history(history, event, repository, :hearts_broken, "Kiery otwarte.")
      end
      if trick.size < 4
        state[:current_player] = next_player(state, actor)
        return
      end

      cards = decoded_trick(state)
      winner = trick.fetch(HeartsRules.trick_winner(cards)).first
      state.fetch(:captured).fetch(winner).concat(cards)
      points = cards.count { |suit, _| suit == :hearts } + (cards.include?([:spades, 12]) ? 13 : 0)
      name = GameRoomContent.utf8(participant_name(winner))
      message = "#{name} bierze lew\u0119. Punkty karne: #{points}."
      message += " Wychodzi do nast\u0119pnej lewy." if state[:play_count] < 52
      add_history(history, event, repository, :trick, message, actor: winner)
      trick.clear
      state[:current_player] = winner
      settle_hearts_round(state, event, repository, history) if state[:play_count] == 52
    end

    def settle_hearts_round(state, event, repository, history)
      if state[:private_cards]
        state[:phase], state[:current_player] = :private_round_end, nil
        return
      end

      seats = state.fetch(:seats)
      penalties = HeartsRules.settle(seats.map { |seat| state.fetch(:captured).fetch(seat) })
      seats.zip(penalties).each { |seat, points| state.fetch(:scores)[seat] += points }
      state[:round_penalties] = seats.zip(penalties).to_h
      moon = penalties.index(0) if penalties.count(26) == 3
      if moon
        name = GameRoomContent.utf8(participant_name(seats.fetch(moon)))
        add_history(history, event, repository, :round_result, "#{name} zebra\u0142 wszystkie karty karne.")
      end
      seats.zip(penalties).each do |seat, points|
        name = GameRoomContent.utf8(participant_name(seat))
        add_history(history, event, repository, :round_result,
          "#{name}. Punkty rozdania: #{points}. Wynik meczu: #{state[:scores].fetch(seat)}.")
      end
      state[:current_player] = nil
      if state[:scores].values.max >= 100 && winning_units(state).one?
        finish_game(state, event, repository, history)
      else
        state[:phase] = :round_complete
      end
    end
  end
end

require_relative '../generated/rulebooks/hearts'
