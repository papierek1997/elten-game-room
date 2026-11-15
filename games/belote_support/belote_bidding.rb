require_relative "belote_cards"
require_relative "belote_deal"
require_relative "belote_bot"

module GameRoomGames
  module BeloteBidding
    LABELS = {
      pass: "Pas", clubs: "Trefl", diamonds: "Karo", hearts: "Kier", spades: "Pik"
    }.freeze

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      if state[:phase] == :meld_end
        return [] unless same_user?(state[:current_player], actor)
        skip = {"kind" => "command", "action" => "belote_skip_meld"}
        pending = state[:pending_meld]
        if pending.last == 13
          queen = BeloteCards.encode([state[:trump], 12])
          return [skip] unless hand_for(state, actor).include?(queen)
        end
        return [{"kind" => "command", "action" => "belote_meld", "play" => state[:play_count]}, skip]
      end
      return super unless state[:phase] == :bidding
      return [] unless same_user?(state[:current_player], actor)

      bid_choices(state).map do |choice|
        {"kind" => "command", "action" => "belote_bid", "choice" => choice.to_s}
      end
    end

    def action_for(selection, replay, actor, context: nil)
      return super unless selection["action"] == "belote_bid"
      return [:invalid, nil] unless legal_actions(replay, actor, context: context)
        .any? { |bid| bid.all? { |key, value| selection[key] == value } }

      plan = event_plan("belote_bid", selection["choice"])
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

      [:ok, plan]
    end

    protected

    def coinchee?(state)
      state.fetch(:options, {})["variant"] == "coinchee"
    end

    def two_stage_deal?(state)
      !coinchee?(state) || state.fetch(:options, {})['coinchee_two_stage'] == true
    end

    def bid_label(choice)
      return "Kontra" if choice == :double
      return "Rekontra" if choice == :redouble
      return LABELS.fetch(choice) if choice.is_a?(Symbol)

      points, suit = choice.split(":")
      "#{points}, #{LABELS.fetch(suit.to_sym)}"
    end

    def bidding_header(state)
      unless coinchee?(state)
        return "Wybierz atut. Odkryta karta: #{playing_card_label(state.fetch(:upcard))}"
      end

      return "Coinch\u00e9e. Wybierz ofert\u0119 lub pas." unless state[:contract]

      "#{bid_label("#{state[:contract]}:#{state[:trump]}")}. Mno\u017cnik #{state[:multiplier]}. Wybierz decyzj\u0119."
    end

    def coinchee_choices(state)
      choices = [:pass]
      taker = state[:taker]
      if taker
        same_team = unit_for(state, state[:current_player]) == unit_for(state, taker)
        choices << :double if !same_team && state[:multiplier] == 1
        choices << :redouble if same_team && state[:multiplier] == 2
      end
      if state[:multiplier] == 1
        first = state[:contract] ? state[:contract] + 10 : 80
        first.step(160, 10) do |points|
          BeloteRound::SUITS.each { |suit| choices << "#{points}:#{suit}" }
        end
      end
      choices
    end

    def apply_coinchee_bid(state, choice)
      case choice
      when :pass
        state[:passes] += 1
        if state[:taker] && state[:passes] == 3
          if two_stage_deal?(state)
            complete_belote_deal(state)
          else
            state[:phase], state[:current_player] = :playing, first_player(state)
          end
          return
        elsif !state[:taker] && state[:passes] == 4
          state[:phase], state[:current_player] = :round_complete, nil
          return
        end
      when :double, :redouble
        state[:multiplier] *= 2
        state[:passes] = 0
      else
        points, suit = choice.split(":")
        state[:contract], state[:trump], state[:taker] = points.to_i, suit.to_sym, state[:current_player]
        state[:passes] = 0
      end
      state[:current_player] = next_player(state, state[:current_player])
    end

    def bid_choices(state)
      return coinchee_choices(state) if coinchee?(state)

      BeloteDeal.bid_choices(BeloteCards.decode(state.fetch(:upcard)).first, state.fetch(:passes))
    end

    def apply_extra_card_event(state, event, session, repository, history)
      return apply_meld(state, event, session, repository, history) if event["action"] == "belote_meld"
      if event["action"] == "belote_skip_meld"
        return false unless state[:phase] == :meld_end && event["value"] == state[:play_count].to_s &&
          same_user?(state[:current_player], repository.actor_of(event, session))

        finish_meld_decision(state, event, repository, history)
        return true
      end
      return super unless event["action"] == "belote_bid"
      return false unless state[:phase] == :bidding

      actor = repository.actor_of(event, session)
      return false unless same_user?(state[:current_player], actor)

      choice = bid_choices(state).find { |bid| bid.to_s == event["value"] }
      return false unless choice

      if coinchee?(state)
        name = GameRoomContent.utf8(participant_name(state[:current_player]))
        add_history(history, event, repository, :bid, "#{name}: #{bid_label(choice)}.")
        apply_coinchee_bid(state, choice)
        add_history(history, event, repository, :contract, round_information_text(state)) if state[:phase] == :playing
        return true
      end

      if choice == :pass
        state[:passes] += 1
        if state[:passes] == 8
          state[:phase], state[:current_player] = :round_complete, nil
        else
          state[:current_player] = next_player(state, actor)
        end
      else
        state[:taker], state[:trump] = state[:current_player], choice
        add_history(history, event, repository, :contract, round_information_text(state))
        complete_belote_deal(state)
      end
      true
    end

    def bid_score(state, actor, action)
      hand = hand_for(state, actor).filter_map { |card| BeloteCards::DECODED[card] }
      if coinchee?(state)
        return 1 if state[:contract] && action["choice"] == "pass"
        strongest = BeloteRound::SUITS.max_by { |suit| hand.count { |card| card.first == suit } }
        return action["choice"] == "80:#{strongest}" ? 1 : 0
      end

      choice = BeloteBot.bid(bid_choices(state), hand, BeloteCards.decode(state.fetch(:upcard)))
      action["choice"] == choice.to_s ? 1 : 0
    end
  end
end
