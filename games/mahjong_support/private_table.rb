# frozen_string_literal: true
require_relative 'private_flow'
require_relative 'private_events'
require_relative '../../lib/private_card_dealing'
require_relative '../../lib/private_card_disclosure'
require_relative '../../lib/game_snapshot'
require_relative 'private_table_replay'

GameRoomPrivateCards.register('mahjong', host: %w[mahjong_begin private_deal],
  claim: %w[private_ready mahjong_prepared mahjong_drawn mahjong_ready],
  take: %w[initial_hand mahjong_take mahjong_bonus_take mahjong_indicator],
  reveal: %w[mahjong_move mahjong_flower], deals: ['mahjong_begin'])

module GameRoomGames
  using GameRoomLocalization::Translations

  module MahjongPrivateTable
    include MahjongPrivateTableReplay
    AUDIT_TAPES = %i[private_audit_events private_audit_sources].freeze

    def replay(session, events, repository)
      return super unless GameRoomPrivateCards.enabled?(session)
      # Input/resource and the bounded checkpoint are one adapter-local cache.
      # Keep admission and refusal together; this pure reducer performs no I/O.
      (@mahjong_private_replay_lock ||= Mutex.new).synchronize do
        replay_private_table(session, events, repository)
      end
    end

    private def replay_private_table(session, events, repository)
      players, profile, session_id = mahjong_table_replay_context(session, repository)
      source = events.is_a?(Array) ? events : events.to_a
      context = session.reject { |key, _| key == '__game_revision' }
      resource = repository.replay_resource_identity(session) if repository.respond_to?(:replay_resource_identity)
      context_bytes = Marshal.dump([context, players]).bytesize
      if !resource || context_bytes > GameRoomReplayCache::MAX_BYTES
        clear_private_table_cache
        return cold_private_table_replay(context, source, repository, players, profile, session_id)
      end
      previous = @mahjong_private_input if @mahjong_private_resource.equal?(resource)
      input = GameRoomReplayCache::Input.new(context, source, repository, previous: previous)
      if input.retention_bytes + context_bytes > GameRoomReplayCache::MAX_BYTES
        clear_private_table_cache
        return cold_private_table_replay(context, source, repository, players, profile, session_id)
      end
      cache = @mahjong_private_cache ||= GameRoomReplayCache.new
      checkpoint = cache.reduce(input, context: [profile, session_id, :private_mahjong],
        identities: [repository, resource, GameRoomLocalization.cache_token]) do |saved, prefix|
        if saved
          state, positions, history = restore_private_table_checkpoint(saved, input)
        else
          state, _, history = mahjong_table_initial_checkpoint(input.players, profile, session_id)
          state = initial_private_table_state(state, input.session)
          positions = []
        end
        accepted = positions.map { |position| input.events.fetch(position) }
        current = private_table_reduce(state, accepted, history.dup, input.events.drop(prefix), input.session, input)
        checkpoint_state = current.state.reject { |key, _| AUDIT_TAPES.include?(key) }
        tapes = AUDIT_TAPES.each_with_object({}) do |key, result|
          result[key] = current.state[key]&.map { |event| input.index_of(event) } if current.state.key?(key)
        end
        [checkpoint_state, GameRoomSnapshot::Log.from_owned(current.accepted_events.map { |event| input.index_of(event) }),
          GameRoomSnapshot::Log.from_owned(current.history, previous: history), tapes]
      end
      # The two independent budgets are serialized retention limits, not RSS:
      # input + full context <=8MiB, owned checkpoint <=8MiB in the shared cache.
      if cache.retained_bytes.positive?
        @mahjong_private_input, @mahjong_private_resource = input, resource
      else
        clear_private_table_cache
      end
      state, positions, history = restore_private_table_checkpoint(checkpoint, input)
      accepted = GameRoomSnapshot::Log.from_sealed(positions.map { |position| input.events.fetch(position) }, bytes: input.retained_bytes)
      private_table_replay(state.freeze, accepted, history)
    end

    def incremental_replay(previous, session, events, repository)
      return nil if GameRoomPrivateCards.enabled?(session)
      super
    end

    def automatic_action(replay, actor, context: nil)
      return super unless replay.state[:private_cards]
      state = replay.state
      actor = replay.players.find { |player| same_user?(player, actor) } || actor
      owner = context&.table_owner || state[:private_owner]
      host_action = %i[awaiting_deal private_prepare].include?(state[:phase]) && same_user?(state[:private_viewer], owner) && same_user?(actor, replay.players.first)
      return nil if state[:private_error] || (!same_user?(state[:private_viewer], actor) && !host_action)
      action = GameRoomPrivateCardDealing.automatic(state, actor, owner: owner)
      action ||= 'mahjong_begin' if state[:phase] == :awaiting_deal && host_action
      action ||= 'private_show' if GameRoomPrivateCardDisclosure.command(state, actor)
      if state[:phase] == :private_flowers && same_user?(actor, state[:private_setup_player])
        action ||= state[:hands].fetch(actor).any? { |tile| tile.is_a?(Integer) && tile >= 136 } ? 'mahjong_flower' : 'mahjong_prepared'
      elsif state[:phase] == :private_bonus_take && same_user?(actor, state[:private_setup_player] || state.dig(:private_drawing, :actor))
        action ||= 'mahjong_bonus_take'
      elsif state[:phase] == :private_draw_result && same_user?(actor, state.dig(:private_drawing, :actor))
        card = state[:private_drawing][:tile]
        action ||= card.is_a?(Integer) && card >= 136 ? 'mahjong_flower' : 'mahjong_drawn'
      elsif state[:phase] == :private_indicator && replay.players.any? { |player| same_user?(actor, player) } &&
          (same_user?(actor, owner) || replay.players.none? { |player| same_user?(player, owner) } && same_user?(actor, replay.players.first))
        action ||= 'mahjong_indicator'
      elsif state[:phase] == :playing && state[:private_opening] && same_user?(actor, replay.players.fetch(state[:round].flow.seat))
        return mahjong_scoped_selection(GameRoomMahjong::TableEvents.to_selection(
          {seat: state[:round].flow.seat, generation: state[:round].flow.generation, type: :draw}), state)
      end
      action && {'kind'=>'command', 'action'=>action}
    end

    def action_for(selection, replay, actor, context: nil)
      return super unless replay.state[:private_cards]
      state = replay.state
      actor = replay.players.find { |player| same_user?(player, actor) } || actor
      return [:finished, nil] if replay.finished?
      return [:stale, nil] if context && context.session_id != state[:session_id]
      host_action = %i[awaiting_deal private_prepare].include?(state[:phase]) &&
        same_user?(state[:private_viewer], context&.table_owner || state[:private_owner]) && same_user?(actor, replay.players.first)
      return [:invalid, nil] if state[:private_error] || (!same_user?(actor, state[:private_viewer]) && !host_action)
      automatic = automatic_action(replay, actor, context: context)
      if automatic == selection && automatic
        command = private_table_command(automatic['action'], state, actor)
        return [:ok, ActionPlan.new(events: [command])] if command
      end
      return [:invalid, nil] unless %i[playing between_hands].include?(state[:phase])
      if state[:phase] == :between_hands
        status, plan = super
        return [status, plan] unless status == :ok
        event = plan.events.fetch(0)
        return [:ok, ActionPlan.new(events: [GameRoomPrivateCards.command(event.action, event.value, operation: 'claim')])]
      end
      seat = replay.players.index { |player| same_user?(actor, player) }
      return [:not_your_turn, nil] unless seat
      input = mahjong_unscoped_selection(selection.to_h, state)
      action = input && GameRoomMahjong::TableEvents.selection(input, round: state[:round], seat: seat)
      return [:invalid, nil] unless action
      cards = private_table_packet(state, action)
      value = GameRoomMahjong::PrivateEvents.encode(action, hand: state[:hand_number], cards: cards)
      if %i[draw replacement].include?(action[:type]) && !state[:round].flow.wall.empty?
        command = GameRoomPrivateCards.command('mahjong_take', value, operation: 'take', pool_id: state[:private_pool], count: 1)
      else
        request = {operation: 'claim'}
        private_cards = cards - state[:private_public]
        receipts = private_cards.map { |card| GameRoomPrivateCardLedger.locate(state, actor, card) }
        return [:invalid, nil] if receipts.any?(&:nil?)
        if receipts.any? && receipts.map { |item| item[:draw_id] }.uniq.one? &&
            receipts.none? { |item| GameRoomPrivateCardLedger.known?(state, item) }
          request = receipts.first.slice(:pool_id, :draw_id).merge(operation: 'reveal', values: receipts.map { |item| item[:value] })
        end
        command = GameRoomPrivateCards.command('mahjong_move', value, **request)
      end
      [:ok, ActionPlan.new(events: [command])]
    end

    def legal_actions(replay, actor, context: nil)
      return super unless replay.state[:private_cards]
      return [] unless same_user?(actor, replay.state[:private_viewer]) && !replay.state[:private_error] &&
        %i[playing between_hands].include?(replay.state[:phase])
      super
    end

    def active_actors(replay)
      return super unless replay.state[:private_cards]
      return [] if replay.finished? || replay.state[:private_error]
      return super if %i[playing between_hands awaiting_deal].include?(replay.state[:phase])
      replay.players.select { |actor| automatic_action(replay, actor) }
    end

    def surface_spec(replay, viewer:, context: nil)
      state = replay.state
      return super unless state[:private_cards]
      own = replay.players.index { |player| same_user?(player, viewer) }
      waiting = !%i[playing between_hands finished].include?(state[:phase]) || state[:private_error] ||
        own && state[:hands].fetch(replay.players[own]).any? { |tile| GameRoomPrivateCardLedger.hidden?(tile) }
      return super unless waiting
      text = state[:private_error] ? _('The server deck is inconsistent. This game cannot continue.') :
        state[:phase] == :private_show ? _('Waiting for players to reveal their cards.') : _('Waiting for all players to receive their cards.')
      mahjong_table_info('mahjong-private-wait', _('Mahjong'), text)
    end

    def concurrent_session_input?(before, after, selection)
      return false if after.state[:private_cards] && before.state[:phase] != after.state[:phase]
      super
    end

    def participant_scores(replay)
      state = replay.state
      return super unless state[:private_cards] && state[:private_finish_pending]
      values = state[:match]&.scores || Array.new(replay.players.size, 0)
      replay.players.each_with_index.to_h { |player, seat| [player, values[seat]] }
    end

    private

    def clear_private_table_cache
      @mahjong_private_input = @mahjong_private_resource = @mahjong_private_cache = nil
    end

    def initial_private_table_state(initial, session)
      state = initial.dup
      GameRoomPrivateCardLedger.initialize_state(state, session)
      state[:hands] = state[:players].to_h { |player| [player, []] }
      state[:private_flowers] = state[:players].to_h { |player| [player, []] }
      state
    end

    def cold_private_table_replay(session, events, repository, players, profile, session_id)
      initial, _, history = mahjong_table_initial_checkpoint(players, profile, session_id)
      private_table_reduce(initial_private_table_state(initial, session), [], history, events, session, repository)
    end

    def restore_private_table_checkpoint(checkpoint, input)
      state, positions, history, tapes = checkpoint
      # Only the shared cache's full authenticated prefix match allows these
      # positions to refer to current canonical records. Never recover by ID.
      restored = state.merge(tapes.transform_values { |indexes| indexes&.map { |index| input.events.fetch(index) } })
      [restored, positions, history]
    end

    def private_table_command(action, state, actor)
      case action
      when 'mahjong_begin'
        GameRoomPrivateCards.command(action, (state[:hand_number] + 1).to_s, operation: 'claim')
      when 'private_deal', 'private_ready', 'initial_hand'
        GameRoomPrivateCardDealing.command(state, action, actor)
      when 'private_show'
        GameRoomPrivateCardDisclosure.command(state, actor)
      when 'mahjong_prepared', 'mahjong_drawn'
        GameRoomPrivateCards.command(action, state[:hand_number].to_s, operation: 'claim')
      when 'mahjong_flower'
        hand = state[:phase] == :private_flowers ? state[:hands].fetch(actor) : [state[:private_drawing][:tile]]
        card = hand.find { |tile| tile.is_a?(Integer) && tile >= 136 }
        receipt = card && GameRoomPrivateCardLedger.locate(state, actor, card)
        return nil unless receipt
        request = GameRoomPrivateCardLedger.known?(state, receipt) ? {operation: 'claim'} : receipt.merge(operation: 'reveal')
        GameRoomPrivateCards.command(action, card.to_s, **request)
      when 'mahjong_bonus_take'
        GameRoomPrivateCards.command(action, state[:hand_number].to_s, operation: 'take', pool_id: state[:private_pool], count: 1)
      when 'mahjong_indicator'
        GameRoomPrivateCards.command(action, state[:hand_number].to_s, operation: 'take', pool_id: state[:private_pool],
          count: state[:private_indicators].size, visibility: 'public')
      end
    end

    def private_table_packet(state, action)
      return [] if GameRoomMahjong::PrivateEvents.winning?(action)
      return [action[:tile]] if %i[discard riichi].include?(action[:type])
      kinds = GameRoomMahjong::PrivateEvents.packet_kinds(action).dup
      if action[:type] == :claim && kinds.any?
        discarded = GameRoomMahjong::Tiles.kind(state[:round].flow.discards.last.last)
        kinds.delete_at(kinds.index(discarded))
      end
      available = state[:hands].fetch(state[:players].fetch(action[:seat])).dup
      kinds.map do |kind|
        card = available.find { |tile| tile.is_a?(Integer) && GameRoomMahjong::Tiles.kind(tile) == kind }
        raise ArgumentError, 'Missing private Mahjong packet' unless card
        available.delete(card)
        card
      end
    end
  end
end
