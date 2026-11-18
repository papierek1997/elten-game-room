# Frozen producer for the immutable v1/v2/v3 Quiz corpus only. Current local
# simulations and live tables both generate q: questions. Historical tests
# intentionally keep the original event bytes, RNG samples and answer indices.
module GameRoomTest
  module HistoricalQuizQuestionProducer
    private

    def automatic_plan(action, state, actor, context)
      return super unless action == 'start_question'
      return [:not_your_turn, nil] unless state[:phase] == :starting && owner?(state[:players], actor)
      return [:invalid, nil] unless next_question_pause_over?(state, context&.now)

      question = draw_question(state, context)
      return [:invalid, nil] unless question

      deadline = context.now.to_i + state[:options]['answer_time'].to_i
      value = [state[:round], state[:position] + 1, question['id'], deadline].join(',')
      [:ok, event_plan('question', value)]
    end
  end
end
