require_relative '../../lib/game_reduction'
require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class QuizParty
    module Reduction
      private

      def apply_replay_event(frame, input)
        case input.action
        when "round_draw" then reduce_round_draw(frame, input)
        when "round_category" then reduce_round_category(frame, input)
        when "question" then reduce_question(frame, input)
        when "answer_commit" then reduce_answer_commit(frame, input)
        when "answers_closed" then reduce_answers_closed(frame, input)
        when "answer_nonce" then reduce_answer_nonce(frame, input)
        when "answer_pick" then reduce_answer_pick(frame, input)
        when "question_finished" then reduce_question_finished(frame, input)
        when "tournament_elimination" then reduce_tournament_elimination(frame, input)
        else false
        end
      end

      def reduce_round_draw(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
        parsed = if input.source['__server_random'] || value.include?(',n:')
          parse_seeded_categories(state,input.source)
        else
          parse_round_draw(value)
        end
        drawn = parsed == nil ? nil : categories_by_codes(state, parsed[:categories])
        if state[:phase] == :drawing && owner?(players, actor) && parsed != nil &&
            drawn != nil && drawn.length == round_choice_count(state) &&
            parsed[:round] == state[:completed_rounds] + 1
          state[:choices] = drawn
          state[:phase] = :choosing
          state[:resume_at] = 0
          accepted_event = true
          history << history_entry(
            event_id,
            _("Round %{round}. The drawn categories are: %{categories}.") % {
              round: state[:completed_rounds] + 1,
              categories: drawn.map { |category| category_label(category) }.join("; ")
            },
            actor,
            :round_draw
          )
        end
        accepted_event
      end

      def reduce_round_category(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        accepted_event = false
        parsed = parse_round_category(value)
        expected_round = state[:completed_rounds] + 1
        expected_chooser = players.index(current_chooser(state))
        category = parsed == nil ? nil : category_by_code(state, parsed[:category])
        if state[:phase] == :choosing && parsed != nil && category != nil &&
            state[:choices].include?(category) &&
            parsed[:round] == expected_round && parsed[:attempt] == state[:attempt] + 1 &&
            parsed[:chooser] == expected_chooser && same_user?(players[expected_chooser], actor)
          state[:attempt] = parsed[:attempt]
          state[:round] = parsed[:round]
          state[:category] = category
          state[:position] = 0
          state[:phase] = :starting
          accepted_event = true
          history << history_entry(
            event_id,
            _("Round %{round}. %{player} chose the category %{category}.") % {
              round: state[:round],
              player: participant_name(actor),
              category: category_label(category)
            },
            actor,
            :round_start
          )
        end
        accepted_event
      end

      def reduce_question(frame, input)
        state = frame.state
        players = frame.players
        options = frame.options
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        timestamp = input.timestamp
        accepted_event = false
        parsed = if input.source['__server_random'] || value.match?(/,[nq]:/)
          parse_seeded_question(state,input.source)
        else
          parse_question(value)
        end
        question = parsed == nil ? nil : question_by_id(state, parsed[:question_id])
        if state[:phase] == :starting && owner?(players, actor) && parsed != nil &&
            question != nil && question["category"].to_s == state[:category].to_s &&
            parsed[:round] == state[:round] && parsed[:position] == state[:position] + 1 &&
            drawable_question?(state, parsed[:question_id]) && timestamp != nil
          # The owner enforces the presentation pause before creating this
          # transition. Rechecking it while replaying would be unsafe: the
          # sender's optimistic record and the native LiveSessions record can
          # legitimately receive different wall-clock timestamps. Phase,
          # position and authenticated ownership make the transition valid.
          reset_used_questions(state) if fresh_questions(state).empty?
          state[:position] = parsed[:position]
          state[:question_id] = parsed[:question_id]
          state.delete(:answer_order_seed)
          state[:answer_order_seed] = parsed[:answer_order_seed] if parsed.key?(:answer_order_seed)
          state[:deadline] = timestamp + state[:options]["answer_time"].to_i
          state[:resume_at] = 0
          state[:used_questions] << parsed[:question_id]
          state[:commitments] = {}
          state[:reveals] = {}
          state[:reveal_parts] = {}
          state[:phase] = :answering
          accepted_event = true
          history << history_entry(
            event_id,
            question["prompt"].to_s,
            actor,
            :question
          )
        end
        accepted_event
      end

      def reduce_answer_commit(frame, input)
        state = frame.state
        players = frame.players
        actor = input.actor
        value = input.value
        timestamp = input.timestamp
        accepted_event = false
        commitment = decode_answer_value(state, value, digest: true)
        if state[:phase] == :answering && includes_player?(tournament_remaining_players(state), actor) &&
            !player_hash_key?(state[:commitments], actor) && commitment != nil &&
            timestamp != nil && !closing_deadline_reached?(state, timestamp)
          state[:commitments][canonical_player(players, actor)] = commitment
          accepted_event = true
        end
        accepted_event
      end

      def reduce_answers_closed(frame, input)
        state = frame.state
        players = frame.players
        actor = input.actor
        value = input.value
        timestamp = input.timestamp
        accepted_event = false
        if state[:phase] == :answering && owner?(players, actor) && value == question_key(state) &&
            answers_may_close?(state, timestamp)
          state[:phase] = :revealing
          accepted_event = true
        end
        accepted_event
      end

      def reduce_answer_nonce(frame, input)
        state = frame.state
        players = frame.players
        actor = input.actor
        value = input.value
        accepted_event = false
        accepted_event = accept_reveal_part(state, players, actor, :nonce, value)
        accepted_event
      end

      def reduce_answer_pick(frame, input)
        state = frame.state
        players = frame.players
        actor = input.actor
        value = input.value
        accepted_event = false
        accepted_event = accept_reveal_part(state, players, actor, :answer, value)
        accepted_event
      end

      def reduce_question_finished(frame, input)
        state = frame.state
        players = frame.players
        history = frame.history
        actor = input.actor
        event_id = input.id
        value = input.value
        timestamp = input.timestamp
        accepted_event = false
        parsed = parse_question_result(value)
        if state[:phase] == :revealing && owner?(players, actor) && parsed != nil &&
            parsed[:round] == state[:round] && parsed[:position] == state[:position] &&
            parsed[:mask] == expected_score_mask(state) && question_may_finish?(state, timestamp)
          accepted_event = true
          history.concat(question_result_history(state, event_id, actor))
          HiddenSubmissions::Cleanup.confirm(state, question_key(state), state[:commitments])
          apply_question_scores(state, parsed[:mask])
          if state[:position] >= QUESTIONS_PER_ROUND
            advance_tournament_chooser(state)
            state[:completed_rounds] += 1
            remember_tournament_checkpoint(state, event_id:event_id, index:state[:completed_rounds])
            state[:phase] = :drawing
            state[:choices] = []
            history << history_entry(
              event_id,
              _("Round %{round} ended. %{scores}") % {
                round: state[:completed_rounds],
                scores: scores_text(state)
              },
              actor,
              :round_end
            )
            frame.winner, frame.draw = update_match_ending(state, history, event_id)
            state[:phase] = :finished if frame.winner != nil || frame.draw
            state[:resume_at] = timestamp.to_i + NEXT_ROUND_PAUSE if state[:phase] == :drawing
          else
            state[:phase] = :starting
            state[:resume_at] = timestamp.to_i + NEXT_QUESTION_PAUSE
          end
        end
        accepted_event
      end

      def reduce_tournament_elimination(frame, input)
        state = frame.state
        departed = tournament_elimination_players(input.source, players:frame.players)
        active = tournament_remaining_players(state)
        return false unless departed && %i[drawing choosing starting answering revealing].include?(state[:phase]) &&
          (departed - active).empty? && (active - departed).length >= 2

        # Keep the current chooser through a round already in progress. At its
        # end, advance once in the original seat order, skipping removed seats.
        state[:category_chooser] ||= current_chooser(state)
        (state[:tournament_eliminations] ||= []) << departed
        if %i[drawing choosing].include?(state[:phase]) && departed.include?(state[:category_chooser])
          advance_tournament_chooser(state)
        end
        if %i[answering revealing].include?(state[:phase])
          HiddenSubmissions::Cleanup.confirm(state, question_key(state), state[:commitments].select do |player, _|
            includes_player?(departed, player)
          end)
          %i[commitments reveals reveal_parts].each do |key|
            state[key].delete_if { |player, _| includes_player?(departed, player) }
          end
        end
        departed.each do |player|
          frame.history << history_entry(input.id,
            _("%{player} left this game.") % {player: participant_name(player)}, player, :departure)
        end
        true
      end
    end
    include Reduction
  end
end
