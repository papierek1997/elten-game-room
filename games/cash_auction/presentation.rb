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
            extra_commands: seat == state[:leader] ? [] : [GameSurfaces::Command.new(id: 'pass', label: _('Pass'), enabled: true)])
        elsif state[:phase] == :answering
          question = state[:question]
          GameSurfaces::QuestionSpec.new(id: question_id(state), mode: :single_choice,
            prompt: question[:prompt], prompt_as_text: true, submit_on_select: true, read_only: seat != state[:leader],
            options: question[:choices].each_with_index.map do |answer, index|
              GameSurfaces::QuestionOption.new(id: index.to_s, label: ('A'.ord + index).chr + '. ' + answer, value: index.to_s)
            end)
        elsif state[:phase] == :opening_chests && seat && state[:chests][seat] > 0
          GameSurfaces::CommandPanelSpec.new(commands: [GameSurfaces::Command.new(id: 'open_chest',
            label: _('Open a black chest'), enabled: true, payload: {'round'=>state[:round], 'remaining'=>state[:chests][seat]})])
        else
          GameSurfaces::QuestionSpec.new(id: "cash-auction:status:#{state[:round]}", mode: :information,
            prompt: _('Cash Auction'), value: status_text(replay, viewer), read_only: true)
        end
      end

      def game_field_header(replay, viewer); status_text(replay, viewer); end

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
        started = state[:auction_deadline] - 3 * interval
        return [] if now >= state[:auction_deadline]
        ordinal = ((now - started) / interval).floor
        return [] unless ordinal.between?(1, 2)
        message = (ordinal == 1 ? _('%{player}, %{amount}, going once.') : _('%{player}, %{amount}, going twice.')) % {
          player: GameRoomParticipants.short_name(replay.players[state[:leader]]), amount: state[:highest]}
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
        when 'answer' then history.any? { |entry| entry.kind == :correct_answer } ? 'replay' : 'quiz_wrong_answer'
        when 'chest' then 'auction_chest'
        end
      end

      def event_speech_tail_sound(event:, before_replay:, after_replay:, viewer:)
        'auction_gavel' if event['action'] == 'all_in' || event['action'] == 'auction_closed' && before_replay&.state&.[](:leader)
      end

      def live_name_protected_texts(event, repository, replay, viewer)
        return [replay.state[:category_label]].compact if event['action'] == 'auction_start'
        return [] unless %w[question answer].include?(event['action'])
        question = replay.state[:question]
        question ? [question[:prompt], *question[:choices]] : []
      end

      private

      def auction_event_history(event, actor, event_id, state, before, bank)
        seat = player_index(state[:players], actor)
        player = participant_name(actor)
        kind = :game
        message = case event['action']
        when 'wheel' then _('The category wheel is spinning.')
        when 'auction_start'
          category = state[:chest] ? _('Black chest') : bank.category_label(state[:category])
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
            text = _('%{player}, %{amount}, for the third time. Sold!') % {
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
          answer = state[:question][:choices][state[:question][:correct_index]]
          if correct
            _('%{player} answered correctly and takes the pool: %{amount}.') % {player: player, amount: before[:pot]}
          else
            _('%{player} answered incorrectly. Correct answer: %{answer}. The pool carries over.') % {player: player, answer: answer}
          end
        when 'chest'
          reward = state[:last_chest_reward]
          if reward == 'bankrupt'
            _('%{player} opens a black chest: bankrupt.') % {player: player}
          else
            _('%{player} opens a black chest: %{amount} points. Balance: %{balance}.') % {player: player, amount: reward, balance: state[:cash][seat]}
          end
        end
        entries = [HistoryEntry.new(key: "cash-auction:#{event_id}", event_id: event_id, actor: actor, kind: kind, text: message)]
        state[:players].each_with_index do |participant, index|
          next unless state[:eliminated][index] && !before[:eliminated][index]
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:eliminated:#{index}", event_id: event_id,
            actor: participant, kind: :game, text: _('%{player} is eliminated.') % {player: participant_name(participant)})
        end
        if state[:phase] == :opening_chests && before[:phase] != :opening_chests
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:chests", event_id: event_id, actor: actor,
            kind: :game, text: _('Open your black chests before the final result.'))
        elsif state[:phase] == :drawing && state[:completed_rounds] >= state[:options]['rounds']
          entries << HistoryEntry.new(key: "cash-auction:#{event_id}:tie", event_id: event_id, actor: actor,
            kind: :game, text: _('The leaders are tied. An extra round will decide the match.'))
        end
        entries
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
            round: state[:round], pool: state[:pot], amount: state[:highest], player: leader}
        when :question_pending, :answering
          _('%{player} answers the question.') % {player: participant_name(replay.players[state[:leader]])}
        when :opening_chests then _('Open your black chests before the final result.')
        end
      end
    end
    include Presentation
  end
end
