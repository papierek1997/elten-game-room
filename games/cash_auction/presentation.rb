# encoding: UTF-8
module GameRoomGames
  using GameRoomLocalization::Translations
  class CashAuction
    module Presentation
      def surface_spec(replay, viewer)
        state, seat = replay.state, player_index(replay.players, viewer)
        if state[:phase] == :auction && seat && !state[:eliminated][seat] && !state[:passed][seat]
          GameSurfaces::QuestionSpec.new(id: auction_id(state), mode: :text,
            prompt: _('Bid amount; type A for all-in and press Enter'),
            show_submit_button: false, clear_on_submit: true, max_length: 8,
            text_shortcuts: custom_game_shortcuts(replay, viewer).map { |shortcut| [shortcut.key, shortcut.modifiers] })
        elsif state[:phase] == :answering
          question = state[:question]
          GameSurfaces::QuestionSpec.new(id: question_id(state), mode: :single_choice,
            prompt: question[:prompt], prompt_as_text: true, submit_on_select: true, read_only: seat != state[:leader],
            extra_commands: R.revised?(state) && seat == state[:leader] && !state[:hint_used] && state[:cash][seat] >= R.hint_price(state) ?
              [GameSurfaces::Command.new(id: 'hint', label: _('Remove two wrong answers for %{price} points') % {price: R.hint_price(state)}, enabled: true)] : [],
            options: question[:choices].each_with_index.filter_map do |answer, index|
              next if state.fetch(:hidden_answers, []).include?(index)
              GameSurfaces::QuestionOption.new(id: index.to_s, label: ('A'.ord + index).chr + '. ' + answer, value: index.to_s)
            end)
        elsif state[:phase] == :opening_chests && !R.percentage_chests?(state) && seat && state[:chests][seat] > 0
          GameSurfaces::CommandPanelSpec.new(commands: [GameSurfaces::Command.new(id: 'open_chest',
            label: _('Open a black chest'), enabled: true, payload: {'round'=>state[:round], 'remaining'=>state[:chests][seat]})])
        else
          GameSurfaces::QuestionSpec.new(id: "cash-auction:status:#{state[:round]}", mode: :information,
            prompt: _('Cash Auction'), value: status_text(replay, viewer), read_only: true)
        end
      end

      def game_field_header(replay, viewer); status_text(replay, viewer); end

      def custom_game_shortcuts(replay, viewer)
        state = replay.state
        seat = player_index(replay.players, viewer)
        scores = shortcut_feature_data(:scores, replay, viewer)[:message]
        own = seat ? points_text(replay, [seat]) : _('You are observing this game.')
        others = points_text(replay, replay.players.each_index.reject { |index| index == seat })
        [
          ['s', state[:phase] == :auction ? [:shift] : [], _('read the scores'), scores],
          ['p', [], _('read the pool'), _('Pool: %{points}.') % {points: state[:pot]}],
          ['t', [], _('read whose turn it is'), auction_turn_text(replay, viewer)],
          ['h', [], _('read the current bids'), bidding_text(replay)],
          ['d', [], _('read your points'), own],
          ['d', [:shift], _('read the other players’ points'), others]
        ].map do |key, modifiers, label, message|
          GameShortcut.new(key: key, modifiers: modifiers, label: label, kind: :announcement, message: message)
        end
      end

      def shortcut_feature_data(feature, replay, viewer)
        return super unless feature.to_sym == :scores
        {message: replay.players.each_with_index.map do |player, seat|
          _('%{player}: points: %{points}; black chests: %{chests}') % {
            player: participant_name(player), points: replay.state[:cash][seat], chests: replay.state[:chests][seat]}
        end.join('; ')}
      end

      def timer_announcements(replay, viewer, now: nil)
        state = replay.state
        return [] unless state[:phase] == :auction && state[:leader]
        now ||= GameRoomSessionClock.for_state(state)
        interval = state[:options]['count_interval']
        started = state[:auction_deadline] - R.auction_duration(state)
        return [] if now >= state[:auction_deadline]
        ordinal = ((now - started) / interval).floor
        return [] unless ordinal.between?(1, R.revised?(state) ? 3 : 2)
        template = case ordinal
        when 1 then _('%{player}, %{amount}, going once.')
        when 2 then _('%{player}, %{amount}, going twice.')
        else _('%{player}, %{amount}, going three times.')
        end
        message = template % {
          player: GameRoomParticipants.display_name(replay.players[state[:leader]]), amount: state[:highest]}
        [["cash-auction:#{state[:game_id]}:#{state[:round]}:#{state[:bid_revision]}:#{ordinal}", message,
          ordinal == 1 ? 'auction_call_low' : 'auction_call_high', :skip_on_reconstruction]]
      end

      def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
        case event['action']
        when 'wheel' then 'roulette_spin'
        when 'auction_start' then 'roulette_chips'
        when 'bid', 'all_in'
          seat = after_replay.state[:leader]
          seat && after_replay.state[:cash][seat].zero? ? 'poker_all_in' : 'poker_raise'
        when 'pass' then 'poker_fold'
        when 'question' then 'draw'
        when 'hint' then 'roulette_chips'
        when 'answer' then history.any? { |entry| entry.kind == :correct_answer } ? 'replay' : 'quiz_wrong_answer'
        when 'chest' then 'auction_chest'
        when 'open_chests'
          'auction_chest' if history.any? { |entry| entry.kind == :chests_opening }
        end
      end

      def event_speech_tail_sound(event:, before_replay:, after_replay:, viewer:)
        'auction_gavel' if event['action'] == 'all_in' || event['action'] == 'auction_closed' && before_replay&.state&.[](:leader)
      end

      def event_presentation_stages(event, repository, _before, after, viewer)
        unless event['action'] == 'open_chests'
          return [{descriptions: describe_event_for_display(event, repository, after, viewer), wait_for_sounds: false}]
        end
        entries = after.history.select { |entry| entry.event_id == repository.event_id(event) }
        introduction, rewards = entries.partition { |entry| entry.kind == :chests_opening }
        result, rewards = rewards.partition { |entry| entry.key.to_s.end_with?(':tie') }
        [{history: [], descriptions: introduction.map(&:text), delay: 1.0},
         {history: introduction, descriptions: [], wait_for_sounds: true},
         {history: rewards, descriptions: rewards.map(&:text), delay: 4.0},
         {history: result, descriptions: result.map(&:text)}]
      end

      private

      def points_text(replay, seats)
        seats.map do |seat|
          count = replay.state[:cash][seat]
          points = n_('%{count} point', '%{count} points', count) % {count: count}
          "#{participant_name(replay.players[seat])}: #{points}"
        end.join('; ')
      end

      def auction_turn_text(replay, viewer)
        return _('All eligible players may bid now.') if replay.state[:phase] == :auction

        status_text(replay, viewer)
      end

      def bidding_text(replay)
        state = replay.state
        return _('There is no auction in progress.') unless state[:phase] == :auction

        replay.players.each_with_index.map do |player, seat|
          status = if state[:eliminated][seat]
            _('eliminated')
          elsif state[:passed][seat]
            _('passed')
          elsif state[:leader] == seat
            _('highest bid: %{amount}') % {amount: state[:highest]}
          elsif state[:contributions][seat].positive?
            _('bid: %{amount}') % {amount: state[:contributions][seat]}
          else
            _('no bid yet')
          end
          '%{player}: %{status}' % {player: participant_name(player), status: status}
        end.join('; ')
      end

      def auction_answer_text(state, player, correct, pot)
        answer = state[:question][:choices][state[:question][:correct_index]]
        if correct
          template = R.revised?(state) ? _('%{player} answered correctly: %{answer}. Pool won: %{amount}.') :
            _('%{player} answered correctly and takes the pool: %{amount}.')
          template % {player: player, answer: answer, amount: pot}
        else
          _('%{player} answered incorrectly. Correct answer: %{answer}. The pool carries over.') % {player: player, answer: answer}
        end
      end

      def auction_event_history(event, actor, event_id, state, before, bank)
        seat = player_index(state[:players], actor)
        player = participant_name(actor)
        kind = :game
        message = case event['action']
        when 'wheel' then _('The category wheel is spinning.')
        when 'auction_start'
          category = state[:chest] ? _('Black chest') : bank.category_label(state[:category], include_set: true)
          if state[:phase] == :auction
            _('Category: %{category}. Each remaining player pays an ante of %{ante}. Start!') % {category: category, ante: state[:options]['ante']}
          else
            _('Category: %{category}. The ante eliminates the players who cannot pay.') % {category: category}
          end
        when 'bid'
          _('%{player} bids %{amount}.') % {player: player, amount: state[:highest]}
        when 'all_in'
          _('%{player} goes all-in for %{amount} and wins the auction.') % {player: player, amount: state[:highest]}
        when 'pass'
          text = p_('Bidding', '%{player} passes.') % {player: player}
          penalty = before[:cash][seat] - state[:cash][seat]
          text += ' ' + _('Pass penalty paid into the pool: %{amount}.') % {amount: penalty} if penalty > 0
          text
        when 'auction_closed'
          if before[:leader]
            text = (R.revised?(state) ? _('Sold to %{player} for %{amount}.') : _('%{player}, %{amount}, for the third time. Sold!')) % {
              player: participant_name(state[:players][before[:leader]]), amount: before[:highest]}
            text
          else
            _('No bid was made. The pool carries over to the next round.')
          end
        when 'question'
          kind = :question
          question = state[:question]
          ([question[:prompt]] + question[:choices].each_with_index.map { |choice, index| ('A'.ord+index).chr + '. ' + choice }).join("\n")
        when 'answer'
          correct = event['value'].split('|').last.to_i == state[:question][:correct_index]
          kind = correct ? :correct_answer : :wrong_answer
          auction_answer_text(state, player, correct, before[:pot])
        when 'hint'
          _('%{player} buys a hint for %{price} points. Two wrong answers are removed.') % {player: player, price: before[:cash][seat] - state[:cash][seat]}
        when 'open_chests' then _('Opening the black chests!')
        when 'chest'
          reward = state[:last_chest_reward]
          if R.revised?(state)
            _('%{player} opens a black chest: an additional prize of %{amount}.') % {player: player, amount: reward}
          elsif reward == 'bankrupt'
            _('%{player} opens a black chest: bankrupt.') % {player: player}
          else
            _('%{player} opens a black chest: %{amount} points. Balance: %{balance}.') % {player: player, amount: reward, balance: state[:cash][seat]}
          end
        end
        entries = [HistoryEntry.new(key: "cash-auction:#{event_id}", event_id: event_id, actor: actor, kind: kind, text: message)]
        if R.revised?(state) && %w[all_in auction_closed].include?(event['action'])
          state[:round_penalties].each_with_index do |penalty, index|
            next unless penalty.positive?
            participant = state[:players][index]
            entries << HistoryEntry.new(key: "cash-auction:#{event_id}:inactivity:#{index}", event_id: event_id,
              actor: participant, kind: :game,
              text: (R.question_pool_auction?(state) ?
                _('%{player} made no bid in three consecutive auctions and pays %{amount} into the pool.') :
                _('%{player} made no bid in three consecutive auctions and loses %{amount} points.')) % {
                player: participant_name(participant), amount: penalty})
          end
        end
        state[:players].each_with_index do |participant, index|
          next unless state[:eliminated][index] && !before[:eliminated][index]
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:eliminated:#{index}", event_id: event_id,
            actor: participant, kind: :game, text: _('%{player} is eliminated.') % {player: participant_name(participant)})
        end
        append_chest_history(entries, state, event_id) if event['action'] == 'open_chests'
        if state[:phase] == :opening_chests && before[:phase] != :opening_chests && !R.percentage_chests?(state)
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:chests", event_id: event_id, actor: actor,
            kind: :game, text: _('Open your black chests before the final result.'))
        elsif state[:phase] == :drawing && (R.revised?(state) ? state[:question_target] != before[:question_target] : state[:completed_rounds] >= state[:options]['rounds'])
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:tie", event_id: event_id, actor: actor,
            kind: :game, text: _('The leaders are tied. An extra round will decide the match.'))
        end
        entries
      end

      def append_chest_history(entries, state, event_id)
        entries.first.kind = :chests_opening
        state[:last_chest_rewards].each_with_index do |(index, reward), number|
          participant = state[:players][index]
          text = reward.zero? ? _('%{player} opens a black chest: no change.') % {player: participant_name(participant)} :
            _('%{player} opens a black chest: %{percent}.') % {
              player: participant_name(participant), percent: format('%+d%%', reward)}
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:chest:#{number}", event_id: event_id,
            actor: participant, kind: :game, text: text)
        end
        state[:players].each_with_index do |participant, index|
          next if state[:chest_percentages][index].zero?
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:chest-balance:#{index}", event_id: event_id,
            actor: participant, kind: :game, text: _('%{player}: %{balance} points after opening the chests.') % {
              player: participant_name(participant), balance: state[:cash][index]})
        end
      end

      def auction_id(state); "cash-auction:#{state[:game_id]}:bid:#{state[:round]}"; end
      def question_id(state); "cash-auction:#{state[:game_id]}:answer:#{state[:round]}:#{state[:question][:question_id]}"; end

      def status_text(replay, viewer)
        state = replay.state
        return result_text(replay) if replay.finished?
        case state[:phase]
        when :drawing, :spinning then _('The category wheel is spinning.')
        when :auction
          leader = state[:leader] ? participant_name(replay.players[state[:leader]]) : _('No bids yet')
          _('Round %{round}; pool: %{pool}; highest bid: %{amount}; leader: %{player}.') % {
            round: R.revised?(state) ? state[:completed_rounds] + 1 : state[:round],
            pool: state[:pot], amount: state[:highest], player: leader}
        when :question_pending, :answering
          _('%{player} answers the question.') % {player: participant_name(replay.players[state[:leader]])}
        when :opening_chests then R.percentage_chests?(state) ? _('Black chests') : _('Open your black chests before the final result.')
        end
      end
    end
    include Presentation
  end
end
