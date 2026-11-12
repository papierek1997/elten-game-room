# frozen_string_literal: true
module GameRoomGames
  using GameRoomLocalization::Translations

  module MahjongPrivateTableReplay
    private

    def private_table_reduce(state, accepted, history, events, session, repository)
      seen = accepted.to_h { |event| [repository.event_id(event).to_i, true] }
      events.each do |event|
        number = repository.event_id(event).to_i
        next if number <= 0 || seen[number] || state[:phase] == :finished || state[:private_error]
        actor = repository.actor_of(event, session)
        observed = GameRoomPrivateCardLedger.observe_reveal(state, event, actor)
        candidate = private_table_copy(state)
        additions = []
        unless private_table_apply(candidate, event, actor, session, repository, additions)
          # A native reveal can be valid evidence even when its associated
          # rule action is refused. Replay it at its original position during
          # audit, without adding it to accepted moves or consuming a card.
          if observed && state[:private_audit_sources] && !state[:private_finish_pending]
            state[:private_audit_sources] = state[:private_audit_sources] + [event]
          end
          next
        end
        if candidate[:private_audit_events] && !candidate[:private_finish_pending] && event['action'] != 'mahjong_begin'
          private_table_record_audit_move(candidate, event)
        end
        private_table_audit(candidate, session, repository, additions) if candidate[:private_audit_ready] && !candidate[:private_auditing]
        state = candidate
        accepted << event
        seen[number] = true
        additions.each do |text|
          history << HistoryEntry.new(key: "mahjong:#{number}:#{history.length}", event_id: number,
            actor: actor, kind: :move, text: GameRoomContent.utf8(text))
        end
      end
      private_table_replay(state, accepted, history)
    end

    def private_table_copy(state)
      # Immutable audit inputs are shared, never recursively copied for every
      # receipt. Mutable hands and pool ledgers still have independent snapshots.
      audit = state.slice(:private_audit_start, :private_audit_events, :private_audit_sources,
        :round, :match, :profile, :players, :private_values)
      GameRoomSnapshot.copy(state.reject { |key, _| audit.key?(key) }).merge(audit)
    end

    def private_table_apply(state, event, actor, session, repository, text)
      seat = state[:players].index { |player| same_user?(player, actor) }
      actor = state[:players][seat] if seat
      if event['action'] == 'mahjong_begin'
        return false unless state[:phase] == :awaiting_deal && event['value'] == (state[:hand_number] + 1).to_s
        state[:private_audit_start] = state.slice(:session_id, :players, :profile, :match, :hand_number, :ready_seats)
        state[:private_audit_events] = [event]
        state[:private_audit_sources] = [event]
        state[:hand_number] += 1
        state[:private_deal_key] = state[:hand_number].to_s
        state[:round] = nil
        state[:private_flowers] = state[:players].to_h { |player| [player, []] }
        hands = state[:players].to_h { |player| [player, Array.new(13)] }
        profile = state[:profile]
        deck = GameRoomMahjong::Tiles.set(bonuses: profile['variant'] != 'riichi', sanma: profile['variant'] == 'riichi' && profile['seats'] == 3)
        GameRoomPrivateCardDealing.prepare(state, hands, deck: deck)
        return true
      end
      return false unless seat
      if %w[private_deal private_ready initial_hand].include?(event['action'])
        return false unless GameRoomPrivateCardDealing.apply(state, event, actor)
        if state[:phase] == :awaiting_deal
          state[:phase] = :private_flowers
          state[:private_setup_player] = state[:players].fetch(state[:match]&.dealer || 0)
          state[:private_prepared] = []
        end
        return true
      end
      case event['action']
      when 'mahjong_prepared' then private_table_receive_prepared(state, event, actor, seat, session, repository, text)
      when 'mahjong_flower' then private_table_flower(state, event, actor)
      when 'mahjong_bonus_take' then private_table_receive_bonus_take(state, event, actor, seat, session, repository, text)
      when 'mahjong_take' then private_table_receive_take(state, event, actor, seat, session, repository, text)
      when 'mahjong_drawn' then private_table_receive_drawn(state, event, actor, seat, session, repository, text)
      when 'mahjong_indicator' then private_table_receive_indicator(state, event, actor, seat, session, repository, text)
      when 'mahjong_move' then private_table_receive_move(state, event, actor, seat, session, repository, text)
      when 'private_show' then private_table_receive_show(state, event, actor, seat, session, repository, text)
      when 'mahjong_ready' then private_table_receive_ready(state, event, actor, seat, session, repository, text)
      else false
      end
    rescue JSON::ParserError
      false
    end

    def private_table_receive_prepared(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :private_flowers && same_user?(state[:private_setup_player], actor) &&
        event['value'] == state[:hand_number].to_s && state[:hands].fetch(actor).length == 13 &&
        state[:hands].fetch(actor).none? { |tile| tile.is_a?(Integer) && tile >= 136 }
      state[:private_prepared] << state[:players][seat]
      if state[:private_prepared].length == state[:players].length
        private_table_open(state)
      else
        state[:private_setup_player] = state[:players].fetch((seat + 1) % state[:players].length)
      end
      true
    end

    def private_table_receive_bonus_take(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :private_bonus_take &&
        same_user?(state[:private_setup_player] || state.dig(:private_drawing, :actor), actor) && event['value'] == state[:hand_number].to_s
      cards = GameRoomPrivateCardLedger.record_take(state, event, actor, count: 1)
      return false unless cards
      if state[:private_setup_player]
        state[:hands].fetch(actor).concat(cards)
        state[:phase] = :private_flowers
      else
        state[:private_drawing][:tile] = cards.first
        state[:private_drawing][:empty] = false
        state[:phase] = :private_draw_result
      end
      true
    end

    def private_table_receive_take(state, event, actor, seat, session, repository, text)
      parsed = GameRoomMahjong::PrivateEvents.decode(event['value'], seat: seat, hand: state[:hand_number])
      return false unless state[:phase] == :playing && parsed && %i[draw replacement].include?(parsed[0][:type]) &&
        state[:round].legal_actions(seat: seat).include?(parsed[0]) && !state[:round].flow.wall.empty?
      cards = GameRoomPrivateCardLedger.record_take(state, event, actor, count: 1)
      return false unless cards
      state[:private_drawing] = {actor: state[:players][seat], action: parsed[0], tile: cards.first, bonuses: [], empty: false}
      state[:phase] = :private_draw_result
      true
    end

    def private_table_receive_drawn(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :private_draw_result && same_user?(state.dig(:private_drawing, :actor), actor) &&
        event['value'] == state[:hand_number].to_s
      tile = state[:private_drawing][:tile]
      return false if tile.is_a?(Integer) && tile >= 136
      if state[:private_drawing][:empty] && !state[:private_auditing]
        state[:private_empty_draw] = event
        private_table_finish(state, event)
      else
        private_table_finish_draw(state, text)
        private_table_finish(state, event) if state[:round].finished?
      end
      true
    end

    def private_table_receive_indicator(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :private_indicator && event['value'] == state[:hand_number].to_s
      positions = state[:private_indicators]
      cards = GameRoomPrivateCardLedger.record_take(state, event, actor, count: positions.size, public: true)
      return false unless cards && cards.all? { |tile| tile.is_a?(Integer) && tile < 136 }
      reserve = state[:round].flow.reserve.dup
      positions.each_with_index { |position, index| reserve[position] = cards[index] }
      state[:round] = state[:round].with(flow: state[:round].flow.with(reserve: reserve))
      state[:private_indicators] = nil
      state[:phase] = :playing
      if (pending = state.delete(:private_indicator_move))
        private_table_perform(state, pending, event, session, repository, text)
      end
      true
    end

    def private_table_receive_move(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :playing
      parsed = GameRoomMahjong::PrivateEvents.decode(event['value'], seat: seat, hand: state[:hand_number])
      return false unless parsed && private_table_preflight?(state, parsed[0], parsed[1])
      action, cards = parsed
      if %i[draw replacement].include?(action[:type])
        return false unless state[:round].flow.wall.empty?
        state[:private_empty_move] = parsed
        private_table_finish(state, event) unless state[:private_auditing]
        private_table_perform(state, parsed, event, session, repository, text) if state[:private_auditing]
        return true
      end
      if GameRoomMahjong::PrivateEvents.winning?(action)
        state[:private_pending_move] = parsed
        waiting = GameRoomPrivateCardDisclosure.prepare(state, [actor], purpose: 'mahjong-action')
        private_table_continue_move(state, event, session, repository, text) unless waiting
      elsif cards.any?
        if event['__server_pool'] || (cards - state[:private_public]).empty?
          return GameRoomPrivateCardLedger.with_cards(state, event, actor, hand: state[:hands].fetch(actor), cards: cards) do
            private_table_perform(state, parsed, event, session, repository, text)
          end
        end
        state[:private_pending_move] = parsed
        waiting = GameRoomPrivateCardDisclosure.prepare(state, [actor], purpose: 'mahjong-action', cards: {actor=>cards})
        private_table_continue_move(state, event, session, repository, text) unless waiting
      else
        return private_table_perform(state, parsed, event, session, repository, text)
      end
      true
    end

    def private_table_receive_show(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :private_show
      purpose = state[:private_disclosure][:purpose]
      return false unless GameRoomPrivateCardDisclosure.apply(state, event, actor)
      if GameRoomPrivateCardDisclosure.complete?(state)
        pending = state.delete(:private_disclosure)
        state[:phase], state[:current_player] = pending[:resume]
        if purpose == 'mahjong-action'
          private_table_continue_move(state, event, session, repository, text)
        else
          private_table_audit(state, session, repository, text)
        end
      end
      true
    end

    def private_table_receive_ready(state, event, actor, seat, session, repository, text)
      return false unless state[:phase] == :between_hands
      data = JSON.parse(event['value'], max_nesting: 2)
      return false unless data == {'v'=>1, 'h'=>state[:hand_number]} && !state[:ready_seats].include?(seat)
      state[:ready_seats] = (state[:ready_seats] + [seat]).sort.freeze
      state[:phase] = :awaiting_deal if state[:ready_seats].size == state[:players].size
      text << (_('%{player} is ready for the next hand.') % {player: participant_name(actor)})
      true
    end

    def private_table_flower(state, event, actor)
      setup = state[:phase] == :private_flowers && same_user?(actor, state[:private_setup_player])
      drawn = state[:phase] == :private_draw_result && same_user?(actor, state.dig(:private_drawing, :actor))
      return false unless (setup || drawn) && event['value'].match?(/\A1(?:3[6-9]|4[0-3])\z/)
      card = event['value'].to_i
      hand = setup ? state[:hands].fetch(actor) : [state[:private_drawing][:tile]]
      accepted = GameRoomPrivateCardLedger.with_cards(state, event, actor, hand: hand, cards: [card]) do
        hand.delete(card)
        true
      end
      return false unless accepted
      if setup
        state[:private_flowers].fetch(actor) << card
      else
        state[:private_drawing][:bonuses] << card
        state[:private_drawing][:tile] = nil
      end
      if !setup && state[:round].flow.wall.length <= state[:private_drawing][:bonuses].length
        state[:private_drawing][:empty] = true
        state[:phase] = :private_draw_result
      else
        state[:phase] = :private_bonus_take
      end
      true
    end

    def private_table_open(state)
      state[:private_setup_player] = nil
      variant = state[:profile]['variant']
      reserved = variant == 'riichi' ? 14 : 0
      size = state[:private_deck].size - state[:hands].values.sum(&:size) - state[:private_flowers].values.sum(&:size)
      placeholders = Array.new(size) { |index| "mahjong-wall:#{index}" }
      reserve = reserved.zero? ? [] : placeholders.pop(reserved)
      dealer = state[:match]&.dealer || 0
      flow = GameRoomMahjong::PrivateTileFlow.new(hands: state[:players].map { |player| state[:hands].fetch(player) },
        flowers: state[:players].map { |player| state[:private_flowers].fetch(player) }, wall: placeholders, reserve: reserve,
        seat: dealer, replacement_source: variant == 'riichi' ? :riichi : :wall_back)
      ledger = variant == 'riichi' ? GameRoomMahjong::PrivateRiichiState.new(
        points: state[:match]&.points || Array.new(state[:players].size, 30000), sticks: state[:match]&.sticks || 0) : nil
      state[:round] = GameRoomMahjong::PrivateTableRound.new(flow: flow, variant: variant, dealer: dealer,
        round_wind: state[:match]&.round_wind || 27, honba: state[:match]&.honba || 0, riichi_state: ledger)
      state[:private_opening] = true
      state[:phase] = variant == 'riichi' ? :private_indicator : :playing
      state[:private_indicators] = [4] if variant == 'riichi'
    end

    def private_table_sync_flow(state, packet: [], actor: nil)
      round = state[:round]
      hands = state[:players].map { |player| state[:hands].fetch(player).dup }
      old = round.flow.hands[round.flow.seat]
      index = old.index(round.flow.last_draw) if round.flow.last_draw
      last_draw = index && hands[round.flow.seat][index]
      if actor && packet.any?
        seat = state[:players].index { |player| same_user?(player, actor) }
        return false unless packet.all? { |tile| hands[seat].include?(tile) }
        hands[seat] = packet + (hands[seat] - packet)
      end
      state[:round] = round.with(flow: round.flow.with(hands: hands, last_draw: last_draw)).refresh_claims
      true
    end

    def private_table_preflight?(state, action, cards)
      round, seat = state[:round], action[:seat]
      return false if round.finished? || action[:generation] != round.flow.generation
      hand = state[:hands].fetch(state[:players].fetch(seat))
      return false unless (cards & state[:private_public]).all? { |tile| hand.include?(tile) }
      if action[:type] == :claim
        return false unless round.window && round.window.pending.include?(seat)
        unless %i[pass win].include?(action[:choice].first)
          return false unless round.flow.phase == :reactions
          expected = GameRoomMahjong::Hand.tiles_for(action[:choice]).dup
          discarded = GameRoomMahjong::Tiles.kind(round.flow.discards.last.last)
          index = expected.index(discarded)
          return false unless index
          expected.delete_at(index)
          return false unless cards.map { |tile| GameRoomMahjong::Tiles.kind(tile) }.sort == expected.sort
        end
      else
        return false unless round.flow.seat == seat
        expected = %i[draw replacement].include?(action[:type]) ? action[:type] : :discard
        return false unless round.flow.phase == expected
      end
      true
    end

    def private_table_continue_move(state, event, session, repository, text)
      pending = state.delete(:private_pending_move)
      action = pending.first
      if state[:profile]['variant'] == 'riichi' && GameRoomMahjong::PrivateEvents.winning?(action) &&
          state[:round].riichi_state.levels[action[:seat]].positive?
        flow = state[:round].flow
        state[:private_indicators] = ((9 - flow.replacement_draws)..9).select { |index| !flow.reserve[index].is_a?(Integer) }
        unless state[:private_indicators].empty?
          state[:private_indicator_move], state[:phase] = pending, :private_indicator
          return
        end
      end
      private_table_perform(state, pending, event, session, repository, text)
    end

    def private_table_perform(state, parsed, event, session, repository, text)
      action, cards = parsed
      actor = state[:players].fetch(action[:seat])
      raise ArgumentError, 'Missing proved Mahjong packet' unless private_table_sync_flow(state, packet: cards, actor: actor)
      begin
        following = state[:round].action(**action)
      rescue ArgumentError
        return false
      end
      state[:round] = following
      state[:hands] = state[:players].each_with_index.to_h { |player, seat| [player, state[:round].flow.hands[seat].dup] }
      text << mahjong_table_move_text(action, actor)
      private_table_finish(state, event) if state[:round].finished?
      true
    end

    def private_table_finish_draw(state, text)
      pending = state.delete(:private_drawing)
      private_table_sync_flow(state)
      flow = state[:round].flow.receive(pending[:tile], bonuses: pending[:bonuses], opening: state.delete(:private_opening) == true)
      state[:round] = state[:round].with(flow: flow).action(**pending[:action])
      state[:hands] = state[:players].each_with_index.to_h { |player, seat| [player, state[:round].flow.hands[seat].dup] }
      state[:phase] = :playing
      text << mahjong_table_move_text(pending[:action], pending[:actor])
      if state[:round].flow.replacement_source == :riichi && pending[:action][:type] == :replacement
        state[:private_indicators] = [4]
        state[:phase] = :private_indicator
      end
    end

    def private_table_finish(state, event)
      private_table_record_audit_move(state, event)
      if state[:private_auditing]
        private_table_commit_result(state)
        return
      end
      state[:private_finish_pending] = true
      state[:phase] = :private_audit
      waiting = GameRoomPrivateCardDisclosure.prepare(state, state[:players], purpose: 'mahjong-audit')
      # A final draw needs no extra reveal if every remaining hand is public.
      state[:private_audit_ready] = true unless waiting
    end

    def private_table_audit(state, session, repository, text)
      values = state[:private_draws].to_h do |id, draw|
        exposed = state[:private_known].fetch(id, [])
        exposed = state[:private_values].fetch(id, exposed) if draw[:count] == exposed.size
        return state[:private_error] = :incomplete_audit unless exposed.size == draw[:count] || draw[:used].size == draw[:count]
        [id, exposed]
      end
      audit_session = session.merge('__private_draws'=>values)
      initial = state[:private_audit_start].merge(phase: :awaiting_deal, round: nil)
      GameRoomPrivateCardLedger.initialize_state(initial, audit_session)
      initial.merge!(hands: initial[:players].to_h { |player| [player, []] }, private_auditing: true)
      replay = private_table_reduce(initial, [], [], state[:private_audit_sources], audit_session, repository)
      unless replay.accepted_events == state[:private_audit_events] && !replay.state[:private_error] &&
          %i[finished between_hands].include?(replay.state[:phase])
        state[:private_error] = :invalid_round
        return
      end
      state.merge!(replay.state.slice(:round, :match, :phase, :ready_seats, :hands))
      state.delete(:private_finish_pending)
      state.delete(:private_audit_ready)
      state.delete(:private_empty_move)
      state.delete(:private_empty_draw)
    end

    def private_table_record_audit_move(state, event)
      %i[private_audit_events private_audit_sources].each do |key|
        state[key] = state.fetch(key) + [event] unless state.fetch(key).last.equal?(event)
      end
    end

    def private_table_commit_result(state)
      if state[:private_empty_move]
        parsed = state.delete(:private_empty_move)
        private_table_sync_flow(state)
        state[:round] = state[:round].action(**parsed.first) unless state[:round].finished?
      elsif state[:private_empty_draw]
        private_table_finish_draw(state, [])
      end
      round = state[:round]
      raise ArgumentError, 'Unaudited Mahjong end' unless round.finished? && round.result
      state[:match] = state[:match].advance(round: round, hand_number: state[:hand_number]) if state[:match]
      state[:phase] = state[:match] && !state[:match].finished? ? :between_hands : :finished
      state[:ready_seats] = [].freeze
    end

    def private_table_replay(state, accepted, history)
      normal = %i[playing between_hands awaiting_deal finished].include?(state[:phase])
      return mahjong_table_replay(state.freeze, accepted, history) if normal && !state[:private_error]
      Replay.new(board: nil, players: state[:players], current_player: nil, winner: nil, draw: false,
        accepted_events: accepted, history: history, state: state.freeze)
    end
  end
end
