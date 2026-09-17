require "json"
require_relative "game_bots"

module BibliosPlanning
  class Strategy
    def initialize(fallback: GameRoomBots::HeuristicStrategy.new)
      @fallback = fallback
    end

    def choose(actions:, actor:, random_source:, game:, replay:, context: nil, **_extra)
      choices = actions.to_a
      return nil if choices.empty?
      return choices.first if choices.length == 1

      packets = choices.select { |action| action["kind"].to_s == "card_packet" }
      return packets.min_by { |action| packet_cost(game, action) } if !packets.empty?

      @fallback.choose(
        actions: choices, actor: actor, random_source: random_source,
        game: game, replay: replay, context: context
      )
    end

    private

    def packet_cost(game, action)
      cards = parse(action["cards"])
      [cards.sum { |card| card_cost(game, card) }, cards.length]
    end

    def card_cost(game, card)
      game.gold?(card) ? game.gold_value(card) * 2 : game.card_value(card)
    end

    def parse(value)
      JSON.parse(value.to_s).map(&:to_s)
    rescue JSON::ParserError
      []
    end
  end
end
