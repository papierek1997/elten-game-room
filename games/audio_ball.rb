# encoding: UTF-8
require_relative 'base'
require_relative '../lib/audio_ball/difficulty'
require_relative '../lib/audio_ball/sound_pack'
require_relative '../lib/audio_ball/rotation'
require_relative '../lib/realtime/p2p_options'
require_relative '../lib/sports_rankings/game'

require_relative "../lib/game_room_localization"

GameRoomServerRandom.register('audio_ball', ['audio_ball_start'])

module GameRoomGames
  using GameRoomLocalization::Translations
  class AudioBall < Base
    include GameRoomSportsRankings::Game
    def tournament_small_point_policy(options:)
      tournament_target_small_points(normalize_options(options).fetch('sets_to_win') * POINTS_TO_WIN)
    end

    include PublicHistoryAnnouncements
    include GameRoomRealtime::P2POptions::GameOptions

    POINTS_TO_WIN = 7
    SET_BREAK = 5

    def notification_option_keys(_options); %w[team_size difficulty sets_to_win]; end
    def notification_variant(options)
      count = options['sets_to_win']
      sets = n_('first to %{count} set', 'first to %{count} sets', count) % {count: count} if count.is_a?(Integer) && count.between?(1, 3)
      [options['team_size']==2 ? _('Doubles') : nil, notification_choice(options, 'difficulty'), sets].compact.join(', ')
    end

    def id; 'audio_ball'; end
    def name; _('Audio Ball'); end

    def short_description
      _("Listen to the incoming ball, choose the right defence and return it with a shot of your own.")
    end
    def audio_game?; true; end
    def maximum_players; 4; end
    def team_size(options,player_count:); normalize_options(options)['team_size']; end
    def supports_bots?; true; end
    def supports_bot_move_delay?; false; end
    # The session runner persists agreed points, never advances ball physics.
    def background_client?; true; end
    def tournament_execution_kind; :realtime; end
    def tournament_realtime_point_action; 'audio_ball_point'; end
    def controller_change_phase_error(_replay); nil; end
    def personal_settings_label; _('Audio Ball settings'); end
    def personal_settings_action; :show_audio_ball_settings; end
    def supports_saved_games?; false; end
    def recording_audio_kind; 'audio_ball'; end
    def shortcut_features; []; end

    def _(source); GameRoomContent.utf8(super(source)); end
    def participant_name(player); GameRoomContent.utf8(super(player)); end

    def build_client(program, **services)
      require_relative '../lib/audio_ball/audio'
      require_relative '../lib/audio_ball/client'
      GameRoomAudioBall::Client.new(program, self, transport: services[:transport],
        **services.slice(:clock, :channel_factory, :audio))
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
        OptionDefinition.new(key:'team_size',label:_('Match type'),kind: :choice,default:0,
          choices:[OptionChoice.new(value:0,label:_('Single')),OptionChoice.new(value:2,label:_('Doubles'))]),
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
      assignment=team_assignment(state[:options],players:players)
      teams=assignment ? assignment.seats : [0,1]
      labels=score_labels(state[:options],players)
      units=assignment ? assignment.team_ids : players
      accepted = []
      history = [starting_history(players)]
      winner = nil
      events.each do |event|
        break if winner
        author = event['__insertion_user'] || repository.actor_of(event, session)
        next unless valid_roster?(players,state[:options]) && same_user?(author, event['__authority_user'] || owner)
        value = event['value']
        next unless value.is_a?(String) && value.length <= 64
        case event['action']
        when 'audio_ball_start'
          recipe_fields=players.length==4 ? {players:4} : {}
          next unless GameRoomServerRandom.valid_recipe_event?(event, kind: 'first_server',**recipe_fields)
          next unless state[:first_server] == nil && /\A[0-3]\z/.match?(value) && value.to_i<players.length
          state[:first_server] = value.to_i
          accepted << event
        when 'audio_ball_point'
          match = point_match(value, state[:rally])
          next unless state[:first_server] != nil && match && set_ready?(state, event_time(session, event))
          side = match[1].to_i
          state[:scores][side] += 1
          state[:rally] += 1
          state[:set_resume_at] = nil
          state[:last_point] = { winner: side, scores: state[:scores].dup,
            set_number: state[:set_number], set_finished: false, match_finished: false, timeout: match[2] != nil }
          accepted << event
          event_id = repository.event_id(event)
          if match[2]
            history << HistoryEntry.new(key: "timeout:#{event_id}", event_id: event_id, actor: units[1 - side], kind: :move,
              text: _('%{player} did not hit the ball in time. The opponent receives a point.') % { player: labels[1 - side] })
          end
          history << HistoryEntry.new(key: "point:#{event_id}", event_id: event_id, actor: units[side], kind: :move,
            text: _('%{player} scores. %{first}: %{one}; %{second}: %{two}.') % {
              player: labels[side], first: labels[0], one: state[:scores][0],
              second: labels[1], two: state[:scores][1] })
          if state[:scores][side] >= POINTS_TO_WIN && state[:scores][side] - state[:scores][1 - side] >= 2
            state[:sets][side] += 1
            state[:last_point][:set_finished] = true
            history << HistoryEntry.new(key: "set:#{event_id}", event_id: event_id, actor: units[side], kind: :set,
              text: _('%{player} wins set %{set}. Sets: %{first}: %{one}; %{second}: %{two}.') % {
                player: labels[side], set: state[:set_number], first: labels[0],
                one: state[:sets][0], second: labels[1], two: state[:sets][1] })
            if state[:sets][side] >= state[:options]['sets_to_win']
              winner = units[side]
              state[:last_point][:match_finished] = true
              result=result_history(event_id: event_id, winner: winner)
              result.text=_('%{player} won the game.')%{player:labels[side]} if assignment
              history << result
            else
              state[:set_number] += 1
              state[:scores] = [0, 0]
              state[:set_resume_at] = event_time(session, event) + SET_BREAK if event['created_at']
            end
          end
        end
      end
      state[:server] = GameRoomAudioBall::Rotation.seat(teams,state[:first_server],state[:set_number]-1+state[:scores].sum/2) unless state[:first_server] == nil
      state[:owner] = session['__table_owner'] || owner
      Replay.new(board: nil, players: players, current_player: nil, winner: winner, draw: false,
        accepted_events: accepted, history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] unless valid_roster?(replay.players,replay.state[:options]) && owner_authority?(replay, actor, context)
      return [:invalid, nil] unless selection['kind'] == 'command'
      if selection['action'] == 'audio_ball_start' && replay.state[:first_server] == nil && context.random_source
        if context.server_random
          fields=replay.players.length==4 ? {players:4} : {}
          return [:ok, ActionPlan.new(events: [GameRoomServerRandom.recipe_command(action: 'audio_ball_start', kind: 'first_server',**fields)])]
        end
        first_server = context.random_source.roll(count: 1, sides: replay.players.length).values.first - 1
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
      return nil if replay.finished? || !valid_roster?(replay.players,replay.state[:options]) || !owner_authority?(replay, actor, context)
      return { 'kind' => 'command', 'action' => 'audio_ball_start' } if replay.state[:first_server] == nil
      return nil unless set_ready?(replay.state, context.now)
      point = context.local_data&.[]('audio_ball_point')
      return { 'kind' => 'command', 'action' => 'audio_ball_point', 'point' => point } if point_match(point, replay.state[:rally])
      nil
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def options_error(options, player_count: nil)
      doubles=normalize_options(options)['team_size']==2
      if player_count && player_count!=(doubles ? 4 : 2)
        return doubles ? _('Doubles requires exactly four players.') : _('Audio Ball requires exactly two players.')
      end
      seats=options.to_h[GameRoomTeams::OPTION_KEY]
      if doubles && seats && (!seats.is_a?(Array) || seats.size!=4 || seats.count(0)!=2 || seats.count(1)!=2)
        _('Doubles requires two teams of two players.')
      end
    end

    def score_labels(options,players)
      assignment=team_assignment(options,players:players)
      assignment ? assignment.team_ids.map { |id| assignment.members_for(id).map { |p| participant_name(p) }.join(', ') } : players.map { |p| participant_name(p) }
    end

    def result_text(replay)
      assignment=team_assignment(replay.state[:options],players:replay.players)
      return super unless assignment && replay.winner
      _('%{player} won the game.')%{player:score_labels(replay.state[:options],replay.players)[assignment.team_ids.index(replay.winner)]}
    end

    def bot_reward(replay, actor)
      return 0.0 if !replay.finished? || replay.draw || !GameRoomParticipants.includes?(replay.players, actor)
      assignment = team_assignment(replay.state[:options], players: replay.players)
      assignment ? (replay.winner == assignment.team_ids[assignment.team_index_for(actor)] ? 1.0 : -1.0) : super
    end

    def participant_scores(replay)
      scores = replay.state[replay.state[:options]['sets_to_win'] > 1 ? :sets : :scores]
      assignment=team_assignment(replay.state[:options],players:replay.players)
      replay.players.each_with_index.to_h { |player, index| [player, scores[assignment ? assignment.team_index_for(player) : index]] }
    end

    # Public accepted rallies survive the per-set score reset. Export all
    # points in the match, while the game's normal display retains its sets.
    # Earlier result policies keep the original, absent small-score export.
    def tournament_export_small_scores(replay, options:)
      scores = [0, 0]
      replay.accepted_events.each do |event|
        next unless event['action'] == 'audio_ball_point'
        side = /\A\d{1,8}:([01])(:timeout)?\z/.match(event['value'].to_s)
        raise Base::Tournaments::InvalidResult, 'Invalid accepted rally' unless side
        scores[side[1].to_i] += 1
      end
      assignment=team_assignment(options,players:replay.players)
      units = assignment ? assignment.team_ids : replay.players
      {scores: units.each_with_index.to_h { |unit, side| [unit, scores.fetch(side)] }, order: 'higher'}
    end

    def tournament_selected_small_scores(replay, options:)
      tournament_export_small_scores(replay, options: options)
    end

    def surface_spec(replay, viewer)
      GameSurfaces::AudioBallSpec.new(game_id: id, header: _('Audio Ball playfield'),
        players: replay.players.map { |player| participant_name(player) }, viewer: player_index(replay.players, viewer),
        scores: replay.state[:scores], sets: replay.state[:sets], set_number: replay.state[:set_number], finished: replay.finished?,
        teams:team_assignment(replay.state[:options],players:replay.players)&.seats,
        score_labels:score_labels(replay.state[:options],replay.players))
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

    def event_time(session, event)
      return nil unless event['created_at']
      GameRoomSessionClock.from_server(session, event['created_at'].to_i, event: event)
    end

    def set_ready?(state, now)
      state[:set_resume_at] == nil || now == nil || now.to_f >= state[:set_resume_at]
    end

    def point_match(value, rally)
      /\A#{rally}:([01])(:timeout)?\z/.match(value) if value.is_a?(String) && value.length <= 64
    end

    def valid_roster?(players, options = default_options)
      GameRoomParticipants.unique(players).length==players.length && options_error(options,player_count:players.length).nil?
    end

    def owner_authority?(replay, actor, context)
      context && same_user?(context.table_owner, replay.state[:owner]) &&
        (same_user?(actor, context.table_owner) || same_user?(actor, replay.players.first))
    end
  end
end

require_relative 'generated/rulebooks/audio_ball'
