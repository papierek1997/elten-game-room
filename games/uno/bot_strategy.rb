require_relative '../../lib/own_continuations'
require_relative '../../lib/game_snapshot'

module GameRoomGames
  class Uno
    class BotStrategy < GameRoomBots::HeuristicStrategy
      attr_reader :last_stats

      def choose(actions:, actor:, game:, replay:, **arguments)
        choices = actions.to_a
        @last_stats = {nodes: 0, fast_reaction: true}
        state = replay.state
        urgent = choices.any? { |a| %w[uno catch buzz].include?(a['action']) }
        reactive = state[:current_player] != actor || choices.any? { |a| a['interception'] || a['straight'] }
        if !urgent && !reactive && choices.size > 1 && game.send(:hand_for,state,actor).size <= 10
          limit = state[:options]['interceptions'] ? 32 : 256
          choices, nodes = game.send(:bot_finishing_continuations, replay, actor, choices, limit)
          @last_stats = {nodes: nodes, fast_reaction: false}
        end
        super(actions: choices, actor: actor, game: game, replay: replay, **arguments)
      end
    end

    class BotRepository
      def actor_of(event, _session = nil); event.fetch('actor'); end
      def event_id(event); event.fetch('id'); end
    end

    private

    def bot_finishing_continuations(replay, actor, choices, limit)
      real = replay.state
      player = player_key(real,actor)
      return [choices,0] if real[:pending_draw].positive? || real[:buzzer_active]
      # Foreign card identities, deck order/seed and private proofs are not
      # inputs. Dummy zero cards preserve only public hand lengths; no foreign
      # turn or unknown draw is simulated. Transfers terminate this search.
      state = GameRoomSnapshot.copy(real.reject do |key,_|
        [:hands,:draw_pile,:seed,:challenge_legal].include?(key) || key.to_s.start_with?('private_')
      end)
      state[:hands] = real[:hands].to_h do |owner,hand|
        [owner, owner == player ? hand.dup : Array.new(hand.size,'R0a')]
      end
      state[:draw_pile], state[:seed] = [], nil
      repository = BotRepository.new
      wrap = lambda do |position|
        Replay.new(players:position[:players], current_player:position[:current_player],
          state:position, winner:position[:winner], draw:false, accepted_events:[], history:[])
      end
      allowed = lambda do |position,action|
        next true if action['action'] == 'choose_colour'
        next false unless action['action'] == 'play'
        card = action['card']
        draw_penalty(position,card).zero? && !buzzer?(card) && card_type(card) != 'C' &&
          !(position[:options]['zero_seven'] && [0,7].include?(card_number(card)))
      end
      transition = lambda do |position,action|
        next nil unless allowed.call(position,action)
        child = GameRoomSnapshot.copy(position)
        value = action['action'] == 'choose_colour' ? "#{action['choice']}|0" : "#{action['card']}|#{action['choice']}|0"
        event = {'id'=>1,'actor'=>player,'action'=>action['action'],'value'=>value}
        applied = reduce_event(child,event,{},repository,[])
        applied ? child : nil
      end
      actions_for = lambda do |position|
        next [] unless position[:phase] == :playing && position[:current_player] == player
        legal_actions(wrap.call(position),player).select { |a| allowed.call(position,a) }
      end
      finisher = GameRoomBots::OwnContinuations.new(limit:limit)
      winners = finisher.finishes(state, actions:choices, next_actions:actions_for, transition:transition,
        finished: ->(position) { position[:hands][player].empty? && !position[:pending_finisher] && !colour_choice_pending?(position) },
        key: ->(position) { Marshal.dump(position) })
      [winners.empty? ? choices : winners, finisher.nodes]
    end
  end
end
