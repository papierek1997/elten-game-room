require_relative '../lib/private_card_game'
require_relative '../lib/private_card_round_audit'

GameRoomPrivateCards.register('tysiac', host: %w[private_deal],
  claim: %w[private_ready bid take_talon contract surrender], take: %w[initial_hand private_draw],
  reveal: %w[pass_card discard_card play contract_play redeal], random: %w[deal])

module GameRoomGames
  module TysiacPrivate
    include GameRoomPrivateCardGame

    private

    def private_event_cards(event, state)
      return Tysiac::SUITS.map { |suit| "9#{suit}" } if event["action"] == "redeal" && event["value"] == "four_nines"
      super
    end

    def private_event_card(event, _state)
      event['value'].to_s.split('|').last if %w[pass_card discard_card play contract_play].include?(event['action'])
    end

    def private_normalize_plan(plan, state)
      return super unless plan.events.map(&:action) == %w[contract play]
      contract, play = plan.events
      ActionPlan.new(events: [EventCommand.new(action: 'contract_play', value: "#{contract.value}|#{play.value}")])
    end

    def private_deal_spec(state)
      deck = state[:hands].values.flatten + state[:talon] + state[:talons].flatten
      state[:talon], state[:talons] = [], [[], []]
      state[:private_talons] = {}
      state[:private_talon_choice] = nil
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state[:hands], deck: deck}
    end

    def finish_bidding(state, event_id, history)
      super
      return unless state[:private_cards] && !two_players?(state)
      private_request_draw(state, actor: state[:taker], count: talon_size(state), purpose: 'talon')
    end

    def reveal_talon(state, event_id, history)
      return if state[:private_cards] && state[:talon].empty?
      super
    end

    def apply_take_talon(state, event, actor, repository, history)
      return super unless state[:private_cards]
      return false unless state[:phase] == :choosing_talon && same_user?(state[:taker], actor) &&
        %w[0 1].include?(event['value'])
      return super unless state[:talons][event['value'].to_i].empty?
      state[:private_talon_choice] = event['value'].to_i
      private_request_draw(state, actor: actor, count: talon_size(state), purpose: 'talon')
      true
    end

    def private_received_cards(state, purpose, cards, event, repository, history)
      if purpose == 'talon'
        state[:private_talons][state[:private_talon_choice] || 0] = cards.dup
        if two_players?(state)
          state[:talons][state[:private_talon_choice]] = cards
          # Resume the same rule, including its normal announcement.
          apply_take_talon(state, event.merge('value'=>state[:private_talon_choice].to_s),
            state[:taker], repository, history)
        else
          state[:talon] = cards
          state[:hands][state[:taker]].concat(cards)
          reveal_talon(state, repository.event_id(event), history)
        end
      elsif purpose == 'set_aside'
        state[:private_talons][1 - state[:private_talon_choice]] = cards.dup
        state[:set_aside].concat(cards)
      end
    end

    def private_after_event(state, event, session, repository, history)
      card = private_event_card(event, state)
      GameRoomPrivateCardLedger.expose_transfer(state, card) if event['action'] == 'pass_card'
      state[:private_round_actions] << event unless event['action'] == 'private_draw'
      if state[:phase] == :playing && two_players?(state) && state[:options]['last_trick_talon'] &&
          state[:hands].values.sum(&:size) == 1 && state[:private_talons].size < 2
        private_request_draw(state, actor: state[:current_player], count: talon_size(state), purpose: 'set_aside')
      end
      return unless [:round_complete, :finished].include?(state[:phase])
      # Surrender does not require exposing the rest of an unplayed hand.
      if event['action'] == 'surrender'
        remember_tournament_checkpoint(state, event_id: repository.event_id(event), index: state[:round], kind: 'deal')
        return
      end
      audit = GameRoomPrivateCardRoundAudit.initial_state(state)
      if audit
        audit[:talon] = state[:private_talons].fetch(0, []).dup unless two_players?(state)
        audit[:talons] = [0, 1].map { |i| state[:private_talons].fetch(i, []).dup } if two_players?(state)
      end
      valid = audit && state[:private_round_actions].all? do |item|
        apply_replay_event(audit, item, session, repository, [])
      end
      if valid
        remember_tournament_checkpoint(state, event_id: repository.event_id(event), index: state[:round], kind: 'deal')
      else
        GameRoomPrivateCardRoundAudit.reject_round(state, event, repository, history)
      end
    end

    def apply_replay_event(state, event, session, repository, history)
      return super unless event['action'] == 'contract_play'
      # Treat the existing contract + first-card shortcut as one card operation.
      if state[:private_cards]
        return super
      end
      apply_contract_play(state, event, repository.actor_of(event, session), repository, history)
    end

    def apply_contract_play(state, event, actor, repository, history)
      bid, mode, card = event['value'].to_s.split('|', -1)
      return false unless state[:phase] == :contract && mode == 'normal'
      candidate = Marshal.load(Marshal.dump(state))
      entries = []
      return false unless apply_contract(candidate, event.merge('value'=>bid), actor, repository, entries) &&
        apply_play(candidate, event.merge('value'=>"#{mode}|#{card}"), actor, repository, entries)
      apply_contract(state, event.merge('value'=>bid), actor, repository, history)
      apply_play(state, event.merge('value'=>"#{mode}|#{card}"), actor, repository, history)
      true
    end
  end
end
