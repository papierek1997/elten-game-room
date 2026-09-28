require_relative "base"
require_relative "../lib/hidden_submissions"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  class Categories < Base
    EASY_CATEGORY_IDS = %w[
      country city name animal plant thing profession food color
    ].freeze
    MEDIUM_CATEGORY_IDS = (EASY_CATEGORY_IDS + %w[
      surname famous_person sport vehicle clothing body_part building musical_instrument book
    ]).freeze
    HARD_CATEGORY_IDS = (MEDIUM_CATEGORY_IDS + %w[
      film song music_group river mountain island language invention chemical_element
    ]).freeze
    CATEGORY_IDS = HARD_CATEGORY_IDS
    CATEGORY_SETS = {
      "easy" => EASY_CATEGORY_IDS,
      "medium" => MEDIUM_CATEGORY_IDS,
      "hard" => HARD_CATEGORY_IDS
    }.freeze
    CATEGORY_SET_CUSTOM = "custom".freeze
    ROUND_CATEGORY_ENCODING_PREFIX = "m:".freeze
    DEFAULT_CUSTOM_CATEGORY_MASK = 0
    ROUND_CATEGORY_COUNTS = (1..9).to_a.freeze
    ANSWER_MAX_LENGTH = 48
    JUDGE_ROTATING = "rotating".freeze
    JUDGE_MASTER = "master".freeze
    TIE_EXTRA_CYCLE = "extra_cycle".freeze
    TIE_SHARED = "shared".freeze
    LANGUAGE_LETTERS = {
      "pl" => %w[A B C D E F G H I J K L M N O P R S T U W Z],
      "en" => ("A".."Z").to_a
    }.freeze
    MINIMUM_ROUND_TIME = 10
    MAXIMUM_ROUND_TIME = 3_600
    DEADLINE_SUBMISSION_GRACE = 3
    DECISION_POINTS = {
      "unique" => 2,
      "partial" => 1,
      "duplicate" => 1,
      "incorrect" => 0
    }.freeze
    REVIEW_DECISIONS = DECISION_POINTS.keys.freeze
    REVIEW_DECISION_CODES = {
      "unique" => "u",
      "partial" => "p",
      "duplicate" => "d",
      "incorrect" => "i"
    }.freeze
    REVIEW_CODE_DECISIONS = REVIEW_DECISION_CODES.invert.freeze

    def id
      "categories"
    end

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
      _("Countries and cities")
    end

    def minimum_players
      2
    end

    def maximum_players
      8
    end

    def rule_sections
      # Generated from docs/rulebooks/categories.json; see tools/compile-rulebooks.rb.
      [
        rule_section(:sheet, GameRoomRules.translate("One letter, several kinds of answer"),
          GameRoomRules.translate("Countries and cities is played by two to eight people. Each round draws a letter and several categories. Write a word or name beginning with that letter for each category. For example, with B and the categories country, city and animal, you might write Brazil, Berlin and bear. The entries must fit their categories, not merely start with the right letter."),
          GameRoomRules.translate("One participant is the judge for that round and does not write answers or earn points. The others fill in their own sheets. Each field accepts up to 48 characters. You may leave a field empty rather than invent an answer. Submit the sheet when finished; it cannot be changed once submitted. Answers stay hidden while anyone is still writing.")),
        rule_section(:judging, GameRoomRules.translate("A person judges the answers"),
          GameRoomRules.translate("When all sheets are submitted or the answer time ends, writing closes and the answers are revealed. The judge sees identical answers grouped within each category and decides whether they fit the letter, category and meaning. This is not automatic dictionary scoring: discuss doubtful entries with the judge."),
          GameRoomRules.translate("A unique correct answer is worth 2 points. An accepted repeated answer gives each author 1 point, as does an answer judged partially correct. An incorrect or empty answer gives zero. Everyone can see the grades and authors. Once every answer group has been assessed, the judge finishes the review and the round's points are added to the scores.")),
        rule_section(:pools, GameRoomRules.translate("Choose a pool, then draw categories from it"),
          GameRoomRules.translate("Answer language is Polish by default; English is also available. It chooses the alphabet for letter draws and the language you agree to answer in, not the interface language. Category labels follow your interface. Letters do not repeat until the selected alphabet has been used up."),
          GameRoomRules.translate("The Easy pool contains country, city, first name, animal, plant, thing, profession, food and colour. Medium adds surname, famous person, sport, vehicle, clothing, body part, building, musical instrument and book. Hard adds film, song, music group, river, mountain, island, language, invention and chemical element. These names describe the pool, not a different scoring system."),
          GameRoomRules.translate("Custom lets you select your own pool from those 27 categories, and remembers the last custom choice locally. Categories shown in each round chooses how many are drawn from the pool: one to nine, default six. It cannot exceed the size of your pool. For example, choosing all nine Easy categories with six per round still draws only six, and the selection may differ next round.")),
        rule_section(:judge, GameRoomRules.translate("Who judges and how long you write"),
          GameRoomRules.translate("Rotating judge is the default: the role moves around the seating order, so everyone sometimes judges instead of scoring. Table master judges every round makes the creator the permanent judge and removes that person from the scoring competition. With two participants, that setting leaves one answering player and one permanent judge."),
          GameRoomRules.translate("Answer time defaults to 90 seconds. Set zero for unlimited time, or 10\u20133600 seconds. Only writing is timed, not judging. Near the deadline the game warns you; at the deadline it submits the text still in your fields rather than clearing it first. A participant whose answers do not arrive during closing is treated as having empty entries. Without a time limit, all answering players must submit to move on.")),
        rule_section(:finish, GameRoomRules.translate("Equal rounds and tied scores"),
          GameRoomRules.translate("Target score defaults to 100 and can be 10\u20131000. With a rotating judge, reaching it does not stop play at once: finish the current full judge cycle, so everyone has judged equally often. With a permanent judge, the completed scoring round can decide the result. The highest eligible total wins, not necessarily the first person who touched the target."),
          GameRoomRules.translate("A tied lead can give a shared victory or require extra play, the default. In extra play only the tied leaders remain in contention. An outside participant judges if possible; if everyone is tied, judging continues over complete cycles. A permanent judge keeps that role. Further play continues until the tied lead is resolved. This game does not support saving a partly completed match.")),
        rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
          GameRoomRules.translate("Tab: next answer field, submission control or review group."),
          GameRoomRules.translate("Shift+Tab: previous answer field or review group."),
          GameRoomRules.translate("Arrows: during review, select a grade."),
          GameRoomRules.translate("Enter: confirm the selected grade or submission action."),
          GameRoomRules.translate("Ctrl+T: read the remaining answer time, also while typing."),
          GameRoomRules.translate("T: outside answer entry, read the letter and judge."),
          GameRoomRules.translate("S: outside answer entry, read the scores."),
          GameRoomRules.translate("V: outside answer entry, read round information."))
      ]
    end

    def option_definitions
      [
        OptionDefinition.new(
          key: "judge_mode",
          label: _("Judge mode"),
          kind: :choice,
          default: JUDGE_ROTATING,
          choices: [
            OptionChoice.new(value: JUDGE_ROTATING, label: _("Rotating judge")),
            OptionChoice.new(value: JUDGE_MASTER, label: _("Table master judges every round"))
          ]
        ),
        OptionDefinition.new(
          key: "answer_language",
          label: _("Answer language"),
          kind: :choice,
          default: "pl",
          choices: [
            OptionChoice.new(value: "pl", label: _("Polish")),
            OptionChoice.new(value: "en", label: _("English"))
          ]
        ),
        OptionDefinition.new(
          key: "category_set",
          label: _("Category pool"),
          kind: :choice,
          default: "easy",
          choices: [
            OptionChoice.new(value: "easy", label: _("Easy, 9 categories")),
            OptionChoice.new(value: "medium", label: _("Medium, 18 categories")),
            OptionChoice.new(value: "hard", label: _("Hard, 27 categories")),
            OptionChoice.new(value: CATEGORY_SET_CUSTOM, label: _("Custom"))
          ]
        ),
        OptionDefinition.new(
          key: "custom_categories",
          label: _("Custom categories"),
          kind: :multiple_choice,
          default: DEFAULT_CUSTOM_CATEGORY_MASK,
          visible_if: { "category_set" => CATEGORY_SET_CUSTOM },
          choices: CATEGORY_IDS.map do |category|
            OptionChoice.new(value: category, label: category_label(category))
          end
        ),
        OptionDefinition.new(
          key: "round_category_count",
          label: _("Categories shown in each round"),
          kind: :choice,
          default: 6,
          choices: ROUND_CATEGORY_COUNTS.map do |count|
            OptionChoice.new(value: count, label: count.to_s)
          end
        ),
        OptionDefinition.new(
          key: "round_time",
          label: _("Time for answers in seconds; 0 means no time limit"),
          kind: :integer,
          default: 90
        ),
        OptionDefinition.new(
          key: "target_score",
          label: _("Target score"),
          kind: :integer,
          default: 100
        ),
        OptionDefinition.new(
          key: "tie_mode",
          label: _("Tied lead at the end"),
          kind: :choice,
          default: TIE_EXTRA_CYCLE,
          choices: [
            OptionChoice.new(value: TIE_EXTRA_CYCLE, label: _("Play another complete cycle")),
            OptionChoice.new(value: TIE_SHARED, label: _("Allow a shared victory"))
          ]
        )
      ]
    end

    def options_error(options, player_count: nil)
      return _("The target score must be between 10 and 1000 points.") if !options["target_score"].to_i.between?(10, 1_000)
      duration = options["round_time"].to_i
      if duration != 0 && !duration.between?(MINIMUM_ROUND_TIME, MAXIMUM_ROUND_TIME)
        return _("The answer time must be 0, or between %{minimum} and %{maximum} seconds.") % {
          minimum: MINIMUM_ROUND_TIME,
          maximum: MAXIMUM_ROUND_TIME
        }
      end
      return _("The selected answer language is not supported.") if !LANGUAGE_LETTERS.key?(options["answer_language"].to_s)
      return _("The selected category pool is not supported.") if !CATEGORY_SETS.key?(options["category_set"].to_s) && options["category_set"].to_s != CATEGORY_SET_CUSTOM
      return _("Select at least one category for the custom pool.") if selected_category_pool(options).empty?
      if !ROUND_CATEGORY_COUNTS.include?(options["round_category_count"].to_i)
        return _("The number of categories shown in a round must be between 1 and 9.")
      end
      if options["round_category_count"].to_i > selected_category_pool(options).length
        return _("The number of categories shown in a round cannot exceed the size of the selected pool.")
      end
      return _("A permanent judge requires at least two participants.") if options["judge_mode"] == JUDGE_MASTER && player_count != nil && player_count.to_i < 2

      nil
    end

    def options_summary(options)
      normalized = normalize_options(options)
      judge = normalized["judge_mode"] == JUDGE_MASTER ? _("table master judge") : _("rotating judge")
      language = normalized["answer_language"] == "pl" ? _("Polish") : _("English")
      pool = category_set_label(normalized["category_set"])
      time = normalized["round_time"].to_i == 0 ? _("no time limit") : _("%{seconds} seconds") % { seconds: normalized["round_time"] }
      _("%{judge}; answers in %{language}; %{pool}; %{categories} categories per round; %{time}; target: %{target} points") % {
        judge: judge,
        language: language,
        pool: pool,
        categories: normalized["round_category_count"],
        time: time,
        target: normalized["target_score"]
      }
    end

    def replay(session, events, repository)
      players = repository.players_for(session)
      options = options_from_json(session["options"])
      state = initial_state(players, options)
      accepted = []
      history = [starting_history(players)]
      winner = nil
      draw = false

      events.each do |event|
        action = event["action"].to_s
        actor = repository.actor_of(event, session)
        next if actor.to_s.empty?
        event_id = repository.event_id(event)
        value = event["value"].to_s
        accepted_event = false

        case action
        when "category_round"
          parsed = parse_round(value)
          expected_round = state[:completed_rounds] + 1
          expected_attempt = state[:attempt] + 1
          expected_judge = judge_index(options, players, expected_round, state)
          if owner?(players, actor) && [:setup, :round_complete].include?(state[:phase]) &&
              parsed != nil && parsed[:round] == expected_round && parsed[:attempt] == expected_attempt &&
              parsed[:judge_index] == expected_judge && valid_round_letter?(parsed[:letter], options, state[:used_letters]) &&
              valid_round_categories?(parsed[:categories], options)
            state[:attempt] = parsed[:attempt]
            state[:round] = parsed[:round]
            state[:judge] = players[parsed[:judge_index]]
            state[:letter] = parsed[:letter]
            state[:round_categories] = parsed[:categories]
            state[:deadline] = parsed[:deadline]
            state[:active_players] = contestants_for_round(players, state[:judge], state)
            state[:commitments] = {}
            state[:reveals] = {}
            state[:reveal_parts] = {}
            state[:decisions] = {}
            state[:review_finished] = false
            state[:round_scores] = {}
            alphabet = LANGUAGE_LETTERS.fetch(options["answer_language"].to_s)
            state[:used_letters].clear if (alphabet - state[:used_letters]).empty?
            state[:used_letters] << parsed[:letter]
            state[:phase] = :answering
            accepted_event = true
            history << history_entry(
              event_id,
              _("Round %{round} started. Letter: %{letter}.") % { round: state[:round], letter: state[:letter] },
              actor,
              :round_start
            )
            history << history_entry(
              event_id,
              _("Categories: %{categories}.") % {
                categories: state[:round_categories].map { |category| category_label(category) }.join(", ")
              },
              actor,
              :round_categories
            )
            history << history_entry(
              event_id,
              _("%{player} is the judge.") % { player: participant_name(state[:judge]) },
              state[:judge],
              :judge
            )
          end
        when "answer_commit"
          if state[:phase] == :answering && includes_player?(state[:active_players], actor) &&
              !player_hash_key?(state[:commitments], actor) && /\A[0-9a-f]{64}\z/.match?(value)
            state[:commitments][canonical_player(state[:active_players], actor)] = value
            accepted_event = true
            history << history_entry(
              event_id,
              _("%{player} submitted their answers.") % { player: participant_name(actor) },
              actor,
              :submission
            )
          end
        when "answers_closed"
          if state[:phase] == :answering && owner?(players, actor)
            state[:phase] = :revealing
            accepted_event = true
            history << history_entry(event_id, _("Answering has closed."), actor, :answers_closed)
          end
        when "answer_nonce"
          accepted_event = accept_reveal_part(state, actor, :nonce, value, event, event_id, history)
        when /\Aanswer_(\d+)\z/
          category_index = Regexp.last_match(1).to_i
          if category_index.between?(0, round_category_ids(state).length - 1)
            accepted_event = accept_reveal_part(state, actor, category_index, value, event, event_id, history)
          end
        when "review_started"
          if state[:phase] == :revealing && (owner?(players, actor) || same_user?(state[:judge], actor))
            state[:phase] = :review
            accepted_event = true
            missing = state[:commitments].keys.reject { |player| player_hash_key?(state[:reveals], player) }
            if !missing.empty?
              history << history_entry(
                event_id,
                _("Missing reveals count as blank answers: %{players}.") % {
                  players: missing.map { |player| participant_name(player) }.join(", ")
                },
                actor,
                :missing_answers
              )
            end
          end
        when "review_correct", "review_incorrect", "review_unique", "review_partial", "review_duplicate"
          item = review_item_by_id(state, value)
          decision = normalize_review_decision(action.sub("review_", ""), item)
          if state[:phase] == :review && same_user?(state[:judge], actor) && item != nil &&
              REVIEW_DECISIONS.include?(decision) && state[:decisions][item[:id]] != decision &&
              !state[:review_finished]
            previous = state[:decisions][item[:id]]
            state[:decisions][item[:id]] = decision
            accepted_event = true
            history << history_entry(
              event_id,
              previous == nil ? review_decision_text(item, decision) : review_change_text(item, previous, decision),
              actor,
              :review
            )
          end
        when "review_clear"
          item = review_item_by_id(state, value)
          if state[:phase] == :review && same_user?(state[:judge], actor) && item != nil &&
              state[:decisions].key?(item[:id]) && !state[:review_finished]
            previous = state[:decisions].delete(item[:id])
            accepted_event = true
            history << history_entry(event_id, review_clear_text(item, previous), actor, :review)
          end
        when "review_finished"
          if state[:phase] == :review && same_user?(state[:judge], actor) &&
              all_reviews_assessed?(state) && !state[:review_finished]
            state[:review_finished] = true
            accepted_event = true
            history << history_entry(event_id, _("The judge finished reviewing the answers."), actor, :review_end)
          end
        when "review_commit"
          decisions = parse_review_commit(state, value)
          if state[:phase] == :review && same_user?(state[:judge], actor) && decisions != nil &&
              !state[:review_finished]
            review_items(state).each do |item|
              decision = decisions.fetch(item[:id])
              previous = state[:decisions][item[:id]]
              next if previous == decision

              state[:decisions][item[:id]] = decision
              history << history_entry(
                event_id,
                previous == nil ? review_decision_text(item, decision) : review_change_text(item, previous, decision),
                actor,
                :review
              )
            end
            state[:review_finished] = true
            accepted_event = true
            history << history_entry(event_id, _("The judge finished reviewing the answers."), actor, :review_end)
          end
        when "round_score"
          parsed = parse_score(value)
          expected = expected_round_scores(state)
          scored_player = parsed == nil ? nil : state[:active_players][parsed[:player_index]]
          if state[:phase] == :review && owner?(players, actor) && reviews_complete?(state) &&
              scored_player != nil && expected[scored_player] == parsed[:points] &&
              !player_hash_key?(state[:round_scores], scored_player)
            player = scored_player
            state[:round_scores][player] = parsed[:points]
            state[:scores][player] = state[:scores].fetch(player, 0) + parsed[:points]
            accepted_event = true
            history << history_entry(
              event_id,
              _("%{player} scored %{points} points in this round.") % {
                player: participant_name(player),
                points: parsed[:points]
              },
              player,
              :score
            )
          end
        when "round_finished"
          if state[:phase] == :review && owner?(players, actor) && round_scores_complete?(state)
            state[:completed_rounds] += 1
            state[:phase] = :round_complete
            accepted_event = true
            history << history_entry(
              event_id,
              _("Round %{round} ended.") % { round: state[:completed_rounds] },
              actor,
              :round_end
            )
            winner, draw = update_match_ending(state, history, event_id)
            state[:phase] = :finished if winner != nil || draw
          end
        when "round_cancelled"
          if [:revealing, :review].include?(state[:phase]) && owner?(players, actor)
            state[:phase] = :round_complete
            accepted_event = true
            history << history_entry(
              event_id,
              _("The round was cancelled. The judge order did not advance."),
              actor,
              :round_cancelled
            )
          end
        end

        accepted << event if accepted_event
      end

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
      when :answering
        answering_surface(state, viewer)
      when :revealing
        revealing_surface(state, viewer)
      when :review
        review_surface(state, viewer)
      else
        information_surface("categories_status", status_text(state, viewer))
      end
    end

    def game_field_header(replay, viewer)
      state = replay.state
      return name if state[:round].to_i <= 0

      _("Round %{round}; letter %{letter}; judge: %{judge}") % {
        round: state[:round],
        letter: state[:letter],
        judge: participant_name(state[:judge])
      }
    end

    def action_for(selection, replay, actor, context: nil)
      return [:finished, nil] if replay.finished?
      state = replay.state
      kind = selection["kind"].to_s
      action = selection["action"].to_s

      if kind == "answer_sheet" && action == "submit"
        return submit_answers(selection, state, actor, context)
      end
      if kind == "review" && action == "change"
        return submit_review_change(selection, state, actor)
      end
      if kind == "review" && action == "finish"
        return finish_review(selection, state, actor)
      end
      if kind == "command"
        return command_action(action, state, actor, context)
      end
      if kind == "automatic"
        return automatic_plan(action, selection, state, actor, context)
      end

      [:invalid, nil]
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      if state[:phase] == :revealing
        if player_hash_key?(state[:reveals], actor)
          context&.hidden_submissions&.discard(
            session_id: context.session_id,
            round_id: round_id(state),
            user: actor
          )
        elsif player_hash_key?(state[:commitments], actor)
          envelope = context&.hidden_submissions&.reveal(
            session_id: context.session_id,
            round_id: round_id(state),
            user: actor,
            commitment: player_hash_value(state[:commitments], actor)
          )
          return surface_action("automatic", "reveal", "envelope" => envelope) if envelope != nil
        end
      end

      return nil if !owner?(state[:players], actor)

      case state[:phase]
      when :setup, :round_complete
        return surface_action("automatic", "start_round")
      when :answering
        if commitments_complete?(state) || closing_deadline_reached?(state, context&.now)
          return surface_action("automatic", "close_answers")
        end
      when :revealing
        return surface_action("automatic", "start_review") if reveals_complete?(state)
      when :review
        return surface_action("automatic", "score_round") if reviews_complete?(state)
      end
      nil
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      return true if same_user?(actor, table_owner)

      state = replay.state
      state[:phase] == :revealing && player_hash_key?(state[:commitments], actor) &&
        !player_hash_key?(state[:reveals], actor)
    end

    def automatic_action_due?(replay, actor, context: nil)
      state = replay.state
      owner?(state[:players], actor) && state[:phase] == :answering &&
        closing_deadline_reached?(state, context&.now)
    end

    def automatic_surface_action(replay, actor, surface:, context: nil)
      state = replay.state
      return nil if state[:phase] != :answering || !includes_player?(state[:active_players], actor)
      return nil if player_hash_key?(state[:commitments], actor) || !deadline_reached?(state, context&.now)
      return nil if !surface.respond_to?(:submission_action)

      surface.submission_action
    end

    def automatic_actor(replay, viewer, table_owner:)
      state = replay.state
      return viewer if state[:phase] == :revealing && player_hash_key?(state[:commitments], viewer) &&
        !player_hash_key?(state[:reveals], viewer)
      super
    end

    def automatic_surface_identity(replay)
      [round_id(replay.state), replay.state[:phase]]
    end

    def concurrent_session_input?(before, after, selection)
      selection["kind"].to_s == "answer_sheet" && selection["action"].to_s == "submit" &&
        before.state[:phase] == :answering && after.state[:phase] == :answering &&
        round_id(before.state) == round_id(after.state)
    end

    def timer_announcements(replay, viewer, now: nil)
      state = replay.state
      now ||= GameRoomSessionClock.for_state(state).to_i
      return [] if state[:phase] != :answering || state[:deadline].to_i <= 0

      remaining = state[:deadline].to_i - now.to_i
      announcements = []
      if remaining <= 20 && remaining > 0
        announcements << ["categories:#{round_id(state)}:twenty", _("20 seconds remain.")]
      end
      if remaining <= 0
        announcements << ["categories:#{round_id(state)}:expired", _("Time is up.")]
      end
      announcements
    end

    def participant_status(replay, participant, connected: true)
      return _("disconnected") if !connected

      state = replay.state
      return _("judge") if same_user?(state[:judge], participant) && state[:phase] != :review
      return _("judging") if same_user?(state[:judge], participant) && state[:phase] == :review
      return _("finished") if state[:phase] == :finished
      return nil if !includes_player?(state[:active_players], participant)

      case state[:phase]
      when :answering
        player_hash_key?(state[:commitments], participant) ? _("finished writing") : _("writing")
      when :revealing
        player_hash_key?(state[:reveals], participant) ? nil : _("waiting to reveal")
      when :review
        _("waiting for the judge")
      else
        _("waiting for the next round")
      end
    end

    def participant_scores(replay)
      replay.state[:scores].dup
    end

    def shortcut_features
      [:turn, :remaining_time, :scores, :round_summary]
    end

    def shortcut_feature_data(feature, replay, viewer)
      state = replay.state
      case feature.to_sym
      when :turn
        { message: letter_and_judge_text(state) }
      when :remaining_time
        { message: remaining_time_text(state) }
      when :scores
        { message: scores_text(state, sorted: true) }
      when :round_summary
        { message: cycle_status_text(state) }
      else
        super
      end
    end

    def describe_event(event, repository, replay, viewer)
      action = event["action"].to_s
      actor = repository.actor_of(event)
      if (action.start_with?("review_") || action == "review_commit") && same_user?(actor, viewer)
        return []
      end
      event_id = repository.event_id(event)
      entries = replay.history.select { |entry| entry.event_id.to_i == event_id }
      entries.map(&:text)
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

    private

    def initial_state(players, options)
      {
        players: players,
        options: options,
        phase: :setup,
        round: 0,
        attempt: 0,
        completed_rounds: 0,
        judge: nil,
        letter: "",
        deadline: 0,
        active_players: [],
        commitments: {},
        reveals: {},
        reveal_parts: {},
        decisions: {},
        review_finished: false,
        round_scores: {},
        round_categories: [],
        scores: contestants(players, options).each_with_object({}) { |player, result| result[player] = 0 },
        used_letters: [],
        final_end_round: nil,
        tie_break_players: nil,
        winners: []
      }
    end

    def answering_surface(state, viewer)
      if includes_player?(state[:active_players], viewer) && !player_hash_key?(state[:commitments], viewer)
        sheet = GameSurfaces::AnswerSheetSpec.new(
          id: round_id(state),
          title: game_field_header(Replay.new(state: state), viewer),
          fields: round_category_ids(state).map do |category|
            GameSurfaces::AnswerField.new(
              id: category,
              label: _("%{category} for letter %{letter}") % {
                category: category_label(category),
                letter: state[:letter]
              },
              required: false,
              max_length: ANSWER_MAX_LENGTH
            )
          end,
          submit_label: _("Finish answering")
        )
        return sheet
      end

      message = if same_user?(state[:judge], viewer)
        _("You are the judge. Wait until all players finish answering.")
      elsif player_hash_key?(state[:commitments], viewer)
        _("Your answers were submitted. Waiting for the other players.")
      else
        _("Waiting for the players to finish answering.")
      end
      information_surface("answering_status", message)
    end

    def revealing_surface(state, viewer)
      message = if player_hash_key?(state[:reveals], viewer)
        _("Your answers have been revealed. Waiting for the other players.")
      elsif player_hash_key?(state[:commitments], viewer)
        _("Revealing your submitted answers.")
      else
        _("Waiting for submitted answers to be revealed.")
      end
      missing = state[:commitments].keys.reject { |player| player_hash_key?(state[:reveals], player) }
      unless missing.empty?
        message += " " + _("Waiting for answers from: %{players}.") % { players: missing.map { |player| participant_name(player) }.join(", ") }
        if owner?(state[:players], viewer) || same_user?(state[:judge], viewer)
          message += " " + _("You can begin review without the missing answers.")
        end
      end
      with_review_commands(information_surface("revealing_status", message), state, viewer)
    end

    def review_surface(state, viewer)
      if same_user?(state[:judge], viewer)
        return with_cancel_command(review_spec(state), state, viewer)
      end
      information_surface(
        "review_waiting",
        _("%{judge} is reviewing the answers. Confirmed assessments will appear in the game history.") % {
          judge: participant_name(state[:judge])
        }
      )
    end

    def review_spec(state)
      GameSurfaces::ReviewSpec.new(
        id: round_id(state),
        header: _("Review answers for letter %{letter}") % { letter: state[:letter] },
        items: review_items(state).map do |item|
          GameSurfaces::ReviewItem.new(
            id: item[:id],
            author: "",
            category: category_label(item[:category]),
            answer: item[:answer],
            status: review_item_status(state, item),
            decision: state[:decisions][item[:id]],
            decision_ids: item[:players].length > 1 ? %w[duplicate incorrect] : %w[unique partial incorrect]
          )
        end,
        decisions: [
          GameSurfaces::ReviewDecision.new(id: "unique", label: _("Unique, 2 points")),
          GameSurfaces::ReviewDecision.new(id: "partial", label: _("Partially correct, 1 point")),
          GameSurfaces::ReviewDecision.new(id: "duplicate", label: _("Identical, 1 point")),
          GameSurfaces::ReviewDecision.new(id: "incorrect", label: _("Incorrect, 0 points"))
        ],
        empty_label: _("There are no non-empty answers to review"),
        submit_label: _("Finish review"),
        read_only: false
      )
    end

    def with_review_commands(surface, state, viewer)
      commands = []
      if owner?(state[:players], viewer) || same_user?(state[:judge], viewer)
        commands << GameSurfaces::Command.new(
          id: "start_review",
          label: _("Begin review without missing answers"),
          enabled: true
        )
      end
      if owner?(state[:players], viewer)
        commands << GameSurfaces::Command.new(
          id: "cancel_round",
          label: _("Cancel the round"),
          enabled: true
        )
      end
      commands.empty? ? surface : composite(surface, "status", commands)
    end

    def with_cancel_command(surface, state, viewer)
      return surface if !owner?(state[:players], viewer)

      composite(
        surface,
        "review",
        [GameSurfaces::Command.new(id: "cancel_round", label: _("Cancel the round"), enabled: true)]
      )
    end

    def composite(surface, id, commands)
      GameSurfaces::CompositeSpec.new(
        parts: [
          GameSurfaces::SurfacePart.new(id: id, surface: surface),
          GameSurfaces::SurfacePart.new(
            id: "commands",
            surface: GameSurfaces::CommandPanelSpec.new(commands: commands)
          )
        ]
      )
    end

    def information_surface(id, message)
      GameSurfaces::QuestionSpec.new(
        id: id,
        prompt: name,
        mode: :information,
        value: message
      )
    end

    def submit_answers(selection, state, actor, context)
      return [:not_your_turn, nil] if state[:phase] != :answering || !includes_player?(state[:active_players], actor)
      return [:already_submitted, nil] if player_hash_key?(state[:commitments], actor)
      return [:invalid, nil] if context == nil || context.hidden_submissions == nil

      source = selection["answers"]
      return [:invalid, nil] if !source.respond_to?(:key?)
      answers = round_category_ids(state).each_with_object({}) do |category, result|
        answer = (source[category] || source[category.to_sym]).to_s.strip
        return [:answer_too_long, nil] if answer.length > ANSWER_MAX_LENGTH
        result[category] = answer
      end
      envelope = context.hidden_submissions.prepare(
        session_id: context.session_id,
        round_id: round_id(state),
        user: actor,
        payload: answers
      )
      [:ok, event_plan("answer_commit", envelope.commitment)]
    rescue HiddenSubmissions::StorageError
      [:local_storage_unavailable, nil]
    end

    def submit_review_change(selection, state, actor)
      return [:not_your_turn, nil] if state[:phase] != :review || !same_user?(state[:judge], actor)
      return [:already_submitted, nil] if state[:review_finished]

      item = review_item_by_id(state, selection["item_id"])
      return [:invalid, nil] if item == nil
      decision = selection["decision"].to_s
      if decision.empty?
        return [:invalid, nil] if !state[:decisions].key?(item[:id])
        return [:ok, event_plan("review_clear", item[:id])]
      end
      return [:invalid, nil] if !REVIEW_DECISIONS.include?(decision)
      return [:invalid, nil] if state[:decisions][item[:id]] == decision

      [:ok, event_plan("review_#{decision}", item[:id])]
    end

    def finish_review(selection, state, actor)
      return [:not_your_turn, nil] if state[:phase] != :review || !same_user?(state[:judge], actor)
      return [:already_submitted, nil] if state[:review_finished]
      source = selection["decisions"]
      return [:invalid, nil] if !source.respond_to?(:key?)

      items = review_items(state)
      expected_ids = items.map { |item| item[:id] }.sort
      supplied_ids = source.keys.map(&:to_s).sort
      return [:invalid, nil] if supplied_ids != expected_ids

      encoded = items.map do |item|
        decision = if source.key?(item[:id])
          source[item[:id]]
        elsif source.key?(item[:id].to_sym)
          source[item[:id].to_sym]
        end
        decision = decision.to_s
        return [:invalid, nil] if !review_decision_allowed?(item, decision)

        REVIEW_DECISION_CODES.fetch(decision)
      end.join

      [:ok, event_plan("review_commit", encoded)]
    end

    def command_action(action, state, actor, context)
      case action
      when "close_answers"
        return [:not_your_turn, nil] if state[:phase] != :answering || !owner?(state[:players], actor)
        [:ok, event_plan("answers_closed", state[:round])]
      when "start_review"
        allowed = owner?(state[:players], actor) || same_user?(state[:judge], actor)
        return [:not_your_turn, nil] if state[:phase] != :revealing || !allowed
        [:ok, event_plan("review_started", state[:round])]
      when "cancel_round"
        return [:not_your_turn, nil] if ![:revealing, :review].include?(state[:phase]) || !owner?(state[:players], actor)
        [:ok, event_plan("round_cancelled", state[:round])]
      else
        [:invalid, nil]
      end
    end

    def automatic_plan(action, selection, state, actor, context)
      case action
      when "start_round"
        return [:not_your_turn, nil] if !owner?(state[:players], actor) || ![:setup, :round_complete].include?(state[:phase])
        available = available_letters(state[:options], state[:used_letters])
        draw = available.length == 1 ? 1 : context.random_source.roll(count: 1, sides: available.length).values.first
        letter = available[draw - 1]
        round = state[:completed_rounds] + 1
        attempt = state[:attempt] + 1
        judge = judge_index(state[:options], state[:players], round, state)
        duration = state[:options]["round_time"].to_i
        deadline = duration > 0 ? context.now.to_i + duration : 0
        categories = draw_categories(state[:options], draw, round)
        value = [attempt, round, judge, letter, deadline, encode_round_categories(categories)].join(",")
        [:ok, event_plan("category_round", value)]
      when "close_answers"
        return [:not_your_turn, nil] if state[:phase] != :answering || !owner?(state[:players], actor)
        return [:invalid, nil] if !commitments_complete?(state) && !closing_deadline_reached?(state, context&.now)
        [:ok, event_plan("answers_closed", state[:round])]
      when "reveal"
        return reveal_plan(selection["envelope"], state, actor, context)
      when "start_review"
        return [:not_your_turn, nil] if state[:phase] != :revealing || !owner?(state[:players], actor)
        return [:invalid, nil] if !reveals_complete?(state)
        [:ok, event_plan("review_started", state[:round])]
      when "score_round"
        return score_round_plan(state, actor)
      else
        [:invalid, nil]
      end
    end

    def reveal_plan(envelope, state, actor, context)
      return [:invalid, nil] if state[:phase] != :revealing || envelope == nil
      return [:invalid, nil] if !same_user?(envelope.user, actor) || envelope.round_id.to_s != round_id(state)
      return [:invalid, nil] if envelope.session_id.to_i != context.session_id.to_i
      commitment = player_hash_value(state[:commitments], actor)
      return [:invalid, nil] if commitment.to_s.empty? || commitment != envelope.commitment || !context.hidden_submissions.verify(envelope)

      events = [EventCommand.new(action: "answer_nonce", value: envelope.nonce)]
      round_category_ids(state).each_with_index do |category, index|
        events << EventCommand.new(action: "answer_#{index}", value: envelope.payload.fetch(category, "").to_s)
      end
      [:ok, ActionPlan.new(events: events)]
    end

    def score_round_plan(state, actor)
      return [:not_your_turn, nil] if state[:phase] != :review || !owner?(state[:players], actor)
      return [:invalid, nil] if !reviews_complete?(state)

      scores = expected_round_scores(state)
      events = state[:active_players].each_with_index.map do |player, index|
        EventCommand.new(action: "round_score", value: "#{index},#{scores.fetch(player)}")
      end
      events << EventCommand.new(action: "round_finished", value: state[:round].to_s)
      [:ok, ActionPlan.new(events: events)]
    end

    def accept_reveal_part(state, actor, part, value, _event, _event_id, _history)
      return false if state[:phase] != :revealing || !player_hash_key?(state[:commitments], actor)
      return false if player_hash_key?(state[:reveals], actor)
      return false if part == :nonce && !/\A[0-9a-f]{64}\z/.match?(value)
      return false if part != :nonce && value.length > ANSWER_MAX_LENGTH

      player = canonical_player(state[:active_players], actor)
      parts = state[:reveal_parts][player] ||= {}
      return false if parts.key?(part)

      parts[part] = value
      categories = round_category_ids(state)
      complete = parts.key?(:nonce) && (0...categories.length).all? { |index| parts.key?(index) }
      if complete
        payload = categories.each_with_index.each_with_object({}) do |(category, index), result|
          result[category] = parts[index]
        end
        commitment = player_hash_value(state[:commitments], player)
        if HiddenSubmissions::Commitment.valid?(payload: payload, nonce: parts[:nonce], commitment: commitment)
          state[:reveals][player] = payload
        end
      end
      true
    end

    def update_match_ending(state, history, event_id)
      target = state[:options]["target_score"].to_i
      contestants = state[:tie_break_players].to_a
      contestants = contestants(state[:players], state[:options]) if contestants.empty?
      highest = contestants.map { |player| player_hash_value(state[:scores], player).to_i }.max.to_i
      cycle = state[:options]["judge_mode"] == JUDGE_ROTATING ? state[:players].length : 1
      if state[:final_end_round] == nil && highest >= target
        state[:final_end_round] = ((state[:completed_rounds] + cycle - 1) / cycle) * cycle
        history << history_entry(
          event_id,
          _("The target score was reached. The final judge cycle has begun."),
          "",
          :final_cycle
        )
      end
      return [nil, false] if state[:final_end_round] == nil || state[:completed_rounds] < state[:final_end_round]

      leaders = score_leaders(state, contestants)
      if leaders.length > 1 && state[:options]["tie_mode"] == TIE_EXTRA_CYCLE
        state[:tie_break_players] = leaders
        outside_judges = state[:players].reject do |player|
          leaders.any? { |leader| same_user?(leader, player) }
        end
        state[:final_end_round] = state[:completed_rounds] + (outside_judges.empty? ? cycle : 1)
        history << history_entry(
          event_id,
          _("The lead is tied. A tie-break will be played only by %{players}; the judge will be selected from the other participants.") % {
            players: leaders.map { |player| participant_name(player) }.join(", ")
          },
          "",
          :tie_cycle
        )
        return [nil, false]
      end

      state[:winners] = leaders
      state[:tie_break_players] = nil
      if leaders.length == 1
        history << history_entry(
          event_id,
          _("%{player} won the game.") % { player: participant_name(leaders.first) },
          leaders.first,
          :result
        )
        [leaders.first, false]
      else
        history << history_entry(
          event_id,
          _("The game ended with a shared victory: %{players}.") % {
            players: leaders.map { |player| participant_name(player) }.join(", ")
          },
          "",
          :result
        )
        [nil, true]
      end
    end

    def review_items(state)
      groups = {}
      state[:active_players].each_with_index do |player, player_index|
        answers = player_hash_value(state[:reveals], player)
        next if !answers.respond_to?(:key?)
        round_category_ids(state).each_with_index do |category, category_index|
          answer = answers[category].to_s.strip
          next if answer.empty?
          group_key = [category, normalize_answer(answer)]
          group = groups[group_key] ||= {
            id: "#{state[:round]}:#{player_index}:#{category_index}",
            players: [],
            category: category,
            answer: answer
          }
          group[:players] << player
        end
      end
      groups.values
    end

    def parse_review_commit(state, value)
      items = review_items(state)
      codes = value.to_s.chars
      return nil if codes.length != items.length

      items.each_with_index.each_with_object({}) do |(item, index), result|
        decision = REVIEW_CODE_DECISIONS[codes[index]]
        return nil if !review_decision_allowed?(item, decision)

        result[item[:id]] = decision
      end
    end

    def review_decision_allowed?(item, decision)
      allowed = item[:players].length > 1 ? %w[duplicate incorrect] : %w[unique partial incorrect]
      allowed.include?(decision.to_s)
    end

    def review_item_by_id(state, id)
      review_items(state).find { |item| item[:id] == id.to_s }
    end

    def review_item_status(state, item)
      decision = state[:decisions][item[:id]]
      return decision_label(decision) if decision != nil

      return nil if item[:players].length <= 1

      _("identical answer from %{count} players") % { count: item[:players].length }
    end

    def review_decision_text(item, decision)
      _("%{players}: %{category}: %{answer}; decision: %{decision}.") % {
        players: review_players_text(item),
        category: category_label(item[:category]),
        answer: item[:answer],
        decision: decision_label(decision)
      }
    end

    def review_change_text(item, previous, decision)
      _("%{players}: %{category}: %{answer}; the judge changed the decision from %{previous} to %{decision}.") % {
        players: review_players_text(item),
        category: category_label(item[:category]),
        answer: item[:answer],
        previous: decision_label(previous),
        decision: decision_label(decision)
      }
    end

    def review_clear_text(item, previous)
      _("%{players}: %{category}: %{answer}; the judge removed the assessment %{previous}.") % {
        players: review_players_text(item),
        category: category_label(item[:category]),
        answer: item[:answer],
        previous: decision_label(previous)
      }
    end

    def review_players_text(item)
      item[:players].map { |player| participant_name(player) }.join(", ")
    end

    def decision_label(decision)
      case decision.to_s
      when "unique" then _("unique, 2 points")
      when "partial" then _("partially correct, 1 point")
      when "duplicate" then _("identical, 1 point")
      when "incorrect" then _("incorrect, 0 points")
      else decision.to_s
      end
    end

    def expected_round_scores(state)
      scores = state[:active_players].each_with_object({}) { |player, result| result[player] = 0 }
      review_items(state).each do |item|
        decision = state[:decisions][item[:id]]
        points = DECISION_POINTS.fetch(decision.to_s, 0)
        item[:players].each { |player| scores[player] += points }
      end
      scores
    end

    def all_reviews_assessed?(state)
      review_items(state).all? { |item| state[:decisions].key?(item[:id]) }
    end

    def reviews_complete?(state)
      state[:review_finished] && all_reviews_assessed?(state)
    end

    def round_scores_complete?(state)
      expected = expected_round_scores(state)
      state[:active_players].all? do |player|
        player_hash_value(state[:round_scores], player).to_i == expected.fetch(player)
      end && state[:round_scores].length == state[:active_players].length
    end

    def commitments_complete?(state)
      state[:active_players].all? { |player| player_hash_key?(state[:commitments], player) }
    end

    def reveals_complete?(state)
      state[:commitments].keys.all? { |player| player_hash_key?(state[:reveals], player) }
    end

    def deadline_reached?(state, now)
      state[:deadline].to_i > 0 && now.to_i >= state[:deadline].to_i
    end

    def closing_deadline_reached?(state, now)
      state[:deadline].to_i > 0 && now.to_i >= state[:deadline].to_i + DEADLINE_SUBMISSION_GRACE
    end

    def contestants(players, options)
      return players.drop(1) if options["judge_mode"] == JUDGE_MASTER

      players.dup
    end

    def contestants_for_round(players, judge, state = nil)
      tied = state == nil ? [] : state[:tie_break_players].to_a
      candidates = tied.empty? ? players : tied
      candidates.reject { |player| same_user?(player, judge) }
    end

    def judge_index(options, players, round, state = nil)
      return 0 if options["judge_mode"] == JUDGE_MASTER

      tied = state == nil ? [] : state[:tie_break_players].to_a
      judges = players.each_index.reject do |index|
        tied.any? { |player| same_user?(player, players[index]) }
      end
      return (round.to_i - 1) % players.length if tied.empty? || judges.empty?

      judges[(round.to_i - 1) % judges.length]
    end

    def available_letters(options, used)
      letters = LANGUAGE_LETTERS.fetch(options["answer_language"].to_s)
      remaining = letters.reject { |letter| used.include?(letter) }
      remaining.empty? ? letters : remaining
    end

    def selected_category_pool(options)
      set = options["category_set"].to_s
      return CATEGORY_SETS.fetch(set) if CATEGORY_SETS.key?(set)
      return [] if set != CATEGORY_SET_CUSTOM

      mask = options["custom_categories"].to_i
      CATEGORY_IDS.each_with_index.filter_map do |category, index|
        category if (mask & (1 << index)) != 0
      end
    end

    def draw_categories(options, random_value, round)
      pool = selected_category_pool(options)
      count = options["round_category_count"].to_i
      seed = random_value.to_i * 1_000_003 + round.to_i * 97 + pool.length
      shuffled = pool.dup
      (shuffled.length - 1).downto(1) do |index|
        seed = (seed * 1_103_515_245 + 12_345) & 0x7fffffff
        selected_index = seed % (index + 1)
        shuffled[index], shuffled[selected_index] = shuffled[selected_index], shuffled[index]
      end
      selected = shuffled.first(count)
      pool.select { |category| selected.include?(category) }
    end

    def valid_round_categories?(categories, options)
      values = categories.to_a
      pool = selected_category_pool(options)
      values.length == options["round_category_count"].to_i && values.uniq.length == values.length &&
        values.all? { |category| pool.include?(category) }
    end

    def encode_round_categories(categories)
      mask = categories.to_a.reduce(0) do |result, category|
        index = CATEGORY_IDS.index(category.to_s)
        raise ArgumentError, "unknown category" if index == nil

        result | (1 << index)
      end
      raise ArgumentError, "empty category selection" if mask == 0

      "#{ROUND_CATEGORY_ENCODING_PREFIX}#{mask.to_s(36)}"
    end

    def decode_round_categories(value)
      text = value.to_s
      return text.split(".") if !text.start_with?(ROUND_CATEGORY_ENCODING_PREFIX)

      encoded = text.delete_prefix(ROUND_CATEGORY_ENCODING_PREFIX)
      return nil if !/\A[0-9a-z]+\z/.match?(encoded)

      mask = Integer(encoded, 36)
      return nil if mask <= 0 || mask >= (1 << CATEGORY_IDS.length)

      CATEGORY_IDS.each_with_index.filter_map do |category, index|
        category if (mask & (1 << index)) != 0
      end
    rescue ArgumentError
      nil
    end

    def round_category_ids(state)
      state[:round_categories].to_a
    end

    def valid_round_letter?(letter, options, used)
      available_letters(options, used).include?(letter)
    end

    def parse_round(value)
      parts = value.to_s.split(",", -1)
      return nil if parts.length != 6 || !/\A[A-Z]\z/.match?(parts[3])

      categories = decode_round_categories(parts[5])
      return nil if categories == nil

      {
        attempt: Integer(parts[0], 10),
        round: Integer(parts[1], 10),
        judge_index: Integer(parts[2], 10),
        letter: parts[3],
        deadline: Integer(parts[4], 10),
        categories: categories
      }
    rescue ArgumentError
      nil
    end

    def parse_score(value)
      parts = value.to_s.split(",", 2)
      return nil if parts.length != 2

      { player_index: Integer(parts[0], 10), points: Integer(parts[1], 10) }
    rescue ArgumentError
      nil
    end

    def category_label(category)
      case category.to_s
      when "country" then _("Country")
      when "city" then _("City")
      when "name" then _("Name")
      when "animal" then _("Animal")
      when "plant" then _("Plant")
      when "thing" then _("Thing")
      when "profession" then _("Profession")
      when "food" then _("Food")
      when "color" then _("Color")
      when "surname" then _("Surname")
      when "famous_person" then _("Famous person")
      when "sport" then _("Sport")
      when "vehicle" then _("Vehicle")
      when "clothing" then _("Clothing item")
      when "body_part" then _("Body part")
      when "building" then _("Building")
      when "musical_instrument" then _("Musical instrument")
      when "book" then _("Book")
      when "film" then _("Film")
      when "song" then _("Song")
      when "music_group" then _("Music group")
      when "river" then p_("categories", "River")
      when "mountain" then _("Mountain")
      when "island" then _("Island")
      when "language" then _("Language")
      when "invention" then _("Invention")
      when "chemical_element" then _("Chemical element")
      else category.to_s
      end
    end

    def category_set_label(set)
      case set.to_s
      when "easy" then _("easy category pool")
      when "medium" then _("medium category pool")
      when "hard" then _("hard category pool")
      when CATEGORY_SET_CUSTOM then _("custom category pool")
      else set.to_s
      end
    end

    def round_status_text(state)
      return _("The first round is being prepared.") if state[:round].to_i <= 0
      time = if state[:phase] == :answering && state[:deadline].to_i > 0
        _("%{seconds} seconds remaining") % { seconds: [state[:deadline] - GameRoomSessionClock.for_state(state).to_i, 0].max }
      else
        phase_label(state[:phase])
      end
      _("Letter %{letter}; judge: %{judge}; %{status}.") % {
        letter: state[:letter],
        judge: participant_name(state[:judge]),
        status: time
      }
    end

    def letter_and_judge_text(state)
      return _("The first round is being prepared.") if state[:round].to_i <= 0

      _("Letter %{letter}; judge: %{judge}.") % {
        letter: state[:letter],
        judge: participant_name(state[:judge])
      }
    end

    def remaining_time_text(state)
      return _("There is no time limit in this game.") if state[:deadline].to_i <= 0
      return _("The answer time has ended.") if state[:phase] != :answering

      _("%{seconds} seconds remaining.") % {
        seconds: [state[:deadline].to_i - GameRoomSessionClock.for_state(state).to_i, 0].max
      }
    end

    def scores_text(state, sorted: false)
      players = contestants(state[:players], state[:options])
      scores = players.to_h { |p| [p, player_hash_value(state[:scores], p).to_i] }
      players = score_announcement_order(players, scores) if sorted
      values = players.map do |player|
        _("%{player}: %{points}") % {
          player: participant_name(player),
          points: player_hash_value(state[:scores], player).to_i
        }
      end
      _("Scores: %{scores}.") % { scores: values.join("; ") }
    end

    def cycle_status_text(state)
      text = _("Round %{round}; completed rounds: %{completed}.") % {
        round: [state[:round].to_i, 1].max,
        completed: state[:completed_rounds]
      }
      if state[:final_end_round] != nil
        text += " " + _("The final cycle ends after round %{round}.") % { round: state[:final_end_round] }
      end
      text
    end

    def status_text(state, viewer)
      return result_text(Replay.new(state: state)) || scores_text(state) if state[:phase] == :finished
      return _("Preparing round %{round}.") % { round: state[:completed_rounds] + 1 } if [:setup, :round_complete].include?(state[:phase])

      round_status_text(state)
    end

    def phase_label(phase)
      case phase
      when :revealing then _("revealing answers")
      when :review then _("reviewing answers")
      when :round_complete then _("round completed")
      when :finished then _("game finished")
      else _("answering")
      end
    end

    def score_leaders(state, candidates)
      maximum = candidates.map { |player| player_hash_value(state[:scores], player).to_i }.max.to_i
      candidates.select { |player| player_hash_value(state[:scores], player).to_i == maximum }
    end

    def required_decision_key(replay, viewer)
      return nil if replay == nil || replay.finished?
      state = replay.state
      if state[:phase] == :answering
        return nil unless includes_player?(state[:active_players], viewer) && !player_hash_key?(state[:commitments], viewer)
        return [:answering, round_id(state)]
      end
      super
    end
    public :required_decision_key

    def current_actor(state)
      return state[:judge] if state[:phase] == :review

      nil
    end

    def round_id(state)
      "round-#{state[:round]}-attempt-#{state[:attempt]}"
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

    def normalize_answer(answer)
      answer.to_s.strip.downcase.gsub(/\s+/, " ")
    end

    def normalize_review_decision(decision, item)
      if decision.to_s == "correct"
        return item != nil && item[:players].length > 1 ? "duplicate" : "unique"
      end

      decision.to_s
    end


  end
end
