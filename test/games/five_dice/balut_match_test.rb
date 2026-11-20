require_relative "../../support/cat_head_tail"
require_relative "../../../games/balut"

game = GameRoomGames::Balut.new
players = %w[Alice Bob]
repo = CatHeadTailRepository.new(players)
coordinator = GameRoomBots::Coordinator.new
context = Struct.new(:random_source, :server_random).new(GameRoomRandom::LocalSecureSource.new, false)
session = {"options" => JSON.generate(game.default_options)}
events = []
361.times do
  replay = game.replay(session, events, repo)
  assert(replay.accepted_events.length == events.length, "A planned event was refused")
  if replay.finished?
    sheets = replay.state[:sheets]
    assert(players.all? { |player| sheets.fetch(player).values.all? { |row| row.size == 4 } }, "Incomplete score sheet")
    puts "PASS Balut: complete 28-turn game through shared bot coordinator"
    exit
  end
  decision = coordinator.decide_next(game: game, replay: replay, context: context, controlled_actors: players)
  assert(decision, "Bot stalled")
  status, plan = game.action_for(decision.action, replay, decision.actor, context: context)
  assert(status == :ok && plan.events.size == 1, "Bot plan was invalid")
  event = plan.events.first
  events << cht_event(events.length + 1, decision.actor, event.action, event.value)
end
raise "Match did not finish within the legal turn bound"


