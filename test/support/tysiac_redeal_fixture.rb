require_relative "new_games_fixture"
require_relative "../../games/tysiac"

class TysiacRedealFixture
  attr_reader :game, :players, :session, :repository, :events

  def initialize(options = {}, players: %w[Alice Bob Carol])
    @game, @players = GameRoomGames::Tysiac.new, players
    @session = {"options"=>JSON.generate(@game.normalize_options(options))}
    @repository, @events = NewGames116Repository.new(players), []
    @random = GameRoomRandom::SeededSource.new(195)
  end

  def replay; game.replay(session, events, repository); end
  def state; replay.state; end
  def context; GameRoomGames::ActionContext.new(random_source: @random); end
  def deal(seed)
    events << {"id"=>events.size + 1, "actor"=>players.first, "action"=>"deal", "value"=>"1|0|#{seed}"}
    raise "Invalid seeded fixture" unless replay.accepted_events.size == events.size
  end

  def move(selection, actor: replay.current_player)
    status, plan = game.action_for(selection, replay, actor, context: context)
    return status unless status == :ok
    plan.events.each do |command|
      events << {"id"=>events.size + 1, "actor"=>actor, "action"=>command.action, "value"=>command.value}
    end
    raise "Rule replay rejected the plan" unless replay.accepted_events.size == events.size
    status
  end

  def bid(value); move({"kind"=>"command", "action"=>"bid", "bid"=>value}); end
  def request(reason, actor: replay.current_player); move({"kind"=>"command", "action"=>"redeal", "reason"=>reason}, actor: actor); end
  def redeal
    action = game.automatic_action(replay, players.first, context: context)
    raise "No automatic new deal" unless action
    move(action, actor: players.first)
  end

  def self.seed_for
    game = GameRoomGames::Tysiac.new
    (1..50_000).each do |number|
      seed = "%032x" % number
      deck = game.send(:shuffled_deck, seed)
      return seed if yield(deck)
    end
    raise "No matching deck found"
  end
end
