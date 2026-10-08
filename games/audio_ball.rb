# encoding: UTF-8
require_relative 'base'
require_relative '../lib/audio_ball/difficulty'
require_relative '../lib/audio_ball/sound_pack'
require_relative '../lib/realtime/p2p_options'

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class AudioBall < Base
    include PublicHistoryAnnouncements
    include GameRoomRealtime::P2POptions::GameOptions

    POINTS_TO_WIN = 7
    SET_BREAK = 5

    def notification_option_keys(_options); %w[difficulty sets_to_win]; end
    def notification_variant(options)
      count = options['sets_to_win']
      sets = n_('first to %{count} set', 'first to %{count} sets', count) % {count: count} if count.is_a?(Integer) && count.between?(1, 3)
      [notification_choice(options, 'difficulty'), sets].compact.join(', ')
    end

    def id; 'audio_ball'; end
    def name; _('Audio Ball'); end

    def short_description
      _("Listen to the incoming ball, choose the right defence and return it with a shot of your own.")
    end
    def audio_game?; true; end
    def supports_bots?; true; end
    def supports_bot_move_delay?; false; end
    # The session runner persists agreed points, never advances ball physics.
    def background_client?; true; end
    def controller_change_phase_error(_replay); nil; end
    def personal_settings_label; _('Audio Ball settings'); end
    def personal_settings_action; :show_audio_ball_settings; end
    def supports_saved_games?; false; end
    def shortcut_features; []; end

    def _(source); GameRoomContent.utf8(super(source)); end
    def participant_name(player); GameRoomContent.utf8(super(player)); end

    def build_client(program, **services)
      require_relative '../lib/audio_ball/audio'
      require_relative '../lib/audio_ball/client'
      GameRoomAudioBall::Client.new(program, self, transport: services[:transport])
    end

    def audio_tutorial_entries
      [
        ['up', _('Ball sound: Up arrow or W')],
        ['left', _('Ball sound: Left arrow or D')],
        ['down', _('Ball sound: Down arrow or S')],
        ['prepare', _('Preparing the ball: Right arrow or A')],
        ['stop', _('Ball stopped after a successful defence')]
      ].map do |role, label|
        GameRoomAudioTutorial::Entry.new(label: label, asset: GameRoomAudioBall::SoundPack::DEFAULT.fetch(role),
          asset_resolver: ->(program) { GameRoomAudioBall::SoundPack.asset(role, program) })
      end
    end

    def option_definitions
      [
        OptionDefinition.new(key: 'mode', label: _('Game mode'), kind: :choice, default: 'classic',
          choices: [OptionChoice.new(value: 'classic', label: _('Classic'))]),
        OptionDefinition.new(key: 'difficulty', label: _('Difficulty and ball speed'), kind: :choice, default: GameRoomAudioBall::Difficulty::DEFAULT,
          choices: GameRoomAudioBall::Difficulty::PROFILES.each_with_index.map do |profile, i|
            OptionChoice.new(value: i + 1, label: _(profile.fetch(:label)))
          end),
        OptionDefinition.new(key: 'sets_to_win', label: _('Sets to win'), kind: :choice, default: 1,
          choices: [1, 2, 3].map { |count| OptionChoice.new(value: count, label: count.to_s) })
      ] + p2p_option_definitions
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      owner = session['__insertion_user'].to_s
      owner = session['player_one'].to_s if owner.empty?
      owner = players.first.to_s if owner.empty?
      state = { options: options_from_json(session['options']), owner: owner,
        scores: [0, 0], sets: [0, 0], set_number: 1, rally: 0,
        first_server: nil, server: nil, last_point: nil, set_resume_at: nil }
      accepted = []
      history = [starting_history(players)]
      winner = nil
      events.each do |event|
        break if winner
        author = event['__insertion_user'] || repository.actor_of(event, session)
        next unless valid_roster?(players) && same_user?(author, event['__authority_user'] || owner)
        value = event['value']
        next unless value.is_a?(String) && value.length <= 64
        case event['action']
        when 'audio_ball_start'
          next unless state[:first_server] == nil && /\A[01]\z/.match?(value)
          state[:first_server] = value.to_i
          accepted << event
        when 'audio_ball_point'
          match = point_match(value, state[:rally])
          next unless state[:first_server] != nil && match && set_ready?(state, event['created_at'])
          side = match[1].to_i
          state[:scores][side] += 1
          state[:rally] += 1
          state[:set_resume_at] = nil
          state[:last_point] = { winner: side, scores: state[:scores].dup,
            set_number: state[:set_number], set_finished: false, match_finished: false, timeout: match[2] != nil }
          accepted << event
          event_id = repository.event_id(event)
          if match[2]
            history << HistoryEntry.new(key: "timeout:#{event_id}", event_id: event_id, actor: players[1 - side], kind: :move,
              text: _('%{player} did not hit the ball in time. The opponent receives a point.') % { player: participant_name(players[1 - side]) })
          end
          history << HistoryEntry.new(key: "point:#{event_id}", event_id: event_id, actor: players[side], kind: :move,
            text: _('%{player} scores. %{first}: %{one}; %{second}: %{two}.') % {
              player: participant_name(players[side]), first: participant_name(players[0]), one: state[:scores][0],
              second: participant_name(players[1]), two: state[:scores][1] })
          if state[:scores][side] >= POINTS_TO_WIN && state[:scores][side] - state[:scores][1 - side] >= 2
            state[:sets][side] += 1
            state[:last_point][:set_finished] = true
            history << HistoryEntry.new(key: "set:#{event_id}", event_id: event_id, actor: players[side], kind: :set,
              text: _('%{player} wins set %{set}. Sets: %{first}: %{one}; %{second}: %{two}.') % {
                player: participant_name(players[side]), set: state[:set_number], first: participant_name(players[0]),
                one: state[:sets][0], second: participant_name(players[1]), two: state[:sets][1] })
            if state[:sets][side] >= state[:options]['sets_to_win']
              winner = players[side]
              state[:last_point][:match_finished] = true
              history << result_history(event_id: event_id, winner: winner)
            else
              state[:set_number] += 1
              state[:scores] = [0, 0]
              state[:set_resume_at] = event['created_at'].to_i + SET_BREAK if event['created_at']
            end
          end
        end
      end
      state[:server] = (state[:first_server] + state[:set_number] - 1 + state[:scores].sum / 2) % 2 unless state[:first_server] == nil
      state[:owner] = session['__table_owner'] || owner
      Replay.new(board: nil, players: players, current_player: nil, winner: winner, draw: false,
        accepted_events: accepted, history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] unless valid_roster?(replay.players) && owner_authority?(replay, actor, context)
      return [:invalid, nil] unless selection['kind'] == 'command'
      if selection['action'] == 'audio_ball_start' && replay.state[:first_server] == nil && context.random_source
        first_server = context.random_source.roll(count: 1, sides: 2).values.first - 1
        return [:ok, event_plan('audio_ball_start', first_server)]
      end
      if selection['action'] == 'audio_ball_point' && replay.state[:first_server] != nil
        return [:invalid, nil] unless set_ready?(replay.state, context.now)
        point = selection['point']
        expected = context.local_data&.[]('audio_ball_point')
        return [:ok, event_plan('audio_ball_point', point)] if point == expected && point_match(point, replay.state[:rally])
      end
      [:invalid, nil]
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !valid_roster?(replay.players) || !owner_authority?(replay, actor, context)
      return { 'kind' => 'command', 'action' => 'audio_ball_start' } if replay.state[:first_server] == nil
      return nil unless set_ready?(replay.state, context.now)
      point = context.local_data&.[]('audio_ball_point')
      return { 'kind' => 'command', 'action' => 'audio_ball_point', 'point' => point } if point_match(point, replay.state[:rally])
      nil
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def options_error(_options, player_count: nil)
      _('Audio Ball requires exactly two players.') if player_count != nil && player_count != 2
    end

    def participant_scores(replay)
      scores = replay.state[replay.state[:options]['sets_to_win'] > 1 ? :sets : :scores]
      replay.players.each_with_index.to_h { |player, index| [player, scores[index]] }
    end

    def surface_spec(replay, viewer)
      GameSurfaces::AudioBallSpec.new(game_id: id, header: _('Audio Ball playfield'),
        players: replay.players.map { |player| participant_name(player) }, viewer: player_index(replay.players, viewer),
        scores: replay.state[:scores], sets: replay.state[:sets], set_number: replay.state[:set_number], finished: replay.finished?)
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = [
        surface_shortcut(key: 's', modifiers: [:shift], label: _('read points and sets'), command: 'scores'),
        surface_shortcut(key: 't', label: _('read the server and connection status'), command: 'server')
      ]
      if !replay.finished? && player_index(replay.players, viewer) != nil
        shortcuts << surface_shortcut(key: 'w', modifiers: [:control], label: _('hurry the opponent holding the ball'), command: 'hurry')
      end
      shortcuts
    end

    def rule_sections
      generated_rule_sections
    end

    private

    def set_ready?(state, now)
      state[:set_resume_at] == nil || now == nil || now.to_f >= state[:set_resume_at]
    end

    def point_match(value, rally)
      /\A#{rally}:([01])(:timeout)?\z/.match(value) if value.is_a?(String) && value.length <= 64
    end

    def valid_roster?(players)
      players.length == 2 && GameRoomParticipants.unique(players).length == 2
    end

    def owner_authority?(replay, actor, context)
      context && same_user?(context.table_owner, replay.state[:owner]) &&
        (same_user?(actor, context.table_owner) || same_user?(actor, replay.players.first))
    end
  end
end

require_relative 'generated/rulebooks/audio_ball'
