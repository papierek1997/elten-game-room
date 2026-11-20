require_relative '../game_bots'

module GameRoomCashAuction
  # Declining an unaffordable auction is a local bot decision, not a move.
  # The shared coordinator may try another actor and the normal auction clock
  # still closes the auction; a new offer lets this bot reconsider its budget.
  class BiddingStrategy < GameRoomBots::HeuristicStrategy
    def choose(actions:, actor:, random_source:, game: nil, replay: nil, context: nil, **extra)
      if game && replay && replay.state[:phase] == :auction
        actions = actions.to_a.select { |action| game.bot_action_score(replay, actor, action, context: context) >= 0 }
      end
      super(actions: actions, actor: actor, random_source: random_source,
        game: game, replay: replay, context: context, **extra)
    end
  end
end
