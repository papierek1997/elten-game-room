require_relative 'base'
require_relative '../lib/billiards/presentation'
require_relative '../lib/billiards/strategy'
require_relative '../lib/billiards/rules'
require_relative '../lib/billiards/match_presentation'
require_relative '../lib/billiards/spatial_audio'
require_relative '../lib/game_replay_cache'

module GameRoomGames
  using GameRoomLocalization::Translations

  class Billiards < Base
    include PublicHistoryAnnouncements
    B = GameRoomBilliards
    def id; 'billiards'; end
    def name; _('Billiards'); end
    def short_description; _('Play pool, snooker, English billiards or carom with spoken aiming and simulated ball contacts.'); end
    def notification_option_keys(options)
      options['discipline'] == 'friendly' ? %w[discipline layout] : ['discipline']
    end
    def minimum_players; 1; end
    def maximum_players; 8; end
    def supports_bots?; true; end
    def player_spatial_audio?; true; end
    def bot_strategy; @bot_strategy ||= B::Strategy.new; end
    def private_table_required?(options); !B::Rules.competition?(normalize_options(options)); end
    def tournament_capabilities(options: {})
      {version: 1, player_counts: [].freeze, execution: :turn_based}.freeze
    end
    def rule_sections; generated_rule_sections; end
    def paced_event_presentation?; true; end
    def shortcut_features; [:turn, :scores]; end

    def shortcut_feature_data(feature, replay, viewer)
      return super unless feature.to_sym == :scores
      {message: replay.players.each_with_index.map do |player, i|
        if B::Rules.competition?(replay.state[:options])
          line = _('%{player}; rounds won: %{count}') % {player: participant_name(player), count: replay.state[:racks][i]}
          line += '; ' + _('Points: %{points}') % {points: replay.state[:scores][i]} if B::Rules.points_game?(replay.state)
          if replay.state[:options]['discipline'] == 'cutthroat'
            line += '; ' + _('Balls remaining: %{count}') % {count: B::Cutthroat.remaining(replay.state, i)}
          end
          GameRoomContent.utf8(line)
        else
          _('%{player}; points: %{points}') % {player: participant_name(player), points: replay.state[:scores].fetch(i)}
        end
      end.join('; ')}
    end

    def option_definitions
      [OptionDefinition.new(key: 'discipline', label: _('Billiards discipline'), kind: :choice, default: 'friendly', choices: [
        OptionChoice.new(value: 'friendly', label: _('Social billiards')),
        OptionChoice.new(value: 'eight', label: _('Pool: 8-ball')),
        OptionChoice.new(value: 'nine', label: _('Pool: 9-ball')),
        OptionChoice.new(value: 'snooker', label: _('Snooker: 15 reds')),
        OptionChoice.new(value: 'ten', label: _('Pool: 10-ball')),
        OptionChoice.new(value: 'straight', label: _('Pool: 14.1 continuous')),
        OptionChoice.new(value: 'one_pocket', label: _('Pool: One Pocket')),
        OptionChoice.new(value: 'bank_short', label: _('Bank Pool: 9 balls')),
        OptionChoice.new(value: 'bank_full', label: _('Bank Pool: 15 balls')),
        OptionChoice.new(value: 'cutthroat', label: _('Cutthroat: three players')),
        OptionChoice.new(value: 'blackball', label: _('Blackball')),
        OptionChoice.new(value: 'english', label: _('English Billiards')),
        OptionChoice.new(value: 'carom', label: _('Carom: straight rail')),
        OptionChoice.new(value: 'one_cushion', label: _('Carom: one cushion')),
        OptionChoice.new(value: 'three_cushion', label: _('Carom: three cushions')),
        OptionChoice.new(value: 'pyramid', label: _('Free Pyramid'))]),
       OptionDefinition.new(key: 'race_to', label: _('Racks or frames needed to win (1 to 25)'), kind: :integer, default: 1,
         visible_if: {'discipline'=>%w[eight nine snooker ten straight one_pocket bank_short bank_full cutthroat blackball english carom one_cushion three_cushion pyramid]}),
       OptionDefinition.new(key: 'point_target', label: _('Points needed to win (1 to 1000)'), kind: :integer, default: 100,
         visible_if: {'discipline'=>%w[straight english carom one_cushion three_cushion]}),
       OptionDefinition.new(key: 'english_limit', label: _('English Billiards match limit'), kind: :choice, default: 'points', visible_if: {'discipline'=>'english'}, choices: [
         OptionChoice.new(value: 'points', label: _('Points')), OptionChoice.new(value: 'time', label: _('Time'))]),
       OptionDefinition.new(key: 'time_limit_minutes', label: _('Time limit in minutes (1 to 180)'), kind: :integer, default: 30,
         visible_if: {'discipline'=>'english', 'english_limit'=>'time'}),
       OptionDefinition.new(key: 'baulk_crossing', label: _('Require baulk crossing during long English billiards breaks'), kind: :boolean, default: false, visible_if: {'discipline'=>'english'}),
       OptionDefinition.new(key: 'equalizing', label: _('Allow an equalizing inning'), kind: :boolean, default: true,
         visible_if: {'discipline'=>%w[carom one_cushion three_cushion]}),
       OptionDefinition.new(key: 'rounds', label: _('Number of social rounds (1 to 30)'), kind: :integer, default: 1, visible_if: {'discipline'=>'friendly'}),
       OptionDefinition.new(key: 'layout', label: _('Ball layout'), kind: :choice, default: 'single', visible_if: {'discipline'=>%w[practice friendly]}, choices: [
        OptionChoice.new(value: 'single', label: _('One object ball')),
        OptionChoice.new(value: 'diamond', label: _('Nine-ball diamond, without competition rules')),
        OptionChoice.new(value: 'triangle', label: _('Fifteen-ball triangle, without competition rules'))]),
       OptionDefinition.new(key: 'shots', label: _('Practice shot limit (1 to 500)'), kind: :integer, default: 30, visible_if: {'discipline'=>'practice'}),
       OptionDefinition.new(key: 'accurate', label: _('More accurate physics (480 steps per second)'), kind: :boolean, default: false),
       OptionDefinition.new(key: 'bot_skill', label: _('Computer aiming strength'), kind: :choice, default: 'medium', choices: [
         OptionChoice.new(value: 'easy', label: _('Easy')), OptionChoice.new(value: 'medium', label: _('Medium')),
         OptionChoice.new(value: 'hard', label: _('Hard'))])]
    end

    def options_error(options, player_count: nil)
      options = normalize_options(options)
      if B::Rules.competition?(options)
        if options['discipline'] == 'friendly'
          return _('Social billiards requires 2 to 8 players.') if player_count && !player_count.between?(2, 8)
          return _('The number of rounds must be from 1 to 30.') unless options['rounds'].between?(1, 30)
        elsif options['discipline'] == 'cutthroat'
          return _('Cutthroat requires exactly three players.') if player_count && player_count != 3
        else
          return _('Competitive billiards requires exactly two players.') if player_count && player_count != 2
        end
        if options['discipline'] != 'friendly'
          return _('The match target must be from 1 to 25.') unless options['race_to'].between?(1, 25)
        end
        if %w[straight english carom one_cushion three_cushion].include?(options['discipline']) &&
            !(options['discipline'] == 'english' && options['english_limit'] == 'time')
          return _('The point target must be from 1 to 1000.') unless options['point_target'].between?(1, 1000)
        end
        if options['discipline'] == 'english' && options['english_limit'] == 'time'
          return _('The time limit must be from 1 to 180 minutes.') unless options['time_limit_minutes'].between?(1, 180)
        end
      else
        return _('The practice shot limit must be from 1 to 500.') unless options['shots'].between?(1, 500)
      end
      nil
    end

    def table_creation_options(values = {})
      result = super
      result['discipline'] = 'friendly' unless values.key?('discipline') || values.key?(:discipline)
      result['discipline'] = 'friendly' if result['discipline'] == 'practice'
      result['layout'] = 'diamond' if result['discipline'] == 'friendly' && !values.key?('layout') && !values.key?(:layout)
      result
    end

    def normalize_options(values)
      result = super
      raw = values.is_a?(Hash) ? values['discipline'] || values[:discipline] : nil
      result['discipline'] = 'practice' if raw.nil? || raw == 'practice'
      seed = values['rack_seed'] || values[:rack_seed] if values.is_a?(Hash)
      result['rack_seed'] = seed if seed.is_a?(Integer) && seed.between?(0, 2**31 - 1)
      result
    end

    def new_game_options(values)
      result = normalize_options(values)
      result['discipline'] = 'friendly' if result['discipline'] == 'practice'
      result['rack_seed'] = SecureRandom.random_number(2**31) if B::Rules.competition?(result)
      result
    end

    def starting_balls(layout)
      B::Rules.practice_balls(layout)
    end

    def replay(session, events, repository)
      input = GameRoomReplayCache::Input.new(session, events, repository)
      options = options_from_json(session['options'])
      @replay_cache ||= GameRoomReplayCache.new
      state, indices, history = @replay_cache.reduce(input, context: options) do |checkpoint, prefix|
        initial = {balls: starting_balls(options['layout']), options: options,
          game_id: session['__id'] || session['id'], revision: 0, shots: 0, scores: Array.new(input.players.length, 0), turn: 0, phase: :playing, last: nil, undo: nil, seen: {}}
        if !checkpoint && B::Rules.competition?(options)
          raise ArgumentError, 'Invalid billiards player count' if options_error(options, player_count: input.players.length)
          initial.merge!(racks: Array.new(input.players.length, 0), rack_number: 0, winner: nil)
          B::Rules.setup(initial)
        end
        state, indices, history = checkpoint || [initial, [], [starting_history(input.players)]]
        input.events.drop(prefix).each_with_index do |event, offset|
          break if state[:phase] == :finished
          actor, event_id = input.actor_of(event), input.event_id(event)
          clock_action = %w[clock_start time].include?(event['action']) && timed_billiards?(state)
          expected = clock_action ? input.players.first : input.players[state[:turn]]
          next if state[:seen][event_id] || !same_user?(actor, expected)
          data = parse_value(event['action'], event['value'])
          next unless valid_action?(event['action'], data, state, input.players.length)
          time = event['created_at'] && GameRoomSessionClock.from_server(session, event['created_at'].to_i, event: event)
          next unless timed_event_allowed?(state, event['action'], time)
          if clock_action
            apply_clock_event(state, event['action'], time)
          else
            next_frame = event['action'] == 'choice' && state[:choices][data['choice']] == 'next'
            apply_event(state, event['action'], data, input.players.length)
            state[:english_started_at] = nil if next_frame && timed_billiards?(state)
          end
          state[:revision] += 1
          state[:seen][event_id] = true
          indices << prefix + offset
          history << HistoryEntry.new(key: "billiards:#{event_id}", event_id: event_id, actor: actor,
            kind: :move, text: event_text(event['action'], actor, state, data, input.players))
        end
        [state, indices, history]
      end
      Replay.new(players: input.players, current_player: state[:phase] == :finished ? nil : input.players[state[:turn]],
        winner: state[:winner] && input.players[state[:winner]], draw: state[:phase] == :finished && state[:winner].nil?, board: nil, state: state, history: history,
        accepted_events: indices.map { |i| input.events.fetch(i) })
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      return clock_action_for(selection, replay, actor, context) if %w[clock_start time].include?(selection['action'])
      return [:not_your_turn, nil] unless same_user?(actor, replay.current_player)
      return [:invalid, nil] unless selection['kind'] == 'billiards'
      if timed_billiards?(replay.state) && replay.state[:phase] == :playing
        return [:invalid, nil] unless replay.state[:english_started_at] && !billiards_time_due?(replay.state, context&.now)
      end
      action = selection['action']
      data = selection.to_h.reject { |k, _| %w[kind action source].include?(k.to_s) }
      return [:invalid, nil] unless valid_action?(action, data, replay.state, replay.players.length)
      # The human surface and bot planner precompute outside the write lock.
      # Revalidate the complete input here; a cached result grants no authority.
      B::Physics.simulate(B::Rules.table(replay.state[:options]), replay.state[:balls], data['shot'], accurate: replay.state[:options]['accurate'],
        cue_id: data.fetch('cue', B::Rules.cue_id(replay.state))) if action == 'shot'
      wire = case action
      when 'shot'
        base = [B::Rules.competition?(replay.state[:options]) ? 2 : 1, data['revision'], *data['shot'].values_at('angle', 'power', 'top', 'side')]
        if B::Rules.advanced?(replay.state[:options])
          rails = data['rails'].reduce(1) { |bits, side| (bits << 2) | side }
          [3, *base.drop(1), *data.values_at('call', 'pocket', 'mode', 'cue'), rails]
        else
          B::Rules.competition?(replay.state[:options]) ? base + data.values_at('call', 'pocket', 'mode') : base
        end
      when 'place' then [1, *data.values_at('revision', 'ball', 'x', 'y')]
      when 'choice' then [2, data['revision'], data['choice']]
      else [1, data['revision']]
      end
      value = JSON.generate(wire)
      return [:invalid, nil] if value.bytesize > 64
      [:ok, event_plan(action, value)]
    rescue B::Physics::LimitExceeded
      [:simulation_failed, nil]
    end

    def legal_actions(replay, actor, context: nil)
      return [] if replay.finished? || !same_user?(actor, replay.current_player)
      if B::Rules.competition?(replay.state[:options])
        state = replay.state
        return [] if timed_billiards?(state) && !state[:english_started_at]
        return state[:choices].each_index.map { |i| {'kind'=>'billiards', 'action'=>'choice', 'revision'=>state[:revision], 'choice'=>i} } unless state[:choices].empty?
        actions = [{'kind'=>'billiards', 'action'=>'concede', 'revision'=>state[:revision]}]
        actions << {'kind'=>'billiards', 'action'=>'stalemate', 'revision'=>state[:revision]}
        actions << {'kind'=>'billiards', 'action'=>'head_spot', 'revision'=>state[:revision]} if B::Rules.head_spot(state)
        cue = state[:balls].find { |b| b.id == B::Rules.cue_id(state) }
        if cue&.on_table?
          call = if B::Rules.snooker?(state) then B::Rules.snooker_targets(state).first
          elsif %w[nine friendly].include?(state[:options]['discipline']) || state[:breaking] && !B::Rules.calls_break?(state[:options]) then 0
          else B::Rules.pool_targets(state).first
          end
          selection = {'kind'=>'billiards', 'action'=>'shot', 'revision'=>state[:revision], 'call'=>call, 'pocket'=>0, 'mode'=>0,
            'shot'=>{'angle'=>0, 'power'=>350, 'top'=>0, 'side'=>0}}
          implementation = B::Rules.engine(state[:options])
          selection['call'] = 0 if implementation && !implementation.uses_calls?
          selection.merge!('cue'=>cue.id, 'rails'=>[]) if B::Rules.advanced?(state[:options])
          selection['rails'] = [0] if %w[bank_short bank_full].include?(state[:options]['discipline']) && !state[:breaking]
          actions.unshift(selection) if selection['call'] && B::Rules.valid_declaration?(state, selection)
        end
        return actions
      end
      # The continuous input domain is validated by action_for, not enumerated
      # into millions of angles merely to find the player whose turn it is.
      actions = [{'kind'=>'billiards', 'action'=>'finish', 'revision'=>replay.state[:revision]}]
      if replay.state[:balls].first.on_table?
        actions.unshift('kind'=>'billiards', 'action'=>'shot', 'revision'=>replay.state[:revision],
          'shot'=>{'angle'=>0, 'power'=>350, 'top'=>0, 'side'=>0})
      end
      actions
    end

    def result_text(replay)
      return nil unless replay.finished?
      return _('Practice finished.') unless B::Rules.competition?(replay.state[:options])
      return _('The match is tied, %{score}.') % {score: replay.state[:racks].join(':')} if replay.draw
      _('%{player} wins the match, %{score}.') % {player: participant_name(replay.winner), score: replay.state[:racks].join(':')}
    end

    def surface_spec(replay, viewer)
      GameSurfaces::BilliardsSpec.new(game_id: replay.state[:game_id], epoch: replay.state[:revision], balls: replay.state[:balls].map(&:dup),
        enabled: !replay.finished? && same_user?(replay.current_player, viewer), options: replay.state[:options].dup,
        last: replay.state[:last], last_shot: replay.state[:last_shot]&.dup,
        undo: !!replay.state[:undo] && replay.players.one?, shots: replay.state[:shots],
        rules: B::Rules.competition?(replay.state[:options]) ? Marshal.load(Marshal.dump(replay.state.slice(:phase, :on, :hand, :groups, :turn, :breaking,
          :choices, :decision, :push_available, :free_ball, :ruling, :scores, :racks, :miss_chain, :break_points, :final_ball,
          :blackball_free, :point_pockets, :pyramid_cue, :pyramid_foul_break))) : nil)
    end

    def custom_game_shortcuts(replay, viewer)
      definitions = B::Controls.shortcuts(competition: B::Rules.competition?(replay.state[:options]))
      definitions.map do |key, modifiers, command, label|
        surface_shortcut(key: key, modifiers: modifiers, label: label, command: command)
      end
    end

    def move_error(status)
      return _('This shot could not be simulated. The table has not changed.') if status == :simulation_failed
      return _('The billiards position or input has changed. Check the current table and try again.') if status == :invalid
      super
    end

    def event_presentation_stages(event, repository, _before, after, _viewer)
      return nil unless event['action'] == 'shot'
      result = after.state[:last]
      contacts = result.events.select { |e| e[:kind] == :pocket || e.fetch(:speed, 0) >= 0.08 }
      # Contacts in the same short interval share one cue of each type, keeping
      # a dense break audible and bounded while preserving every contact in U.
      groups = contacts.group_by { |contact| (contact[:t] * 20).floor }.values
      stages = groups.each_with_index.map do |items, i|
        following = groups[i + 1]&.first&.fetch(:t) || [result.duration, items.first[:t] + 0.2].min
        {descriptions: [], history: items.map { |item| HistoryEntry.new(kind: :billiards_sound, value: item.dup) },
          delay: [(following - items.first[:t]), 1.5].min, defer_replay: true, wait_for_sounds: false}
      end
      stages << {descriptions: after.history.select { |h| h.event_id == repository.event_id(event) }.map(&:text), history: [], delay: 0.0}
      stages
    end

    def event_sound_cues(event:, history:, **_arguments)
      return nil unless event['action'] == 'shot'
      history.to_a.select { |entry| entry.kind == :billiards_sound }.map { |entry| B::Presentation.cue(entry.value) }
    end

    def event_sound_positions(history:, replay:)
      table = B::Rules.table(replay.state[:options])
      history.to_a.each_with_object({}) do |entry, positions|
        next unless entry.kind == :billiards_sound
        name = B::Presentation.cue(entry.value)
        positions[name] ||= B::SpatialAudio.position(table, entry.value) if name
      end
    end

    private

    def parse_value(action, value)
      return nil unless value.is_a?(String) && value.bytesize <= 64
      wire = JSON.parse(value)
      return nil unless wire.is_a?(Array) && [1, 2, 3].include?(wire.first) && wire.all? { |v| v.is_a?(Integer) }
      case action
      when 'shot'
        if wire.first == 3 && wire.length == 11
          return nil unless wire[10].between?(1, 2**25 - 1)
          rails, bits = [], wire[10]
          while bits > 1
            rails.unshift(bits & 3)
            bits >>= 2
          end
          return nil unless bits == 1 && rails.length <= 12
          {'revision'=>wire[1], 'shot'=>%w[angle power top side].zip(wire[2, 4]).to_h,
            'call'=>wire[6], 'pocket'=>wire[7], 'mode'=>wire[8], 'cue'=>wire[9], 'rails'=>rails}
        elsif wire.first == 2 && wire.length == 9
          {'revision'=>wire[1], 'shot'=>%w[angle power top side].zip(wire[2, 4]).to_h, 'call'=>wire[6], 'pocket'=>wire[7], 'mode'=>wire[8]}
        elsif wire.first == 1 && wire.length == 6
          {'revision'=>wire[1], 'shot'=>%w[angle power top side].zip(wire.drop(2)).to_h}
        end
      when 'place'
        %w[revision ball x y].zip(wire.drop(1)).to_h if wire.first == 1 && wire.length == 5
      when 'choice'
        {'revision'=>wire[1], 'choice'=>wire[2]} if wire.first == 2 && wire.length == 3
      else
        {'revision'=>wire[1]} if wire.first == 1 && wire.length == 2
      end
    rescue JSON::ParserError
      nil
    end

    def valid_action?(action, data, state, players)
      return false unless data.is_a?(Hash) && data['revision'].is_a?(Integer) && data['revision'] == state[:revision]
      if B::Rules.competition?(state[:options])
        case action
        when 'clock_start'
          return data.keys == ['revision'] && timed_billiards?(state) && state[:phase] == :playing && state[:english_started_at].nil?
        when 'time'
          return data.keys == ['revision'] && timed_billiards?(state) && state[:phase] == :playing && !state[:english_started_at].nil?
        when 'shot'
          keys = B::Rules.advanced?(state[:options]) ? %w[call cue mode pocket rails revision shot] : %w[call mode pocket revision shot]
          advanced_valid = !B::Rules.advanced?(state[:options]) || data['cue'].is_a?(Integer) && data['rails'].is_a?(Array) &&
            data['rails'].length <= 12 && data['rails'].all? { |v| v.is_a?(Integer) && v.between?(0, 3) } &&
            (%w[bank_short bank_full].include?(state[:options]['discipline']) || data['rails'].empty?)
          return data.keys.sort == keys && advanced_valid && B::Physics.valid_shot?(data['shot']) && B::Rules.valid_declaration?(state, data)
        when 'place'
          return data.keys.sort == %w[ball revision x y] && data['ball'].is_a?(Integer) && [data['x'], data['y']].all? { |v| v.is_a?(Integer) } &&
            B::Rules.placement?(state, data['ball'], data['x'] / 10_000.0, data['y'] / 10_000.0)
        when 'choice'
          return data.keys.sort == %w[choice revision] && data['choice'].is_a?(Integer) && data['choice'].between?(0, state[:choices].length - 1)
        when 'concede'
          return data.keys == ['revision'] && state[:phase] == :playing
        when 'stalemate'
          return data.keys == ['revision'] && state[:phase] == :playing && state[:choices].empty?
        when 'head_spot'
          return data.keys == ['revision'] && !B::Rules.head_spot(state).nil?
        else return false
        end
      end
      case action
      when 'shot'
        data.keys.sort == %w[revision shot] && B::Physics.valid_shot?(data['shot']) && state[:balls].first.on_table?
      when 'place'
        data.keys.sort == %w[ball revision x y] && data['ball'].is_a?(Integer) && state[:balls].any? { |b| b.id == data['ball'] } &&
          [data['x'], data['y']].all? { |v| v.is_a?(Integer) } &&
          B::Table.new.placement?(state[:balls], data['ball'], data['x'] / 10_000.0, data['y'] / 10_000.0)
      when 'undo'
        data.keys == ['revision'] && players == 1 && !state[:undo].nil?
      when 'reset', 'pass', 'finish'
        data.keys == ['revision']
      else false
      end
    end

    def apply_event(state, action, data, players)
      if B::Rules.competition?(state[:options])
        case action
        when 'shot'
          before = state.merge(balls: state[:balls].map(&:dup), scores: state[:scores].dup, fouls: state[:fouls].dup, groups: state[:groups]&.dup)
          result = B::Physics.simulate(B::Rules.table(state[:options]), state[:balls], data['shot'], accurate: state[:options]['accurate'], cue_id: data.fetch('cue', B::Rules.cue_id(state)))
          state[:last], state[:last_shot], state[:balls] = result, data['shot'].dup, result.balls.map(&:dup)
          state[:shots] += 1
          B::Rules.resolve_shot(state, before, result, data)
        when 'place'
          ball = state[:balls].find { |b| b.id == data['ball'] }
          ball.x, ball.y, ball.status = data['x'] / 10_000.0, data['y'] / 10_000.0, :table
        when 'choice' then B::Rules.choose(state, state[:choices].fetch(data['choice']))
        when 'concede' then B::Rules.concede(state)
        when 'stalemate'
          state[:offer_turn] = state[:turn]
          state[:offer_remaining] = (1...players).map { |offset| (state[:turn] + offset) % players }
            .reject { |seat| state[:cutthroat_conceded] && state[:cutthroat_conceded][seat] }
          state[:turn] = state[:offer_remaining].first
          state[:decision], state[:choices], state[:ruling] = :stalemate, %w[agree decline], {}
        when 'head_spot' then B::Rules.spot_pool(state, B::Rules.head_spot(state))
        end
        return
      end
      case action
      when 'shot'
        state[:undo] = [state[:balls].map(&:dup), state[:shots], state[:scores].dup]
        result = B::Physics.simulate(B::Table.new, state[:balls], data['shot'], accurate: state[:options]['accurate'])
        state[:last], state[:last_shot], state[:balls] = result, data['shot'].dup, result.balls.map(&:dup)
        state[:shots] += 1
        state[:scores][state[:turn]] += result.events.count { |e| e[:kind] == :pocket && e[:a] != 0 }
        state[:turn] = (state[:turn] + 1) % players
        if state[:shots] >= state[:options]['shots']
          state[:phase] = :finished
        end
      when 'place'
        ball = state[:balls].find { |b| b.id == data['ball'] }
        ball.x, ball.y, ball.status = data['x'] / 10_000.0, data['y'] / 10_000.0, :table
      when 'undo'
        state[:balls], state[:shots], state[:scores] = state[:undo]
        state[:undo], state[:last] = nil, nil
      when 'reset'
        state[:balls], state[:last], state[:undo] = starting_balls(state[:options]['layout']), nil, nil
      when 'pass'
        state[:turn] = (state[:turn] + 1) % players
      when 'finish'
        state[:phase] = :finished
      end
    end

    def event_text(action, actor, state, data, players)
      player = participant_name(actor)
      discipline = state[:options].fetch('discipline', 'practice')
      if B::Rules.competition?(state[:options])
        text = case action
        when 'clock_start' then _('The timed frame has started.')
        when 'time' then _('The time limit has been reached.')
        when 'shot' then _('%{player} plays a shot. %{summary}') % {player: player, summary: B::Presentation.summary(state[:last], discipline: discipline)}
        when 'concede' then _('%{player} concedes the rack or frame.') % {player: player}
        when 'choice' then _('%{player} confirms the decision.') % {player: player}
        when 'place' then _('%{player} places the cue ball.') % {player: player}
        when 'stalemate' then _('%{player} proposes reracking without a winner.') % {player: player}
        when 'head_spot' then _('%{player} requests spotting the nearest legal object ball.') % {player: player}
        end
        parts = [text, B::MatchPresentation.ruling(state), B::MatchPresentation.next_stroke(state)]
        if state[:phase] == :rack_end
          parts << if state[:rack_winner].nil?
            _('The rack or frame is tied. Score: %{score}.') % {score: state[:racks].join(':')}
          else
            _('%{player} wins the rack or frame. Score: %{score}.') % {
              player: participant_name(players.fetch(state[:rack_winner])), score: state[:racks].join(':')}
          end
        end
        return GameRoomContent.utf8(parts.reject(&:empty?).join(' '))
      end
      case action
      when 'shot' then _('%{player} plays a shot. %{summary}') % {player: player, summary: B::Presentation.summary(state[:last])}
      when 'place' then _('%{player} places %{ball} at X %{x} cm, Y %{y} cm.') % {player: player,
        ball: B::Presentation.ball(data['ball']), x: data['x'] / 100.0, y: data['y'] / 100.0}
      when 'undo' then _('%{player} restores the position before the last shot.') % {player: player}
      when 'reset' then _('%{player} sets up the original practice layout.') % {player: player}
      when 'pass' then _('%{player} passes the cue to the next player.') % {player: player}
      when 'finish' then _('%{player} finishes practice.') % {player: player}
      end
    end
  end
end

require_relative '../lib/billiards/controls'
require_relative 'billiards_clock'
require_relative 'generated/rulebooks/billiards'
