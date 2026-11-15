require_relative '../../lib/private_card_round_audit'

module GameRoomGames
  # Private receipts prove ownership. The ordinary reducer additionally checks
  # Go and pegging against the disclosed hands before counting or a match win.
  module CribbagePrivate
    protected

    def private_deal_spec(state)
      state[:private_crib_audited] = false
      GameRoomPrivateCardRoundAudit.begin_round(state)
      {hands: state.fetch(:hands), deck: CribbageCards::DECK}
    end

    def private_received_cards(state, purpose, cards, event, repository, history)
      return super unless purpose == 'cribbage_starter'

      state[:starter] = cards.fetch(0)
      reveal_cribbage_starter(state, event, repository, history)
    end

    def private_after_event(state, event, session, repository, history)
      if %w[crib_discard crib_go play].include?(event['action']) ||
          event['action'] == 'private_draw' && event['value'] == 'cribbage_starter'
        state.fetch(:private_round_actions) << event
      end
      return unless [:counting, :crib_audit].include?(state[:phase])

      return if GameRoomPrivateCardDisclosure.prepare(state, state[:seats],
        purpose: 'cribbage_crib', zone: :crib)
      state.delete(:private_disclosure)
      disclose_cribbage_hands(state, event, session, repository, history)
    end

    def private_disclosure_completed(state, purpose, event, session, repository, history)
      case purpose
      when 'cribbage_crib'
        disclose_cribbage_hands(state, event, session, repository, history)
      when 'cribbage_hands'
        audit_cribbage_round(state, event, session, repository, history)
      end
    end

    def disclose_cribbage_hands(state, event, session, repository, history)
      return if GameRoomPrivateCardDisclosure.prepare(state, state[:seats],
        purpose: 'cribbage_hands')
      state.delete(:private_disclosure)
      audit_cribbage_round(state, event, session, repository, history)
    end

    def audit_cribbage_round(state, event, session, repository, history)
      audit = GameRoomPrivateCardRoundAudit.initial_state(state)
      audit_history = []
      discards = state[:crib].transform_values { |cards| cards.sort }
      valid = audit && discards.values.all? { |cards| cards.size == 2 } &&
        state.fetch(:private_round_actions).all? do |record|
          if record['action'] == 'private_draw'
            proof = record['__server_pool']
            next false unless proof && proof['visibility'] == 'public' && proof['count'] == 1
            audit[:starter] = state[:private_pools].fetch(proof['pool_id'])[:cards].fetch(proof['values'].first - 1)
            reveal_cribbage_starter(audit, record, repository, audit_history)
            next true
          end
          if record['action'] == 'crib_discard'
            actor = repository.actor_of(record, session)
            card = discards.fetch(actor).shift
            slot = hand_for(audit, actor).index(card)
            next false unless slot
            record = record.merge('value' => slot.to_s)
          end
          apply_replay_event(audit, record, session, repository, audit_history)
        end
      valid &&= discards.values.all?(&:empty?) && [:manual_count, :finished].include?(audit[:phase])
      unless valid
        return GameRoomPrivateCardRoundAudit.reject_round(state, event, repository, history)
      end

      state.merge!(audit)
      state[:private_crib_audited] = true
      if state[:phase] == :finished
        audit_history.select { |entry| entry.kind == :result }.each do |entry|
          entry.event_id = repository.event_id(event)
          history << entry
        end
      else
        add_history(history, event, repository, :count, count_announcement(state))
      end
    end
  end
end
