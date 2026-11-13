require_relative "../../support/cat_head_tail"
require_relative "../../../games/backgammon"

rules = GameRoomGames::BackgammonRules
assert(rules.legal([{1=>1}, {}], 0, [1,6]) == [[1,0,6]], "Higher die must be used")
assert(rules.legal([{25=>1, 6=>1}, {1=>2}], 0, [1,2]).all? { |m| m[0] == 25 }, "Bar must enter first")
assert(rules.apply([{8=>1}, {20=>1}], 0, [8,5,3])[1] == {25=>1}, "Hit must send checker to bar")
assert(rules.moves([{1=>1,6=>1}, {}], 0, 4) == [[6,2,4]], "Cannot bear off below a farther checker")
game = GameRoomGames::Backgammon.new
players = %w[Alice Bob]
repo = CatHeadTailRepository.new(players)
session = {"options" => JSON.generate({"variant" => "hyper"})}
context = Struct.new(:random_source, :server_random).new(GameRoomRandom::SeededSource.new(87), false)
coordinator = GameRoomBots::Coordinator.new
events = []
240.times do
  replay = game.replay(session, events, repo)
  assert(replay.accepted_events.size == events.size, "Invalid replay")
  if replay.finished?
    assert(replay.board.any? { |side| side.fetch(0, 0) == 3 }, "Winner has not borne off all three checkers")
    puts "PASS Hypergammon: legal moves and complete game through Power Games bot coordinator"
    exit
  end
  decision = coordinator.decide_next(game: game, replay: replay, context: context, controlled_actors: players)
  assert(decision, "No bot decision")
  status, plan = game.action_for(decision.action, replay, decision.actor, context: context)
  assert(status == :ok, "Invalid bot decision")
  event = plan.events.first
  events << cht_event(events.size + 1, decision.actor, event.action, event.value)
end
raise "Game did not complete"


