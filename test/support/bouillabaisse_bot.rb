require_relative 'assertions'
require_relative 'elten_array_shuffle'
require_relative '../../games/bouillabaisse'

module GameRoomTest
  module BouillabaisseBot
    extend Assertions
    module_function

    def position(hands:, round:, actor: 'A', trick: [], taken: {}, plays: [], all_or_nothing: false,
      penalties: {'suit'=>'H', 'rank'=>'Q', 'card'=>'QH'})
      game = GameRoomGames::Bouillabaisse.new
      players = hands.keys
      taken = players.to_h { |player| [player, taken.fetch(player, [])] }
      deck = hands.values.flatten + taken.values.flatten + trick.map(&:last)
      assert(deck.uniq == deck, 'Duplicate card in a strategy fixture')
      state = game.send(:initial_state, players, game.normalize_options('all_or_nothing'=>all_or_nothing))
      state.update(hands: hands, round: round, round_deck: deck, penalties: penalties, phase: :playing,
        current_player: actor, trick: trick, taken: taken, tricks: taken.transform_values { |cards| cards.size / players.size })
      events = [{'action'=>'deal', 'value'=>'public deal evidence, not a bot input'}]
      events.concat(plays.map { |player, card| {'action'=>'play', 'actor'=>player, 'value'=>card} })
      replay = GameRoomGames::Replay.new(players: players, current_player: actor, state: state, accepted_events: events, history: [])
      [game, replay]
    end

    def choose(game, replay, actor = replay.current_player)
      actions = game.legal_actions(replay, actor)
      choice = game.bot_strategy.choose(actions: actions, observation: game.bot_observation(replay, actor))
      assert(actions.include?(choice), 'Planner selected an illegal card')
      choice.fetch('card')
    end
  end
end
