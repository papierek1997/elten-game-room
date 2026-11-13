# encoding: UTF-8
module GameRoomGames
  using GameRoomLocalization::Translations
  class CashAuction
    module Actions
      def automatic_action_allowed?(replay, actor, table_owner:)
        !replay.finished? && same_user?(actor, table_owner)
      end

      def automatic_action_due?(replay, actor, context: nil)
        return false if replay.finished? || !same_user?(actor, replay.players.first)
        state, now = replay.state, action_time(replay.state, context)
        case state[:phase]
        when :drawing, :spinning then now >= state.fetch(:resume_at, 0)
        when :auction then now >= state[:auction_deadline]
        when :question_pending then true
        else false
        end
      end

      def automatic_action(replay, actor, context: nil)
        return nil unless automatic_action_due?(replay, actor, context: context)
        action = {drawing: 'wheel', spinning: 'auction_start', auction: 'auction_closed', question_pending: 'question'}[replay.state[:phase]]
        {'kind'=>'automatic', 'action'=>action}
      end

      def action_for(selection, replay, actor, context: nil)
        return [:finished, nil] if replay.finished?
        state, seat = replay.state, player_index(replay.players, actor)
        now = action_time(state, context)
        if selection['kind'] == 'automatic'
          return [:invalid, nil] unless same_user?(actor, replay.players.first) && automatic_action_due?(replay, actor, context: context)
          expected = automatic_action(replay, actor, context: context)['action']
          return [:invalid, nil] unless selection['action'] == expected
          case expected
          when 'wheel' then return [:ok, server_seed_plan('wheel', template: "#{state[:round]+1}|{seed}")]
          when 'auction_start' then return [:ok, event_plan('auction_start', (state[:round]+1).to_s)]
          when 'auction_closed' then return [:ok, event_plan('auction_closed', [state[:round], state[:bid_revision], state[:auction_deadline]].join('|'))]
          when 'question' then return [:ok, server_seed_plan('question', template: "#{state[:round]}|#{state[:bid_revision]}|{seed}")]
          end
        end
        return [:not_your_turn, nil] unless seat
        if selection['action'] == 'open_chest'
          return [:invalid, nil] unless state[:phase] == :opening_chests && state[:chests][seat] > 0 &&
            selection['round'] == state[:round] && selection['remaining'] == state[:chests][seat]
          return [:ok, server_seed_plan('chest', template: "#{state[:round]}|#{seat}|#{state[:chests][seat]}|{seed}")]
        end
        return [:not_your_turn, nil] if state[:eliminated][seat]
        if state[:phase] == :auction
          return [:invalid, nil] unless selection['kind'] == 'question' && selection['question_id'] == auction_id(state)
          return [:invalid, nil] if state[:passed][seat] || now >= state[:auction_deadline]
          if selection['action'] == 'pass'
            return [:invalid, nil] if seat == state[:leader]
            return [:ok, event_plan('pass', state[:round].to_s)]
          end
          return [:invalid, nil] unless selection['action'] == 'submit'
          text = selection['answer'].to_s.strip
          amount = if text.match?(/\Aa\z/i)
            state[:cash][seat] + state[:contributions][seat]
          elsif text.match?(/\A[0-9]{1,8}\z/)
            text.to_i
          end
          return [:invalid_bet, nil] unless amount && amount > state[:highest] && amount <= state[:cash][seat] + state[:contributions][seat]
          return [:ok, event_plan('bid', "#{state[:round]}|#{amount}")]
        end
        if state[:phase] == :answering && seat == state[:leader] && selection['kind'] == 'question' &&
            selection['question_id'] == question_id(state) && selection['action'] == 'submit' && selection['answer'].to_s.match?(/\A[0-3]\z/)
          return [:ok, event_plan('answer', "#{state[:round]}|#{state[:bid_revision]}|#{selection['answer']}")]
        end
        [:invalid, nil]
      end

      def legal_actions(replay, actor, context: nil)
        state, seat = replay.state, player_index(replay.players, actor)
        return [] unless seat && !replay.finished?
        if state[:phase] == :opening_chests && state[:chests][seat] > 0
          return [{'kind'=>'command', 'action'=>'open_chest', 'round'=>state[:round], 'remaining'=>state[:chests][seat]}]
        end
        return [] if state[:eliminated][seat]
        if state[:phase] == :auction && !state[:passed][seat] && action_time(state, context) < state[:auction_deadline]
          base = {'kind'=>'question', 'question_id'=>auction_id(state)}
          actions = seat == state[:leader] ? [] : [base.merge('action'=>'pass')]
          maximum = state[:cash][seat] + state[:contributions][seat]
          amount = [state[:highest] + [state[:options]['ante'], 1].max, maximum].min
          actions << base.merge('action'=>'submit', 'answer'=>amount.to_s) if amount > state[:highest]
          actions << base.merge('action'=>'submit', 'answer'=>'A') if maximum > amount
          return actions
        elsif state[:phase] == :answering && seat == state[:leader]
          return (0..3).map { |index| {'kind'=>'question', 'action'=>'submit', 'question_id'=>question_id(state), 'answer'=>index.to_s} }
        end
        []
      end

      def bot_observation(replay, actor)
        state = replay.state
        {phase: state[:phase], round: state[:round], players: replay.players.map(&:dup),
          seat: player_index(replay.players, actor), cash: state[:cash].dup, pot: state[:pot],
          highest: state[:highest], leader: state[:leader], passed: state[:passed].dup,
          contributions: state[:contributions].dup, eliminated: state[:eliminated].dup,
          chests: state[:chests].dup, question: question_bank(state[:options]).public_view(state[:question])}
      end

      def move_error_for(status, selection: nil, replay: nil, actor: nil)
        return super unless status == :invalid_bet && replay
        seat = player_index(replay.players, actor)
        return super unless seat
        maximum = replay.state[:cash][seat] + replay.state[:contributions][seat]
        return _('You have no points available to raise the bid.') if maximum <= replay.state[:highest]
        _('Enter an amount above %{minimum} and at most %{maximum}, or A for all-in.') % {
          minimum: replay.state[:highest], maximum: maximum}
      end

      def bot_action_score(replay, actor, action, context: nil)
        state, seat = replay.state, player_index(replay.players, actor)
        return 0.0 unless state[:phase] == :auction && action['action'] == 'submit'
        maximum = state[:cash][seat] + state[:contributions][seat]
        amount = action['answer'] == 'A' ? maximum : action['answer'].to_i
        # With no future question, risk only a modest part of the bankroll.
        budget = [maximum / 3, state[:pot] / 2 + state[:options]['ante']].min
        amount <= budget ? 10.0 : -10.0
      end

      private

      def action_time(state, context); (context&.now || GameRoomSessionClock.for_state(state)).to_i; end
    end
    include Actions
  end
end
