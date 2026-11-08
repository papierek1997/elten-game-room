require_relative '../lib/private_card_game'

GameRoomPrivateCards.register('poker', host: %w[private_deal private_recycle turn_timeout],
  claim: %w[private_ready bet exchange], take: %w[initial_hand private_draw], random: %w[deal], ordered: true)

module GameRoomGames
  module PokerPrivate
    include GameRoomPrivateCardGame
    using GameRoomLocalization::Translations

    private

    def private_deal_spec(state)
      deck = poker_deck(state[:options])
      state[:deck] = Array.new(deck.size - state[:hands].values.sum(&:size), :private_card)
      state[:private_discarded] = state[:players].to_h { |player| [player, []] }
      {hands: state[:hands], deck: deck}
    end

    # Exchanging positions, rather than names, does not disclose discarded
    # cards. Every view has the same ordered slots from each native draw.
    def private_normalize_plan(plan, state)
      event = plan.events.first
      return plan unless event.action == 'exchange'
      payload = GameRoomTurnClock.payload(state, {'value'=>event.value})
      cards = payload.split(',').reject(&:empty?)
      hand = state[:hands].fetch(state[:current_player])
      indices = cards.map { |card| hand.index(card) }
      return nil if indices.any?(&:nil?)
      value = indices.join(',')
      value += '~' + event.value.rpartition('~').last if GameRoomTurnClock.enabled?(state)
      ActionPlan.new(events: [EventCommand.new(action: 'exchange', value: value)])
    end

    def private_dealing_applied(state, event, _session, repository, history)
      return if private_waiting?(state)
      if state[:private_exchange]
        private_exchange_draw(state)
      elsif event['action'] == 'initial_hand' && betting_complete?(state)
        progress_after_action(state, state[:players][state[:dealer_index]], repository.event_id(event), history)
      end
    end

    def apply_exchange(state, event, actor, repository, history)
      return super unless state[:private_cards]
      return false unless state[:phase] == :exchange && same_user?(state[:current_player], actor)
      text = event['value'].to_s
      return false unless text.empty? || text.match?(/\A[0-4](?:,[0-4])*\z/)
      indices = text.empty? ? [] : text.split(',').map(&:to_i)
      maximum = state[:options]['draw_five'] ? 5 : 3
      player = player_key(state, actor)
      hand = state[:hands][player]
      return false unless indices.size <= maximum && indices.uniq.size == indices.size && indices.all? { |index| index < hand.size }
      return super if indices.empty?
      cards = indices.map { |index| hand[index] }
      indices.sort.reverse_each { |index| hand.delete_at(index) }
      state[:private_exchange] = {actor: player, count: cards.size, remaining: cards.size,
        cards: cards, event_id: repository.event_id(event)}
      private_exchange_draw(state)
      true
    end

    def private_exchange_draw(state)
      pending = state[:private_exchange]
      if state[:deck].empty?
        players = state[:private_discarded].select { |_, cards| !cards.empty? }.keys
        if players.empty?
          state[:private_error] = :missing_replacement_cards
        elsif !GameRoomPrivateCardDisclosure.prepare(state, players, purpose: 'recycle', zone: :private_discarded)
          private_recycle_discards(state)
        end
      else
        private_request_draw(state, actor: pending[:actor], count: [pending[:remaining], state[:deck].size].min,
          purpose: 'exchange', public: false)
      end
    end

    def private_recycle_discards(state)
      cards = state[:private_discarded].values.flatten
      state[:deck] = Array.new(cards.size, :private_card)
      state[:draw_discards] = []
      state[:private_discarded] = state[:players].to_h { |player| [player, []] }
      state[:recycle] += 1
      GameRoomPrivateCardDealing.recycle(state, cards, players: seated_players(state))
    end

    def advance_community_street(state, event_id, history)
      return super unless state[:private_cards]
      # Consume the burn privately, then expose only the community cards.
      private_request_draw(state, actor: state[:players][state[:dealer_index]], count: 1, purpose: 'burn', public: false)
    end

    def private_received_cards(state, purpose, cards, event, repository, history)
      state[:deck].shift(cards.size)
      id = repository.event_id(event)
      case purpose
      when 'burn'
        private_request_draw(state, actor: state[:players][state[:dealer_index]], count: state[:street].zero? ? 3 : 1, purpose: 'community')
      when 'community'
        state[:community].concat(cards)
        label = [_("Flop"), _("Turn"), p_("poker", "River")].fetch(state[:street])
        history << HistoryEntry.new(key: "stage:#{id}:community:#{state[:street] + 1}",
          text: _("%{stage}: %{cards}.") % {stage: label, cards: cards.map { |card| poker_card_label(card) }.join(', ')},
          event_id: id, actor: '', kind: :game)
        start_betting_street(state, state[:street] + 1)
        run_out_if_needed(state, id, history)
      when 'exchange'
        pending = state[:private_exchange]
        state[:hands][pending[:actor]].concat(cards)
        pending[:remaining] -= cards.size
        if pending[:remaining] > 0
          private_exchange_draw(state)
        else
          player = pending[:actor]
          state[:private_discarded][player].concat(pending[:cards])
          state[:draw_discards].concat(Array.new(pending[:count], :private_card))
          state[:exchanged][player] = true
          history << HistoryEntry.new(key: "exchange:#{pending[:event_id]}",
            text: n_("%{player} exchanged %{count} card.", "%{player} exchanged %{count} cards.", pending[:count]) % {
              player: participant_name(player), count: pending[:count]}, event_id: id, actor: player, kind: :game)
          state.delete(:private_exchange)
          advance_exchange(state, player, id, history)
        end
      end
    end

    def run_out_if_needed(state, event_id, history)
      return super unless state[:private_cards]
      return if actionable_players(state).size > 1
      state[:street] < 3 ? advance_community_street(state, event_id, history) : showdown(state, event_id, history)
    end

    def showdown(state, event_id, history)
      return super unless state[:private_cards]
      return if GameRoomPrivateCardDisclosure.prepare(state, contenders(state), purpose: 'showdown')
      super
    end

    def private_disclosure_completed(state, purpose, event, _session, repository, history)
      if purpose == 'showdown'
        showdown(state, repository.event_id(event), history)
      elsif purpose == 'recycle'
        private_recycle_discards(state)
      end
    end

    def can_open_draw_betting?(state, player)
      return true if state[:private_reducing] && state[:hands][player].any? { |card| GameRoomPrivateCardLedger.hidden?(card) }
      super
    end
  end
end
