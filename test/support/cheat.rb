require 'json'
require_relative 'assertions'
require_relative '../../games/cheat'

module GameRoomTest
  module CheatFixture
    include Assertions

    class Repository
      def initialize(players); @players = players; end
      def players_for(_session); @players; end
      def actor_of(event, _session = nil); event.fetch('actor'); end
      def event_id(event); event.fetch('id'); end
    end

    class RandomSource < GameRoomRandom::Source
      def initialize(seed); @random = Random.new(seed); end
      def source_name; 'cheat_test'; end
      protected
      def next_value(sides); @random.rand(sides) + 1; end
    end

    def cheat_start(variant = 'ascending', count = 3, seed = '1234567890abcdef1234567890abcdef')
      @game = GameRoomGames::Cheat.new
      @players = Array.new(count) { |index| "Player#{index + 1}" }
      @repository = Repository.new(@players)
      @session = {'options' => JSON.generate(@game.normalize_options('variant' => variant))}
      @events = [{'id' => 1, 'actor' => @players.first, 'action' => 'cheat_deal', 'value' => "0|#{seed}"}]
      @replay = @game.replay(@session, @events, @repository)
    end

    def cheat_move(selection, actor = @replay.current_player)
      status, plan = @game.action_for(selection, @replay, actor)
      assert_equal(:ok, status, "Refused #{selection.inspect}")
      plan.events.each do |command|
        @events << {'id' => @events.length + 1, 'actor' => actor, 'action' => command.action, 'value' => command.value}
        assert(command.value.length <= 64, 'Move exceeds the native value limit')
      end
      @replay = @game.replay(@session, @events, @repository)
      assert_equal(@events.length, @replay.accepted_events.length)
      cheat_conservation(@replay.state)
      @replay
    end

    def cheat_play(cards, claim = nil)
      state = @replay.state
      {'kind' => 'card_packet', 'action' => 'play', 'cards' => JSON.generate(cards),
       'choice' => claim || @game.send(:allowed_claims, state).first,
       'boundary' => state[:sequence].to_s(36)}
    end

    def cheat_command(action)
      state = @replay.state
      {'kind' => 'command', 'action' => action, 'boundary' => state[:sequence].to_s(36),
       'packet' => state[:last_packet]&.fetch(:id)&.to_s(36)}
    end

    def cheat_conservation(state)
      cards = state[:hands].values.flatten + state[:pile] + state[:removed]
      assert_equal(52, cards.length)
      assert_equal(52, cards.uniq.length)
      assert_equal(@game.send(:standard_deck).sort, cards.sort)
    end
  end
end
