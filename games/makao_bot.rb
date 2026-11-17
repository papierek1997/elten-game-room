require_relative '../lib/own_continuations'
require_relative '../lib/game_snapshot'

module GameRoomGames
  class Makao
    class BotStrategy < GameRoomBots::HeuristicStrategy
      def choose(actions:,actor:,game:,replay:,**arguments)
        choices = actions.to_a
        if choices.size>1 && choices.none? { |a| %w[catch makao].include?(a['action']) } &&
            game.send(:hand_for,replay.state,actor).size<=9
          proved = game.send(:bot_own_finishes,replay,actor,choices)
          choices = proved unless proved.empty?
        end
        super(actions:choices,actor:actor,game:game,replay:replay,**arguments)
      end
    end

    private

    def bot_own_finishes(replay,actor,actions)
      real = replay.state
      player = player_key(real,actor)
      return [] unless same_user?(real[:current_player],player)
      # A known waiting turn may return play to us. A pending draw/skip
      # defence belongs to an opponent and stops the proof, even if our attack
      # looks strong. No hand transfer or unknown draw is predicted.
      state = GameRoomSnapshot.copy(real.reject do |key,_|
        [:hands,:draw_pile,:seed].include?(key) || key.to_s.start_with?('private_')
      end)
      state[:hands] = real[:hands].to_h { |owner,hand|[owner,owner==player ? hand.dup : Array.new(hand.size,'5C')] }
      state[:draw_pile] = []
      repository = Object.new
      def repository.event_id(event); event['id']; end
      wrap = ->(p) { Replay.new(players:p[:players],current_player:p[:current_player],state:p,history:[],accepted_events:[]) }
      available = lambda do |p|
        next [] unless p[:phase]==:playing && same_user?(p[:current_player],player) &&
          p[:draw_penalty].to_i.zero? && p[:skip_penalty].to_i.zero?
        legal_actions(wrap.call(p),player).select { |a|a['action']=='play' }
      end
      transition = lambda do |p,a|
        next nil unless a['action']=='play'
        cards = JSON.parse(a['cards'])
        next nil unless cards.is_a?(Array) && !cards.empty?
        child = GameRoomSnapshot.copy(p)
        event = {'id'=>1,'value'=>"#{cards.join(',')}|#{a['choice']}"}
        apply_play(child,event,player,repository,[]) ? child : nil
      end
      GameRoomBots::OwnContinuations.new(limit:128).finishes(state,actions:actions,
        next_actions:available,transition:transition,key:->(p) { Marshal.dump(p) },
        finished:->(p) { p[:phase]==:finished && same_user?(p[:winner],player) })
    end
  end
end
