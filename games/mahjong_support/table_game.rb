# frozen_string_literal: true
require_relative '../base'
require_relative '../../lib/game_bots'
require_relative '../../lib/game_replay_cache'
require_relative 'table_events'
require_relative 'table_presentation'
require_relative 'mcr_deal'
require_relative 'hong_kong_deal'
require_relative 'riichi_deal'
require_relative 'rules'
require_relative 'match_state'
require_relative '../mahjong_rules'

module GameRoomGames
  using GameRoomLocalization::Translations

  # Table session adapter, with optional whole-match progression.
  module MahjongTableGame
    include MahjongTablePresentation
    include MahjongRules
    def mahjong_rulebook_scope; :table; end

    class Strategy
      include GameRoomBots::ReplayOnlyStrategy
      def choose(actions:, game:, replay:, actor:)
        selected = game.table_bot_selection(replay, actor)
        actions.find { |action| action == selected }
      end
    end

    def supports_bots?; true; end
    def session_history_capacity(_options); 32_768; end
    def bot_strategy; @mahjong_table_strategy ||= Strategy.new; end
    def build_presentation_game; build_session_game; end

    def replay(session, events, repository)
      _players, profile, session_id = mahjong_table_replay_context(session, repository)
      @mahjong_table_repository = repository
      # The CAS token changes after every write, but is not game semantics.
      # The cache still authenticates the complete event prefix and actors.
      source_events = events.is_a?(Array) ? events : events.to_a
      input = GameRoomReplayCache::Input.new(session.reject { |key, _| key == '__game_revision' }, source_events, repository,
        previous: @mahjong_table_input)
      @mahjong_table_input = input.retention_bytes <= GameRoomReplayCache::MAX_BYTES ? input : nil
      @mahjong_table_cache ||= GameRoomReplayCache.new
      checkpoint = @mahjong_table_cache.reduce(input, context: [profile, session_id],
        identities: [repository, GameRoomLocalization.cache_token]) do |previous, prefix|
        previous ||= mahjong_table_initial_checkpoint(input.players, profile, session_id)
        state, accepted_positions, history = previous
        accepted = accepted_positions.map { |position| input.events.fetch(position) }
        current = reduce_mahjong_table(state, accepted, history.dup, input.events.drop(prefix), input.session, input)
        positions = current.accepted_events.map { |event| input.index_of(event) }
        [current.state, GameRoomSnapshot::Log.from_owned(positions, previous: accepted_positions),
          GameRoomSnapshot::Log.from_owned(current.history, previous: history)]
      end
      state, accepted_positions, history = checkpoint
      # Accepted records are the cache's authenticated, deeply sealed copies,
      # not caller-owned Hashes. Repeated snapshot copies share only these logs;
      # the current hand/model remains an isolated mutable copy.
      unless @mahjong_accepted_input.equal?(input.events) && @mahjong_accepted_positions.equal?(accepted_positions)
        @mahjong_accepted_input, @mahjong_accepted_positions = input.events, accepted_positions
        @mahjong_accepted_log = GameRoomSnapshot::Log.from_sealed(accepted_positions.map { |position| input.events.fetch(position) },
          bytes: input.retained_bytes)
      end
      accepted = @mahjong_accepted_log
      mahjong_table_replay(state, accepted, history)
    end

    def incremental_replay(previous, session, events, repository)
      return nil unless previous&.state && @mahjong_table_repository.equal?(repository) && repository.respond_to?(:session_id)
      return nil unless previous.state[:session_id] == repository.session_id(session) && repository.players_for(session) == previous.players
      profile = mahjong_table_profile(session)
      return nil unless profile == previous.state[:profile]
      reduce_mahjong_table(previous.state, previous.accepted_events.dup, previous.history.dup, events, session, repository)
    end

    def automatic_action(replay, actor, context: nil)
      return nil unless replay&.state&.fetch(:phase) == :awaiting_deal && same_user?(actor, replay.players.first)
      action = {'kind'=>'command', 'action'=>'deal'}
      action['hand'] = replay.state[:hand_number] + 1 if replay.state[:match]
      action.freeze
    end

    def automatic_action_due?(replay, actor, context: nil)
      !automatic_action(replay, actor, context: context).nil?
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:stale, nil] if context && context.session_id != replay.state[:session_id]
      seat = replay.players.index { |player| same_user?(player, actor) }
      return [:not_your_turn, nil] unless seat
      input = selection.to_h
      if replay.state[:phase] == :between_hands
        ready = mahjong_ready_selection(replay.state, seat)
        return [:invalid, nil] unless ready && input.reject { |key, _| key == 'source' } == ready
        return [:ok, event_plan('mahjong_ready', JSON.generate('v'=>1, 'h'=>replay.state[:hand_number]))]
      end
      if replay.state[:phase] == :awaiting_deal
        return [:invalid, nil] unless seat == 0 && selection.to_h['kind'] == 'command' && selection.to_h['action'] == 'deal' && context && (context.server_random || context.random_source)
        if replay.state[:match]
          return [:stale, nil] unless input['hand'].is_a?(Integer) && input['hand'] == replay.state[:hand_number] + 1
        end
        if context.server_random
          data = {'v'=>1}
          data['h'] = input['hand'] if replay.state[:match]
          command = GameRoomServerRandom.recipe_command(action: 'mahjong_deal', kind: 'seed_json', data: data)
          return [:ok, ActionPlan.new(events: [command])]
        end
        values = context.random_source.roll(count: 8, sides: 256).values
        return [:invalid, nil] unless values.is_a?(Array) && values.length == 8 && values.all? { |value| value.is_a?(Integer) && value.between?(1, 256) }
        seed = values.reduce(0) { |number, value| (number << 8) | (value - 1) } & ((1 << 63) - 1)
        payload = {'v'=>1, 'r'=>seed}
        if replay.state[:match]
          return [:invalid, nil] unless input['hand'].is_a?(Integer) && input['hand'] == replay.state[:hand_number] + 1
          payload['h'] = input['hand']
        end
        return [:ok, event_plan('mahjong_deal', JSON.generate(payload))]
      end
      input = mahjong_unscoped_selection(input, replay.state)
      return [:stale, nil] unless input
      action = GameRoomMahjong::TableEvents.selection(input, round: replay.state[:round], seat: seat)
      return [:invalid, nil] unless action
      value = GameRoomMahjong::TableEvents.encode(action)
      value = JSON.generate(JSON.parse(value).merge('h'=>replay.state[:hand_number])) if replay.state[:match]
      return [:invalid, nil] if value.bytesize > 64
      [:ok, event_plan('mahjong_move', value)]
    end

    def active_actors(replay)
      return [] if replay.finished?
      return [replay.players.first] if replay.state[:phase] == :awaiting_deal
      if replay.state[:phase] == :between_hands
        return replay.players.each_with_index.filter_map { |player, seat| player unless replay.state[:ready_seats].include?(seat) }
      end
      round = replay.state[:round]
      seats = %i[reactions kong_reactions].include?(round.flow.phase) ? round.window.pending : [round.flow.seat]
      seats.map { |seat| replay.players.fetch(seat) }
    end

    def required_decision_key(replay, viewer)
      return nil unless active_actors(replay).any? { |actor| same_user?(actor, viewer) }
      round = replay.state[:round]
      [replay.state[:hand_number], replay.state[:phase], round ? round.flow.generation : :deal, viewer.to_s.downcase]
    end

    def concurrent_session_input?(before, after, selection)
      return false unless before && after && before.players == after.players &&
        before.state[:session_id] == after.state[:session_id] && before.state[:hand_number] == after.state[:hand_number] &&
        before.state[:profile] == after.state[:profile]
      if before.state[:phase] == :between_hands && after.state[:phase] == :between_hands
        input = selection.to_h
        return input['kind'] == 'command' && input['action'] == 'ready' && input['hand'].is_a?(Integer) && input['hand'] == after.state[:hand_number]
      end
      first, last = before&.state&.dig(:round), after&.state&.dig(:round)
      return false unless first && last && !after.finished? && before.players == after.players &&
        before.state[:session_id] == after.state[:session_id] && before.state[:profile] == after.state[:profile] &&
        %i[reactions kong_reactions].include?(first.flow.phase) && first.flow.phase == last.flow.phase && first.window && last.window &&
        first.flow.generation == last.flow.generation && first.flow.discards.last == last.flow.discards.last &&
        first.window.offers == last.window.offers
      input = mahjong_unscoped_selection(selection.to_h, after.state)
      return false unless input
      input['kind'] == 'question' && input['action'] == 'submit' &&
        input['question_id'] == "mahjong-claim:#{last.flow.generation}"
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !replay.state[:round]
      seat = replay.players.index { |player| same_user?(player, actor) }
      return [] unless seat
      return [mahjong_ready_selection(replay.state, seat)].compact if replay.state[:phase] == :between_hands
      replay.state[:round].legal_actions(seat: seat).map do |action|
        mahjong_scoped_selection(GameRoomMahjong::TableEvents.to_selection(action), replay.state)
      end
    end

    def table_bot_selection(replay, actor)
      seat = replay.players.index { |player| same_user?(player, actor) }
      return nil unless seat && replay.state[:round] && !replay.finished?
      return mahjong_ready_selection(replay.state, seat) if replay.state[:phase] == :between_hands
      selected = replay.state[:round].bot_action(seat: seat)
      selected && mahjong_scoped_selection(GameRoomMahjong::TableEvents.to_selection(selected), replay.state)
    end

    def surface_spec(replay, viewer:, context: nil)
      if replay.state[:round]
        spec = table_surface_spec(replay.state[:round], players: replay.players, viewer: viewer)
        return spec unless replay.state[:match]
        spec = mahjong_scoped_surface(spec, replay.state)
        parts = spec.parts.dup
        scores = participant_scores(replay)
        lines = replay.players.each_with_index.map do |player, seat|
          _('%{player}: %{points}') % {player: participant_name(player), points: replay.state[:match].initial_points[seat] + scores[player]}
        end
        parts << mahjong_table_part('match_scores', mahjong_table_info('mahjong-match-scores', _('Match scores'), lines.join("\n")))
        if replay.state[:phase] == :between_hands
          seat = replay.players.index { |player| same_user?(player, viewer) }
          if seat && mahjong_ready_selection(replay.state, seat)
            command = GameSurfaces::Command.new(id: 'ready', label: _('Ready for the next hand'), payload: {'hand'=>replay.state[:hand_number]})
            parts << mahjong_table_part('match_ready', GameSurfaces::CommandPanelSpec.new(commands: [command]))
          end
        end
        return GameSurfaces::CompositeSpec.new(parts: mahjong_order_table_parts(parts))
      end
      mahjong_table_info('mahjong-awaiting-deal', _('Mahjong'), _('Waiting for the game to start'))
    end

    def participant_scores(replay)
      round = replay.state[:round]
      if replay.state[:match]
        scores = replay.state[:match].scores.dup
        if replay.state[:phase] == :playing && round&.riichi_state
          scores.each_index { |seat| scores[seat] += round.riichi_state.points[seat] - round.riichi_state.starting_points[seat] }
        end
        return replay.players.each_with_index.to_h { |player, seat| [player, scores[seat]] }
      end
      replay.players.each_with_index.to_h do |player, seat|
        points = if round&.result
          round.result.payments.fetch(seat)
        elsif round&.riichi_state
          round.riichi_state.points[seat] - round.riichi_state.starting_points[seat]
        else
          0
        end
        [player, points]
      end
    end

    private

    # Public/private adapters share the same validated start, without preparing
    # a second empty-log cache which could retain an unbudgeted private map.
    def mahjong_table_replay_context(session, repository)
      players = repository.players_for(session).dup.freeze
      profile = mahjong_table_profile(session)
      unless %w[mcr riichi hong_kong].include?(profile['variant']) && players.length == profile['seats'] &&
          players.map { |player| player.to_s.downcase }.uniq.length == players.length
        raise ArgumentError, 'Unsupported internal mahjong table profile'
      end
      session_id = repository.respond_to?(:session_id) ? repository.session_id(session) : (session['__id'] || session['id'])
      identity_supplied = repository.respond_to?(:session_id) || session.key?('__id') || session.key?('id')
      raise ArgumentError, 'Invalid mahjong session' if identity_supplied && !(session_id.is_a?(Integer) && session_id.positive?)
      [players, profile, session_id]
    end

    def mahjong_table_initial_checkpoint(players, profile, session_id)
      match = profile['match_winds'].positive? ? GameRoomMahjong::MatchState.new(
        variant: profile['variant'], seats: profile['seats'], winds: profile['match_winds']) : nil
      state = {session_id: session_id, players: players, profile: profile, phase: :awaiting_deal, round: nil,
        match: match, hand_number: 0, ready_seats: [].freeze}.freeze
      [state, [], [starting_history(players)]]
    end

    def mahjong_table_profile(session)
      options = options_from_json(session['options'])
      winds = options.fetch('match_winds', 0)
      raise ArgumentError, 'Invalid mahjong match length' unless winds.is_a?(Integer) && winds.between?(0, 4)
      profile = GameRoomMahjong::Rules.normalize(options).merge('match_winds'=>winds)
      profile['fan_progress'] = 'no' if options['fan_progress'] == 'no'
      profile.freeze
    end

    def mahjong_ready_selection(state, seat)
      return nil unless state[:phase] == :between_hands && !state[:ready_seats].include?(seat)
      {'kind'=>'command', 'action'=>'ready', 'hand'=>state[:hand_number]}.freeze
    end

    def mahjong_scoped_selection(input, state)
      return input unless state[:match]
      result = input.dup
      if result['kind'] == 'question'
        result['question_id'] = "#{result['question_id']}:h#{state[:hand_number]}"
      else
        result['hand'] = state[:hand_number]
      end
      result.freeze
    end

    def mahjong_unscoped_selection(input, state)
      return input unless state[:match]
      result = input.dup
      if result['kind'] == 'question'
        suffix = ":h#{state[:hand_number]}"
        return nil unless result['question_id'].is_a?(String) && result['question_id'].end_with?(suffix)
        result['question_id'] = result['question_id'].delete_suffix(suffix)
      else
        return nil unless result['hand'].is_a?(Integer) && result['hand'] == state[:hand_number]
        result.delete('hand')
      end
      result
    end

    def mahjong_scoped_surface(spec, state)
      parts = spec.parts.map do |part|
        surface = part.surface.dup
        if surface.is_a?(GameSurfaces::QuestionSpec)
          surface.id = "#{surface.id}:h#{state[:hand_number]}"
        elsif surface.is_a?(GameSurfaces::CommandPanelSpec)
          surface.commands = surface.commands.map do |command|
            copy = command.dup
            copy.payload = (command.payload || {}).merge('hand'=>state[:hand_number])
            copy
          end
        end
        mahjong_table_part(part.id, surface)
      end
      GameSurfaces::CompositeSpec.new(parts: parts)
    end

    def mahjong_table_move(value, seat, state)
      return GameRoomMahjong::TableEvents.decode(value, seat: seat) unless state[:match]
      return nil unless value.is_a?(String) && value.bytesize <= 64
      data = JSON.parse(value, max_nesting: 3)
      return nil unless data.is_a?(Hash) && data['h'].is_a?(Integer) && data.delete('h') == state[:hand_number]
      GameRoomMahjong::TableEvents.decode(JSON.generate(data), seat: seat)
    rescue JSON::ParserError
      nil
    end

    def reduce_mahjong_table(state, accepted, history, events, session, repository)
      seen = accepted.to_h { |event| [repository.event_id(event).to_i, true] }
      events.each do |event|
        event_id = repository.event_id(event).to_i
        next if event_id <= 0 || seen[event_id] || state[:phase] == :finished
        actor = repository.actor_of(event, session)
        seat = state[:players].index { |player| same_user?(player, actor) }
        next unless seat
        match, hand_number, ready_seats = state.values_at(:match, :hand_number, :ready_seats)
        if event['action'] == 'mahjong_deal'
          next unless seat == 0 && state[:phase] == :awaiting_deal
          seed = mahjong_table_seed(event['value'], hand: match ? hand_number + 1 : nil)
          next unless seed
          profile = state[:profile]
          if match
            round = match.next_round(seed: seed)
          else
            flow = case profile['variant']
            when 'mcr' then GameRoomMahjong::MCRDeal.shuffled(seed: seed)
            when 'hong_kong' then GameRoomMahjong::HongKongDeal.shuffled(seed: seed)
            else GameRoomMahjong::RiichiDeal.shuffled(seed: seed, seats: profile['seats'])
            end
            round = GameRoomMahjong::TableRound.new(flow: flow, variant: profile['variant'], dealer: 0)
          end
          hand_number += 1
          phase, ready_seats = :playing, [].freeze
          text = _('The mahjong tiles have been dealt.')
        elsif event['action'] == 'mahjong_ready' && state[:phase] == :between_hands
          value = event['value']
          next unless value.is_a?(String) && value.bytesize <= 64
          begin
            data = JSON.parse(value, max_nesting: 2)
          rescue JSON::ParserError
            next
          end
          next unless data.is_a?(Hash) && data.keys.sort == %w[h v] && data['v'].is_a?(Integer) && data['v'] == 1 &&
            data['h'].is_a?(Integer) && data['h'] == hand_number && !ready_seats.include?(seat)
          ready_seats = (ready_seats + [seat]).sort.freeze
          round = state[:round]
          phase = ready_seats.length == state[:players].length ? :awaiting_deal : :between_hands
          text = _('%{player} is ready for the next hand.') % {player: participant_name(actor)}
        elsif event['action'] == 'mahjong_move' && state[:phase] == :playing
          action = mahjong_table_move(event['value'], seat, state)
          next unless action && state[:round].legal_action?(action)
          round = state[:round].action(**action)
          phase = round.finished? ? :finished : :playing
          if match && round.finished?
            match = match.advance(round: round, hand_number: hand_number)
            phase = match.finished? ? :finished : :between_hands
            ready_seats = [].freeze
          end
          text = mahjong_table_move_text(action, actor)
        else
          next
        end
        state = state.merge(round: round, phase: phase, match: match, hand_number: hand_number, ready_seats: ready_seats).freeze
        accepted << event
        seen[event_id] = true
        # Tile faces from a draw never enter the public history.
        history << HistoryEntry.new(key: "mahjong:#{event_id}", event_id: event_id, actor: actor,
          kind: :move, text: GameRoomContent.utf8(text))
      end
      mahjong_table_replay(state, accepted, history)
    end

    def mahjong_table_replay(state, accepted, history)
      result = state[:round]&.result
      winner, draw = nil, false
      if state[:phase] == :finished
        if state[:match]
          best = state[:match].points.max
          leaders = state[:match].points.each_index.select { |seat| state[:match].points[seat] == best }
          winner = state[:players].fetch(leaders.first) if leaders.length == 1
          draw = leaders.length != 1
        else
          winner = state[:players].fetch(result.winner) unless result.draw?
          draw = result.draw?
        end
      end
      current = state[:phase] == :awaiting_deal ? state[:players].first : state[:phase] == :finished ? nil :
        state[:phase] == :between_hands ? state[:players].each_with_index.find { |_, seat| !state[:ready_seats].include?(seat) }.first :
          state[:players].fetch(%i[reactions kong_reactions].include?(state[:round].flow.phase) ? state[:round].window.pending.first : state[:round].flow.seat)
      Replay.new(board: nil, players: state[:players], current_player: current, winner: winner,
        draw: draw, accepted_events: accepted, history: history, state: state)
    end

    def mahjong_table_seed(value, hand: nil)
      return nil unless value.is_a?(String) && value.bytesize <= 64
      data = JSON.parse(value, max_nesting: 2)
      keys = hand ? %w[h r v] : %w[r v]
      return nil unless data.is_a?(Hash) && data.keys.sort == keys && (!hand || data['h'].is_a?(Integer) && data['h'] == hand) && data['v'].is_a?(Integer) && data['v'] == 1 &&
        data['r'].is_a?(Integer) && data['r'].between?(0, (1 << 63) - 1)
      data['r']
    rescue JSON::ParserError
      nil
    end

    def mahjong_table_move_text(action, actor)
      player = participant_name(actor)
      case action[:type]
      when :draw, :replacement
        _('%{player} drew a tile.') % {player: player}
      when :discard
        _('%{player} discarded %{tile}.') % {player: player, tile: GameRoomMahjong::TileLabels.label(action[:tile])}
      when :win
        _('%{player} declared Mahjong.') % {player: player}
      when :concealed_kong
        _('%{player} declared a concealed kong.') % {player: player}
      when :added_kong
        _('%{player} proposed a kong of %{tile}.') % {player: player, tile: GameRoomMahjong::TileLabels.label(action[:tile] * 4)}
      when :riichi
        _('%{player} declared riichi, discarding %{tile}.') % {player: player, tile: GameRoomMahjong::TileLabels.label(action[:tile])}
      when :claim
        if action[:choice] == [:pass]
          _('%{player} passed.') % {player: player}
        elsif action[:choice] == [:win]
          _('%{player} declared Mahjong.') % {player: player}
        else
          _('%{player} claimed %{set}.') % {player: player, set: mahjong_claim_label(action[:choice])}
        end
      end
    end
  end
end
