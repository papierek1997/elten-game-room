# encoding: UTF-8
require_relative 'base'
require_relative '../lib/axel_pong/engine'

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class AxelPong < Base
    include PublicHistoryAnnouncements

    CUSTOM_TARGET_RANGE = (2..999).freeze

    def id; 'axel_pong'; end
    def name; _('Axel Pong'); end
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
      ]
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

    def build_client(program, **_services)
      require_relative '../lib/axel_pong/client'
      GameRoomPong::Client.new(program, self)
    end

    def session_runner?; false; end
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
      return nil if replay.finished? || point == nil
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
      # Generated from docs/rulebooks/axel_pong.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:origin, GameRoomRules.translate("About this adaptation"),
          GameRoomRules.translate("Axel Pong is not an original project by papierek. The game was originally called Dragon-Pong, was later improved by Axel and balteam, and has now been ported to ELTEN with their permission.")),
        rule_section(:court, GameRoomRules.translate("Follow the ball by sound"),
          GameRoomRules.translate("Axel Pong is an audio paddle game for two players, or four players in doubles. Move your paddle along your end of the court and return the ball before it passes you. You score one point when your opponent misses. You can play with other people or add bots to the table. Headphones make it much easier to hear where the ball is."),
          GameRoomRules.translate("Each player hears the court from their own end. A ball to your left sounds on the left; a ball to your right sounds on the right. It grows louder as it approaches you. A side-wall bounce has a higher pitch near your end and a lower pitch near the opponent. Paddle steps also have a pitch cue for position. There is no need to announce every movement: use C when you want to check your paddle's position.")),
        rule_section(:rally, GameRoomRules.translate("Serving and returning"),
          GameRoomRules.translate("Keep focus on the Pong playfield. Hold Left or Right to move, and press Up or Space to serve or hit. To serve diagonally, hold a direction while serving. A return is possible only when the ball is approaching your end and your paddle is close enough to it. A centred hit goes straight; an off-centre hit sends the ball diagonally. Hits speed up the ball, while lateral motion gradually weakens and loses more speed at a wall."),
          GameRoomRules.translate("In Single, the first server is chosen at the start of a human match; against a bot, the human starts. Service changes after every two completed points. After a point there is a three-second break for the goal recording, followed by the score and a further 2.7-second serve delay. You can reposition your paddle during this pause, but serving requires a new press after it ends."),
          GameRoomRules.translate("When creating the table, choose 7, 11 or 21 points to win, or select Custom number. With Custom number selected, Tab takes you to an edit field where you can enter a whole number from 2 to 999. In both Single and Doubles, reaching the target is not enough: you also need a lead of at least two points. At 10\u201310 in an 11-point match, 11\u201310 does not end the match; 12\u201310 does. The last choice, Unlimited, keeps counting points without declaring a winner or ending the match because of the score. Play continues until the table is closed or its owner ends the match with Ctrl+Q."),
          GameRoomRules.translate("Automatic return is a personal setting, off by default. When enabled, your paddle returns a reachable ball automatically near your end. You still position the paddle and serve yourself. Open Pong settings with Ctrl+P to change it; your opponent chooses independently."),
          GameRoomRules.translate("The first serve becomes available once the players are connected and ready, without an extra countdown. In a human-only match, you hear the variant, difficulty and target, then who serves. The break after subsequent points remains as described above.")),
        rule_section(:doubles, GameRoomRules.translate("Doubles"),
          GameRoomRules.translate("Choose Single or Doubles immediately after Game mode when creating the table. Doubles requires four players. Before starting, the table master assigns two players to each team in the standard team selection window. Each player has their own paddle and can reposition at any time. Partners must return alternately: if A serves to C, the rally continues C, B, D, A, C. Only the designated player can return, including automatic returns and shield returns. Each step is positioned at the paddle of the player who moved."),
          GameRoomRules.translate("The first player in each team uses a different footstep recording, while their partner keeps the standard footsteps. For teams A and B against C and D, A and C use the new sound; B and D keep the usual sound. Footstep pitch still indicates paddle position, without an extra pitch shift for either partner. Serves and returns by A and C are pitched four semitones lower than those by B and D. Everyone hears the same distinction, including spectators after changing perspective. Simultaneous paddle sounds do not cut each other off."),
          GameRoomRules.translate("The starting team is chosen once for the match. Each service block lasts two points. For teams A and B against C and D, the first cycle is A to C, D to B, B to D, C to A. The next cycle is A to D, C to B, B to C, D to A; then these cycles repeat. If the other team starts, exchange the teams' roles. Within every rally, the order is server, receiver, server's partner, receiver's partner, repeated until the point ends. Both partners share their team's points and victory."),
          GameRoomRules.translate("At the beginning of each two-point service block, the game announces who will serve against whom. After the spoken announcement, there is the same 2.7-second serve delay as in Single. The second serve uses the normal Single delay without repeating the announcement. You can move your paddle during the break, but serving requires a fresh press when the break ends. S reads Team A and Team B, both partners' names and the scores, separated by punctuation. T reads the server, receiver and connection status; C still reads your own paddle position.")),
        rule_section(:mouse, GameRoomRules.translate("Moving with the mouse"),
          GameRoomRules.translate("On Windows, mouse control is always available in the Pong playfield; you do not need to enable it. Move the mouse mainly left or right to move your paddle in steps; a large sweep does not jump across the court. Click the left mouse button to serve or return the ball. Holding it can also return a reachable ball just before it passes your goal, but it does not automatically serve after the pause between points. Up, Space and the arrow keys still work. As in the original audio mode, a click hits before the mouse movement from the same frame is applied."),
          GameRoomRules.translate("Mouse movement works only while the Pong playfield and the ELTEN window are active. The pointer is kept near the centre of that window so the screen edge does not stop you. Chat, settings, help, another application or a lost connection suspends mouse control. Returning to play discards movement made elsewhere. This option adds no graphics and changes no Windows mouse settings. There is no mouse on/off switch.")),
        rule_section(:arcade, GameRoomRules.translate("Classic and Arcade"),
          GameRoomRules.translate("Choose Classic or Arcade in the Game mode list when creating the table. Classic is the default and follows the normal rules above. In Arcade, every paddle return has two independent chances of 7 percent: a shield for the player who returned the ball (both partners in Doubles) and an invisible ball. Both may happen on the same hit. A serve alone does not trigger these effects."),
          GameRoomRules.translate("A shield protects the whole goal for ten seconds of play. It returns a missed ball straight ahead without being used up. Winning another shield resets its time to ten seconds instead of adding to the remaining time; in Doubles, either partner resets it for both. An invisible ball is silent until a paddle returns it or a goal is scored. A shield bounce does not reveal it. Activation and shield expiry have distinct sounds; E reports the current effects. The remaining shield time is preserved between points and does not run down while waiting for a serve.")),
        rule_section(:difficulty, GameRoomRules.translate("Speed and opponents"),
          GameRoomRules.translate("Difficulty and ball speed has six levels: Easy, Normal, Hard, Insane, Impossible and Nightmare. Higher settings start with a faster ball. Against a bot, they also change reaction time, movement, aim and the chance of an error. The bot tracks the visible ball with limited precision and does not track an invisible ball. It may still return an invisible ball if its paddle happens to be in the right place.")),
        rule_section(:personal, GameRoomRules.translate("Your Pong settings"),
          GameRoomRules.translate("Ctrl+P and the Pong settings item in the table menu open the same local panel as the Axel Pong category in Game Room settings. Besides automatic return, you can adjust your paddle movement, the opponent's movement and the recorded announcer separately. Each volume ranges from 0 to 200 percent; 100 percent keeps the original balance, and 0 mutes that group. Game Room's overall volume still applies. Save keeps these values for your future matches on this computer; Cancel leaves them unchanged. They are not table rules and do not change the opponent's settings. The match continues while this panel is open, but its controls do not move your paddle.")),
        rule_section(:echo, GameRoomRules.translate("Finding the sides by sound"),
          GameRoomRules.translate("Shift+E changes side-wall cues between off, noise and tones. These are additional local sounds that help you judge your paddle's distance from the left and right edges. The nearer an edge is, the louder its cue. This setting does not move your paddle or change what your opponent hears. Game Room's sound-volume and mute controls still apply.")),
        rule_section(:hurry, GameRoomRules.translate("An opponent who does not serve"),
          GameRoomRules.translate("When playing another person, Ctrl+W warns the opponent to serve within ten seconds. It is available only after the normal break, while it is their serve and the ball has not been served yet. A valid serve cancels the warning; otherwise you receive a point. Repeated presses do not extend the deadline, and a new warning cannot be sent for fifteen seconds. Observers cannot issue warnings. A broken connection does not count as a late serve.")),
        rule_section(:connection, GameRoomRules.translate("When the connection is interrupted"),
          GameRoomRules.translate("The table and score use Game Room's normal session; movement uses Communications. During a human match, each player calculates their own flight and return locally. Lost or delayed paddle-position updates alone do not stop the ball. Serves, returns and misses travel separately in order. An actual connection failure pauses the rally; a replacement connection restarts the unfinished point with the confirmed score unchanged. Observers may listen but cannot control a paddle. Unfinished matches cannot currently be saved.")),
        rule_section(:watching, GameRoomRules.translate("Watching a match"),
          GameRoomRules.translate("C reads the name and paddle position of the player you are watching. S, T and E also work for observers: check the score, server and active effects without controlling the game. At the end of the match, you hear victory or defeat for the selected player or their team."),
          GameRoomRules.translate("As an observer, use the number keys in the Pong playfield to choose a player's perspective: 1 selects the first player, 2 the second, and in Doubles 3 the third and 4 the fourth. The numbers follow the player order in the match, not the teams. The game confirms the player's name. This changes only your listening perspective and the order of the spoken score after a point; it does not let you move any paddle. The choice stays in place between points. The keys do not select a perspective while you are typing in chat or reading history.")),
        rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
          GameRoomRules.translate("Left arrow: move the paddle left."),
          GameRoomRules.translate("Right arrow: move the paddle right."),
          GameRoomRules.translate("Up arrow: serve or return the ball."),
          GameRoomRules.translate("Space: serve or return the ball."),
          GameRoomRules.translate("Ctrl+P: open your Pong settings."),
          GameRoomRules.translate("S: read scores."),
          GameRoomRules.translate("T: read the server and connection status."),
          GameRoomRules.translate("C: read your paddle position, or the observed player's position when watching."),
          GameRoomRules.translate("E: read active shields and invisible ball."),
          GameRoomRules.translate("Shift+E: change side-wall cues."),
          GameRoomRules.translate("1: as an observer, listen from the first player's perspective."),
          GameRoomRules.translate("2: as an observer, listen from the second player's perspective."),
          GameRoomRules.translate("3: as an observer in Doubles, listen from the third player's perspective."),
          GameRoomRules.translate("4: as an observer in Doubles, listen from the fourth player's perspective."),
          GameRoomRules.translate("Ctrl+W: hurry the opponent before a serve."))
      ]
    end
  end
end
