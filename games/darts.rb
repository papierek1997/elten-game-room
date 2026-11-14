# encoding: UTF-8
require_relative 'base'
require_relative '../lib/darts/scoring'
require_relative '../lib/server_random'

GameRoomServerRandom.register('darts', ['darts_start'])

module GameRoomGames
  using GameRoomLocalization::Translations

  class Darts < Base
    include PublicHistoryAnnouncements

    THROW_PATTERN = /\A(\d{1,5}):(-?\d{1,4}):(-?\d{1,4}):(\d{1,6}):([ma])\z/
    DIFFICULTIES = %w[easy normal hard].freeze

    def id; 'darts'; end
    def name; _('Darts'); end
    def short_description; _('Guide an unstable audio cursor and throw three darts as close to the centre as possible.'); end
    def minimum_players; 1; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def background_client?; true; end
    def audio_game?; true; end
    def precise_action_clock?; true; end
    def shortcut_features; []; end
    def personal_settings_label; _('Darts settings'); end
    def personal_settings_action; :show_darts_settings; end

    def option_definitions
      [
        OptionDefinition.new(key: 'mode', label: _('Mode'), kind: :choice, default: 'game', choices: [
          OptionChoice.new(value: 'game', label: _('Game')),
          OptionChoice.new(value: 'training', label: _('Sound training'))
        ]),
        OptionDefinition.new(key: 'difficulty', label: _('Difficulty'), kind: :choice, default: 'normal', choices: [
          OptionChoice.new(value: 'easy', label: _('Easy')),
          OptionChoice.new(value: 'normal', label: _('Normal')),
          OptionChoice.new(value: 'hard', label: _('Hard'))
        ]),
        OptionDefinition.new(key: 'rounds', label: _('Number of rounds'), kind: :choice, default: 3,
          choices: [1, 3, 5, 10].map { |count| OptionChoice.new(value: count, label: count.to_s) }),
        OptionDefinition.new(key: 'progressive', label: _('Increase difficulty during the match'), kind: :boolean, default: false),
        OptionDefinition.new(key: 'time_limit', label: _('Time for one dart'), kind: :choice, default: 10, choices: [
          OptionChoice.new(value: 0, label: _('No limit')),
          *[5, 10, 15, 20].map { |seconds| OptionChoice.new(value: seconds, label: _('%{seconds} seconds') % {seconds: seconds}) }
        ]),
        OptionDefinition.new(key: 'timeout_result', label: _('When time runs out'), kind: :choice, default: 'auto', choices: [
          OptionChoice.new(value: 'auto', label: _('Throw from the current position')),
          OptionChoice.new(value: 'zero', label: _('Score zero points'))
        ], visible_if: ->(options) { options['time_limit'].to_i.positive? }),
        OptionDefinition.new(key: 'mouse_input', label: _('Use relative mouse movement and the left button'), kind: :boolean, default: false)
      ]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      if values['mode'] == 'training' && player_count && player_count != 1
        return _('Sound training is available only at a one-player table.')
      end
      nil
    end

    def notification_option_keys(_options); %w[mode difficulty rounds progressive time_limit]; end
    def notification_variant(options)
      parts = [notification_choice(options, 'mode'), notification_choice(options, 'difficulty')]
      round_count = options['rounds'].to_i
      parts << n_('%{count} round', '%{count} rounds', round_count) % {count: round_count}
      parts << _('progressive difficulty') if options['progressive']
      parts << notification_choice(options, 'time_limit')
      parts.compact.join(', ')
    end
    def options_summary(options); notification_variant(normalize_options(options)); end

    def build_client(program, **services)
      require_relative '../lib/darts/client'
      GameRoomDarts::Client.new(program, self, **services.slice(:clock, :mouse, :audio))
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session['options'])
      owner = session['__table_owner'] || session['__insertion_user'] || players.first
      roster_valid = valid_roster?(players, options)
      state = initial_state(players, options, owner)
      accepted = []
      history = [starting_history(players)]
      winner = nil

      events.each do |event|
        break if winner
        actor = repository.actor_of(event, session)
        author = event['__insertion_user'] || actor
        case event['action'].to_s
        when 'darts_start'
          next unless roster_valid && state[:phase] == :opening && same_user?(actor, players.first) && same_user?(author, owner)
          next unless seed = GameRoomServerRandom.text_seed_value(event, template: '{seed}')

          state[:seed] = seed
          state[:phase] = :playing
          state[:current_player] = players.first
          accepted << event
        when 'darts_throw'
          next unless state[:phase] == :playing || state[:phase] == :tiebreak
          next unless same_user?(actor, state[:current_player])
          throw = parse_throw(event['value'], expected_index: state[:throw_index], options: options)
          next unless throw

          throw[:player] = state[:current_player]
          throw[:round] = state[:round]
          throw[:difficulty] = active_difficulty(state)
          throw[:tiebreak] = state[:phase] == :tiebreak
          throw[:points] = GameRoomDarts::Scoring.points(throw[:x], throw[:y])
          state[:throws][state[:current_player]] << throw
          state[:scores][state[:current_player]] += throw[:points] unless throw[:tiebreak]
          accepted << event
          event_id = repository.event_id(event)
          history << throw_history(event_id, throw)
          advance_after_throw(state, players)
          if state[:phase] == :finished
            winner = state[:winner]
            history << result_history(event_id: event_id, winner: winner)
          end
        end
      end

      Replay.new(board: nil, players: players, current_player: state[:current_player], winner: winner,
        draw: false, accepted_events: accepted, history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return [:invalid, nil] unless valid_roster?(replay.players, replay.state[:options])
      if replay.state[:phase] == :opening
        return [:invalid, nil] unless selection['kind'] == 'command' && selection['action'] == 'darts_start' &&
          same_user?(actor, replay.players.first) && context&.random_source
        return [:invalid, nil] unless same_user?(context.table_owner, replay.state[:owner])
        return [:ok, server_seed_plan('darts_start')] if context.server_random

        seed = context.random_source.roll(count: 16, sides: 256).values.map { |number| (number - 1).to_s(16).rjust(2, '0') }.join
        return [:ok, event_plan('darts_start', seed)]
      end
      return [:not_your_turn, nil] unless same_user?(actor, replay.current_player)
      return [:invalid, nil] unless selection['kind'] == 'darts' && selection['action'] == 'throw'

      if GameRoomParticipants.bot?(actor)
        return [:invalid, nil] unless selection['bot'] == true && context&.random_source
        value = bot_throw_value(replay, context.random_source)
      else
        value = selection['value']
        expected = context&.local_data&.[]('darts_throw')
        return [:invalid, nil] unless value.is_a?(String) && value == expected
      end
      return [:invalid, nil] unless parse_throw(value, expected_index: replay.state[:throw_index], options: replay.state[:options])

      [:ok, event_plan('darts_throw', value)]
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || replay.state[:phase] == :opening || !same_user?(actor, replay.current_player)
      return [] unless GameRoomParticipants.bot?(actor)

      [{'kind' => 'darts', 'action' => 'throw', 'bot' => true}]
    end

    def automatic_action(replay, actor, context: nil)
      if replay.state[:phase] == :opening
        return {'kind' => 'command', 'action' => 'darts_start'} if same_user?(actor, replay.players.first)
        return nil
      end
      return nil unless same_user?(actor, replay.current_player) && !GameRoomParticipants.bot?(actor)
      value = context&.local_data&.[]('darts_throw')
      return nil unless parse_throw(value, expected_index: replay.state[:throw_index], options: replay.state[:options])

      {'kind' => 'darts', 'action' => 'throw', 'value' => value}
    end

    def automatic_action_due?(replay, actor, context: nil)
      automatic_action(replay, actor, context: context) != nil
    end

    def automatic_actor(replay, viewer, table_owner:)
      return replay.players.first if replay.state[:phase] == :opening
      viewer
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      return same_user?(table_owner, replay.state[:owner]) && same_user?(actor, replay.players.first) if replay.state[:phase] == :opening
      same_user?(actor, replay.current_player)
    end

    def participant_scores(replay); replay.state[:scores].dup; end

    def surface_spec(replay, viewer)
      return nil if replay.finished?

      active = same_user?(viewer, replay.current_player)
      header = active ? throw_prompt_text(replay) : _('Darts playfield')
      GameSurfaces::DartsSpec.new(game_id: id, header: header,
        players: replay.players.map { |player| participant_name(player) },
        viewer: player_index(replay.players, viewer), current_player: player_index(replay.players, replay.current_player),
        throw_index: replay.state[:throw_index], round: replay.state[:round], dart: replay.state[:dart],
        difficulty: active_difficulty(replay.state), scores: replay.players.map { |player| replay.state[:scores][player] },
        active: active, finished: false,
        training: replay.state[:options]['mode'] == 'training')
    end

    def throw_prompt_text(replay)
      _('Round %{round} throw %{dart}') % {round: replay.state[:round], dart: replay.state[:dart]}
    end

    def custom_game_shortcuts(replay, viewer)
      shortcuts = [surface_shortcut(key: 's', label: _('read scores'), command: 'scores')]
      if replay.state[:options]['mode'] == 'training' && same_user?(viewer, replay.current_player)
        shortcuts << surface_shortcut(key: 'c', label: _('read the training cursor sector'), command: 'position')
      end
      shortcuts
    end

    def result_text(replay)
      if replay.players.length == 1 && replay.finished?
        score = replay.state[:scores][replay.players.first]
        n_('%{player} completed the game with %{score} point.',
          '%{player} completed the game with %{score} points.', score) % {
            player: participant_name(replay.players.first), score: score
          }
      else
        super
      end
    end

    # The local client layers the physical board impact with one pitch-coded
    # quality cue. The shared presenter retains speech/history, but must not
    # play a second generic impact over that pair.
    def event_sound_cues(event:, **_arguments); nil; end

    # The local client delays impact, score and the terminal cue until after
    # the audible flight. The shared presenter must not reveal the result first.
    def result_sound_cue(**_context); nil; end

    def rule_sections
      generated_rule_sections
    end

    def training_position_text(x, y)
      sector = GameRoomDarts::Scoring.sector(x, y)
      {
        center: _('centre'), east: _('right'), north_east: _('upper right'), north: _('up'),
        north_west: _('upper left'), west: _('left'), south_west: _('lower left'),
        south: _('down'), south_east: _('lower right')
      }.fetch(sector)
    end

    private

    def valid_roster?(players, options)
      players.length.between?(minimum_players, maximum_players) &&
        GameRoomParticipants.unique(players).length == players.length &&
        options_error(options, player_count: players.length) == nil
    end

    def initial_state(players, options, owner)
      {
        options: options, owner: owner, phase: :opening, seed: nil,
        round: 1, dart: 1, throw_index: 0, current_player: nil,
        player_index: 0, scores: players.to_h { |player| [player, 0] },
        throws: players.to_h { |player| [player, []] }, tiebreakers: [],
        tiebreak_index: 0, tiebreak_scores: {}, tiebreak_cycle: 0, winner: nil
      }
    end

    def parse_throw(value, expected_index:, options:)
      match = THROW_PATTERN.match(value.to_s)
      return nil unless match && match[1].to_i == expected_index
      x, y, time_ms = match[2].to_i, match[3].to_i, match[4].to_i
      return nil unless GameRoomDarts::Scoring.bounded_coordinate?(x) && GameRoomDarts::Scoring.bounded_coordinate?(y)
      maximum = options['time_limit'].to_i.positive? ? options['time_limit'].to_i * 1_000 : 600_000
      return nil unless time_ms.between?(0, maximum)
      return nil if match[5] == 'a' && options['time_limit'].to_i.zero?

      {index: expected_index, x: x, y: y, time_ms: time_ms, automatic: match[5] == 'a'}
    end

    def bot_throw_value(replay, random_source)
      values = random_source.roll(count: 3, sides: 1_000).values
      maximum_radius = {'easy' => 620, 'normal' => 470, 'hard' => 340}.fetch(active_difficulty(replay.state))
      radius = ((values[0] - 1) / 999.0)**1.7 * maximum_radius
      angle = (values[1] - 1) / 1_000.0 * Math::PI * 2
      limit = replay.state[:options]['time_limit'].to_i
      maximum_time = (limit.positive? ? limit * 1_000 : 10_000)
      time = 500 + ((values[2] - 1) / 999.0 * [maximum_time - 500, 1].max).round
      time = [time, maximum_time].min
      encode_throw(replay.state[:throw_index], (Math.cos(angle) * radius).round,
        (Math.sin(angle) * radius).round, time, false)
    end

    def encode_throw(index, x, y, time_ms, automatic)
      [index, x, y, time_ms, automatic ? 'a' : 'm'].join(':')
    end

    def active_difficulty(state)
      return state[:options]['difficulty'] unless state[:options]['progressive']
      rounds = state[:options]['rounds'].to_i
      progress = (state[:round].to_i - 1).to_f / [rounds, 1].max
      return 'easy' if progress < 1.0 / 3
      return 'normal' if progress < 2.0 / 3
      'hard'
    end

    def advance_after_throw(state, players)
      state[:throw_index] += 1
      if state[:phase] == :tiebreak
        player = state[:current_player]
        state[:tiebreak_scores][player] = state[:throws][player].last[:points]
        state[:tiebreak_index] += 1
        if state[:tiebreak_index] < state[:tiebreakers].length
          state[:current_player] = state[:tiebreakers][state[:tiebreak_index]]
        else
          best = state[:tiebreak_scores].values.max
          leaders = state[:tiebreakers].select { |name| state[:tiebreak_scores][name] == best }
          if leaders.length == 1
            finish(state, leaders.first)
          else
            state[:tiebreakers] = leaders
            state[:tiebreak_index] = 0
            state[:tiebreak_scores] = {}
            state[:tiebreak_cycle] += 1
            state[:current_player] = leaders.first
          end
        end
        return
      end

      if state[:dart] < 3
        state[:dart] += 1
        return
      end
      state[:dart] = 1
      state[:player_index] += 1
      if state[:player_index] < players.length
        state[:current_player] = players[state[:player_index]]
        return
      end
      state[:player_index] = 0
      if state[:round] < state[:options]['rounds']
        state[:round] += 1
        state[:current_player] = players.first
        return
      end

      best = state[:scores].values.max
      leaders = players.select { |player| state[:scores][player] == best }
      if leaders.length == 1 || players.length == 1
        finish(state, leaders.first)
      else
        state[:phase] = :tiebreak
        state[:tiebreakers] = leaders
        state[:tiebreak_index] = 0
        state[:tiebreak_scores] = {}
        state[:tiebreak_cycle] = 1
        state[:current_player] = leaders.first
      end
    end

    def finish(state, winner)
      state[:phase] = :finished
      state[:winner] = winner
      state[:current_player] = nil
    end

    def throw_history(event_id, throw)
      text = if throw[:automatic]
        n_('%{player} throws automatically and scores %{points} point.',
          '%{player} throws automatically and scores %{points} points.', throw[:points]) % {
            player: participant_name(throw[:player]), points: throw[:points]
          }
      else
        n_('%{player} scores %{points} point.', '%{player} scores %{points} points.', throw[:points]) % {
          player: participant_name(throw[:player]), points: throw[:points]
        }
      end
      HistoryEntry.new(key: "darts:#{event_id}", event_id: event_id, actor: throw[:player],
        kind: :move, text: text, value: throw[:points])
    end
  end
end

require_relative 'generated/rulebooks/darts'
