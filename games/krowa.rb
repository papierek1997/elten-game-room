# encoding: UTF-8

require_relative "base"
require_relative "../lib/hidden_submissions"
require_relative "krowa_support/word_bank"
require_relative "krowa_support/presentation"

module GameRoomGames
  # Rules and deterministic replay only. Room membership, invites, observers,
  # reconnects and the ordered event log belong to the shared Game Room stack.
  class Krowa < Base
    include KrowaPresentation

    TOWER_ATTEMPTS_PER_LETTER = 8

    def initialize(bank: KrowaWordBank.default)
      @bank = bank
    end

    def id; "krowa"; end
    def name; _("Krowa"); end
    def minimum_players; 1; end
    def maximum_players; 8; end
    def perfect_information?; false; end
    def requires_server_clock?; true; end

    def build_client(program)
      require_relative "krowa_support/client"
      KrowaClient.new(program, self)
    end

    def build_start_guard(program, user:)
      require_relative "krowa_support/daily_access"
      KrowaDailyAccess.new(program, user: user)
    end

    def build_leaderboard_client(program)
      require_relative "krowa_support/leaderboards"
      KrowaLeaderboardClient.new(program, self)
    end

    def waiting_view_spec(_viewer, history_empty_label: nil)
      GameRoomLayout::ViewSpec.new(history_empty_label: history_empty_label,
        status_commands: krowa_status_commands)
    end

    def table_join_error(options, viewer:, owner:)
      return nil if same_user?(viewer, owner)
      return _("Daily Krowa cannot be observed or played at another person's table.") if options["variant"] == "daily"

      nil
    end

    def join_as_observer?(options, viewer:, owner:)
      !same_user?(viewer, owner) && options["variant"] == "random"
    end

    def role_selection_allowed?(options)
      !%w[daily random].include?(options["variant"])
    end

    def table_invitations_allowed?(options)
      options["variant"] != "daily"
    end

    def run_room_command(program, command, viewer:)
      return false unless %w[krowa_gallery krowa_audio].include?(command.to_s)

      client = build_client(program)
      command.to_s == "krowa_gallery" ? client.open_gallery : client.open_settings
      true
    ensure
      client&.close
    end

    def leave_confirmation(replay, viewer, own_table:)
      return nil if replay == nil || replay.finished?
      return nil unless replay.state.to_h.dig(:options, "variant").to_s == "daily"
      return nil unless replay.players.any? { |player| same_user?(player, viewer) }

      warning = _("If you leave the table, today's Daily Krowa will remain unavailable even if you have not guessed the word or surrendered. Are you sure you want to leave?")
      own_table ? "#{warning} #{_("The table will be closed.")}" : warning
    end

    def option_definitions
      [
        choice("variant", _("Krowa variant"), "daily", [
          ["daily", _("Daily Krowa")], ["random", _("Random word")],
          ["race", _("Race")], ["tower", _("Word Tower")]
        ]),
        choice("length", _("Number of letters - Random word and Race"), 0,
          [[0, _("Random")]] + (3..13).map { |size| [size, size.to_s] }),
        choice("race_scoring", _("Race - scoring criterion"), "attempts", [
          ["attempts", _("Number of attempts")], ["time", _("Guessing time")]
        ])
      ]
    end

    def tower_attempt_limit(length)
      length * TOWER_ATTEMPTS_PER_LETTER
    end

    def save_game_error(replay)
      variant = replay.state.to_h.dig(:options, "variant").to_s
      return _("Saving is available only in Race and Word Tower.") if %w[daily random].include?(variant)

      super
    end

    def normalize_word(word)
      @bank.normalize(word)
    end

    def options_error(options, player_count: nil)
      return nil if player_count.nil?
      if %w[daily random].include?(options["variant"])
        return nil if player_count == 1
        return _("This variant is for exactly one player. Other people may only observe Random word.")
      end

      minimum = 2
      return nil if player_count.between?(minimum, maximum_players)
      _("This variant requires %{minimum} to %{maximum} players.") % {minimum: minimum, maximum: maximum_players}
    end

    def options_summary(options)
      label = option_definitions.first.choices.find { |item| item.value == options["variant"] }.label
      length = options["length"].to_i.zero? ? _("random length") : _("%{count} letters") % {count: options["length"]}
      score = options["race_scoring"] == "time" ? _("by time") : _("by number of attempts")
      return _("%{variant}; 3 to 9 letters") % {variant: label} if options["variant"] == "daily"
      return _("%{variant}; 3 to 8 letters; %{count} attempts per letter") % {
        variant: label, count: TOWER_ATTEMPTS_PER_LETTER
      } if options["variant"] == "tower"
      options["variant"] == "race" ? "#{label}; #{length}; #{score}" : "#{label}; #{length}"
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = {options: options, phase: :setup, round: 0, length: 0, started_ms: 0,
        players: players, pending: {}, attempts: [], results: {}, completed: [],
        used_words: [], turn: 0, commitment: nil, nonce: nil, solution: nil,
        last_solution: nil, day: nil, reason: nil, winners: [], vocabulary: [],
        surrender_words: {}}
      history = [starting_history(players)]
      accepted = []
      if options_error(options, player_count: players.length)
        state[:phase] = :invalid
      else
        events.each do |event|
          actor = repository.actor_of(event, session)
          actor = players.find { |player| same_user?(player, actor) }
          next unless actor
          event_id = repository.event_id(event).to_i
          next unless apply_event(state, event, actor, event_id, history)
          accepted << event
        end
      end
      finished = [:finished, :invalid].include?(state[:phase])
      Replay.new(board: [], players: players,
        current_player: tower?(state) && state[:phase] == :active ? players[state[:turn]] : nil,
        winner: finished ? state[:winners].first : nil,
        draw: finished && state[:winners].empty?, accepted_events: accepted,
        history: history, state: state)
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      player = replay.players.find { |name| same_user?(name, actor) }
      return [:not_player, nil] unless player
      kind, action = selection["kind"].to_s, selection["action"].to_s
      if kind == "automatic" && owner?(state, player)
        return automatic_plan(action, state, player, context)
      end
      return [:waiting, nil] unless state[:phase] == :active
      if kind == "question" && %w[submit add_word].include?(action)
        return [:stale, nil] unless selection["question_id"] == "krowa-answer-#{state[:round]}"
        return [:add_word_unavailable, nil] if action == "add_word" && !user_vocabulary_allowed?(state)
        word = @bank.normalize(selection["answer"])
        local = Array(context&.local_data&.fetch("dictionary", []))
        adding = user_vocabulary_allowed?(state) && (action == "add_word" || local.include?(word))
        return [:unknown_noun, nil] if adding && !valid_added_word?(word)
        extra = adding ? [word] : []
        status = guess_status(state, player, word, extra: extra)
        return [status, nil] unless status == :ok
        return [:clock, nil] unless context&.now
        ordinal = attempts_for(state, player).length + 1
        elapsed = [(context.now.to_f * 1000).round - state[:started_ms], 0].max
        plan = event_plan("krowa_guess", "#{state[:round]}|#{ordinal}|#{word}|#{elapsed}")
        if adding && !known_word?(state, word)
          plan.events.unshift(EventCommand.new(action: "krowa_vocab", value: word))
        end
        return [:ok, plan]
      end
      if kind == "command" && action == "surrender"
        return [:not_host, nil] if tower?(state) && !owner?(state, player)
        return [:finished, nil] if !tower?(state) && state[:results].key?(player)
        return [:pending, nil] unless state[:pending].empty? || (!tower?(state) && !state[:pending].key?(player))
        return [:ok, event_plan("krowa_surrender", state[:round].to_s)]
      end
      if kind == "command" && action == "reroll" && state[:options]["variant"] == "race"
        return [:not_host, nil] unless owner?(state, player)
        return [:pending, nil] unless state[:pending].empty?
        return [:ok, event_plan("krowa_reroll", state[:round].to_s)]
      end
      [:invalid, nil]
    end

    def automatic_action(replay, actor, context: nil)
      return nil unless owner?(replay.state, actor)
      action = case replay.state[:phase]
      when :setup then "prepare"
      when :active
        if !replay.state[:pending].empty?
          "evaluate"
        elsif replay.state[:options]["variant"] == "race" &&
            replay.state[:surrender_words].any? { |_player, word| word == nil }
          "reveal_surrender"
        end
      when :revealing then "reveal"
      end
      action && {"kind" => "automatic", "action" => action}
    end

    def active_actors(replay)
      return [] unless replay.state[:phase] == :active
      return [replay.current_player] if tower?(replay.state)
      replay.players.reject { |player| replay.state[:results].key?(player) }
    end

    def move_error(status)
      {
        wrong_length: _("Wrong number of letters."), unknown_noun: _("This noun is not in the dictionary."),
        duplicate: _("This word has already been tried."), pending: _("The attempt is waiting to be checked."),
        not_your_turn: _("Another person is playing now."), waiting: _("Wait for the round to start."),
        not_player: _("An observer does not take part in the game."), not_host: _("Only the host can do this."),
        missing_secret: _("The host's local secret is missing. Return to the computer where the game was started."),
        clock: _("Could not retrieve the server time."), stale: _("Another word has already started."),
        add_word_unavailable: _("Custom words can be added only in a single-player Daily Krowa or Random word game.")
      }.fetch(status) { super }
    end

    private

    def choice(key, label, default, values)
      OptionDefinition.new(key: key, label: label, kind: :choice, default: default,
        choices: values.map { |value, text| OptionChoice.new(value: value, label: text) })
    end

    def krowa_status_commands
      [
        GameSurfaces::Command.new(id: "krowa_gallery", label: _("Krowa gallery")),
        GameSurfaces::Command.new(id: "krowa_audio", label: _("Krowa settings (Ctrl+D)"))
      ]
    end

    def tower?(state); state[:options]["variant"] == "tower"; end
    def owner?(state, actor); same_user?(state[:players].first, actor); end
    def user_vocabulary_allowed?(state)
      state[:players].length == 1 && %w[random daily].include?(state[:options]["variant"])
    end

    def solo_variant?(state)
      %w[random daily].include?(state[:options]["variant"])
    end

    def finish_word_if_ready(state)
      if state[:results].length == state[:players].length
        state[:phase], state[:reason] = :revealing, :complete
      elsif state[:options]["variant"] == "race" && state[:pending].empty? &&
          state[:results].length == state[:players].length - 1
        last = state[:players].find { |player| !state[:results].key?(player) }
        return if attempt_race_still_open_for?(state, last)
        state[:results][last] = {solved: false, attempts: attempts_for(state, last).length, race_closed: true}
        state[:phase], state[:reason] = :revealing, :complete
      end
    end

    def attempt_race_still_open_for?(state, player)
      return false unless state[:options]["race_scoring"] == "attempts"
      solved_attempts = state[:results].values.filter_map do |result|
        result[:attempts].to_i if result[:solved]
      end
      return false if solved_attempts.empty?
      attempts_for(state, player).length < solved_attempts.min
    end

    def attempts_for(state, player)
      tower?(state) ? state[:attempts] : state[:attempts].select { |item| item[:player] == player }
    end

    def valid_added_word?(word)
      word.length.between?(3, 13) && /\A[a-ząćęłńóśźż]+\z/.match?(word)
    end

    def known_word?(state, word)
      @bank.include?(word) || state[:vocabulary].include?(word)
    end

    def guess_status(state, player, word, extra: [])
      return :finished if state[:results].key?(player)
      return :not_your_turn if tower?(state) && state[:players][state[:turn]] != player
      return :pending if state[:pending].key?(player)
      return :wrong_length if word.length != state[:length]
      return :unknown_noun unless known_word?(state, word) || extra.include?(word)
      return :duplicate if attempts_for(state, player).any? { |item| item[:word] == word }
      :ok
    end

    def envelope(state, actor, context, round = state[:round])
      return nil unless context&.hidden_submissions
      context.hidden_submissions.reveal(session_id: context.session_id,
        round_id: "krowa:#{round}", user: actor,
        commitment: round == state[:round] ? state[:commitment] : nil)
    end

    def automatic_plan(action, state, actor, context)
      return [:invalid, nil] unless context&.hidden_submissions && context.random_source
      case action
      when "prepare"
        return [:invalid, nil] unless state[:phase] == :setup
        return [:clock, nil] unless context.now && context.now.to_f.positive?
        round = state[:round] + 1
        stored = envelope(state, actor, context, round)
        if stored.nil?
          day, word = if state[:options]["variant"] == "daily"
            @bank.daily(context.now)
          else
            maximum = tower?(state) ? 8 : 13
            length = tower?(state) ? 0 : state[:options]["length"]
            [nil, @bank.choose(length: length, maximum: maximum, excluded: state[:used_words], random: context.random_source)]
          end
          stored = context.hidden_submissions.prepare(session_id: context.session_id,
            round_id: "krowa:#{round}", user: actor, payload: {"word" => word, "day" => day})
        end
        meta = [round, stored.payload["word"].length, (context.now.to_f * 1000).round, stored.payload["day"]]
        commands = [EventCommand.new(action: "krowa_round", value: JSON.generate(meta)),
          EventCommand.new(action: "krowa_commit", value: stored.commitment)]
        [:ok, ActionPlan.new(events: commands)]
      when "evaluate"
        return [:invalid, nil] unless state[:phase] == :active && !state[:pending].empty?
        stored = envelope(state, actor, context)
        return [:missing_secret, nil] unless stored && context.hidden_submissions.verify(stored)
        pending = state[:pending].values.min_by { |item| item[:id] }
        matches = @bank.matches(pending[:word], stored.payload["word"])
        elapsed = pending[:elapsed]
        [:ok, event_plan("krowa_score", [state[:round], pending[:id], matches, elapsed].join("|"))]
      when "reveal_surrender"
        return [:invalid, nil] unless state[:phase] == :active && state[:options]["variant"] == "race"
        target = state[:surrender_words].find { |_player, word| word == nil }&.first
        target_index = state[:players].index { |player| same_user?(player, target) }
        return [:invalid, nil] if target_index == nil
        stored = envelope(state, actor, context)
        return [:missing_secret, nil] unless stored && context.hidden_submissions.verify(stored)
        [:ok, event_plan("krowa_surrender_word", JSON.generate([state[:round], target_index, stored.payload["word"]]))]
      when "reveal"
        return [:invalid, nil] unless state[:phase] == :revealing
        stored = envelope(state, actor, context)
        return [:missing_secret, nil] unless stored && context.hidden_submissions.verify(stored)
        [:ok, ActionPlan.new(events: [EventCommand.new(action: "krowa_nonce", value: stored.nonce),
          EventCommand.new(action: "krowa_word", value: stored.payload["word"])])]
      else
        [:invalid, nil]
      end
    end

    def apply_event(state, event, actor, event_id, history)
      action, value = event["action"].to_s, event["value"].to_s
      return false if [:finished, :invalid].include?(state[:phase])
      case action
      when "krowa_vocab"
        return false unless user_vocabulary_allowed?(state)
        return false unless state[:phase] == :active && valid_added_word?(value) && !known_word?(state, value)
        state[:vocabulary] << value
        history << entry(event_id, _("%{player} adds a noun: %{word}.") % {player: actor, word: value}, actor, :dictionary)
      when "krowa_round"
        return false unless owner?(state, actor) && state[:phase] == :setup
        round, length, started, day = JSON.parse(value)
        return false unless round.is_a?(Integer) && round == state[:round] + 1 && length.is_a?(Integer) && (3..13).cover?(length)
        return false unless started.is_a?(Integer) && started.positive?
        return false if tower?(state) && length > 8
        return false if state[:options]["variant"] == "daily" && (length > 9 || !/\A\d{4}-\d{2}-\d{2}\z/.match?(day.to_s))
        configured = state[:options]["length"].to_i
        return false if %w[random race].include?(state[:options]["variant"]) && configured.positive? && length != configured
        state.merge!(round: round, length: length, started_ms: started, day: day, phase: :preparing,
          pending: {}, attempts: [], results: {}, commitment: nil, nonce: nil, solution: nil, reason: nil,
          turn: tower?(state) ? state[:turn] : 0, surrender_words: {})
      when "krowa_commit"
        return false unless owner?(state, actor) && state[:phase] == :preparing && /\A[0-9a-f]{64}\z/.match?(value)
        state[:commitment], state[:phase] = value, :active
        announcement = solo_variant?(state) ? _("%{length} letters.") : _("Round %{round}. %{length} letters.")
        history << entry(event_id, announcement % {round: state[:round], length: state[:length]}, actor, :round_start)
      when "krowa_guess"
        round, ordinal, word, elapsed = value.split("|", 4)
        return false unless /\A\d+\z/.match?(round.to_s) && /\A\d+\z/.match?(ordinal.to_s)
        return false unless state[:phase] == :active && round.to_i == state[:round] && guess_status(state, actor, word.to_s) == :ok
        return false unless /\A\d+\z/.match?(elapsed.to_s) && elapsed.to_i < (1 << 53)
        return false unless ordinal.to_i == attempts_for(state, actor).length + 1
        state[:pending][actor] = {id: event_id, player: actor, word: word, ordinal: ordinal.to_i, elapsed: elapsed.to_i}
      when "krowa_score"
        return false unless owner?(state, actor) && state[:phase] == :active
        parts = value.split("|")
        return false unless parts.length == 4 && parts.all? { |part| /\A\d+\z/.match?(part) }
        round, request_id, matches, elapsed = parts.map(&:to_i)
        pending = state[:pending].values.min_by { |item| item[:id] }
        return false unless pending && pending[:id] == request_id && round == state[:round] && matches.between?(0, state[:length]) && elapsed == pending[:elapsed]
        state[:pending].delete(pending[:player])
        trial = pending.merge(matches: matches, elapsed: elapsed, event_id: event_id)
        state[:attempts] << trial
        history << entry(event_id, _("%{player}: %{word}, %{matches} of %{length}.") % {
          player: pending[:player], word: pending[:word], matches: matches, length: state[:length]
        }, pending[:player], :guess)
        if matches == state[:length]
          state[:results][pending[:player]] = {attempts: attempts_for(state, pending[:player]).length, elapsed: elapsed, solved: true}
          history << entry(event_id, _("%{player} guesses the word in %{count} attempts.") % {player: pending[:player], count: state[:results][pending[:player]][:attempts]}, pending[:player], :solved)
          state[:phase], state[:reason] = :revealing, :solved if tower?(state)
        end
        if tower?(state)
          state[:turn] = (state[:turn] + 1) % state[:players].length
          if state[:phase] == :active && state[:attempts].length >= tower_attempt_limit(state[:length])
            state[:phase], state[:reason] = :revealing, :limit
          end
        else
          finish_word_if_ready(state)
        end
      when "krowa_surrender"
        return false unless state[:phase] == :active && value == state[:round].to_s
        return false if state[:pending].key?(actor) || (tower?(state) && !state[:pending].empty?)
        if tower?(state)
          return false unless owner?(state, actor)
          state[:phase], state[:reason] = :revealing, :surrender
        else
          return false if state[:results].key?(actor)
          state[:results][actor] = {solved: false, attempts: attempts_for(state, actor).length}
          state[:surrender_words][actor] = nil if state[:options]["variant"] == "race"
          finish_word_if_ready(state)
        end
        history << entry(event_id, _("%{player} surrenders.") % {player: actor}, actor, :surrender)
      when "krowa_surrender_word"
        return false unless owner?(state, actor) && state[:phase] == :active && state[:options]["variant"] == "race"
        round, target_index, word = JSON.parse(value)
        return false unless target_index.is_a?(Integer)
        target = state[:players][target_index]
        return false unless round.to_i == state[:round] && target && state[:surrender_words].key?(target)
        return false unless state[:surrender_words][target] == nil && @bank.include?(word) && word.length == state[:length]
        state[:surrender_words][target] = word
      when "krowa_reroll"
        return false unless owner?(state, actor) && state[:options]["variant"] == "race" && state[:phase] == :active && state[:pending].empty? && value == state[:round].to_s
        state[:phase], state[:reason] = :revealing, :reroll
        history << entry(event_id, _("The host changes the word. Race attempts and time start over."), actor, :reroll)
      when "krowa_nonce"
        return false unless owner?(state, actor) && state[:phase] == :revealing && /\A[0-9a-f]{64}\z/.match?(value)
        state[:nonce] = value
      when "krowa_word"
        return false unless owner?(state, actor) && state[:phase] == :revealing && @bank.include?(value) && value.length == state[:length]
        return false unless HiddenSubmissions::Commitment.valid?(payload: {"word" => value, "day" => state[:day]}, nonce: state[:nonce], commitment: state[:commitment])
        return false unless state[:attempts].all? { |trial| @bank.matches(trial[:word], value) == trial[:matches] }
        return false unless state[:surrender_words].values.compact.all? { |word| word == value }
        state[:solution] = state[:last_solution] = value
        state[:used_words] << value
        history << entry(event_id, _("Solution: %{word}.") % {word: value}, actor, :solution)
        if state[:reason] == :reroll
          state[:phase] = :setup
        elsif tower?(state) && state[:reason] == :solved
          state[:completed] << {word: value, attempts: state[:attempts].length}
          state[:phase] = :setup
        else
          state[:phase] = :finished
          state[:winners] = winners(state) unless tower?(state)
        end
      else
        return false
      end
      true
    rescue JSON::ParserError, TypeError, ArgumentError
      false
    end

    def winners(state)
      solved = state[:results].select { |_player, result| result[:solved] }
      metric = state[:options]["variant"] == "race" && state[:options]["race_scoring"] == "time" ? :elapsed : :attempts
      best = solved.values.map { |result| result[metric] }.min
      solved.select { |_player, result| result[metric] == best }.keys
    end

    def entry(event_id, text, actor, kind)
      HistoryEntry.new(key: "krowa:#{event_id}:#{kind}", event_id: event_id, text: text, actor: actor, kind: kind)
    end
  end
end
