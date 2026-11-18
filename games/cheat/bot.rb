module GameRoomGames
  class Cheat
    class Strategy
      include GameRoomBots::ReplayOnlyStrategy

      def choose(actions:, observation:, actor:, random_source:)
        return nil if actions.empty?
        if observation['phase'] == 'reaction'
          matching = observation['hand'].count { |card| card[observation['variant'] == 'suit' ? 1 : 0] == observation['claim'] }
          remaining = observation['variant'] == 'suit' ? 13 : 4
          suspicion = matching + observation['packet_size'] > remaining ? 100 :
            12 + matching * 17 + (observation['packet_size'] - 1) * 12
          suspicion += 30 if observation['author_count'] == 0
          action = random_source.roll(count: 1, sides: 100).values.first <= suspicion ? 'challenge' : 'accept'
          return actions.find { |candidate| candidate['action'] == action }
        end
        plays = actions.select { |candidate| candidate['action'] == 'play' }
        pass = actions.find { |candidate| candidate['action'] == 'pass' }
        truthful = plays.select do |candidate|
          JSON.parse(candidate['cards']).all? { |card| card[observation['variant'] == 'suit' ? 1 : 0] == candidate['choice'] }
        end
        roll = random_source.roll(count: 1, sides: 100).values.first
        return pass if pass && truthful.empty? && observation['pile_count'] >= 8 && roll <= 40
        pool = !truthful.empty? && roll <= 75 ? truthful : plays
        maximum = pool.map { |candidate| JSON.parse(candidate['cards']).length }.max
        GameRoomBots.random_choice(pool.select { |candidate| JSON.parse(candidate['cards']).length == maximum }, random_source)
      end
    end

    def bot_strategy
      @bot_strategy ||= Strategy.new
    end

    def bot_observation(replay, actor)
      state = replay.state
      packet = state[:last_packet]
      {'phase' => state[:phase].to_s, 'variant' => state[:options]['variant'],
       'hand' => hand_for(state, actor).to_a.dup, 'counts' => state[:players].map { |player| state[:hands].fetch(player).length },
       'claim' => state[:last_claim], 'packet_size' => state[:phase] == :reaction ? packet[:cards].length : 0,
       'author_count' => packet ? state[:hands].fetch(packet[:actor]).length : nil,
       'pile_count' => state[:pile].length, 'revealed' => state[:revealed].keys.sort,
       'passed_seats' => state[:passed].map { |player| state[:players].index(player) }}
    end

    def legal_actions(replay, actor, context: nil)
      state = replay.state
      return [] if replay.finished? || !same_user?(state[:current_player], actor)
      base = {'boundary' => state[:sequence].to_s(36)}
      if state[:phase] == :reaction
        return %w[challenge accept].map { |action| base.merge('kind' => 'command', 'action' => action, 'packet' => state[:last_packet][:id].to_s(36)) }
      end
      return [] unless state[:phase] == :playing
      hand = hand_for(state, actor)
      maximum = state[:options]['variant'] == 'suit' ? 1 : 4
      actions = allowed_claims(state).flat_map do |claim|
        matching = hand.select { |card| matches_claim?(card, claim, state[:options]['variant']) }
        packets = hand.map { |card| [card] } + [hand.first(maximum), hand.last(maximum)]
        1.upto([maximum, matching.length].min) { |count| packets << matching.first(count) }
        packets.reject(&:empty?).uniq.map do |cards|
          base.merge('kind' => 'card_packet', 'action' => 'play', 'cards' => JSON.generate(cards), 'choice' => claim)
        end
      end
      if state[:options]['variant'] == 'fixed_bluff' && !state[:pile].empty?
        actions << base.merge('kind' => 'command', 'action' => 'pass')
      end
      actions
    end
  end
end
