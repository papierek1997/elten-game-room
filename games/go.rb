require_relative 'base'
require_relative '../lib/game_bots'
require_relative '../lib/go_position'

module GameRoomGames
  using GameRoomLocalization::Translations

  class Go < Base
    include PublicHistoryAnnouncements
    def id; 'go'; end
    def name; _('Go'); end
    def short_description; _('Surround territory, capture stones and protect the liberties of your groups.'); end
    def supports_bots?; true; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end
    def rule_sections; generated_rule_sections; end
    def notification_option_keys(_options); %w[variant size]; end

    def option_definitions
      [OptionDefinition.new(key: 'variant', label: _('Variant'), kind: :choice, default: 'area', choices: [
        OptionChoice.new(value: 'area', label: _('Chinese-style area scoring')),
        OptionChoice.new(value: 'territory', label: _('Territory scoring with agreed dead groups and seki')),
        OptionChoice.new(value: 'atari', label: _('Atari Go: first capture wins'))]),
       OptionDefinition.new(key: 'size', label: _('Board size'), kind: :choice, default: '9', choices:
         %w[9 13 19].map { |size| OptionChoice.new(value: size, label: "#{size} x #{size}") }),
       OptionDefinition.new(key: 'komi', label: _('White compensation (komi)'), kind: :choice, default: '7.5',
         visible_if: {'variant' => %w[area territory]}, choices: %w[0 0.5 5.5 6.5 7.5].map do |value|
           OptionChoice.new(value: value, label: value)
         end)]
    end

    def replay(session, events, repository)
      players, options = repository.players_for(session), options_from_json(session['options'])
      board = Array.new(options['size'].to_i ** 2)
      state = {players: players, options: options, stones: board, seen: {GameRoomGoPosition.key(board) => true},
        captures: [0, 0], passes: 0, phase: :playing, dead: [], neutral: [], approved: [], moves: 0,
        current_player: players.first, winner: nil, draw: false, scores: nil}
      accepted, history, seen = [], [starting_history(players)], {}
      events.each do |event|
        break if state[:phase] == :finished
        event_id, actor = repository.event_id(event), repository.actor_of(event, session)
        next if seen[event_id] || !same_user?(actor, state[:current_player])
        action, value = event['action'].to_s, event['value'].to_s
        before_captures = state[:captures].sum
        next unless apply_go_event(state, action, value, actor)
        accepted << event
        seen[event_id] = true
        history << HistoryEntry.new(key: "go:#{event_id}", event_id: event_id, actor: actor,
          kind: :move, text: go_event_text(action, value, actor, state))
        captured = state[:captures].sum - before_captures
        if captured > 0
          history << HistoryEntry.new(key: "capture:#{event_id}", event_id: event_id, actor: actor, kind: :capture,
            text: _('%{player} captures %{count} stones.') % {player: participant_name(actor), count: captured})
        end
        if state[:scores] && state[:phase] == :finished
          history << HistoryEntry.new(key: "score:#{event_id}", event_id: event_id, actor: actor, kind: :score,
            text: _('Black %{black}; White %{white}, including komi.') % {black: state[:scores][0] / 2.0, white: state[:scores][1] / 2.0})
        end
        history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw]) if state[:phase] == :finished
      end
      Replay.new(board: state[:stones].each_slice(options['size'].to_i).map(&:dup), players: players,
        current_player: state[:current_player], winner: state[:winner], draw: state[:draw],
        state: state, accepted_events: accepted, history: history)
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(replay.current_player, actor)
      state, size = replay.state, replay.state[:options]['size'].to_i
      points = state[:stones].each_index.select do |point|
        state[:phase] == :scoring || placement(state, point)
      end
      commands = state[:phase] == :scoring ? %w[accept resume resign] : %w[pass resign]
      points.map { |point| {'kind' => 'grid', 'action' => 'select', 'x' => point % size, 'y' => point / size} } +
        commands.map { |command| {'kind' => 'command', 'action' => command} }
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:not_your_turn, nil] unless same_user?(replay.current_player, actor)
      state, action = replay.state, selection['action'].to_s
      if selection['kind'] == 'grid' && action == 'select'
        x, y, size = selection['x'], selection['y'], state[:options]['size'].to_i
        return [:invalid, nil] unless [x, y].all? { |v| v.is_a?(Integer) && v.between?(0, size - 1) }
        point = y * size + x
        return [:invalid_move, nil] unless state[:phase] == :scoring || placement(state, point)
        return [:ok, event_plan(state[:phase] == :scoring ? 'mark' : 'place', point.to_s)]
      end
      allowed = state[:phase] == :scoring ? %w[accept resume resign] : %w[pass resign]
      allowed.include?(action) ? [:ok, event_plan(action, '')] : [:invalid, nil]
    end

    def move_error(status)
      return _('Choose an empty intersection. Suicide and repetition of an earlier board position are forbidden.') if status == :invalid_move
      super
    end

    def surface_spec(replay, viewer)
      state, size = replay.state, replay.state[:options]['size'].to_i
      cells = state[:stones].each_with_index.map do |stone, point|
        text = stone.nil? ? _('Empty') : (stone == 0 ? _('Black stone') : _('White stone'))
        text += ', ' + _('marked dead') if state[:dead].include?(point)
        text += ', ' + _('neutral territory (seki)') if state[:neutral].include?(point)
        GameRoomContent.utf8(text)
      end
      header = state[:phase] == :scoring ? _('Scoring: select groups to mark dead, or empty regions to mark neutral.') : game_field_header(replay, viewer)
      GameSurfaces::GridSpec.new(width: size, height: size, cells: cells.each_slice(size).to_a,
        header: GameRoomContent.utf8(header), row_origin: :bottom)
    end

    def custom_game_shortcuts(replay, viewer)
      scores = replay.state[:scores] || GameRoomGoPosition.score(replay.state)
      result = [announcement_shortcut(key: 's', label: _('read the current Go score'), message:
        _('Black %{black}; White %{white}, including komi.') % {black: scores[0] / 2.0, white: scores[1] / 2.0})]
      return result if replay.finished? || !same_user?(replay.current_player, viewer)
      pairs = replay.state[:phase] == :scoring ? [['a', 'accept', _('accept the proposed score')], ['r', 'resume', _('resume play')]] : [['p', 'pass', _('pass your turn')]]
      pairs << ['q', 'resign', _('resign this game')]
      result + pairs.map { |key, action, label| GameShortcut.new(key: key, label: label, kind: :action, action_kind: 'command', action_name: action, payload: {}) }
    end

    def participant_scores(replay)
      return nil unless replay.state[:scores]
      replay.players.zip(replay.state[:scores].map { |score| score / 2.0 }).to_h
    end

    def bot_action_score(replay, actor, action, context: nil)
      state = replay.state
      return action['action'] == 'accept' ? 100 : -100 if state[:phase] == :scoring
      return -100_000 if action['action'] == 'resign'
      return state[:moves] >= state[:stones].size * 2 || state[:passes] > 0 ? 100_000 : -10 if action['action'] == 'pass'
      point = action['y'] * state[:options]['size'].to_i + action['x']
      board, captured = placement(state, point)
      marker, size = state[:players].index(state[:current_player]), state[:options]['size'].to_i
      liberties = GameRoomGoPosition.group(board, point, size).last.size
      adjacent = GameRoomGoPosition.neighbors(point, size)
      eye = adjacent.all? { |n| state[:stones][n] == marker }
      captured.size * 100 + [liberties, 4].min * 2 - (liberties == 1 ? 20 : 0) - (eye ? 30 : 0)
    end

    def event_sound_cues(event:, **_arguments)
      event['action'] == 'place' ? 'play2' : nil
    end

    private

    def placement(state, point)
      GameRoomGoPosition.place(state[:stones], point, state[:players].index(state[:current_player]),
        state[:options]['size'].to_i, state[:seen])
    end

    def apply_go_event(state, action, value, actor)
      marker, size = state[:players].index(state[:current_player]), state[:options]['size'].to_i
      if action == 'place' && state[:phase] == :playing
        return false unless /\A(?:0|[1-9]\d*)\z/.match?(value)
        placed = placement(state, value.to_i)
        return false unless placed
        state[:stones], captured = placed
        state[:seen][GameRoomGoPosition.key(state[:stones])] = true
        state[:captures][marker] += captured.size
        state[:passes] = 0
        state[:moves] += 1
        finish_go(state, actor) if state[:options]['variant'] == 'atari' && !captured.empty?
      elsif action == 'pass' && value.empty? && state[:phase] == :playing
        state[:passes] += 1
        if state[:passes] == 2
          if state[:options]['variant'] == 'atari'
            finish_go(state, nil)
          else
            state[:phase] = :scoring
          end
        end
      elsif action == 'mark' && state[:phase] == :scoring && /\A(?:0|[1-9]\d*)\z/.match?(value) && value.to_i < size * size
        point = value.to_i
        if state[:stones][point].nil?
          region = GameRoomGoPosition.group(GameRoomGoPosition.scoring_board(state), point, size).first
          state[:neutral] = (state[:neutral] & region).empty? ? (state[:neutral] | region).sort : state[:neutral] - region
        else
          group = GameRoomGoPosition.group(state[:stones], point, size).first
          state[:dead] = (state[:dead] & group).empty? ? (state[:dead] | group).sort : state[:dead] - group
          state[:neutral] = []
        end
        state[:approved] = []
      elsif action == 'accept' && value.empty? && state[:phase] == :scoring
        return false if state[:approved].include?(actor)
        state[:approved] << actor
        if state[:approved].size == 2
          state[:scores] = GameRoomGoPosition.score(state)
          a, b = state[:scores]
          finish_go(state, a == b ? nil : state[:players][a > b ? 0 : 1])
        end
      elsif action == 'resume' && value.empty? && state[:phase] == :scoring
        state[:phase], state[:passes], state[:dead], state[:neutral], state[:approved] = :playing, 0, [], [], []
      elsif action == 'resign' && value.empty?
        finish_go(state, state[:players][1 - marker])
      else
        return false
      end
      state[:current_player] = state[:players][1 - marker] unless state[:phase] == :finished
      true
    end

    def finish_go(state, winner)
      state[:phase], state[:current_player], state[:winner], state[:draw] = :finished, nil, winner, winner.nil?
    end

    def go_event_text(action, value, actor, state)
      player = participant_name(actor)
      case action
      when 'place' then _('%{player} places a stone at %{field}.') % {player: player, field: field_label(value.to_i % state[:options]['size'].to_i, value.to_i / state[:options]['size'].to_i)}
      when 'mark'
        point = value.to_i
        field = field_label(point % state[:options]['size'].to_i, point / state[:options]['size'].to_i)
        text = if state[:stones][point].nil?
          state[:neutral].include?(point) ? _('%{player} marks the region at %{field} as neutral.') : _('%{player} restores territory scoring for the region at %{field}.')
        else
          state[:dead].include?(point) ? _('%{player} marks the group at %{field} as dead.') : _('%{player} marks the group at %{field} as alive.')
        end
        text % {player: player, field: field}
      when 'accept' then _('%{player} accepts the proposed score.') % {player: player}
      when 'resume' then _('%{player} resumes play.') % {player: player}
      when 'resign' then _('%{player} resigns.') % {player: player}
      else _('%{player} passes.') % {player: player}
      end
    end
  end
end

require_relative 'generated/rulebooks/go'
