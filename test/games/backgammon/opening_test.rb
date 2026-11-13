require_relative "../../support/cat_head_tail"
require_relative "../../../games/backgammon"

game = GameRoomGames::Backgammon.new
repo = CatHeadTailRepository.new(%w[Alice Bob])
events = [cht_event(1, "Alice", "opening", "4,4"),
          cht_event(2, "Bob", "opening", "6,1"),
          cht_event(3, "Alice", "opening", "1,6")]
replay = game.replay({}, events, repo)
assert(replay.accepted_events.map { |e| e["id"] } == [1, 3], "Opening tie or wrong actor mishandled")
assert(replay.current_player == "Bob" && replay.state[:dice] == [1, 6], "Opening roll was not retained")
surface = game.surface_spec(replay, "Bob")
assert(surface.point_moves.any?, "No keyboard move available")
choice = game.legal_actions(replay, "Bob").first
status, plan = game.action_for(choice, replay, "Bob")
assert(status == :ok, "Legal move cannot be submitted")
event = plan.events.first
next_replay = game.replay({}, events + [cht_event(4, "Bob", event.action, event.value)], repo)
assert(next_replay.state[:dice].size == 1 && next_replay.board != replay.board, "Move did not consume a die")
assert(next_replay.current_player == "Bob", "Turn ended despite available second move")
puts "PASS Tryktrak opening, keyboard surface and first move replay"

%w[classic nack hyper].zip([15, 15, 3]).each do |variant, count|
  start = game.replay({"options" => JSON.generate({"variant" => variant})}, [], repo)
  assert(start.board.all? { |side| side.values.sum == count }, "Wrong checker count for #{variant}")
  assert(start.state[:checker_count] == count, "Settlement uses wrong checker count")
  assert(start.board.first.fetch(23, 0) == {"classic" => 0, "nack" => 2, "hyper" => 1}.fetch(variant), "Wrong opening position")
end
puts "PASS Tryktrak variant setups"
