# encoding: UTF-8
require_relative "base"
require_relative "../content/languages"
require_relative "../content/taboo_cards"
require_relative "../lib/game_action_payload"
require_relative "../lib/game_random"
require_relative "../lib/game_turn_clock"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Taboo < Base
    include PublicHistoryAnnouncements
    RESULTS = %w[correct skipped buzzed neutral].freeze
    MODERATOR_ACTIONS = %w[deal begin timeout approve correct_result restart_turn].freeze
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      kinds = history.map(&:kind)
      { taboo_start: "shuffle", taboo_correct: "replay", taboo_skipped: "skip",
        taboo_buzzed: "buzzer2", taboo_timeout: "ding" }.select { |kind,_| kinds.include?(kind) }.values
    end

    def id; "taboo"; end
    def notification_option_keys(_options); %w[content_language_id content_set_id]; end
    def name; _("Taboo"); end

    def short_description
      _("Help your team guess as many words as possible by describing them aloud without using the forbidden words.")
    end
    def minimum_players; 4; end
    def maximum_players; 8; end
    def content_pack_kind; "taboo_cards"; end
    def single_content_set?; true; end
    def default_content_language_id(_set = nil); "pl-PL"; end
    def team_size(_options, player_count:); [4,6,8].include?(player_count) ? player_count / 2 : 0; end
    def option_definitions
      [OptionDefinition.new(key: "turn_seconds", label: _("Time for describing in seconds"), kind: :integer, default: 60),
       OptionDefinition.new(key: "turns_each", label: _("Describing turns per person"), kind: :integer, default: 2)]
    end
    def options_error(options, player_count: nil)
      return _("Taboo requires four, six or eight human players in two equal teams.") if player_count && ![4,6,8].include?(player_count)
      return _("The turn must last from 30 to 300 seconds.") unless options["turn_seconds"].between?(30,300)
      return _("Choose from one to ten describing turns per person.") unless options["turns_each"].between?(1,10)
      return _("The selected Taboo deck is missing or damaged.") unless selected_content_pack(options)&.data&.length == 500
      nil
    rescue ArgumentError, LoadError
      _("The selected Taboo deck is missing or damaged.")
    end

    def initial_state(players, options)
      assignment = team_assignment(options, players: players)
      { players: players.dup, options: options, phase: :awaiting_deal, revision: 0,
        teams: [0,1].map { |i| assignment ? assignment.members_for(i) : [] },
        scores: [0,0], rotations: [0,0], turn: 0, completed: 0, team: nil, current_player: nil,
        deck: [], cycle: 0, serial: 0, card: nil, used: [], review: [], time: 0, deadline: 0,
        seed: nil, winner: nil, draw: false }
    end

    def replay(session, events, repository)
      state = initial_state(repository.players_for(session), options_from_json(session["options"]))
      state[:master] = session["__insertion_user"].to_s.empty? ? state[:players].first : session["__insertion_user"]
      history, accepted, seen = [starting_history(state[:players])], [], {}
      GameRoomActionPayload.each(events, id, repository, session) do |data, actor, batch|
        next if state[:phase] == :finished || batch.any? { |event| seen[repository.event_id(event)] }
        candidate, additions = clone_state(state), []
        authorized = batch.all? do |event|
          author = event["__insertion_user"] || event["actor"]
          same_user?(author, event["__authority_user"] || state[:master])
        end
        next if MODERATOR_ACTIONS.include?(data["action"]) && !authorized
        next unless apply(candidate, data, actor, repository.event_id(batch.last), additions) == :ok
        state = candidate
        history.concat(additions)
        accepted.concat(batch)
        batch.each { |event| seen[repository.event_id(event)] = true }
      end
      GameRoomSessionClock.attach(state, session)
      state[:master] = session['__table_owner'] if session['__table_owner']
      Replay.new(board: [], players: state[:players], current_player: state[:current_player],
        winner: state[:winner], draw: state[:draw], state: state, history: history, accepted_events: accepted)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      input = selection.to_h.transform_keys(&:to_s)
      data = input.select { |key, _| %w[action token index result].include?(key) }
      # A surface action retains the token of the card it actually displayed.
      data["revision"] = replay.state[:revision]
      data["time"] = GameRoomTurnClock.logical_now(replay.state, context)
      if MODERATOR_ACTIONS.include?(data["action"]) && replay.state[:master] && context&.table_owner
        return [:not_your_turn,nil] unless same_user?(context.table_owner,replay.state[:master])
      end
      if data["action"] == "deal"
        return [:invalid, nil] unless context&.random_source
        data["seed"] = context.random_source.roll(count: 16, sides: 256).values.map { |v| (v-1).to_s(16).rjust(2,"0") }.join
      end
      status = apply(clone_state(replay.state), data, actor, 0, [])
      return [status, nil] unless status == :ok
      [:ok, ActionPlan.new(events: GameRoomActionPayload.commands(id, data))]
    end
    def automatic_action(replay, actor, context: nil)
      return nil unless same_user?(actor, replay.players.first)
      state, now = replay.state, (context&.now || GameRoomSessionClock.for_state(replay.state)).to_i
      return { "action" => "deal" } if state[:phase] == :awaiting_deal
      return nil unless state[:deadline] > 0 && now >= state[:deadline]
      return { "action" => "begin", "token" => token(state) } if state[:phase] == :preparing
      return { "action" => "timeout", "token" => token(state) } if state[:phase] == :describing
      nil
    end
    def automatic_action_due?(replay, actor, context: nil); automatic_action(replay, actor, context: context) != nil; end
    def automatic_actor(replay, viewer, table_owner:); same_user?(viewer,table_owner) ? replay.players.first : viewer; end
    def actions_during_bot_turn?; true; end
    def moderator_action?(selection); MODERATOR_ACTIONS.include?(selection.to_h["action"].to_s); end
    def active_actors(replay)
      state = replay.state
      state[:phase] == :describing ? [state[:current_player]] + state[:teams][1-state[:team]] : [state[:current_player]].compact
    end
    def save_game_error(replay)
      return super if replay.finished?
      _("Save Taboo between turns, after the table master approves the review.") unless replay.state[:phase] == :ready
    end
    def participant_scores(replay)
      replay.players.to_h { |p| [p, replay.state[:scores][team_of(replay.state,p)]] }
    end
    def bot_reward(replay, actor)
      return 0 unless replay.finished?
      replay.winner == "team:#{team_of(replay.state,actor)}" ? 1 : -1
    end
    def token(state); "#{state[:turn]}:#{state[:serial]}:#{state[:phase]}"; end
    def master?(state,viewer); same_user?(viewer,state[:master] || state[:players].first); end
    def team_of(state, player); state[:teams].index { |team| team.any? { |p| same_user?(p, player) } }; end
    def card_visible?(state, viewer)
      team = team_of(state, viewer)
      state[:phase] == :describing && team != nil && (team != state[:team] || same_user?(viewer,state[:current_player]))
    end
    def cards(state); selected_content_pack(state[:options]).data; end
    def card_lines(state, viewer)
      return [] unless card_visible?(state,viewer)
      card = cards(state)[state[:card]]
      [card.fetch("word")] + card.fetch("forbidden")
    end

    protected

    def clone_state(value)
      case value
      when Hash then value.to_h { |k,v| [k,clone_state(v)] }
      when Array then value.map { |v| clone_state(v) }
      else value
      end
    end
    def record(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "taboo:#{event_id}:#{history.length}", event_id: event_id, actor: actor, kind: kind, text: text)
    end
    def ready(state)
      state[:turn] += 1
      state[:phase], state[:deadline], state[:card], state[:review] = :ready, 0, nil, []
      team = state[:teams][state[:team]]
      state[:current_player] = team[state[:rotations][state[:team]] % team.length]
    end
    def next_card(state)
      if state[:deck].empty?
        state[:cycle] += 1
        state[:deck] = GameRoomRandom.shuffle((0...cards(state).length).to_a, random: Random.new(state[:seed].to_i(16) + state[:cycle]))
        state[:deck][0], state[:deck][1] = state[:deck][1], state[:deck][0] if state[:deck][0] == state[:used].last
      end
      state[:card] = state[:deck].shift
      state[:used] << state[:card]
      state[:serial] += 1
    end
    def review_points(state)
      result = [0,0]
      state[:review].each do |entry|
        result[state[:team]] += 1 if entry[:result] == "correct"
        result[1-state[:team]] += 1 if %w[skipped buzzed].include?(entry[:result])
      end
      result
    end
    def apply(state, data, actor, event_id, history)
      return :invalid unless data["revision"] == state[:revision] && data["time"].is_a?(Integer) && data["time"] >= state[:time]
      action, now = data["action"], data["time"]
      master = same_user?(actor,state[:players].first)
      giver = same_user?(actor,state[:current_player])
      case action
      when "deal"
        return :not_your_turn unless master
        return :invalid unless state[:phase] == :awaiting_deal && data["seed"].is_a?(String) && /\A[0-9a-f]{32}\z/.match?(data["seed"])
        return :invalid if validation_error(state[:options], player_count: state[:players].length)
        state[:seed] = data["seed"]
        state[:team] = Random.new(data["seed"].to_i(16)).rand(2)
        ready(state)
        record(history,event_id,actor,:deal,_("Taboo is ready. Connect to your voice conversation and use headphones."))
      else
        return :invalid unless data["token"] == token(state)
        case action
        when "start"
          return :not_your_turn unless giver && state[:phase] == :ready
          state[:phase], state[:deadline] = :preparing, now + 3
          record(history,event_id,actor,:preparing,_("%{player} is preparing to describe.") % { player: participant_name(actor) })
        when "begin"
          return :invalid unless master && state[:phase] == :preparing && now >= state[:deadline]
          state[:phase], state[:deadline] = :describing, now + state[:options]["turn_seconds"]
          next_card(state)
          record(history,event_id,state[:current_player],:taboo_start,_("%{player} starts describing for team %{team}.") % { player: participant_name(state[:current_player]), team: state[:team]+1 })
        when "correct", "skipped", "buzzed"
          return :invalid unless state[:phase] == :describing && now < state[:deadline]
          opponent = team_of(state,actor) == 1-state[:team]
          return :not_your_turn unless action == "buzzed" ? opponent : giver
          state[:review] << { card: state[:card], result: action, actor: actor }
          # Do not reveal either the target or forbidden words to guessers.
          record(history,event_id,actor,"taboo_#{action}".to_sym, result_label(action))
          next_card(state)
        when "timeout"
          return :invalid unless master && state[:phase] == :describing && now >= state[:deadline]
          state[:review] << { card: state[:card], result: "neutral", actor: actor }
          state[:phase], state[:deadline], state[:card] = :review, 0, nil
          record(history,event_id,actor,:taboo_timeout,_("Time is up. The table master reviews this turn."))
        when "correct_result"
          return :not_your_turn unless master && state[:phase] == :review
          index, result = data["index"], data["result"]
          return :invalid unless index.is_a?(Integer) && index.between?(0,state[:review].length-1) && RESULTS.include?(result)
          entry = state[:review][index]
          return :invalid if result == entry[:result]
          moderator = state[:master] || actor
          text = _("%{player} corrects %{card}: %{before} → %{after}.") % { player: participant_name(moderator), card: cards(state)[entry[:card]]["word"], before: result_label(entry[:result]), after: result_label(result) }
          entry[:result] = result
          record(history,event_id,moderator,:review_correction,text)
        when "approve"
          return :not_your_turn unless master && state[:phase] == :review
          gained = review_points(state)
          2.times { |i| state[:scores][i] += gained[i] }
          record(history,event_id,actor,:round_result,_("Team 1 gains %{first}; team 2 gains %{second}. Total: %{score1} to %{score2}.") % { first: gained[0], second: gained[1], score1: state[:scores][0], score2: state[:scores][1] })
          state[:completed] += 1
          state[:rotations][state[:team]] += 1
          target = state[:players].length * state[:options]["turns_each"]
          if state[:completed] >= target && state[:completed].even? && state[:scores][0] != state[:scores][1]
            winner = state[:scores][0] > state[:scores][1] ? 0 : 1
            state[:phase], state[:current_player], state[:winner] = :finished, nil, "team:#{winner}"
            record(history,event_id,actor,:result,_("Team %{team} wins Taboo.") % { team: winner+1 })
          else
            state[:team] = 1-state[:team]
            ready(state)
          end
        when "restart_turn"
          return :not_your_turn unless master && [:preparing,:describing,:review].include?(state[:phase])
          ready(state)
          record(history,event_id,actor,:restart,_("The table master cancels this turn's points and repeats it with new cards because of a technical problem."))
        else
          return :invalid
        end
      end
      state[:time], state[:revision] = now, state[:revision]+1
      :ok
    end
  end
end
require_relative "taboo_ui"
