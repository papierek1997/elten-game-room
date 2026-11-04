require_relative '../../lib/game_reduction'
require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Categories
    module Reduction
      private

      def apply_replay_event(frame, input)
        case input.action
        when "category_round" then reduce_category_round(frame, input)
        when "answer_commit" then reduce_answer_commit(frame, input)
        when "answers_closed" then reduce_answers_closed(frame, input)
        when "answer_nonce" then reduce_answer_nonce(frame, input)
        when /\Aanswer_(\d+)\z/ then reduce_answer_field(frame, input)
        when "review_started" then reduce_review_started(frame, input)
        when "review_correct", "review_incorrect", "review_unique", "review_partial", "review_duplicate" then reduce_review_correct(frame, input)
        when "review_clear" then reduce_review_clear(frame, input)
        when "review_finished" then reduce_review_finished(frame, input)
        when "review_commit" then reduce_review_commit(frame, input)
        when "round_score" then reduce_round_score(frame, input)
        when "round_finished" then reduce_round_finished(frame, input)
        when "round_cancelled" then reduce_round_cancelled(frame, input)
        when "participants_departed" then reduce_participants_departed(frame, input)
        when "tournament_elimination" then reduce_tournament_elimination(frame, input)
        else false
        end
      end

      def reduce_category_round(frame, input)
        state = frame.state
        players = frame.players
        options = frame.options
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
        parsed = if input.source['__server_random'] || value.include?(',n:')
          parse_seeded_round(state,input.source)
        else
          parse_round(value)
        end
        expected_round = state[:completed_rounds] + 1
        expected_attempt = state[:attempt] + 1
        expected_judge = judge_index(options, players, expected_round, state)
        if owner?(players, actor) && [:setup, :round_complete].include?(state[:phase]) &&
            parsed != nil && parsed[:round] == expected_round && parsed[:attempt] == expected_attempt &&
            parsed[:judge_index] == expected_judge && valid_round_letters?(parsed, options, state[:used_letters]) &&
            valid_round_categories?(parsed[:categories], options)
          state[:attempt] = parsed[:attempt]
          state[:round] = parsed[:round]
          state[:judge] = options["judge_mode"] == JUDGE_MASTER ? state[:permanent_judge] : players[parsed[:judge_index]]
          state[:letter] = parsed[:letter]
          state[:round_categories] = parsed[:categories]
          state[:category_letters] = options['separate_letters'] ? parsed[:categories].zip(parsed[:letters]).to_h : {}
          state[:deadline] = parsed[:deadline]
          state[:resume_at] = 0
          state[:active_players] = contestants_for_round(players, state[:judge], state)
          state[:round_player_order] = state[:active_players].dup
          state[:judge_queue] = remaining_players(state) if state[:judge_queue].empty?
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
            options['separate_letters'] ? _("Round %{round} started.") % { round: state[:round] } :
              _("Round %{round} started. Letter: %{letter}.") % { round: state[:round], letter: state[:letter] },
            actor,
            :round_start
          )
          history << history_entry(
            event_id,
            _("Categories: %{categories}.") % {
              categories: state[:round_categories].map { |category| round_category_label(state, category) }.join(", ")
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
        accepted_event
      end

      def reduce_answer_commit(frame, input)
        state = frame.state
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
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
        accepted_event
      end

      def reduce_answers_closed(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        accepted_event = false
        if state[:phase] == :answering && owner?(players, actor)
          state[:phase] = :revealing
          accepted_event = true
          history << history_entry(event_id, _("Answering has closed."), actor, :answers_closed)
        end
        accepted_event
      end

      def reduce_answer_nonce(frame, input)
        state = frame.state
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        event = input.source
        accepted_event = false
        accepted_event = accept_reveal_part(state, actor, :nonce, value, event, event_id, history)
        accepted_event
      end

      def reduce_answer_field(frame, input)
        state = frame.state
        history = frame.history
        action = input.action
        actor = input.actor
        event_id = input.id
        value = input.value
        event = input.source
        accepted_event = false
        category_index = action.delete_prefix("answer_").to_i
        if category_index.between?(0, round_category_ids(state).length - 1)
          accepted_event = accept_reveal_part(state, actor, category_index, value, event, event_id, history)
        end
        accepted_event
      end

      def reduce_review_started(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        accepted_event = false
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
        accepted_event
      end

      def reduce_review_correct(frame, input)
        state = frame.state
        history = frame.history
        action = input.action
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
        item = review_item_by_id(state, value)
        decision = normalize_review_decision(action.sub("review_", ""), item)
        if state[:phase] == :review && reviewing_actor?(state, actor, input.source["__authority_user"]) && item != nil &&
            review_decision_allowed?(item, decision) && state[:decisions][item[:id]] != decision &&
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
        accepted_event
      end

      def reduce_review_clear(frame, input)
        state = frame.state
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
        item = review_item_by_id(state, value)
        if state[:phase] == :review && reviewing_actor?(state, actor, input.source["__authority_user"]) && item != nil &&
            state[:decisions].key?(item[:id]) && !state[:review_finished]
          previous = state[:decisions].delete(item[:id])
          accepted_event = true
          history << history_entry(event_id, review_clear_text(item, previous), actor, :review)
        end
        accepted_event
      end

      def reduce_review_finished(frame, input)
        state = frame.state
        history = frame.history
        actor = input.actor
        event_id = input.id
        accepted_event = false
        if state[:phase] == :review && reviewing_actor?(state, actor, input.source["__authority_user"]) &&
            all_reviews_assessed?(state) && !state[:review_finished]
          state[:review_finished] = true
          accepted_event = true
          history << history_entry(event_id, _("The judge finished reviewing the answers."), actor, :review_end)
        end
        accepted_event
      end

      def reduce_review_commit(frame, input)
        state = frame.state
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
        decisions = parse_review_commit(state, value)
        if state[:phase] == :review && reviewing_actor?(state, actor, input.source["__authority_user"]) && decisions != nil &&
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
        accepted_event
      end

      def reduce_round_score(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
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
        accepted_event
      end

      def reduce_round_finished(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        accepted_event = false
        if state[:phase] == :review && owner?(players, actor) && round_scores_complete?(state)
          HiddenSubmissions::Cleanup.confirm(state, round_id(state), state[:commitments])
          state[:completed_rounds] += 1
          remember_tournament_checkpoint(state, event_id:event_id, index:state[:completed_rounds])
          state[:judge_queue].delete(state[:judge])
          state[:phase] = :round_complete
          state[:resume_at] = input.timestamp.to_i + NEXT_ROUND_PAUSE
          accepted_event = true
          history << history_entry(
            event_id,
            _("Round %{round} ended.") % { round: state[:completed_rounds] },
            actor,
            :round_end
          )
          frame.winner, frame.draw = update_match_ending(state, history, event_id)
          state[:phase] = :finished if frame.winner != nil || frame.draw
          if state[:phase] == :finished
            history << history_entry(event_id, scores_text(state, sorted: true), actor, :final_scores)
          end
        end
        accepted_event
      end

      def reduce_round_cancelled(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        accepted_event = false
        if [:revealing, :review].include?(state[:phase]) && owner?(players, actor)
          HiddenSubmissions::Cleanup.confirm(state, round_id(state), state[:commitments])
          rollback_incomplete_scores(state)
          state[:phase] = :round_complete
          accepted_event = true
          history << history_entry(
            event_id,
            _("The round was cancelled. The judge order did not advance."),
            actor,
            :round_cancelled
          )
        end
        accepted_event
      end
    end
    include Reduction
  end
end
