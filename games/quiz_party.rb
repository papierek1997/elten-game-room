require_relative "base"
require_relative "../content/languages"
require_relative "../content/quiz_general_en"
require_relative "../content/quiz_general_ru"
require_relative "../content/quiz_pl_wikidata"
require_relative "../content/quiz_witcher_pl"
require_relative "../lib/game_bots"
require_relative "../lib/hidden_submissions"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class QuizParty < Base
    QUESTIONS_PER_ROUND = 3
    ROUND_CATEGORY_CHOICES = 3
    OPTION_COUNT = 4
    ANSWER_TIME_CHOICES = [5, 6, 7, 8, 9, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60].freeze
    DEFAULT_ANSWER_TIME = 20
    TARGET_SCORE_CHOICES = [15, 20, 25, 30, 40, 50].freeze
    MINIMUM_TARGET_SCORE = 15
    DEADLINE_SUBMISSION_GRACE = 3
    REVEAL_TIMEOUT = 10
    NEXT_QUESTION_PAUSE = 4
    BOT_KNOWLEDGE_PERCENT = 40
    ROLL_LIMIT = 1_000

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      action = event["action"].to_s
      return "shuffle" if action == "round_draw"
      return "draw" if action == "round_category"
      return nil if action != "question_finished"

      answer = history.find do |entry|
        entry.kind == :answer_result && GameRoomParticipants.same?(entry.actor, viewer)
      end
      return nil if answer == nil

      answer.field.to_s == "right" ? "replay" : "quiz_wrong_answer"
    end

    def id
      "quiz"
    end

    def notification_option_keys(_options); %w[content_language_id content_set_id]; end

    def controller_change_phase_error(replay)
      _("The current game contains private data that cannot be transferred at this stage.") if
        %i[answering revealing].include?(replay.state[:phase])
    end

    def save_game_error(_replay)
      _("Saving is not supported for this game.")
    end

    def supports_saved_games?
      false
    end

    def name
      _("Quiz Party")
    end

    def short_description
      _("Choose the correct answers to questions on a topic of your choice.")
    end

    def minimum_players
      2
    end

    def maximum_players
      8
    end

    def supports_bots?
      true
    end

    def perfect_information?
      false
    end

    def content_pack_kind
      :quiz
    end

    def rule_sections
      generated_rule_sections
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "answer_time",
          label: _("Time for one answer in seconds"),
          kind: :choice,
          default: DEFAULT_ANSWER_TIME,
          choices: ANSWER_TIME_CHOICES.map do |seconds|
            OptionChoice.new(value: seconds, label: seconds.to_s)
          end
        ),
        OptionDefinition.new(
          key: "target_score",
          label: _("Target score"),
          kind: :choice,
          default: MINIMUM_TARGET_SCORE,
          choices: TARGET_SCORE_CHOICES.map do |points|
            OptionChoice.new(value: points, label: points.to_s)
          end
        )
      ]
    end

    def options_error(options, player_count: nil)
      if !ANSWER_TIME_CHOICES.include?(options["answer_time"].to_i)
        return _("The answer time must be between %{minimum} and %{maximum} seconds.") % {
          minimum: ANSWER_TIME_CHOICES.first,
          maximum: ANSWER_TIME_CHOICES.last
        }
      end
      if options["target_score"].to_i < MINIMUM_TARGET_SCORE
        return _("The target score must be at least %{minimum} points.") % { minimum: MINIMUM_TARGET_SCORE }
      end
      return _("The selected question set contains no questions.") if pack_questions(options).empty?

      nil
    end

    def options_summary(options)
      normalized = normalize_options(options)
      _("%{seconds} seconds per answer; target: %{target} points") % {
        seconds: normalized["answer_time"],
        target: normalized["target_score"]
      }
    end

    def content_set_choice_label(pack_set, language_id = nil)
      pack = pack_set.packs.find { |candidate| candidate.language_id == language_id.to_s }
      pack = pack_set.packs.first if pack == nil
      return pack_set.title if pack == nil

      _("%{title}, %{questions}") % {
        title: pack_set.title,
        questions: question_count_text(pack_question_count(pack))
      }
    rescue StandardError
      pack_set.title
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = initial_state(players, options)
      accepted = []
      history = [starting_history(players)]
      frame = GameRoomReduction::Frame.new(state: state, players: players, options: options, history: history, draw: false)
      events.each do |event|
        input = GameRoomReduction.decode(event, session, repository)
        next unless input
        timestamp = event_timestamp(event)
        input.timestamp = GameRoomSessionClock.from_server(session, timestamp) if timestamp != nil
        accepted << event if apply_replay_event(frame, input)
      end

      winner, draw = frame.winner, frame.draw
      state[:winner] = winner
      state[:draw] = draw
      GameRoomSessionClock.attach(state, session)
      Replay.new(
        board: [],
        players: players,
        current_player: current_actor(state),
        winner: winner,
        draw: draw,
        accepted_events: accepted,
        history: history,
        state: state
      )
    end

    def surface_spec(replay, viewer)
      state = replay.state
      case state[:phase]
      when :choosing
        choosing_surface(state, viewer)
      when :answering
        answering_surface(state, viewer)
      else
        information_surface("quiz_status", status_text(state, viewer))
      end
    end

    def game_field_header(replay, viewer)
      state = replay.state
      return name if state[:round].to_i <= 0

      _("Round %{round}; category %{category}; question %{position} of %{total}") % {
        round: state[:round],
        category: category_label(state[:category]),
        position: [state[:position].to_i, 1].max,
        total: QUESTIONS_PER_ROUND
      }
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      kind = selection["kind"].to_s
      action = selection["action"].to_s

      return submit_category(selection, state, actor) if kind == "question" && action == "submit" && choosing_selection?(selection, state)
      return submit_answer(selection, state, actor, context) if kind == "question" && action == "submit"
      return automatic_plan(action, state, actor, context) if kind == "automatic"

      [:invalid, nil]
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      if state[:phase] == :revealing
        reveal = pending_reveal(state, actor, context)
        return reveal if reveal != nil
      end

      return nil if !owner?(state[:players], actor)

      case state[:phase]
      when :drawing
        next_question_pause_over?(state, context&.now) ? surface_action("automatic", "draw_categories") : nil
      when :starting
        next_question_pause_over?(state, context&.now) ? surface_action("automatic", "start_question") : nil
      when :answering
        if commitments_complete?(state) || closing_deadline_reached?(state, context&.now)
          surface_action("automatic", "close_answers")
        end
      when :revealing
        finish_due?(state, context&.now) ? surface_action("automatic", "finish_question") : nil
      end
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      return true if same_user?(actor, table_owner)

      state = replay.state
      state[:phase] == :revealing && player_hash_key?(state[:commitments], actor) &&
        !player_hash_key?(state[:reveals], actor)
    end

    def automatic_action_due?(replay, actor, context: nil)
      state = replay.state
      return false if !owner?(state[:players], actor)
      return closing_deadline_reached?(state, context&.now) if state[:phase] == :answering
      return next_question_pause_over?(state, context&.now) if [:starting, :drawing].include?(state[:phase])

      state[:phase] == :revealing && finish_due?(state, context&.now)
    end

    def automatic_surface_action(_replay, _actor, surface: nil, context: nil)
      nil
    end

    def automatic_actor(replay, viewer, table_owner:)
      state = replay.state
      return viewer if state[:phase] == :revealing && player_hash_key?(state[:commitments], viewer) &&
        !player_hash_key?(state[:reveals], viewer)
      super
    end

    def concurrent_session_input?(before, after, selection)
      selection["kind"].to_s == "question" && selection["action"].to_s == "submit" &&
        before.state[:phase] == :answering && after.state[:phase] == :answering &&
        question_key(before.state) == question_key(after.state)
    end

    def timer_announcements(replay, viewer, now: nil)
      state = replay.state
      now ||= GameRoomSessionClock.for_state(state).to_i
      return [] if state[:phase] != :answering || state[:deadline].to_i <= 0

      remaining = state[:deadline].to_i - now.to_i
      announcements = []
      announcements << ["quiz:#{question_key(state)}:five", _("5 seconds remain."), "buzzer2"] if remaining <= 5 && remaining > 0
      announcements << ["quiz:#{question_key(state)}:expired", _("Time is up.")] if remaining <= 0
      announcements
    end

    def participant_status(replay, participant, connected: true)
      return _("disconnected") if !connected

      state = replay.state
      return _("finished") if state[:phase] == :finished
      return _("choosing a category") if state[:phase] == :choosing && same_user?(current_chooser(state), participant)

      case state[:phase]
      when :answering
        player_hash_key?(state[:commitments], participant) ? _("answered") : _("answering")
      when :revealing
        player_hash_key?(state[:reveals], participant) ? nil : _("waiting to reveal")
      else
        _("waiting for the next question")
      end
    end

    def participant_scores(replay)
      replay.state[:scores].dup
    end

    def active_actors(replay)
      state = replay.state
      case state[:phase]
      when :choosing
        current_chooser(state) == nil ? [] : [current_chooser(state)]
      when :answering
        state[:players].reject { |player| player_hash_key?(state[:commitments], player) }
      when :revealing
        state[:players].select do |player|
          player_hash_key?(state[:commitments], player) && !player_hash_key?(state[:reveals], player)
        end
      else
        []
      end
    end

    def required_decision_key(replay, viewer)
      return nil if replay == nil || replay.finished?
      state = replay.state
      if state[:phase] == :answering
        return nil unless active_actors(replay).any? { |actor| same_user?(actor, viewer) }
        return [:answering, state[:round], state[:position]]
      end
      super
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      case state[:phase]
      when :choosing
        return [] if !same_user?(current_chooser(state), actor)

        round_categories(state).map do |category|
          { "kind" => "question", "action" => "submit", "question_id" => category_surface_id(state), "answer" => category }
        end
      when :answering
        return [] if !includes_player?(state[:players], actor) || player_hash_key?(state[:commitments], actor)
        return [] if deadline_reached?(state, context&.now)

        (0...OPTION_COUNT).map do |index|
          { "kind" => "question", "action" => "submit", "question_id" => question_surface_id(state), "answer" => index.to_s }
        end
      when :revealing
        return [] if pending_reveal(state, actor, context) == nil

        [{ "kind" => "automatic", "action" => "reveal" }]
      else
        []
      end
    end

    def bot_action_score(replay, _actor, action, context: nil)
      state = replay.state
      return 0.0 if state[:phase] != :answering

      action["answer"].to_i == correct_option_index(state) ? 1.0 : 0.0
    end

    def bot_observation(replay, actor)
      state = replay.state
      {
        "phase" => state[:phase].to_s,
        "round" => state[:round].to_i,
        "position" => state[:position].to_i,
        "category" => state[:category].to_s,
        "scores" => state[:scores].dup,
        "answered" => player_hash_key?(state[:commitments], actor)
      }
    end

    def bot_strategy
      @bot_strategy ||= BotStrategy.new(knowledge_percent: BOT_KNOWLEDGE_PERCENT)
    end

    def shortcut_features
      [:turn, :remaining_time, :scores, :round_summary]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :turn
        { message: current_question_text(state) }
      when :remaining_time
        { message: remaining_time_text(state) }
      when :scores
        { message: scores_text(state, sorted: true) }
      when :round_summary
        { message: round_summary_text(state) }
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      action = event["action"].to_s
      return [] if ["answer_nonce", "answer_pick", "answers_closed", "answer_commit"].include?(action)

      event_id = repository.event_id(event)
      history_entries_for_display(replay, viewer).select { |entry| entry.event_id.to_i == event_id }.map(&:text)
    end

    def result_text(replay)
      state = replay.state
      winners = state[:winners].to_a
      return nil if winners.empty?
      if winners.length == 1
        _("%{player} won the game with %{points} points.") % {
          player: participant_name(winners.first),
          points: state[:scores].fetch(winners.first, 0)
        }
      else
        _("Shared victory: %{players}, %{points} points.") % {
          players: winners.map { |player| participant_name(player) }.join(", "),
          points: state[:scores].fetch(winners.first, 0)
        }
      end
    end

    class BotStrategy
      include GameRoomBots::ReplayOnlyStrategy

      def initialize(knowledge_percent:)
        @knowledge_percent = knowledge_percent.to_i
      end

      def choose(actions:, actor:, random_source:, game: nil, replay: nil, context: nil, **_extra)
        choices = actions.to_a
        return nil if choices.empty?
        return choices.first if choices.length == 1
        return GameRoomBots.random_choice(choices, random_source) if game == nil || replay == nil

        known = choices.select { |action| game.bot_action_score(replay, actor, action, context: context) > 0.0 }
        return GameRoomBots.random_choice(choices, random_source) if known.empty?
        return GameRoomBots.random_choice(known, random_source) if informed?(random_source)

        GameRoomBots.random_choice(choices, random_source)
      end

      private

      def informed?(random_source)
        random_source.roll(count: 1, sides: 100).values.first <= @knowledge_percent
      end
    end

    def history_entries_for_display(replay, viewer, surface_state: {})
      entries = replay.history.map do |entry|
        next entry if entry.kind != :answer_result

        displayed = entry.dup
        displayed.text = answer_result_text(replay.state, entry, viewer).to_s
        displayed
      end.reject { |entry| entry.kind == :answer_result && entry.text.to_s.empty? }
      # Only reorder each result group, never the questions or room history.
      entries.chunk { |entry| entry.kind == :answer_result ? [:result, entry.event_id] : [:ordinary] }.flat_map do |key, group|
        key.first == :ordinary ? group : group.sort_by { |entry| same_user?(entry.actor, viewer) ? 0 : 1 }
      end
    end

    private

    def initial_state(players, options)
      {
        players: players,
        options: options,
        phase: :drawing,
        round: 0,
        attempt: 0,
        position: 0,
        completed_rounds: 0,
        category: nil,
        choices: [],
        question_id: nil,
        deadline: 0,
        resume_at: 0,
        commitments: {},
        reveals: {},
        reveal_parts: {},
        used_questions: [],
        scores: players.each_with_object({}) { |player, result| result[player] = 0 },
        final_round: nil,
        winners: []
      }
    end

    def choosing_surface(state, viewer)
      categories = round_categories(state)
      if same_user?(current_chooser(state), viewer) && !categories.empty?
        return GameSurfaces::QuestionSpec.new(
          id: category_surface_id(state),
          prompt: _("Choose the category for round %{round}") % { round: state[:completed_rounds] + 1 },
          mode: :single_choice,
          options: categories.map do |category|
            GameSurfaces::QuestionOption.new(id: category, label: category_choice_label(state, category))
          end,
          required: true,
          submit_on_select: true
        )
      end

      information_surface(
        "quiz_choosing",
        _("%{player} is choosing the category for round %{round}.") % {
          player: participant_name(current_chooser(state)),
          round: state[:completed_rounds] + 1
        }
      )
    end

    def answering_surface(state, viewer)
      question = current_question(state)
      if question != nil && includes_player?(state[:players], viewer) &&
          !player_hash_key?(state[:commitments], viewer)
        return GameSurfaces::QuestionSpec.new(
          id: question_surface_id(state),
          prompt: question["prompt"].to_s,
          mode: :single_choice,
          options: shuffled_options(state).each_with_index.map do |answer, index|
            GameSurfaces::QuestionOption.new(id: index.to_s, label: answer)
          end,
          required: true,
          submit_on_select: true,
          prompt_in_choices: true
        )
      end

      information_surface("quiz_answered", status_text(state, viewer))
    end

    def information_surface(id, message)
      GameSurfaces::QuestionSpec.new(id: id, prompt: "", mode: :information, value: message)
    end

    def submit_category(selection, state, actor)
      return [:not_your_turn, nil] if state[:phase] != :choosing || !same_user?(current_chooser(state), actor)

      category = selection["answer"].to_s
      return [:invalid, nil] if !round_categories(state).include?(category)
      code = category_code(state, category)
      return [:invalid, nil] if code == nil

      round = state[:completed_rounds] + 1
      value = [state[:attempt] + 1, round, chooser_index(state[:players], round), code].join(",")
      [:ok, event_plan("round_category", value)]
    end

    def submit_answer(selection, state, actor, context)
      return [:not_your_turn, nil] if state[:phase] != :answering || !includes_player?(state[:players], actor)
      return [:invalid, nil] if selection["question_id"].to_s != question_surface_id(state)
      return [:already_submitted, nil] if player_hash_key?(state[:commitments], actor)
      return [:invalid, nil] if context == nil || context.hidden_submissions == nil
      return [:invalid, nil] if deadline_reached?(state, context.now)

      answer = selection["answer"].to_s
      return [:invalid, nil] if !/\A[0-9]+\z/.match?(answer) || answer.to_i >= OPTION_COUNT

      envelope = context.hidden_submissions.prepare(
        session_id: context.session_id,
        round_id: question_key(state),
        user: actor,
        payload: { "answer" => answer }
      )
      [:ok, event_plan("answer_commit", encode_answer_value(state, envelope.commitment, digest: true))]
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    end

    def automatic_plan(action, state, actor, context)
      case action
      when "draw_categories"
        return [:not_your_turn, nil] if state[:phase] != :drawing || !owner?(state[:players], actor)
        return [:invalid, nil] if !next_question_pause_over?(state, context&.now)

        drawn = draw_round_categories(state, context)
        return [:invalid, nil] if drawn.empty?

        codes = drawn.map { |category| category_code(state, category) }
        return [:invalid, nil] if codes.any?(&:nil?)

        value = [state[:completed_rounds] + 1, codes.join(".")].join(",")
        [:ok, event_plan("round_draw", value)]
      when "start_question"
        return [:not_your_turn, nil] if state[:phase] != :starting || !owner?(state[:players], actor)
        return [:invalid, nil] if !next_question_pause_over?(state, context&.now)

        question = draw_question(state, context)
        return [:invalid, nil] if question == nil

        duration = state[:options]["answer_time"].to_i
        deadline = context.now.to_i + duration
        value = [state[:round], state[:position] + 1, question["id"], deadline].join(",")
        [:ok, event_plan("question", value)]
      when "close_answers"
        return [:not_your_turn, nil] if state[:phase] != :answering || !owner?(state[:players], actor)
        return [:invalid, nil] if !commitments_complete?(state) && !closing_deadline_reached?(state, context&.now)

        [:ok, event_plan("answers_closed", question_key(state))]
      when "reveal"
        return reveal_plan(state, actor, context)
      when "finish_question"
        return [:not_your_turn, nil] if state[:phase] != :revealing || !owner?(state[:players], actor)
        return [:invalid, nil] if !finish_due?(state, context&.now)

        value = [state[:round], state[:position], expected_score_mask(state).to_s(36)].join(",")
        [:ok, event_plan("question_finished", value)]
      else
        [:invalid, nil]
      end
    end

    def pending_reveal(state, actor, context)
      if player_hash_key?(state[:reveals], actor)
        context&.hidden_submissions&.discard(
          session_id: context.session_id,
          round_id: question_key(state),
          user: actor
        )
        return nil
      end
      return nil if !player_hash_key?(state[:commitments], actor)
      return nil if reveal_plan(state, actor, context).first != :ok

      surface_action("automatic", "reveal")
    end

    def reveal_plan(state, actor, context)
      return [:invalid, nil] if state[:phase] != :revealing || context == nil || context.hidden_submissions == nil
      commitment = player_hash_value(state[:commitments], actor)
      return [:invalid, nil] if commitment.to_s.empty?

      envelope = context.hidden_submissions.reveal(
        session_id: context.session_id,
        round_id: question_key(state),
        user: actor,
        commitment: commitment
      )
      return [:invalid, nil] if envelope == nil || envelope.commitment != commitment
      return [:invalid, nil] if !/\A[0-9a-f]{64}\z/.match?(envelope.nonce.to_s)
      return [:invalid, nil] if !context.hidden_submissions.verify(envelope)
      answer = envelope.payload.fetch("answer", "").to_s
      return [:invalid, nil] if !/\A[0-3]\z/.match?(answer)

      [:ok, ActionPlan.new(events: [
        EventCommand.new(action: "answer_nonce", value: encode_answer_value(state, envelope.nonce, digest: true)),
        EventCommand.new(action: "answer_pick", value: encode_answer_value(state, answer))
      ])]
    rescue ArgumentError, TypeError, KeyError, NoMethodError
      # A missing/corrupt local envelope must not starve the owner's timeout.
      [:invalid, nil]
    end

    def accept_reveal_part(state, players, actor, part, value)
      return false if state[:phase] != :revealing || !player_hash_key?(state[:commitments], actor)
      return false if player_hash_key?(state[:reveals], actor)
      value = decode_answer_value(state, value, digest: part == :nonce)
      return false if value == nil
      return false if part == :nonce && !/\A[0-9a-f]{64}\z/.match?(value)
      return false if part == :answer && !/\A[0-3]\z/.match?(value)

      player = canonical_player(players, actor)
      parts = state[:reveal_parts][player] ||= {}
      return false if parts.key?(part)

      parts[part] = value
      if parts.key?(:nonce) && parts.key?(:answer)
        payload = { "answer" => parts[:answer] }
        commitment = player_hash_value(state[:commitments], player)
        if HiddenSubmissions::Commitment.valid?(payload: payload, nonce: parts[:nonce], commitment: commitment)
          state[:reveals][player] = parts[:answer].to_i
        end
      end
      true
    end

    def apply_question_scores(state, mask)
      state[:players].each_with_index do |player, index|
        next if (mask & (1 << index)) == 0

        state[:scores][player] = state[:scores].fetch(player, 0) + 1
      end
    end

    def question_result_history(state, event_id, actor)
      question = current_question(state)
      return [] if question == nil

      correct = shuffled_options(state)[correct_option_index(state)].to_s
      entries = [history_entry(event_id, _("Correct answer: %{answer}.") % { answer: correct }, actor, :answer)]
      right = []
      wrong = []
      state[:players].each do |player|
        answer = player_hash_value(state[:reveals], player)
        if answer != nil && answer.to_i == correct_option_index(state)
          right << player
        else
          wrong << player
        end
      end
      state[:players].each do |player|
        entry = history_entry(event_id, "", player, :answer_result)
        entry.key = "answer_result:#{event_id}:#{player}"
        entry.field = right.include?(player) ? "right" : "wrong"
        entry.value = "#{right.length}/#{wrong.length}"
        entries << entry
      end
      entries
    end

    def answer_result_text(state, entry, viewer)
      right, wrong = entry.value.to_s.split("/", 2)
      mine = if same_user?(entry.actor, viewer)
        entry.field.to_s == "right" ? _("You answered correctly.") : _("You answered incorrectly.")
      else
        nil
      end
      if state[:players].to_a.length <= 3
        named = if entry.field.to_s == "right"
          _("%{player} answered correctly.") % { player: participant_name(entry.actor) }
        else
          _("%{player} answered incorrectly.") % { player: participant_name(entry.actor) }
        end
        return mine == nil ? named : mine
      end
      if mine == nil
        return nil if includes_player?(state[:players], viewer)
        return nil if !same_user?(entry.actor, state[:players].first)
      end

      [
        mine,
        _("%{count} answered correctly.") % { count: right.to_i },
        _("%{count} answered incorrectly.") % { count: wrong.to_i }
      ].compact.join(" ")
    end

    def update_match_ending(state, history, event_id)
      target = state[:options]["target_score"].to_i
      highest = state[:players].map { |player| state[:scores].fetch(player, 0).to_i }.max.to_i
      if state[:final_round] == nil && highest >= target
        state[:final_round] = state[:completed_rounds]
        history << history_entry(event_id, _("The target score was reached."), "", :final_round)
      end
      return [nil, false] if state[:final_round] == nil || state[:completed_rounds] < state[:final_round]

      leaders = score_leaders(state)
      if leaders.length > 1
        state[:final_round] = state[:completed_rounds] + 1
        history << history_entry(
          event_id,
          _("The lead is tied. Another round will be played: %{players}.") % {
            players: leaders.map { |player| participant_name(player) }.join(", ")
          },
          "",
          :tie_round
        )
        return [nil, false]
      end

      state[:winners] = leaders
      history << history_entry(
        event_id,
        _("%{player} won the game.") % { player: participant_name(leaders.first) },
        leaders.first,
        :result
      )
      [leaders.first, false]
    end

    def score_leaders(state)
      maximum = state[:players].map { |player| state[:scores].fetch(player, 0).to_i }.max.to_i
      state[:players].select { |player| state[:scores].fetch(player, 0).to_i == maximum }
    end

    def pack_questions(options)
      pack = selected_content_pack(options)
      return [] if pack == nil

      pack.data["questions"].to_a.select { |question| valid_question?(question) }
    end

    def pack_question_count(pack)
      return pack.entry_count if pack.entry_count != nil
      @pack_question_count_cache ||= {}
      @pack_question_count_cache[pack.id] ||=
        pack.data["questions"].to_a.count { |question| valid_question?(question) }
    end

    def valid_question?(question)
      return false if !question.respond_to?(:key?)

      question["id"].to_s.length.between?(1, 32) && !question["prompt"].to_s.empty? &&
        !question["correct"].to_s.empty? && !question["category"].to_s.empty? &&
        question["wrong"].to_a.length == OPTION_COUNT - 1
    end

    def questions(state)
      @questions_cache ||= {}
      @questions_cache[state[:options]] ||= pack_questions(state[:options])
    end

    def question_index(state)
      @question_index_cache ||= {}
      @question_index_cache[state[:options]] ||= questions(state).each_with_object({}) do |question, index|
        index[question["id"].to_s] = question
      end
    end

    def questions_by_category(state)
      @questions_by_category_cache ||= {}
      @questions_by_category_cache[state[:options]] ||= questions(state).group_by { |question| question["category"].to_s }
    end

    def question_by_id(state, id)
      question_index(state)[id.to_s]
    end

    def current_question(state)
      state[:question_id] == nil ? nil : question_by_id(state, state[:question_id])
    end

    def available_categories(state)
      @available_categories_cache ||= {}
      @available_categories_cache[state[:options]] ||= questions_by_category(state).keys.sort
    end

    def round_choice_count(state)
      count = available_categories(state).length
      count < ROUND_CATEGORY_CHOICES ? count : ROUND_CATEGORY_CHOICES
    end

    def round_categories(state)
      drawn = state[:choices].to_a.map(&:to_s)
      return drawn if !drawn.empty?

      available_categories(state).first(round_choice_count(state))
    end

    def draw_round_categories(state, context)
      remaining = available_categories(state).dup
      round_choice_count(state).times.each_with_object([]) do |_index, drawn|
        break drawn if remaining.empty?

        drawn << remaining.delete_at(random_index(context, remaining.length))
      end
    end

    def categories_by_codes(state, codes)
      values = codes.to_a.map { |code| category_by_code(state, code) }
      return nil if values.any?(&:nil?) || values.uniq.length != values.length

      values
    end

    def category_code(state, category)
      index = available_categories(state).index(category.to_s)
      index == nil ? nil : index.to_s
    end

    def category_by_code(state, code)
      available_categories(state)[code.to_i]
    end

    def category_label(category)
      category.to_s
    end

    def category_choice_label(state, category)
      _("%{category}, %{questions}") % {
        category: category_label(category),
        questions: question_count_text(questions_by_category(state)[category.to_s].to_a.length)
      }
    end

    def question_count_text(count)
      amount = count.to_i
      template = if respond_to?(:n_, true)
        n_("%{count} question", "%{count} questions", amount)
      else
        amount == 1 ? "%{count} question" : "%{count} questions"
      end
      template % { count: amount }
    end

    def draw_question(state, context)
      available = drawable_questions(state)
      return nil if available.empty?

      available[random_index(context, available.length)]
    end

    def category_questions(state)
      questions_by_category(state)[state[:category].to_s] || []
    end

    def fresh_questions(state)
      used = state[:used_questions].to_a
      return category_questions(state) if used.empty?

      used_ids = {}
      used.each { |id| used_ids[id.to_s] = true }
      category_questions(state).reject { |question| used_ids.key?(question["id"].to_s) }
    end

    def drawable_questions(state)
      fresh = fresh_questions(state)
      fresh.empty? ? category_questions(state) : fresh
    end

    def drawable_question?(state, id)
      drawable_questions(state).any? { |question| question["id"].to_s == id.to_s }
    end

    def reset_used_questions(state)
      asked = category_questions(state).map { |question| question["id"].to_s }
      state[:used_questions].reject! { |id| asked.include?(id) }
    end

    def random_index(context, count)
      return 0 if count <= 1
      return context.random_source.roll(count: 1, sides: count).values.first - 1 if count <= ROLL_LIMIT

      roll = context.random_source.roll(count: 2, sides: ROLL_LIMIT).values
      ((roll[0] - 1) * ROLL_LIMIT + (roll[1] - 1)) % count
    end

    def shuffled_options(state)
      question = current_question(state)
      return [] if question == nil

      answers = [question["correct"].to_s] + question["wrong"].to_a.map(&:to_s)
      seed = "#{question["id"]}:#{state[:round]}:#{state[:position]}".each_char.reduce(7) do |result, character|
        (result * 31 + character.ord) & 0x7fffffff
      end
      (answers.length - 1).downto(1) do |index|
        seed = (seed * 1_103_515_245 + 12_345) & 0x7fffffff
        target = seed % (index + 1)
        answers[index], answers[target] = answers[target], answers[index]
      end
      answers
    end

    def correct_option_index(state)
      question = current_question(state)
      return -1 if question == nil

      shuffled_options(state).index(question["correct"].to_s).to_i
    end

    def expected_score_mask(state)
      correct = correct_option_index(state)
      state[:players].each_with_index.reduce(0) do |mask, (player, index)|
        answer = player_hash_value(state[:reveals], player)
        answer != nil && answer.to_i == correct ? mask | (1 << index) : mask
      end
    end

    def commitments_complete?(state)
      state[:players].all? { |player| player_hash_key?(state[:commitments], player) }
    end

    def reveals_complete?(state)
      state[:commitments].keys.all? { |player| player_hash_key?(state[:reveals], player) }
    end

    def event_timestamp(event)
      raw = event["created_at"] || event[:created_at]
      return raw.to_i if raw != nil && raw.to_i > 0

      sequence = event["sequence"] || event[:sequence]
      return sequence.to_i - 1 if sequence != nil && sequence.to_i > 0

      nil
    end

    def answers_may_close?(state, timestamp)
      commitments_complete?(state) || (timestamp != nil && closing_deadline_reached?(state, timestamp))
    end

    def question_may_finish?(state, timestamp)
      reveals_complete?(state) || (timestamp != nil && finish_due?(state, timestamp))
    end

    def finish_due?(state, now)
      return true if reveals_complete?(state)

      state[:deadline].to_i > 0 && now.to_i >= state[:deadline].to_i + REVEAL_TIMEOUT
    end

    def next_question_pause_over?(state, now)
      resume_at = state[:resume_at].to_i
      return true if resume_at <= 0
      return true if now == nil

      now.to_i >= resume_at
    end

    def deadline_reached?(state, now)
      state[:deadline].to_i > 0 && now.to_i >= state[:deadline].to_i
    end

    def closing_deadline_reached?(state, now)
      state[:deadline].to_i > 0 && now.to_i >= state[:deadline].to_i + DEADLINE_SUBMISSION_GRACE
    end

    def chooser_index(players, round)
      players.empty? ? 0 : (round.to_i - 1) % players.length
    end

    def current_chooser(state)
      players = state[:players].to_a
      players[chooser_index(players, state[:completed_rounds] + 1)]
    end

    def choosing_selection?(selection, state)
      selection["question_id"].to_s == category_surface_id(state)
    end

    def category_surface_id(state)
      "quiz-category-#{state[:completed_rounds] + 1}-#{state[:attempt] + 1}"
    end

    def question_surface_id(state)
      "quiz-question-#{state[:round]}-#{state[:position]}"
    end

    def question_key(state)
      "round-#{state[:round]}-question-#{state[:position]}"
    end

    # The turn coordinates bind every fragment to this question, even when
    # an older concurrent append reaches the session during the next question.
    # Base64 preserves the full 256-bit commitment/nonce within the 64-char field.
    def encode_answer_value(state, value, digest: false)
      body = digest ? [[value].pack("H*")].pack("m0") : value
      "#{state[:round].to_i.to_s(36)}.#{state[:position]}:#{body}"
    end

    def decode_answer_value(state, value, digest: false)
      prefix = "#{state[:round].to_i.to_s(36)}.#{state[:position]}:"
      return nil if !value.start_with?(prefix)
      body = value.delete_prefix(prefix)
      return body if !digest
      return nil if !/\A[A-Za-z0-9+\/]{43}=\z/.match?(body)
      decoded = body.unpack1("m0")
      return nil if decoded.bytesize != 32 || [decoded].pack("m0") != body
      decoded.unpack1("H*")
    rescue ArgumentError
      nil
    end

    def parse_round_draw(value)
      parts = value.to_s.split(",", -1)
      return nil if parts.length != 2

      codes = parts[1].to_s.split(".", -1)
      return nil if codes.empty? || codes.any? { |code| !/\A[0-9]{1,3}\z/.match?(code) }

      {
        round: Integer(parts[0], 10),
        categories: codes
      }
    rescue ArgumentError
      nil
    end

    def parse_round_category(value)
      parts = value.to_s.split(",", -1)
      return nil if parts.length != 4

      {
        attempt: Integer(parts[0], 10),
        round: Integer(parts[1], 10),
        chooser: Integer(parts[2], 10),
        category: Integer(parts[3], 10)
      }
    rescue ArgumentError
      nil
    end

    def parse_question(value)
      parts = value.to_s.split(",", -1)
      return nil if parts.length != 4 || parts[2].to_s.empty?

      {
        round: Integer(parts[0], 10),
        position: Integer(parts[1], 10),
        question_id: parts[2],
        deadline: Integer(parts[3], 10)
      }
    rescue ArgumentError
      nil
    end

    def parse_question_result(value)
      parts = value.to_s.split(",", -1)
      return nil if parts.length != 3 || !/\A[0-9a-z]+\z/.match?(parts[2])

      {
        round: Integer(parts[0], 10),
        position: Integer(parts[1], 10),
        mask: Integer(parts[2], 36)
      }
    rescue ArgumentError
      nil
    end

    def current_question_text(state)
      return _("The first round is being prepared.") if state[:round].to_i <= 0
      question = current_question(state)
      return round_summary_text(state) if question == nil || state[:phase] != :answering

      _("%{prompt} %{answers}") % {
        prompt: question["prompt"].to_s,
        answers: shuffled_options(state).each_with_index.map do |answer, index|
          _("%{number}: %{answer}") % { number: index + 1, answer: answer }
        end.join("; ")
      }
    end

    def remaining_time_text(state)
      return _("The answer time has ended.") if state[:phase] != :answering || state[:deadline].to_i <= 0

      _("%{seconds} seconds remaining.") % { seconds: [state[:deadline].to_i - GameRoomSessionClock.for_state(state).to_i, 0].max }
    end

    def scores_text(state, sorted: false)
      players = sorted ? score_announcement_order(state[:players], state[:scores]) : state[:players]
      values = players.map do |player|
        _("%{player}: %{points}") % {
          player: participant_name(player),
          points: state[:scores].fetch(player, 0).to_i
        }
      end
      _("Scores: %{scores}.") % { scores: values.join("; ") }
    end

    def round_summary_text(state)
      return _("The first round is being prepared.") if state[:round].to_i <= 0

      _("Round %{round}; category %{category}; question %{position} of %{total}; target: %{target} points.") % {
        round: state[:round],
        category: category_label(state[:category]),
        position: [state[:position].to_i, 1].max,
        total: QUESTIONS_PER_ROUND,
        target: state[:options]["target_score"]
      }
    end

    def status_text(state, viewer)
      case state[:phase]
      when :finished
        result_text(Replay.new(state: state)) || scores_text(state)
      when :answering
        if player_hash_key?(state[:commitments], viewer)
          _("Answer sent.")
        else
          _("Waiting for the players to answer.")
        end
      when :revealing
        ""
      when :starting
        _("The next question is being prepared.")
      when :drawing
        _("The categories for the next round are being drawn.")
      else
        round_summary_text(state)
      end
    end

    def current_actor(state)
      state[:phase] == :choosing ? current_chooser(state) : nil
    end

    def history_entry(event_id, text, actor, kind)
      HistoryEntry.new(
        key: "#{kind}:#{event_id}:#{text.hash}",
        text: text,
        event_id: event_id,
        actor: actor,
        kind: kind
      )
    end

    def surface_action(kind, action, payload = {})
      GameSurfaces::Action.new(kind: kind, name: action, payload: payload)
    end

    def owner?(players, actor)
      players.first != nil && same_user?(players.first, actor)
    end

    def includes_player?(players, actor)
      players.to_a.any? { |player| same_user?(player, actor) }
    end

    def canonical_player(players, actor)
      players.find { |player| same_user?(player, actor) } || actor.to_s
    end

    def player_hash_key?(hash, actor)
      hash.keys.any? { |player| same_user?(player, actor) }
    end

    def player_hash_value(hash, actor)
      key = hash.keys.find { |player| same_user?(player, actor) }
      key == nil ? nil : hash[key]
    end
  end
end

require_relative 'quiz_party/reduction'

require_relative 'generated/rulebooks/quiz'
