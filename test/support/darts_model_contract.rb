require_relative 'assertions'
require_relative 'contract_values'
require_relative '../../games/darts'
require_relative '../../lib/game_random'

module GameRoomTest
  module DartsModelContract
    extend Assertions
    module_function

    PLAYERS = %w[Alice Bob].freeze
    SEED = 137
    MATCH_SEED = '0123456789abcdef0123456789abcdef'

    class Repository
      def players_for(session); session.fetch('__players'); end
      def actor_of(event, _session = nil); event.fetch('actor'); end
      def event_id(event); event.fetch('id'); end
    end

    # Darts starts through the table owner's server-random command and accepts
    # a locally confirmed coordinate rather than exposing that coordinate as a
    # generic legal action. Capture the real durable protocol explicitly: two
    # complete three-dart turns followed by one sudden-death dart per player.
    def capture
      game = GameRoomGames::Darts.new
      options = game.default_options.merge('rounds' => 1)
      session = {
        '__id' => 1, 'table_id' => 1, 'game' => game.id,
        'options' => JSON.generate(options), '__players' => PLAYERS,
        '__table_owner' => PLAYERS.first, '__insertion_user' => PLAYERS.first
      }
      events = contract_events
      random = GameRoomRandom::SeededSource.new(SEED)
      steps = (0..events.length).map do |count|
        checkpoint(game, session, events.first(count), random)
      end
      final = game.build_session_game.replay(session, events, Repository.new)
      assert_equal(:finished, final.state[:phase], 'Darts contract did not finish')
      assert_equal('Alice', final.winner, 'Darts sudden death changed its winner')
      {
        'game' => game.id, 'seed' => SEED, 'players' => PLAYERS,
        'session' => session, 'steps' => steps, 'events' => events
      }
    end

    def checkpoint(game, session, events, random)
      inputs = ContractValues.digest([session, events])
      replay = game.build_session_game.replay(session, events, Repository.new)
      assert_equal(events, replay.accepted_events, 'Darts rejected a recorded contract event')
      unknown = {
        'id' => 2_000_000_000, 'sequence' => 2_000_000_000,
        'actor' => 'Unknown participant', '__insertion_user' => 'Unknown participant',
        'action' => '__unknown_contract_event__', 'value' => ''
      }
      rejected = game.build_session_game.replay(session, events + [unknown], Repository.new)
      assert_equal(ContractValues.canonical(replay), ContractValues.canonical(rejected),
        'Unknown Darts event changed replay')
      assert_equal(inputs, ContractValues.digest([session, events]), 'Darts replay changed its inputs')
      actions = PLAYERS.to_h do |actor|
        [actor, game.legal_actions(replay, actor,
          context: GameRoomGames::ActionContext.new(table_owner: PLAYERS.first))]
      end
      {
        'events' => events.length, 'replay' => ContractValues.digest(replay),
        'actor' => replay.current_player, 'phase' => replay.state[:phase].to_s,
        'legal' => ContractValues.digest(actions),
        'rng' => random.dup.roll(count: 8, sides: 1_000).values
      }
    end

    def contract_events
      rows = [
        ['Alice', '0:0:0:500:m'], ['Alice', '1:300:0:600:m'], ['Alice', '2:800:0:700:m'],
        ['Bob', '3:0:0:500:m'], ['Bob', '4:300:0:600:m'], ['Bob', '5:800:0:700:m'],
        ['Alice', '6:100:0:800:m'], ['Bob', '7:1000:1000:900:m']
      ]
      start = event(1, 'Alice', 'darts_start', MATCH_SEED)
      [start, *rows.each_with_index.map { |(actor, value), index| event(index + 2, actor, 'darts_throw', value) }]
    end

    def event(id, actor, action, value)
      {'id' => id, 'sequence' => id, 'actor' => actor, '__insertion_user' => actor,
        'action' => action, 'value' => value}
    end
  end
end
