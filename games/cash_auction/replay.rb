# encoding: UTF-8
module GameRoomGames
  using GameRoomLocalization::Translations
  class CashAuction
    module ReplayModel
      def replay(session, events, repository)
        input = GameRoomReplayCache::Input.new(session, events, repository)
        options = options_from_json(session['options'])
        error = options_error(options, player_count: input.players.length)
        raise ArgumentError, error if error
        bank = question_bank(options)
        @auction_replay_cache ||= GameRoomReplayCache.new
        state, positions, history = @auction_replay_cache.reduce(input, context: options,
          identities: [GameRoomLocalization.cache_token, GameRoomParticipants.names_revision]) do |checkpoint, prefix|
          initial = R.initial(input.players, options).merge(game_id: input.session['__id'] || input.session['id'],
            seen: {}, used_questions: [], revision: 0, resume_at: 0, time: 0)
          state, positions, history = checkpoint || [initial, [], [starting_history(input.players)]]
          input.events.drop(prefix).each_with_index do |event, offset|
            break if R.finished?(state)
            actor, event_id = input.actor_of(event), input.event_id(event)
            next unless event_id.is_a?(Integer) && event_id.positive?
            next if state[:seen][event_id]
            timestamp = event['created_at']
            next unless GameRoomSessionClock.valid_event_time?(timestamp) && timestamp.positive?
            timestamp = GameRoomSessionClock.from_server(session, timestamp, event: event)
            next if timestamp < state[:time]
            before = {phase: state[:phase], round: state[:round], pot: state[:pot], cash: state[:cash].dup,
              eliminated: state[:eliminated].dup, leader: state[:leader], highest: state[:highest]}
            next unless apply_auction_event(state, event, actor, event_id, timestamp, bank)
            state[:seen][event_id] = true
            state[:revision] += 1
            state[:time] = timestamp
            state[:resume_at] = timestamp + 4 if state[:phase] == :drawing && before[:round] > 0
            positions << prefix + offset
            history.concat(auction_event_history(event, actor, event_id, state, before, bank))
          end
          [state, positions, history]
        end
        GameRoomSessionClock.attach(state, session)
        current = state[:phase] == :answering ? input.players[state[:leader]] : nil
        Replay.new(board: nil, players: input.players, current_player: current, winner: state[:winner], draw: state[:draw],
          state: state, accepted_events: positions.map { |position| input.events.fetch(position) }, history: history)
      end

      private

      def question_bank(options)
        pack = selected_content_pack(options)
        unless @auction_bank_pack.equal?(pack)
          @auction_bank = GameRoomCashAuction::QuestionBank.new(pack)
          @auction_bank_pack = pack
        end
        @auction_bank
      end

      def apply_auction_event(state, event, actor, event_id, now, bank)
        seat = player_index(state[:players], actor)
        return false unless seat
        value = event['value']
        return false unless value.is_a?(String) && value.bytesize <= 128
        return false if %w[wheel question chest].include?(event['action']) && !event['__server_random'].is_a?(Hash)
        round = state[:round]
        case event['action']
        when 'wheel'
          return false unless seat.zero? && state[:phase] == :drawing && now >= state[:resume_at]
          seed = GameRoomServerRandom.text_seed_value(event, template: "#{round+1}|{seed}")
          return false unless seed
          random = Random.new(seed.to_i(16))
          state[:drawn_chest] = random.rand(100) < state[:options]['black_chest_chance']
          state[:drawn_category] = bank.categories.fetch(random.rand(bank.categories.length))
          state[:phase], state[:resume_at] = :spinning, now + 3
          true
        when 'auction_start'
          return false unless seat.zero? && state[:phase] == :spinning && value == (round+1).to_s && now >= state[:resume_at]
          return false unless R.draw!(state, category: state[:drawn_category], chest: state[:drawn_chest], now: now)
          state[:category_label] = bank.category_label(state[:category])
          true
        when 'bid', 'all_in'
          match = /\A#{round}\|([0-9]{1,8})\z/.match(value)
          match && R.bid!(state, seat, match[1].to_i, now: now, revision: event_id, all_in: event['action'] == 'all_in')
        when 'pass'
          value == round.to_s && now < state[:auction_deadline] && R.pass!(state, seat)
        when 'auction_closed'
          value == [round, state[:bid_revision], state[:auction_deadline]].join('|') && seat.zero? && R.award!(state, now: now)
        when 'question'
          return false unless seat.zero? && state[:phase] == :question_pending
          seed = GameRoomServerRandom.text_seed_value(event, template: "#{round}|#{state[:bid_revision]}|{seed}")
          return false unless seed
          question = bank.draw(category: state[:category], seed: seed.to_i(16), used: state[:used_questions])
          return false unless R.start_question!(state, question)
          state[:used_questions] = question[:used].dup
          true
        when 'answer'
          match = /\A#{round}\|#{state[:bid_revision]}\|([0-3])\z/.match(value)
          return false unless state[:phase] == :answering && match
          R.answer!(state, seat, match[1].to_i == state[:question][:correct_index], now: now)
        when 'chest'
          return false unless state[:phase] == :opening_chests && state[:chests][seat] > 0
          seed = GameRoomServerRandom.text_seed_value(event, template: "#{round}|#{seat}|#{state[:chests][seat]}|{seed}")
          return false unless seed
          reward = CHEST_REWARDS.fetch(Random.new(seed.to_i(16)).rand(CHEST_REWARDS.length))
          return false unless R.open_chest!(state, seat, reward, now: now)
          state[:last_chest_reward] = reward
          true
        else false
        end
      end
    end
    include ReplayModel
  end
end
