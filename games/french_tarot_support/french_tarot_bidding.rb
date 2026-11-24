require_relative "french_tarot_cards"
require_relative "french_tarot_bot"

module GameRoomGames
  using GameRoomLocalization::Translations
  module FrenchTarotBidding
    def tarot_contract_label(contract)
      case contract
      when :pass then _("Pass")
      when :petite then _("Little")
      when :pousse then _("Push")
      when :garde then _("Guard")
      when :garde_sans then _("Guard without the kitty")
      when :garde_contre then _("Guard against the kitty")
      end
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return super unless state[:phase] == :bidding
      return [] unless same_user?(state[:current_player], actor)

      bids(state).map do |choice|
        {"kind" => "command", "action" => "tarot_bid", "choice" => choice.to_s}
      end
    end

    def action_for(selection, replay, actor, context: nil)
      return super unless selection["action"] == "tarot_bid"
      return [:invalid, nil] unless legal_actions(replay, actor, context: context)
        .any? { |bid| bid.all? { |key, value| selection[key] == value } }

      plan = event_plan("tarot_bid", selection["choice"])
      return private_secure_plan(plan, replay.state, actor) if replay.state[:private_cards]

      [:ok, plan]
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = super
      state = replay.state
      return shortcuts unless state[:phase] == :bidding && same_user?(state[:current_player], viewer)

      choices = bids(state).map { |choice| ShortcutChoice.new(value: choice.to_s, label: tarot_contract_label(choice)) }
      shortcuts << GameShortcut.new(key: "b", kind: :choice, label: _("Choose a contract or pass"),
        prompt: _("Choose a contract"), choices: choices, action_kind: "command", action_name: "tarot_bid", value_key: "choice")
    end

    protected

    def bids(state)
      contracts = FrenchTarotScoring::CONTRACTS
      current = contracts.fetch(state[:contract], 0)
      [:pass] + contracts.keys.select do |choice|
        contracts.fetch(choice) > current &&
          (choice != :pousse || (state[:seats].size >= 5 && state[:options]["tarot_push"]))
      end
    end

    def apply_extra_card_event(state, event, session, repository, history)
      return super unless event["action"] == "tarot_bid"
      actor = repository.actor_of(event, session)
      return false unless state[:phase] == :bidding && same_user?(state[:current_player], actor)

      choice = bids(state).find { |candidate| candidate.to_s == event["value"] }
      return false unless choice

      state[:taker], state[:contract] = state[:current_player], choice unless choice == :pass
      text = choice == :pass ? p_("Bidding", "%{player} passes.") % {player: participant_name(actor)} :
        _("%{player} bids %{contract}.") % {player: participant_name(actor), contract: tarot_contract_label(choice)}
      add_history(history, event, repository, :bid, text, actor: actor)
      state[:bid_count] += 1
      if state[:bid_count] == state[:seats].size
        complete_tarot_bidding(state)
        if state[:tarot_misere]
          add_history(history, event, repository, :notice, _("Misère. Avoid taking card points."))
        elsif state[:taker]
          add_history(history, event, repository, :notice, _("Declarer: %{player}.") % {player: participant_name(state[:taker])})
          announce_tarot_kitty(state, event, repository, history)
        elsif !state[:tarot_misere]
          add_history(history, event, repository, :notice, _("Everyone passed. The cards will be dealt again."))
        end
      else
        state[:current_player] = next_player(state, actor)
      end
      true
    end

    def tarot_bid_score(state, actor, action)
      hand = hand_for(state, actor).filter_map { |card| FrenchTarotCards::DECODED[card] }
      action["choice"] == FrenchTarotBot.bid(hand, bids(state)).to_s ? 1 : 0
    end
  end
end
