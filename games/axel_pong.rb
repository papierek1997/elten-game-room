# encoding: UTF-8
require_relative 'base'
require_relative '../lib/axel_pong/engine'
require_relative '../lib/realtime/p2p_options'

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class AxelPong < Base
    include PublicHistoryAnnouncements
    include GameRoomRealtime::P2POptions::GameOptions

    CUSTOM_TARGET_RANGE = (2..999).freeze

    def notification_option_keys(_options); %w[team_size arcade difficulty]; end
    def audio_game?; true; end

    def id; 'axel_pong'; end
    def name; _('Axel Pong'); end

    def short_description
      _("Move your paddle, defend your goal and hit the ball where your opponent cannot stop it.")
    end
    def maximum_players; 4; end
    def supports_bots?; true; end
    def supports_bot_move_delay?; false; end
    def supports_saved_games?; false; end
    def shortcut_features; []; end

    def _(source); GameRoomContent.utf8(super(source)); end
    def participant_name(player); GameRoomContent.utf8(super(player)); end

    def option_definitions
      [
        OptionDefinition.new(key: 'arcade', label: _('Game mode'), kind: :choice, default: false,
          choices: [OptionChoice.new(value: false, label: _('Classic')), OptionChoice.new(value: true, label: _('Arcade'))]),
        OptionDefinition.new(key: 'team_size', label: _('Match type'), kind: :choice, default: 0,
          choices: [OptionChoice.new(value: 0, label: _('Single')), OptionChoice.new(value: 2, label: _('Doubles'))]),
        OptionDefinition.new(key: 'difficulty', label: _('Difficulty and ball speed'), kind: :choice, default: 2,
          choices: [_('Easy'), _('Normal'), _('Hard'), _('Insane'), _('Impossible'), _('Nightmare')].each_with_index.map { |label, i| OptionChoice.new(value: i + 1, label: label) }),
        OptionDefinition.new(key: 'target', label: _('Points to win'), kind: :choice, default: 11,
          choices: [7, 11, 21].map { |n| OptionChoice.new(value: n, label: n.to_s) } + [
            OptionChoice.new(value: 'custom', label: _('Custom number')),
            OptionChoice.new(value: 'unlimited', label: _('Unlimited'))]),
        OptionDefinition.new(key: 'custom_target', label: _('Custom number of points (2-999)'),
          summary_label: _('Custom number of points'), kind: :integer, default: 11,
          visible_if: { 'target' => 'custom' })
      ] + p2p_option_definitions
    end

    def normalize_options(values)
      normalized = super
      source = values.is_a?(Hash) ? values : {}
      if source.key?('custom_target') || source.key?(:custom_target)
        # Keep an empty/invalid edit invalid instead of silently choosing 11.
        raw = source.fetch('custom_target', source[:custom_target])
        normalized['custom_target'] = begin
          Integer(raw.to_s, 10)
        rescue ArgumentError
          0
        end
      end
      normalized
    end

    def points_to_win(options)
      values = normalize_options(options)
      return nil if values['target'] == 'unlimited'
      values['target'] == 'custom' ? values['custom_target'] : values['target']
    end

    def team_size(options, player_count:)
      normalize_options(options)['team_size']
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      if values['target'] == 'custom' && !CUSTOM_TARGET_RANGE.cover?(values['custom_target'])
        return _('Enter a whole number of points from 2 to 999.')
      end
      doubles = values['team_size'] == 2
      if player_count && player_count != (doubles ? 4 : 2)
        return doubles ? _('Doubles requires exactly four players.') : _('Single requires exactly two players.')
      end
      source = options.is_a?(Hash) ? options : {}
      has_seats = source.key?(GameRoomTeams::OPTION_KEY) || source.key?(GameRoomTeams::OPTION_KEY.to_sym)
      seats = source.fetch(GameRoomTeams::OPTION_KEY, source[GameRoomTeams::OPTION_KEY.to_sym])
      if doubles && has_seats && (!seats.is_a?(Array) || seats.length != 4 ||
          !seats.all? { |seat| seat.is_a?(Integer) } || seats.count(0) != 2 || seats.count(1) != 2)
        _('Doubles requires two teams of two players.')
      end
    end

    def valid_roster?(players, options)
      GameRoomParticipants.unique(players).length == players.length && options_error(options, player_count: players.length) == nil
    end

    def score_labels(options, players)
      assignment = team_assignment(options, players: players)
      if assignment
        assignment.team_ids.map.with_index do |team, index|
          names = assignment.members_for(team).map { |player| participant_name(player) }
          _('Team %{team}: %{players}') % { team: %w[A B][index],
            players: _('%{first} and %{second}') % { first: names[0], second: names[1] } }
        end
      else
        players.map { |player| participant_name(player) }
      end
    end

    def participant_scores(replay)
      assignment = team_assignment(replay.state[:options], players: replay.players)
      replay.players.each_with_index.to_h do |player, index|
        [player, replay.state[:scores][assignment ? assignment.team_index_for(player) : index]]
      end
    end

    def bot_reward(replay, actor)
      return 0.0 if !replay.finished? || !GameRoomParticipants.includes?(replay.players, actor)
      assignment = team_assignment(replay.state[:options], players: replay.players)
      assignment ? (replay.winner == "team:#{assignment.team_index_for(actor)}" ? 1.0 : -1.0) : super
    end

    def bot_allied?(replay, first, second)
      assignment = team_assignment(replay.state[:options], players: replay.players)
      assignment ? assignment.teammates_for(first).any? { |player| same_user?(player, second) } : super
    end

    def result_text(replay)
      assignment = team_assignment(replay.state[:options], players: replay.players)
      if assignment && replay.winner
        label = score_labels(replay.state[:options], replay.players)[assignment.team_ids.index(replay.winner)]
        _('%{player} won the game.') % { player: label }
      else
        super
      end
    end

    def build_client(program, **services)
      require_relative '../lib/axel_pong/client'
      GameRoomPong::Client.new(program, self, transport: services[:transport])
    end

    # LiveSessions persists agreed points through the ordinary managed runner.
    # Ball physics and realtime bots retain their separate Progress timer.
    def background_client?; true; end
    def controller_change_phase_error(_replay); nil; end
    def personal_settings_label; _('Pong settings'); end
    def personal_settings_action; :show_pong_settings; end

    def replay(session, events, repository)
      players = repository.players_for(session)
      owner = session['__insertion_user'].to_s
      owner = session['player_one'].to_s if owner.empty?
      owner = players.first.to_s if owner.empty?
      raw_options = begin
        JSON.parse(session['options'].to_s.empty? ? '{}' : session['options'])
      rescue JSON::ParserError
        {}
      end
      options = normalize_options(raw_options)
      target = points_to_win(options)
      valid = valid_roster?(players, raw_options)
      assignment = valid ? team_assignment(options, players: players) : nil
      labels = valid ? score_labels(options, players) : players.map { |player| participant_name(player) }
      scores = [0, 0]
      accepted = []
      history = [starting_history(players)]
      winner = nil
      events.each do |event|
        break if winner
        author = event['__insertion_user'] || repository.actor_of(event, session)
        next unless event['action'] == 'pong_point' && same_user?(author, event['__authority_user'] || owner)
        match = /\A(\d{1,8}):([01])(:timeout)?\z/.match(event['value'].to_s)
        next unless valid && match && match[1].to_i == accepted.length
        side = match[2].to_i
        scores[side] += 1
        accepted << event
        event_id = repository.event_id(event)
        if match[3]
          history << HistoryEntry.new(key: "timeout:#{event_id}", event_id: event_id, actor: assignment ? assignment.team_ids[1 - side] : players[1 - side], kind: :move,
            text: _('%{player} did not serve in time. The opponent receives a point.') % { player: labels[1 - side] })
        end
        history << HistoryEntry.new(key: "point:#{event_id}", event_id: event_id, actor: assignment ? assignment.team_ids[side] : players[side], kind: :move,
          text: _('%{player} scores. %{first}: %{one}; %{second}: %{two}.') % {
            player: labels[side], first: labels[0], one: scores[0], second: labels[1], two: scores[1] })
        if target && scores[side] >= target && (scores[0] - scores[1]).abs >= 2
          winner = assignment ? assignment.team_ids[side] : players[side]
          result = result_history(event_id: event_id, winner: winner)
          result.text = _('%{player} won the game.') % { player: labels[side] } if assignment
          history << result
        end
      end
      Replay.new(board: nil, players: players, current_player: nil, winner: winner, draw: false,
        accepted_events: accepted, history: history,
        state: { options: options, scores: scores, rally: accepted.length, owner: session['__table_owner'] || owner })
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] unless valid_roster?(replay.players, replay.state[:options])
      authority = context && same_user?(context.table_owner, replay.state[:owner]) &&
        (same_user?(actor, context.table_owner) || same_user?(actor, replay.players.first))
      return [:invalid, nil] unless authority &&
        selection['kind'] == 'command' && selection['action'] == 'pong_point'
      point = selection['point']
      expected = context&.local_data&.[]('pong_point')
      return [:invalid, nil] unless point.is_a?(String) && point == expected &&
        /\A#{replay.state[:rally]}:[01](:timeout)?\z/.match?(point)
      [:ok, event_plan('pong_point', point)]
    end

    def automatic_action(replay, _actor, context: nil)
      point = context&.local_data&.[]('pong_point')
      return nil if replay.finished? || !point.is_a?(String) ||
        !/\A#{replay.state[:rally]}:[01](:timeout)?\z/.match?(point)
      { 'kind' => 'command', 'action' => 'pong_point', 'point' => point }
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def surface_spec(replay, viewer)
      GameSurfaces::PongSpec.new(game_id: id, players: replay.players.map { |p| participant_name(p) },
        viewer: player_index(replay.players, viewer), scores: replay.state[:scores],
        score_labels: replay.state[:options]['team_size'] == 2 ? score_labels(replay.state[:options], replay.players) : nil,
        header: _('Pong playfield'), finished: replay.finished?)
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = [
        surface_shortcut(key: 's', label: _('read scores'), command: 'scores'),
        surface_shortcut(key: 't', label: _('read the server and connection status'), command: 'server'),
        surface_shortcut(key: 'c', label: player_index(replay.players, viewer) == nil ? _('read the observed player\'s paddle position') : _('read your paddle position'), command: 'position'),
        surface_shortcut(key: 'e', label: _('read active shields and invisible ball'), command: 'effects'),
        surface_shortcut(key: 'e', modifiers: [:shift], label: _('change side-wall cues'), command: 'echo')
      ]
      if !replay.finished? && player_index(replay.players, viewer) == nil
        shortcuts << surface_shortcut(key: '1', label: _('listen from the first player\'s perspective'), command: 'perspective_first')
        shortcuts << surface_shortcut(key: '2', label: _('listen from the second player\'s perspective'), command: 'perspective_second')
        if replay.players.length == 4
          shortcuts << surface_shortcut(key: '3', label: _('listen from the third player\'s perspective'), command: 'perspective_third')
          shortcuts << surface_shortcut(key: '4', label: _('listen from the fourth player\'s perspective'), command: 'perspective_fourth')
        end
      end
      if !replay.finished? && replay.players.any? { |p| same_user?(p, viewer) } &&
          replay.players.none? { |p| GameRoomParticipants.bot?(p) }
        shortcuts << surface_shortcut(key: 'w', modifiers: [:control], label: _('hurry the opponent before a serve'), command: 'hurry')
      end
      if defined?(GameRoomPong::Audio::CROWD_ASSETS) && !GameRoomPong::Audio::CROWD_ASSETS.empty?
        shortcuts << surface_shortcut(key: 'c', modifiers: [:shift], label: _('toggle the crowd'), command: 'crowd')
      end
      shortcuts
    end

    def rule_sections
      generated_rule_sections
    end
  end
end

require_relative 'generated/rulebooks/axel_pong'
