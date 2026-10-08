# encoding: UTF-8
require_relative "base"
require_relative "../content/languages"
require_relative "../content/scrabble_words_en"
require_relative "../content/scrabble_words_pl"
require_relative "../lib/word_lexicon"
require_relative "../lib/scrabble_rules"
require_relative "../lib/game_action_payload"
require_relative "../lib/game_random"
require_relative "../lib/game_turn_clock"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Scrabble < Base
    include PublicHistoryAnnouncements
    Rules = GameRoomScrabbleRules
    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      kinds = history.map(&:kind)
      return "shuffle" if kinds.include?(:deal)
      return "play" if kinds.include?(:play)
      return "draw" if kinds.include?(:exchange)
    end

    def notification_option_keys(_options); %w[content_language_id]; end

    def id; "scrabble"; end
    def name; _("Scrabble"); end

    def short_description
      _("Build words on a shared board and make use of bonus squares.")
    end
    def personal_settings_label; _("Toggle announcements of placed and removed letters"); end
    def personal_settings_action; :toggle_scrabble_draft_speech; end
    def background_client?; true; end
    def build_client(program, transport:, **_services)
      require_relative "../lib/scrabble_preview"
      GameRoomScrabblePreview.new(program, self, transport: transport)
    end
    def maximum_players; 4; end
    def thinking_time_range; 20..600; end
    def content_pack_kind; "word_dictionary"; end
    def default_content_language_id(_set = nil); "pl-PL"; end
    def single_content_set?; true; end

    def option_definitions
      policies = [_("Correct the move; no penalty"), _("End the turn; no penalty"),
        _("Correct the move; subtract 5 points"), _("End the turn; subtract 5 points"),
        _("Correct the move; subtract 10 points"), _("End the turn; subtract 10 points")]
      [OptionDefinition.new(key: "invalid_word", label: _("Invalid word"), kind: :choice, default: "0",
        choices: policies.each_with_index.map { |label, i| OptionChoice.new(value: i.to_s, label: label) }),
        thinking_time_option]
    end

    def options_error(options, player_count: nil)
      return _("Scrabble requires two to four human players.") if player_count && !player_count.between?(2, 4)
      return thinking_time_options_error(options) if thinking_time_options_error(options)
      selected_content_pack(options).data
      nil
    rescue ArgumentError, Zlib::Error, LoadError
      _("The selected word dictionary is missing or damaged.")
    end

    def initial_state(players, options)
      { players: players.dup, options: options, phase: :awaiting_deal, board: Array.new(225),
        racks: players.to_h { |p| [p, []] }, bag: [], scores: players.to_h { |p| [p,0] },
        current_player: nil, turn: 0, revision: 0, turn_started: 0, turn_deadline: 0,
        idle_turns: 0, words: [], winner: nil, draw: false }
    end

    def replay(session, events, repository)
      state = initial_state(repository.players_for(session), options_from_json(session["options"]))
      history, accepted, seen = [starting_history(state[:players])], [], {}
      GameRoomActionPayload.each(events, id, repository, session) do |data, actor, batch|
        next if state[:phase] == :finished || batch.any? { |event| seen[repository.event_id(event)] }
        candidate, additions = copy_state(state), []
        next unless apply(candidate, data, actor, repository.event_id(batch.last), additions) == :ok
        state = candidate
        history.concat(additions)
        accepted.concat(batch)
        batch.each { |event| seen[repository.event_id(event)] = true }
      end
      GameRoomSessionClock.attach(state, session)
      Replay.new(board: state[:board], players: state[:players], current_player: state[:current_player],
        winner: state[:winner], draw: state[:draw], state: state, history: history, accepted_events: accepted)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      input = selection.to_h.transform_keys(&:to_s)
      data = input.select { |key, _| %w[action placements tiles].include?(key) }
      data.merge!("revision" => replay.state[:revision], "time" => GameRoomTurnClock.logical_now(replay.state, context))
      if %w[deal exchange].include?(data["action"])
        return [:invalid, nil] unless context&.random_source
        data["seed"] = context.random_source.roll(count: 16, sides: 256).values.map { |v| (v-1).to_s(16).rjust(2,"0") }.join
      end
      status = apply(copy_state(replay.state), data, actor, 0, [])
      return [status, nil] unless status == :ok
      [:ok, ActionPlan.new(events: GameRoomActionPayload.commands(id, data))]
    end

    def automatic_action(replay, actor, context: nil)
      return nil if replay.finished? || !same_user?(actor, replay.players.first)
      return { "action" => "deal" } if replay.state[:phase] == :awaiting_deal
      { "action" => "timeout" } if expired?(replay.state, context&.now)
    end
    def automatic_action_due?(replay, actor, context: nil); automatic_action(replay, actor, context: context) != nil; end
    def automatic_actor(replay, viewer, table_owner:); same_user?(viewer,table_owner) ? replay.players.first : viewer; end
    def participant_scores(replay); replay.state[:scores].dup; end
    def shortcut_features; super + [:scores]; end
    def shortcut_feature_data(feature, replay, viewer)
      return { "message" => scores_text(replay.state, sorted: true) } if feature == :scores
      super
    end

    def preview(state, placements)
      Rules.evaluate(state[:board], state[:racks].fetch(state[:current_player], []), tiles(state), placements, language(state).alphabet)
    end
    def language(state); content_registry.language(state[:options][GameRoomContent::LANGUAGE_OPTION_KEY]); end
    def tiles(state); @tiles ||= {}; @tiles[language(state).id] ||= GameRoomScrabbleTiles.tiles(language(state).id); end
    def dictionary(state)
      pack = selected_content_pack(state[:options])
      @lexicons ||= {}
      @lexicons[pack.checksum] ||= GameRoomWords::Lexicon.new(pack, language(state))
    end

    def move_error(status)
      {
        empty_move: _("Place at least one tile to form or extend a word."),
        invalid_placement: _("Choose available tiles and valid board fields."),
        occupied_square: _("That field is already occupied."),
        one_line_required: _("Place the new tiles in one row or column."),
        gap_in_word: _("The word cannot contain an empty gap."),
        cover_center: _("The first word must cover H8."),
        disconnected_word: _("Connect the word to the existing board."),
        word_too_short: _("A word must contain at least two letters."),
        exchange_unavailable: _("You can exchange tiles only when at least eight remain in the bag.")
      }[status] || super
    end

    protected

    def copy_state(value)
      case value
      when Hash then value.to_h { |k,v| [k,copy_state(v)] }
      when Array then value.map { |v| copy_state(v) }
      else value
      end
    end
    def expired?(state, now); state[:phase] == :playing && now && state[:turn_deadline] > 0 && now.to_i >= state[:turn_deadline]; end
    def scores_text(state, sorted: false)
      players = sorted ? score_announcement_order(state[:scores].keys, state[:scores]) : state[:scores].keys
      players.map { |p| "#{participant_name(p)}, #{state[:scores][p]}" }.join("; ")
    end
    def record(history, event_id, actor, kind, text)
      history << HistoryEntry.new(key: "scrabble:#{event_id}:#{history.length}", event_id: event_id, actor: actor, kind: kind, text: text)
    end
    def start_turn(state, time)
      state[:turn] += 1
      state[:turn_started] = time
      seconds = state[:options]["thinking_time"]
      state[:turn_deadline] = seconds > 0 ? time + seconds : 0
    end
    def apply(state, data, actor, event_id, history)
      return :invalid unless data["revision"] == state[:revision] && data["time"].is_a?(Integer) && data["time"] >= state[:turn_started]
      action, time = data["action"], data["time"]
      if action == "deal"
        return :not_your_turn unless same_user?(actor, state[:players].first)
        return :invalid unless state[:phase] == :awaiting_deal && seed_valid?(data) && !validation_error(state[:options], player_count: state[:players].length)
        rng = Random.new(data["seed"].to_i(16))
        state[:bag] = GameRoomRandom.shuffle((0...tiles(state).length).to_a, random: rng)
        state[:players].each { |p| state[:racks][p] = state[:bag].shift(7) }
        state[:phase] = :playing
        state[:current_player] = state[:players][rng.rand(state[:players].length)]
        start_turn(state, time)
        record(history, event_id, actor, :deal, _("The tiles have been dealt."))
      else
        return :invalid unless state[:phase] == :playing
        expected_actor = action == "timeout" ? state[:players].first : state[:current_player]
        return :not_your_turn unless same_user?(actor, expected_actor)
        return :invalid if action == "timeout" ? !expired?(state, time) : expired?(state, time)
        player = state[:current_player]
        rack = state[:racks][player]
        case action
        when "place"
          result = preview(state, data["placements"])
          return result.error if result.error
          invalid = result.words.reject { |word| dictionary(state).include?(word[:word]) }
          unless invalid.empty?
            policy = state[:options]["invalid_word"].to_i
            penalty = [0,0,5,5,10,10][policy]
            state[:scores][player] -= penalty
            record(history, event_id, player, :invalid_word, _("%{player}: invalid words: %{words}. Penalty: %{points}.") % { player: participant_name(player), words: invalid.map { |w| w[:word] }.join(", "), points: penalty })
            next_turn(state, time, event_id, history, placed: false) if policy.odd?
            state[:revision] += 1
            return :ok
          end
          state[:board] = result.board
          state[:scores][player] += result.score
          state[:words].concat(result.words.map { |word| word.merge(player: player, turn: state[:turn]) })
          used = data["placements"].map(&:first)
          state[:racks][player] = rack.reject { |tile| used.include?(tile) } + state[:bag].shift([used.length,state[:bag].length].min)
          location = result.words.map { |w| "#{w[:word]} (#{Rules.field(w[:start])})" }.join(", ")
          record(history, event_id, player, :play, _("%{player} plays %{words}: %{points} points.") % { player: participant_name(player), words: location, points: result.score })
          if state[:bag].empty? && state[:racks][player].empty?
            finish(state, player, event_id, history)
          else
            next_turn(state, time, event_id, history, placed: true)
          end
        when "exchange"
          return :exchange_unavailable if state[:bag].length < 8
          ids = data["tiles"]
          return :invalid unless ids.is_a?(Array) && ids.length.between?(1,7) && ids.uniq == ids && (ids - rack).empty? && seed_valid?(data)
          state[:bag] = GameRoomRandom.shuffle(state[:bag] + ids, random: Random.new(data["seed"].to_i(16)))
          state[:racks][player] = rack.reject { |tile| ids.include?(tile) } + state[:bag].shift(ids.length)
          record(history, event_id, player, :exchange, _("%{player} exchanges %{count} tiles.") % { player: participant_name(player), count: ids.length })
          next_turn(state, time, event_id, history, placed: false)
        when "pass", "timeout"
          record(history, event_id, player, :pass, _("%{player} passes.") % { player: participant_name(player) })
          next_turn(state, time, event_id, history, placed: false)
        else
          return :invalid
        end
      end
      state[:revision] += 1
      :ok
    end
    def seed_valid?(data); /\A[0-9a-f]{32}\z/.match?(data["seed"].to_s); end
    def next_turn(state, time, event_id, history, placed:)
      state[:idle_turns] = placed ? 0 : state[:idle_turns] + 1
      if state[:bag].length <= 7 && state[:idle_turns] >= state[:players].length * 3
        finish(state, nil, event_id, history)
      else
        state[:current_player] = state[:players][(state[:players].index(state[:current_player]) + 1) % state[:players].length]
        start_turn(state, time)
      end
    end
    def finish(state, finisher, event_id, history)
      leftovers = state[:racks].to_h { |p,rack| [p, rack.sum { |tile| tiles(state)[tile][:points] }] }
      leftovers.each { |p,points| state[:scores][p] -= points }
      state[:scores][finisher] += leftovers.values.sum if finisher
      record(history, event_id, finisher, :score, _("Final scores after subtracting unused tiles: %{scores}.") % { scores: scores_text(state) })
      winners = state[:players].select { |p| state[:scores][p] == state[:scores].values.max }
      state[:winner], state[:draw] = winners.one? ? [winners.first,false] : [nil,true]
      state[:phase], state[:current_player], state[:turn_deadline] = :finished, nil, 0
      history << result_history(event_id: event_id, winner: state[:winner], draw: state[:draw])
    end
  end
end

require_relative "scrabble_ui"
